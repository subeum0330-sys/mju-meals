#!/usr/bin/env python3
"""Set the public meal JSON URL for the next iOS/preview build. No secrets."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
from urllib.parse import urlsplit

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("url", help="HTTPS URL of the published meals.json; use --clear to disconnect", nargs="?")
parser.add_argument("--clear", action="store_true")
args = parser.parse_args()
if args.clear:
    if args.url:
        parser.error("Pass either a URL or --clear.")
    value = ""
else:
    value = (args.url or "").strip()
    parts = urlsplit(value)
    if (parts.scheme != "https" or not parts.hostname or parts.username or parts.password
            or parts.query or parts.fragment or any(c.isspace() for c in value)):
        parser.error("Use a public HTTPS JSON URL without credentials, query parameters, or fragments.")
    try:
        port = parts.port
    except ValueError:
        parser.error("Invalid port.")
    if port not in (None, 443):
        parser.error("Use the standard HTTPS port.")

(root / "App/MealFeedConfiguration.json").write_text(
    json.dumps({"feedURL": value}, ensure_ascii=False, indent=2) + "\n")
subprocess.run([sys.executable, str(root / "scripts/generate_xcode_project.py")], check=True)
print("Feed URL configured. Rebuild the app to apply it." if value else "Automatic feed disconnected.")
