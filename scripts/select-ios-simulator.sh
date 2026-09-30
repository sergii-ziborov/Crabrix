#!/usr/bin/env bash
set -euo pipefail

# Xcode runner images change their preinstalled iPhone models independently of
# the Xcode version. Choose an available iOS simulator from the actual image.
xcrun simctl list devices available -j | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" not in runtime:
        continue
    phones = [
        device for device in devices[runtime]
        if device.get("isAvailable")
        and ".iPhone-" in device.get("deviceTypeIdentifier", "")
    ]
    if not phones:
        continue
    selected = sorted(phones, key=lambda device: (
        "Pro" not in device["deviceTypeIdentifier"], device["name"]
    ))[0]
    print("CI simulator: {} ({})".format(selected["name"], runtime), file=sys.stderr)
    print(selected["udid"])
    sys.exit(0)
print("No available iPhone simulator is installed", file=sys.stderr)
sys.exit(1)
'
