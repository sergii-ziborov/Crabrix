#!/usr/bin/env python3
"""Capture the current iPhone/iPad Store, README, and site frames from one app build.

The script clones temporary Simulators, so existing learner data is untouched.
It records both a fresh Academy install and the offline transition path for an
existing learner. Run it with the Release Simulator .app being documented.
"""

import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageStat


BUNDLE_ID = "com.sergiiziborov.Crabrix"
ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "docs/app-store/screenshots"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, capture_output=capture)
    return result.stdout.strip() if capture else ""


def device_for(name: str) -> str:
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j", capture=True))
    for runtime, entries in devices["devices"].items():
        for device in entries:
            if device["name"] == name:
                return device["udid"]
    raise SystemExit(f"No available Simulator template named {name!r}")


def boot_and_install(udid: str, app: Path) -> None:
    run("xcrun", "simctl", "boot", udid)
    run("xcrun", "simctl", "bootstatus", udid, "-b")
    # Clones can carry an earlier screenshot app. Remove only that app's
    # container; the source Simulator and its learner data are untouched.
    subprocess.run(("xcrun", "simctl", "uninstall", udid, BUNDLE_ID),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    run("xcrun", "simctl", "ui", udid, "appearance", "dark")
    run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
        "--batteryState", "discharging", "--batteryLevel", "100", "--wifiMode", "active",
        "--wifiBars", "3")
    run("xcrun", "simctl", "install", udid, str(app))


