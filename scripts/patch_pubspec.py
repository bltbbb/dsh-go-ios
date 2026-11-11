#!/usr/bin/env python3
"""iOS-facing pubspec checks + a platform-difference report.

Kept deliberately conservative: we never rewrite upstream Dart source, so the
patch keeps working when upstream changes.
"""
import argparse
import datetime
import os
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--app-dir", required=True)
args = ap.parse_args()

app_dir = os.path.abspath(args.app_dir)
pubspec = os.path.join(app_dir, "pubspec.yaml")
src = open(pubspec, encoding="utf-8").read()
out_dir = os.environ.get("OUT_DIR", os.path.join(os.path.dirname(app_dir), "..", "out"))
os.makedirs(out_dir, exist_ok=True)

# --- CFBundleVersion needs a +build suffix -----------------------------------
m = re.search(r"^version:\s*(\S+)", src, re.M)
if m:
    version = m.group(1)
    if "+" not in version:
        new = f"version: {version}+1"
        src = src[: m.start()] + new + src[m.end() :]
        open(pubspec, "w", encoding="utf-8").write(src)
        print(f"[pubspec] added build number: {version} -> {version}+1")
    else:
        print(f"[pubspec] version: {version}")
else:
    print("[pubspec] WARNING: version field not found", file=sys.stderr)

# --- scan Dart sources -------------------------------------------------------
roots = [os.path.join(app_dir, "lib"), os.path.join(os.path.dirname(app_dir), "packages")]
dart_files = []
for root in roots:
    for base, _dirs, files in os.walk(root):
        if any(part in (".dart_tool", "build") for part in base.split(os.sep)):
            continue
        for f in files:
            if f.endswith(".dart"):
                dart_files.append(os.path.join(base, f))

android_refs = []
platform_android = []
platform_ios = []
channels = set()
for p in dart_files:
    text = open(p, encoding="utf-8", errors="replace").read()
    rel = os.path.relpath(p, os.path.dirname(app_dir))
    for n, line in enumerate(text.splitlines(), 1):
        if "webview_flutter_android" in line:
            android_refs.append(f"{rel}:{n}: {line.strip()}")
        if "Platform.isAndroid" in line:
            platform_android.append(f"{rel}:{n}: {line.strip()}")
        if "Platform.isIOS" in line:
            platform_ios.append(f"{rel}:{n}: {line.strip()}")
        for hit in re.findall(r"""(?:MethodChannel|EventChannel)\s*\(\s*['"]([^'"]+)['"]""", line):
            channels.add(hit)

report = [
    "DSH Go iOS platform report",
    "generated: " + datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    f"dart files scanned      : {len(dart_files)}",
    f"Platform.isAndroid uses : {len(platform_android)}",
    f"Platform.isIOS uses     : {len(platform_ios)}",
    f"channel names in Dart   : {len(channels)}",
    "",
    "== direct webview_flutter_android imports ==",
    *(android_refs or ["(none)"]),
    "",
    "== Platform.isAndroid occurrences (iOS takes the else branch) ==",
    *(platform_android[:40] or ["(none)"]),
    "",
    "== channel names ==",
    *(sorted(channels) or ["(none)"]),
    "",
]
report_path = os.path.join(out_dir, "PLATFORM_REPORT.txt")
open(report_path, "w", encoding="utf-8").write("\n".join(report) + "\n")

print(f"[pubspec] report: {report_path}")
if android_refs:
    print("[pubspec] NOTE: Dart directly imports webview_flutter_android;", file=sys.stderr)
    print("          iOS builds use the endorsed WKWebView implementation,", file=sys.stderr)
    print("          review those call sites if a WebView page misbehaves.", file=sys.stderr)
