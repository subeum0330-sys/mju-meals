#!/usr/bin/env python3
"""Publish reviewed menu data locally, without API accounts or credentials.

Menu photos must first be reviewed and entered into instagram-reviewed.json.
Publication never changes a menu date or claims that another review took place.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from html import escape
import json
from pathlib import Path
import sys
import tempfile
from urllib.parse import urlsplit

if __package__:
    from .collect import (ACCOUNTS, KST, MAX_PUBLISHED, CollectionError,
                          iso_now, monday_of, timestamp, validate_feed)
else:
    from collect import (ACCOUNTS, KST, MAX_PUBLISHED, CollectionError,
                         iso_now, monday_of, timestamp, validate_feed)


DEFAULT_INPUT = Path(__file__).resolve().parents[1] / "Sources/MealCore/Resources/instagram-reviewed.json"
NAMES = {
    "science-library": "명진당",
    "science-student": "학생회관",
    "science-staff": "방목관 교직원식당",
    "science-dormitory": "생활관·복지동",
}
FEED_FIELDS = {"schemaVersion", "weeks"}
WEEK_FIELDS = {"cafeteriaID", "monday", "username", "postURL", "verifiedAt", "scope",
               "location", "operatingHours", "entries", "processingMethod"}
ENTRY_FIELDS = {"date", "category", "title", "items", "note"}


def only_fields(value, allowed):
    if not isinstance(value, dict) or value.keys() - allowed:
        raise CollectionError("unknown_or_invalid_fields")


def validate_reviewed_feed(feed):
    """Allow only the public, manually reviewed schema, then reuse app validation."""
    only_fields(feed, FEED_FIELDS)
    if type(feed.get("schemaVersion")) is not int or not isinstance(feed.get("weeks"), list):
        raise CollectionError("invalid_feed")
    for week in feed["weeks"]:
        if not isinstance(week, dict):
            raise CollectionError("invalid_week")
        if week.get("processingMethod", "manual") != "manual":
            raise CollectionError("reviewed_data_required")
        only_fields(week, WEEK_FIELDS)
        if not isinstance(week.get("entries"), list):
            raise CollectionError("invalid_entries")
        for entry in week["entries"]:
            only_fields(entry, ENTRY_FIELDS)
    try:
        validate_feed(feed)
        # The Swift snapshot reader rejects explicit ports, including :443.
        # Do not publish a URL the shared collector accepts but the app drops.
        for week in feed["weeks"]:
            if urlsplit(week["postURL"]).port is not None:
                raise CollectionError("invalid_post_url")
        return feed
    except (ValueError, TypeError, OverflowError):
        raise CollectionError("invalid_feed") from None


def encode(document):
    return (json.dumps(document, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CollectionError("duplicate_json_key")
        result[key] = value
    return result


def reject_constant(_value):
    raise CollectionError("invalid_json")


def load_reviewed(path):
    with Path(path).open("rb") as handle:
        data = handle.read(MAX_PUBLISHED + 1)
    if len(data) > MAX_PUBLISHED:
        raise CollectionError("feed_too_large")
    try:
        return json.loads(data, object_pairs_hook=unique_object, parse_constant=reject_constant)
    except (ValueError, UnicodeDecodeError):
        raise CollectionError("invalid_json") from None


def build_status(feed, now):
    current = monday_of(now.astimezone(KST).date())
    upcoming = current + timedelta(days=7)
    accounts = []
    for username, cafeteria_id in ACCOUNTS.items():
        weeks = []
        for week in sorted(feed["weeks"], key=lambda value: value["monday"], reverse=True):
            if week["username"] != username:
                continue
            dates = sorted({entry["date"] for entry in week["entries"]})
            weeks.append({
                "monday": week["monday"], "firstMenuDate": dates[0], "lastMenuDate": dates[-1],
                "menuDates": dates, "verifiedAt": week["verifiedAt"], "postURL": week["postURL"],
                "scope": week["scope"], "entryCount": len(week["entries"]),
            })
        accounts.append({
            "username": username, "cafeteriaID": cafeteria_id, "name": NAMES[cafeteria_id],
            "currentWeekAvailable": any(week["monday"] == current.isoformat() for week in weeks),
            "nextWeekAvailable": any(week["monday"] == upcoming.isoformat() for week in weeks),
            "weeks": weeks,
        })
    return {
        "schemaVersion": 1,
        "publicationMode": "reviewed-upload",
        "processingMethod": "manual",
        "publishedAt": iso_now(now),
        "currentWeekMonday": current.isoformat(),
        "nextWeekMonday": upcoming.isoformat(),
        "accounts": accounts,
    }


def display_time(value):
    return timestamp(value).astimezone(KST).strftime("%Y-%m-%d %H:%M (한국 시간)")


def render_index(status):
    cards = []
    for account in status["accounts"]:
        latest = account["weeks"][0] if account["weeks"] else None
        if latest:
            available = (
                f'<p class="range">{escape(latest["firstMenuDate"])} ~ '
                f'{escape(latest["lastMenuDate"])}</p>'
                f'<p>{escape(latest["scope"])}</p>'
                f'<p class="small">식단이 있는 날짜: {escape(", ".join(latest["menuDates"]))}</p>'
                f'<p class="small">식단 확인: {escape(display_time(latest["verifiedAt"]))}</p>'
                f'<a href="{escape(latest["postURL"], quote=True)}" rel="noopener noreferrer">원본 식단 게시물 보기</a>'
            )
        else:
            available = '<p class="range">아직 확인된 식단이 없어요.</p>'
        current_label = "업로드됨" if account["currentWeekAvailable"] else "아직 업로드되지 않았어요"
        next_label = "업로드됨" if account["nextWeekAvailable"] else "아직 업로드되지 않았어요"
        cards.append(
            '<article>'
            f'<h2>{escape(account["name"])}</h2><p class="account">@{escape(account["username"])}</p>'
            f'<p class="label">가장 최근에 확인된 식단</p>{available}'
            f'<div class="availability"><p>이번 주 ({escape(status["currentWeekMonday"])} 시작): {current_label}</p>'
            f'<p>다음 주 ({escape(status["nextWeekMonday"])} 시작): {next_label}</p></div>'
            '</article>'
        )
    return f'''<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>명지밥 · 자연캠퍼스 식단</title>
  <style>
    :root {{ color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; color: #173c30; background: #f7f6ef; }}
    body {{ max-width: 900px; margin: auto; padding: 36px 20px; line-height: 1.65; }}
    h1 {{ font-size: 2.3rem; margin-bottom: 4px; }} h2 {{ margin: 0; font-size: 1.25rem; }}
    a {{ color: #205c45; text-underline-offset: 3px; }}
    .intro {{ max-width: 650px; }} .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr)); gap: 18px; margin-top: 26px; }}
    article {{ background: white; padding: 24px; border: 1px solid #dfe7da; border-radius: 20px; }}
    article p {{ margin: 9px 0; }} .account, .small, footer {{ color: #506259; font-size: .85rem; overflow-wrap: anywhere; }}
    .label {{ font-size: .85rem; padding-top: 12px; }} .range {{ font-weight: 700; }}
    .availability {{ border-top: 1px solid #e6ebe1; margin-top: 18px; padding-top: 9px; font-size: .85rem; }}
    footer {{ margin-top: 28px; }}
  </style>
</head>
<body>
  <header><h1>명지밥</h1><p>명지대학교 자연캠퍼스 · 확인한 식단을 함께</p></header>
  <div class="intro">
    <p><strong>식단 사진을 확인해 등록하는 방식이에요.</strong> 주 1회 예약 작업이 인스타그램을 열어 날짜와 메뉴를 확인하고, 확인된 식단을 앱에 전달해요. 접속 제한이나 미게시로 확인하지 못한 자료는 채우지 않아요.</p>
    <p><strong>게시 기준: {escape(display_time(status["publishedAt"]))}</strong><br>아래의 이번 주·다음 주 표시는 이 게시 시점 기준이에요. 이용하려는 날짜와 식단 날짜를 확인해 주세요.</p>
    <p>식단이 없는 날짜는 아직 확인되지 않은 상태예요. 휴무를 뜻하지 않으며, 지난 식단을 이번 주 식단으로 옮기지 않아요.</p>
  </div>
  <main class="grid">{"".join(cards)}</main>
  <footer>
    <p>게시 파일 생성: {escape(display_time(status["publishedAt"]))}<br>위 게시 시각과 각 식단의 확인 시각은 달라요. 식단 날짜와 확인 시각은 원래 기록을 유지해요.</p>
    <p><a href="meals.json">앱용 식단 데이터</a> · <a href="status.json">업로드 현황</a></p>
  </footer>
</body>
</html>
'''


def publish_reviewed(input_path, output_dir, *, now=None):
    """Validate/render all output before touching an existing published directory."""
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise CollectionError("invalid_publication_time")
    feed = validate_reviewed_feed(load_reviewed(input_path))
    meals = encode(feed)
    if len(meals) > MAX_PUBLISHED:
        raise CollectionError("feed_too_large")
    status = build_status(feed, now)
    documents = {
        "meals.json": meals,
        "status.json": encode(status),
        "index.html": render_index(status).encode("utf-8"),
    }
    if any(len(content) > MAX_PUBLISHED for content in documents.values()):
        raise CollectionError("publication_too_large")
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".reviewed-", dir=output) as staging:
        staging_path = Path(staging)
        for name, content in documents.items():
            (staging_path / name).write_bytes(content)
        for name in documents:
            (staging_path / name).replace(output / name)
    return status


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="Reviewed menu JSON")
    parser.add_argument("--output-dir", type=Path, default=Path("_site"))
    args = parser.parse_args(argv)
    try:
        status = publish_reviewed(args.input, args.output_dir)
        print(json.dumps({"event": "reviewed_feed_published", "publishedAt": status["publishedAt"],
                          "processingMethod": "manual"}, ensure_ascii=False))
        return 0
    except (CollectionError, ValueError, KeyError, TypeError, OSError) as error:
        # Keep source contents and local paths out of public workflow logs.
        code = str(error) if isinstance(error, CollectionError) else "invalid_data_or_local_io"
        print(json.dumps({"event": "reviewed_publication_failed", "code": code}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