def launch(udid: str, *arguments: str) -> None:
    subprocess.run(("xcrun", "simctl", "terminate", udid, BUNDLE_ID),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    run("xcrun", "simctl", "launch", udid, BUNDLE_ID, *arguments)


def wait_for_baseline(udid: str, count: int) -> None:
    container = Path(run("xcrun", "simctl", "get_app_container", udid, BUNDLE_ID,
                         "data", capture=True))
    marker = container / "Library/Application Support/Crabrix/Courses/baseline-activation-v1.json"
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        if marker.exists():
            data = json.loads(marker.read_text())
            if len(data.get("courseDigests", {})) == count:
                time.sleep(4)  # Let SwiftUI finish the Academy transition.
                return
        time.sleep(1)
    raise RuntimeError(f"Academy baseline did not activate {count} courses on {udid}")


def shot(udid: str, destination: Path, *arguments: str) -> None:
    launch(udid, *arguments)
    # Route pushes and editor syntax painting happen after Academy loads.
    time.sleep(12 if "-CrabrixLearn" in arguments
               or any(value.startswith("--crabrix-auto-") for value in arguments) else 6)
    destination.parent.mkdir(parents=True, exist_ok=True)
    pending = destination.with_name(destination.stem + ".pending.png")
    try:
        run("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(pending))
        # Simulator PNGs carry an opaque alpha channel. App Store Connect
        # rejects alpha channels even when every pixel is fully opaque.
        with Image.open(pending) as captured:
            if "A" in captured.getbands() and captured.getchannel("A").getextrema() != (255, 255):
                raise RuntimeError(f"Screenshot has translucent pixels: {destination}")
            rgb = captured.convert("RGB")
        # A launch can return before SwiftUI paints anything below the status
        # bar. Reject that frame before replacing a valid prior capture.
        app_area = rgb.crop((0, rgb.height // 10, rgb.width, rgb.height * 9 // 10))
        if max(ImageStat.Stat(app_area).stddev) < 5:
            raise RuntimeError(f"Screenshot is blank or still launching: {destination}")
        rgb.save(pending, format="PNG")
        pending.replace(destination)
    finally:
        pending.unlink(missing_ok=True)
    print(destination.relative_to(ROOT), flush=True)


def capture_set(app: Path, template: str, folder: str, frames: list[tuple[str, tuple[str, ...]]]) -> None:
    # Cloning a previously initialized template avoids a long first
    # boot migration on Macs with several installed Simulator runtimes.
    udid = run("xcrun", "simctl", "clone", device_for(template),
               f"Crabrix RC screenshots {folder}", capture=True)
    try:
        boot_and_install(udid, app)
        launch(udid, "-CrabrixTab", "learn")
        wait_for_baseline(udid, 0)
        shot(udid, STORE / folder / "03-learn.png", "-CrabrixTab", "learn")

        # A separate app container installs all seven signed transition packs.
        # UserDefaults sees the appearance argument as a legacy key.
        subprocess.run(("xcrun", "simctl", "uninstall", udid, BUNDLE_ID),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        run("xcrun", "simctl", "install", udid, str(app))
        launch(udid, "-crabrix.appearance", "dark", "-CrabrixTab", "learn")
        wait_for_baseline(udid, 7)
        if folder == "ipad-13":
            # On the iPad Simulator, the verified pack marker can precede the
            # first complete SwiftUI catalog render by several seconds.
            time.sleep(45)
        for name, arguments in frames:
            shot(udid, STORE / folder / name, *arguments)
    finally:
        subprocess.run(("xcrun", "simctl", "shutdown", udid), check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run("xcrun", "simctl", "delete", udid)


def copy_for_docs() -> None:
    sources = {
        "iphone-build.png": "iphone-6.9/01-build.png",
        "iphone-projects.png": "iphone-6.9/02-projects.png",
        "iphone-learn.png": "iphone-6.9/03-learn.png",
        "iphone-my-courses.png": "iphone-6.9/09-my-courses.png",
        "iphone-academy.png": "iphone-6.9/03-learn.png",
        "iphone-library.png": "iphone-6.9/07-library.png",
        "iphone-examples.png": "iphone-6.9/07-library.png",
        "iphone-example-detail.png": "iphone-6.9/10-example-detail.png",
        "iphone-settings.png": "iphone-6.9/08-settings.png",
        "iphone-cyberpunk-settings.png": "iphone-6.9/08-settings.png",
        "ipad-build.png": "ipad-13/01-build.png",
        "ipad-learn.png": "ipad-13/03-learn.png",
        "ipad-my-courses.png": "ipad-13/07-my-courses.png",
        "ipad-library.png": "ipad-13/06-library.png",
    }
    for name, source in sources.items():
        shutil.copyfile(STORE / source, ROOT / "docs/screenshots" / name)
        shutil.copyfile(STORE / source, ROOT / "site/screenshots" / name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Release Simulator Crabrix.app")
    parser.add_argument("--iphone-template", default="Crabrix Shots 6.9",
                        help="existing iPhone 6.9-inch Simulator to clone")
    parser.add_argument("--ipad-template", default="Crabrix Dev iPad",
                        help="existing iPad 13-inch Simulator to clone")
    args = parser.parse_args()
    app = args.app.resolve()
    if not (app / "Info.plist").is_file():
        parser.error(f"not an app bundle: {app}")
    capture_set(app, args.iphone_template, "iphone-6.9", [
        ("01-build.png", ("--crabrix-auto-borrow",)),
        ("02-projects.png", ("-CrabrixTab", "projects")),
        ("09-my-courses.png", ("-CrabrixTab", "learn")),
        ("04-course.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "basics")),
        ("05-lesson.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "borrowing")),
        ("06-profile.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "profile")),
        ("07-library.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "examples")),
        ("10-example-detail.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "example:ferris-pixel-art")),
        ("08-settings.png", ("-CrabrixTab", "settings", "-crabrix.appearance", "cyberpunk")),
    ])
    capture_set(app, args.ipad_template, "ipad-13", [
        ("01-build.png", ("--crabrix-auto-multifile",)),
        ("02-projects.png", ("-CrabrixTab", "projects")),
        ("07-my-courses.png", ("-CrabrixTab", "learn")),
        ("04-lesson.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "borrowing")),
        ("05-profile.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "profile")),
        ("06-library.png", ("-CrabrixTab", "learn", "-CrabrixLearn", "examples")),
    ])
    copy_for_docs()


if __name__ == "__main__":
    main()
