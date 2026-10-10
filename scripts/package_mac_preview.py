#!/usr/bin/env python3
"""Wrap the compiled SwiftUI executable for local Mac UI inspection."""
from pathlib import Path
import plistlib
import json
import shutil
import sys

root = Path(__file__).resolve().parents[1]
executable = Path(sys.argv[1]).resolve()
if not executable.is_file():
    raise SystemExit("Pass the compiled MyongjiMealsPreview executable path.")
resource_bundle = executable.parent / "MyongjiMeals_MealCore.bundle"
if not resource_bundle.is_dir():
    raise SystemExit("The compiled MealCore resource bundle must be beside the executable.")
app = root / "output" / "명지밥 미리보기.app"
contents = app / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(parents=True, exist_ok=True)
binary = contents / "MacOS" / "MyongjiMealsPreview"
replacement = binary.with_suffix(".next")
shutil.copyfile(executable, replacement)
replacement.chmod(0o755)
replacement.replace(binary)
shutil.copyfile(root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", contents / "Resources/AppIcon.png")
shutil.copytree(resource_bundle, contents / "Resources" / resource_bundle.name,
                dirs_exist_ok=True, copy_function=shutil.copyfile)
feed_config = json.loads((root / "App/MealFeedConfiguration.json").read_text())
with (contents / "Info.plist").open("wb") as handle:
    plistlib.dump({
        "CFBundleName": "명지밥 미리보기",
        "CFBundleDisplayName": "명지밥 미리보기",
        "CFBundleIdentifier": "kr.mjubap.preview",
        "CFBundleExecutable": "MyongjiMealsPreview",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleIconFile": "AppIcon.png",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
        "MJUMealFeedURL": feed_config["feedURL"]
    }, handle)
print(app)
