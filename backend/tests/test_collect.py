from copy import deepcopy
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from backend import collect as c

FIXTURE = Path(__file__).parent / "fixtures" / "weekly-posts.json"


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(FIXTURE.read_text())
        self.record = self.fixture["posts"][0]
        self.post = next(c.FixtureInstagram(self.fixture).posts("mju_lounge", None))
        self.extraction = deepcopy(self.record["extraction"])
        self.now = c.timestamp(self.fixture["now"])
        self.empty = {"schemaVersion": 1, "weeks": []}

    def normalize(self):
        return c.normalize_extraction(self.extraction, self.post, self.now)

    def test_golden_fixture_has_dated_automatic_provenance(self):
        week = self.normalize()
        self.assertEqual(week["entries"][1]["items"], ["테스트 김치볶음밥"])
        self.assertEqual(week["monday"], "2026-10-12")
        self.assertEqual(week["processingMethod"], "automatic")
        self.assertEqual(week["temporalBasis"], "printed-year")
        self.assertEqual(week["collectedAt"], "2026-10-13T02:00:00Z")
        self.assertNotIn("images", week)

    def test_wrong_source_and_uncertain_output_never_publish(self):
        for field, value in (("username", "mjhs_yongin"), ("postURL", "https://www.instagram.com/mju_lounge/p/Different/"),
                             ("uncertainties", ["날짜가 불명확함"])):
            with self.subTest(field=field):
                altered = {**self.extraction, field: value}
                with self.assertRaises(c.CollectionError):
                    c.normalize_extraction(altered, self.post, self.now)

    def test_month_day_without_year_resolved_from_post_and_weekday(self):
        self.extraction["yearEvidence"] = ""
        self.extraction["monday"] = ""
        for entry in self.extraction["entries"]:
            entry["date"] = entry["date"][5:]
        result = self.normalize()
        self.assertEqual(result["entries"][0]["date"], "2026-10-12")
        self.assertEqual(result["temporalBasis"], "post-timestamp-and-printed-weekdays")

    def test_missing_year_and_weekday_rejected(self):
        self.extraction["yearEvidence"] = ""
        self.extraction["entries"][0]["dateEvidence"] = "10/12"
        with self.assertRaisesRegex(c.RejectPost, "missing_weekday"):
            self.normalize()

    def test_full_english_weekdays_resolve_yearless_schedule(self):
        self.extraction["yearEvidence"] = ""
        self.extraction["monday"] = ""
        for entry, label in zip(self.extraction["entries"], ("10/12 Monday", "10/13 Tuesday")):
            entry["dateEvidence"] = label
            entry["date"] = ""
        self.assertEqual(self.normalize()["entries"][1]["date"], "2026-10-13")
        for index, name in enumerate(("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")):
            with self.subTest(weekday=name):
                self.assertEqual(c.printed_date("10/12 " + name)[2], index)

    def test_new_year_rollover_uses_post_timestamp(self):
        self.post.published_at = "2026-12-27T23:00:00Z"
        self.now = c.timestamp("2026-12-29T01:00:00Z")
        self.extraction["yearEvidence"] = ""
        self.extraction["monday"] = ""
        for entry, evidence in zip(self.extraction["entries"], ("12/31 (목)", "1/1 (금)")):
            entry["dateEvidence"] = evidence
            entry["date"] = ""
        result = self.normalize()
        self.assertEqual(result["monday"], "2026-12-28")
        self.assertEqual([entry["date"] for entry in result["entries"]], ["2026-12-31", "2027-01-01"])

    def test_conflicting_printed_weekday_rejected(self):
        self.extraction["entries"][0]["dateEvidence"] = "10/12 (화)"
        with self.assertRaisesRegex(c.RejectPost, "conflicting_dates"):
            self.normalize()

    def test_old_menu_never_shifted_to_current_week(self):
        self.now = c.timestamp("2026-12-01T01:00:00Z")
        with self.assertRaisesRegex(c.RejectPost, "outside_collection_window"):
            self.normalize()

    def test_cross_week_cell_rejected(self):
        self.extraction["entries"][1].update(date="2026-10-20", dateEvidence="10/20 (화)")
        with self.assertRaises(c.RejectPost):
            self.normalize()

    def test_inferred_holiday_rejected_but_printed_closure_allowed(self):
        self.extraction["entries"][0]["items"] = ["공휴일"]
        with self.assertRaisesRegex(c.RejectPost, "inferred_closure"):
            self.normalize()
        self.extraction["entries"][0]["closureEvidence"] = "공휴일"
        self.assertEqual(self.normalize()["entries"][0]["items"], ["공휴일"])

    def test_failed_reextraction_preserves_prior_exact_week(self):
        prior = self.normalize()
        self.fixture["posts"][0]["caption"] = "Edited caption"
        self.fixture["posts"][0]["extraction"]["uncertainties"] = ["날짜 판독 불가"]
        feed, status = c.collect({"schemaVersion": 1, "weeks": [prior]},
                                 c.FixtureInstagram(self.fixture), c.FixtureVision(self.fixture), self.now)
        self.assertEqual(feed["weeks"], [prior])
        self.assertTrue(status["hasFailures"])

    def test_unchanged_images_and_caption_skip_paid_extraction(self):
        previous = {"schemaVersion": 1, "weeks": [self.normalize()]}
        vision = c.FixtureVision(self.fixture)
        with patch.object(vision, "extract", side_effect=AssertionError("must not call paid API")):
            feed, status = c.collect(previous, c.FixtureInstagram(self.fixture), vision, self.now)
        self.assertEqual(feed["weeks"], previous["weeks"])
        self.assertEqual(status["unchangedPosts"], 1)

    def test_all_account_api_errors_preserve_feed(self):
        prior = self.normalize()
        class FailedInstagram:
            def posts(self, username, since):
                raise c.HTTPFailure(403)
        feed, status = c.collect({"schemaVersion": 1, "weeks": [prior]}, FailedInstagram(), None, self.now)
        self.assertEqual(feed["weeks"], [prior])
        self.assertEqual(len(status["failures"]), 4)

    def test_previous_feed_failure_does_not_silently_reset_to_seed(self):
        http = c.HTTP()
        for status in (404, 403, 500):
            with self.subTest(status=status), patch.object(http, "json", side_effect=c.HTTPFailure(status)):
                with self.assertRaises(c.HTTPFailure):
                    c.load_previous(http, "https://example.com/meals.json", "unused", False)
        with patch.object(http, "json", side_effect=c.HTTPFailure(500)):
            with self.assertRaises(c.HTTPFailure):
                c.load_previous(http, "https://example.com/meals.json", "unused", True)

    def test_instagram_permalink_normalization_and_account_binding(self):
        self.assertEqual(c.post_url("https://www.instagram.com/p/AbcDef12/", "mju_lounge", True),
                         "https://www.instagram.com/mju_lounge/p/AbcDef12/")
        for bad in ("https://www.instagram.com/mjhs_yongin/p/AbcDef12/", "https://evil.test/mju_lounge/p/AbcDef12/",
                    "https://www.instagram.com/p/AbcDef12/?token=secret"):
            with self.subTest(url=bad), self.assertRaises(c.CollectionError):
                c.post_url(bad, "mju_lounge", True)

    def test_graph_username_response_mismatch_rejected(self):
        http = c.HTTP()
        api = c.Instagram(http, "not-a-real-token", "123456", "v99.0")
        with patch.object(http, "json", return_value={"business_discovery": {"username": "other", "media": {"data": []}}}):
            with self.assertRaisesRegex(c.CollectionError, "business_discovery_unavailable"):
                list(api.posts("mju_lounge", self.now))

    def test_fixture_cli_never_writes_publishable_output(self):
        with tempfile.TemporaryDirectory() as folder, patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(c.main(["--fixture", str(FIXTURE), "--dry-run", "--output-dir", folder]), 0)
            self.assertEqual(list(Path(folder).iterdir()), [])
            self.assertEqual(c.main(["--fixture", str(FIXTURE), "--output-dir", folder]), 1)

    def test_seed_compatible_and_duplicate_week_rejected(self):
        # Running from repository root is the documented command.
        document = json.loads(Path("Sources/MealCore/Resources/instagram-reviewed.json").read_text())
        c.validate_feed(document)
        document["weeks"].append(deepcopy(document["weeks"][0]))
        with self.assertRaisesRegex(c.CollectionError, "duplicate_week"):
            c.validate_feed(document)

    def test_unreadable_newer_post_cannot_fall_back_to_old_post_as_update(self):
        prior = self.normalize()
        newer = deepcopy(self.record)
        newer["postURL"] = newer["extraction"]["postURL"] = "https://www.instagram.com/mju_lounge/p/NewerMenu12/"
        newer["extraction"]["uncertainties"] = ["수정된 메뉴 판독 불가"]
        older = deepcopy(self.record)
        older["caption"] = "An older menu with changed caption"
        older["extraction"]["entries"][0]["items"] = ["과거 메뉴"]
        self.fixture["posts"] = [newer, older]
        feed, status = c.collect({"schemaVersion": 1, "weeks": [prior]},
                                 c.FixtureInstagram(self.fixture), c.FixtureVision(self.fixture), self.now)
        self.assertEqual(feed["weeks"], [prior])
        self.assertEqual(status["updatedWeeks"], 0)

    def test_old_post_in_api_window_is_skipped_without_failure(self):
        now = c.timestamp("2026-11-04T02:00:00Z")
        feed, status = c.collect(self.empty, c.FixtureInstagram(self.fixture), c.FixtureVision(self.fixture), now)
        self.assertEqual(feed["weeks"], [])
        self.assertFalse(status["hasFailures"])
        self.assertEqual(status["unchangedPosts"], 1)
        self.assertEqual(feed["collectorState"]["nonMenuDigests"], [])

    def test_future_post_is_not_permanently_ignored(self):
        earlier = c.timestamp("2026-09-28T02:00:00Z")
        feed, status = c.collect(self.empty, c.FixtureInstagram(self.fixture), c.FixtureVision(self.fixture), earlier)
        self.assertEqual(feed["weeks"], [])
        self.assertFalse(status["hasFailures"])
        later, _ = c.collect(feed, c.FixtureInstagram(self.fixture), c.FixtureVision(self.fixture), self.now)
        self.assertEqual(len(later["weeks"]), 1)

    def test_retention_and_byte_budget_preserve_current_even_on_api_failure(self):
        current = self.normalize()
        old = deepcopy(current)
        old["monday"] = "2025-10-13"
        for entry in old["entries"]:
            entry["date"] = entry["date"].replace("2026-10-12", "2025-10-13").replace("2026-10-13", "2025-10-14")
        recent = deepcopy(current)
        recent["monday"] = "2026-10-05"
        recent["entries"][0]["date"] = "2026-10-05"
        recent["entries"][1]["date"] = "2026-10-06"
        recent["sourceDigest"] = "0" * 64
        prior = {"schemaVersion": 1, "weeks": [old, recent, current]}
        class FailedInstagram:
            def posts(self, username, since):
                raise c.HTTPFailure(403)
        baseline = {"schemaVersion": 1, "generatedAt": c.iso_now(self.now), "weeks": [current], "collectorState": {"nonMenuDigests": []}}
        with patch.object(c, "MAX_PUBLISHED", len(c.encode_document(baseline)) + 1):
            feed, status = c.collect(prior, FailedInstagram(), None, self.now)
        self.assertEqual(feed["weeks"], [current])
        self.assertTrue(status["hasFailures"])


if __name__ == "__main__":
    unittest.main()
