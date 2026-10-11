from copy import deepcopy
from datetime import datetime, timezone
from html.parser import HTMLParser
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from backend import publish_reviewed as p


class ReviewedPublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.input = self.root / "reviewed.json"
        self.output = self.root / "site"
        self.now = datetime(2026, 10, 10, 3, tzinfo=timezone.utc)
        # Synthetic menus stay in the temporary test directory. Changes to the
        # real weekly feed must not change these date/validation test cases.
        accounts = (
            ("mju_lounge", "science-library"),
            ("mjhs_yongin", "science-student"),
            ("mj_bangmok_foodist", "science-staff"),
            ("mj_bokji_foodist", "science-dormitory"),
        )
        self.feed = {"schemaVersion": 1, "weeks": [
            {
                "cafeteriaID": cafeteria_id,
                "monday": "2026-10-05",
                "username": username,
                "postURL": f"https://www.instagram.com/{username}/p/TestOnly01/",
                "verifiedAt": "2026-10-09T02:22:46Z",
                "scope": "테스트 중식",
                "location": "테스트 식당",
                "operatingHours": "테스트 11:00~14:00",
                "entries": [
                    {"date": date, "category": "중식", "title": None,
                     "items": ["테스트 메뉴"], "note": None}
                    for date in ("2026-10-05", "2026-10-09")
                ],
            }
            for username, cafeteria_id in accounts
        ]}

    def write_input(self, feed=None):
        self.input.write_text(json.dumps(self.feed if feed is None else feed, ensure_ascii=False))

    def publish(self, feed=None):
        self.write_input(feed)
        return p.publish_reviewed(self.input, self.output, now=self.now)

    def test_real_reviewed_data_preserves_dates_times_and_sources(self):
        # Integration check deliberately makes no assumptions about which
        # weeks, corrections, or review timestamps the live source contains.
        reviewed = json.loads(p.DEFAULT_INPUT.read_text())
        status = self.publish(reviewed)
        actual = json.loads((self.output / "meals.json").read_text())
        self.assertEqual(actual, reviewed)
        self.assertEqual(status["processingMethod"], "manual")
        self.assertEqual(status["publicationMode"], "reviewed-upload")
        self.assertEqual(status["publishedAt"], "2026-10-10T03:00:00Z")
        summaries = {
            (account["username"], week["monday"]): week
            for account in status["accounts"] for week in account["weeks"]
        }
        self.assertEqual(len(summaries), len(reviewed["weeks"]))
        for week in reviewed["weeks"]:
            summary = summaries[(week["username"], week["monday"])]
            self.assertEqual(summary["verifiedAt"], week["verifiedAt"])
            self.assertEqual(summary["postURL"], week["postURL"])
            self.assertEqual(summary["menuDates"], sorted({entry["date"] for entry in week["entries"]}))
            self.assertEqual(summary["entryCount"], len(week["entries"]))
        page = (self.output / "index.html").read_text()
        self.assertIn("식단 사진을 확인해 등록하는 방식", page)

    def test_invalid_records_leave_existing_site_untouched(self):
        self.publish()
        before = {path.name: path.read_bytes() for path in self.output.iterdir()}
        mutations = [
            ("wrong account", lambda feed: feed["weeks"][0].update(username="mjhs_yongin")),
            ("wrong post", lambda feed: feed["weeks"][0].update(postURL="https://www.instagram.com/mjhs_yongin/p/TestOnly01/")),
            ("non-Monday", lambda feed: feed["weeks"][0].update(monday="2026-10-06")),
            ("outside week", lambda feed: feed["weeks"][0]["entries"][0].update(date="2026-10-12")),
            ("invalid date", lambda feed: feed["weeks"][0]["entries"][0].update(date="2026-02-30")),
            ("no timezone", lambda feed: feed["weeks"][0].update(verifiedAt="2026-10-09T02:22:46")),
            ("automatic", lambda feed: feed["weeks"][0].update(processingMethod="automatic")),
            ("duplicate week", lambda feed: feed["weeks"].append(deepcopy(feed["weeks"][0]))),
            ("top secret", lambda feed: feed.update(INSTAGRAM_ACCESS_TOKEN="must-not-publish")),
            ("week secret", lambda feed: feed["weeks"][0].update(accessToken="must-not-publish")),
            ("entry secret", lambda feed: feed["weeks"][0]["entries"][0].update(rawImage="must-not-publish")),
            ("malformed port", lambda feed: feed["weeks"][0].update(postURL="https://www.instagram.com:bad/mju_lounge/p/TestOnly01/")),
            ("explicit HTTPS port", lambda feed: feed["weeks"][0].update(postURL="https://www.instagram.com:443/mju_lounge/p/TestOnly01/")),
        ]
        for name, mutate in mutations:
            with self.subTest(name=name):
                invalid = deepcopy(self.feed)
                mutate(invalid)
                with self.assertRaises(p.CollectionError):
                    self.publish(invalid)
                self.assertEqual({path.name: path.read_bytes() for path in self.output.iterdir()}, before)

    def test_invalid_input_does_not_create_output_directory(self):
        self.feed["weeks"][0]["entries"][0]["date"] = "2026-10-12"
        with self.assertRaises(p.CollectionError):
            self.publish()
        self.assertFalse(self.output.exists())

    def test_both_input_and_serialized_output_size_limits_apply(self):
        self.publish()
        before = (self.output / "meals.json").read_bytes()
        self.input.write_bytes(b" " * (p.MAX_PUBLISHED + 1))
        with self.assertRaisesRegex(p.CollectionError, "feed_too_large"):
            p.publish_reviewed(self.input, self.output, now=self.now)
        self.write_input()
        compact_size = self.input.stat().st_size
        self.assertGreater(len(p.encode(self.feed)), compact_size)
        with patch.object(p, "MAX_PUBLISHED", compact_size + 1):
            with self.assertRaisesRegex(p.CollectionError, "feed_too_large"):
                p.publish_reviewed(self.input, self.output, now=self.now)
        self.assertEqual((self.output / "meals.json").read_bytes(), before)

    def test_html_escapes_source_text(self):
        self.feed["weeks"][0]["scope"] = '<script>alert("menu")</script> & 백반'
        self.publish()
        page = (self.output / "index.html").read_text()
        self.assertNotIn('<script>alert("menu")</script>', page)
        self.assertIn('&lt;script&gt;alert(&quot;menu&quot;)&lt;/script&gt; &amp; 백반', page)
        class Tags(HTMLParser):
            def __init__(self):
                super().__init__()
                self.tags = []
                self.links = []
            def handle_starttag(self, tag, attrs):
                self.tags.append(tag)
                if tag == "a":
                    self.links.append(dict(attrs)["href"])
        parser = Tags()
        parser.feed(page)
        self.assertNotIn("script", parser.tags)
        for week in self.feed["weeks"]:
            self.assertIn(week["postURL"], parser.links)

    def test_current_week_uses_korea_time_and_old_data_stays_old(self):
        initial = self.publish()
        for account in initial["accounts"]:
            self.assertEqual(account["weeks"][0]["verifiedAt"], "2026-10-09T02:22:46Z")
            self.assertEqual(account["weeks"][0]["firstMenuDate"], "2026-10-05")
            self.assertEqual(account["weeks"][0]["lastMenuDate"], "2026-10-09")
            self.assertTrue(account["currentWeekAvailable"])
            self.assertFalse(account["nextWeekAvailable"])
        self.assertIn("다음 주 (2026-10-12 시작): 아직 업로드되지 않았어요",
                      (self.output / "index.html").read_text())
        # Still Sunday in UTC, but Monday in Korea.
        status = p.publish_reviewed(self.input, self.output, now=datetime(2026, 10, 11, 16, tzinfo=timezone.utc))
        self.assertEqual(status["currentWeekMonday"], "2026-10-12")
        for account in status["accounts"]:
            self.assertFalse(account["currentWeekAvailable"])
            self.assertEqual(account["weeks"][0]["monday"], "2026-10-05")
        self.assertEqual(json.loads((self.output / "meals.json").read_text()), self.feed)

    def test_next_week_is_available_only_for_accounts_with_that_week(self):
        upcoming = deepcopy(self.feed["weeks"][0])
        upcoming["monday"] = "2026-10-12"
        upcoming["entries"] = [{**upcoming["entries"][0], "date": "2026-10-12"}]
        self.feed["weeks"].append(upcoming)
        status = self.publish()
        library = next(account for account in status["accounts"] if account["username"] == "mju_lounge")
        self.assertTrue(library["nextWeekAvailable"])
        self.assertEqual(library["weeks"][0]["menuDates"], ["2026-10-12"])
        self.assertFalse(next(account for account in status["accounts"] if account["username"] == "mjhs_yongin")["nextWeekAvailable"])

    def test_empty_feed_reports_unavailable_without_inventing_dates(self):
        status = self.publish({"schemaVersion": 1, "weeks": []})
        for account in status["accounts"]:
            self.assertEqual(account["weeks"], [])
            self.assertFalse(account["currentWeekAvailable"])
            self.assertFalse(account["nextWeekAvailable"])
        self.assertIn("아직 확인된 식단이 없어요", (self.output / "index.html").read_text())

    def test_duplicate_json_keys_rejected(self):
        self.input.write_text('{"schemaVersion":1,"weeks":[],"weeks":[]}')
        with self.assertRaisesRegex(p.CollectionError, "duplicate_json_key"):
            p.publish_reviewed(self.input, self.output, now=self.now)
        self.assertFalse(self.output.exists())

    def test_cli_needs_no_credentials_and_reports_safe_error(self):
        self.write_input()
        with patch.dict("os.environ", {}, clear=True), patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(p.main(["--input", str(self.input), "--output-dir", str(self.output)]), 0)
        self.input.write_text('{"schemaVersion":1,"weeks":[],"token":"private-example"}')
        with patch("sys.stderr", new_callable=io.StringIO) as stderr:
            self.assertEqual(p.main(["--input", str(self.input), "--output-dir", str(self.output)]), 1)
            self.assertNotIn("private-example", stderr.getvalue())
            self.assertNotIn(str(self.input), stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
