#!/usr/bin/env python3
"""Patch the generated Runner.xcodeproj/project.pbxproj for TrollStore builds."""
import argparse
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--pbxproj", required=True)
ap.add_argument("--bundle-id", required=True)
ap.add_argument("--deployment-target", default="15.0")
args = ap.parse_args()

path = args.pbxproj
src = open(path, encoding="utf-8").read()

# Bundle id: every configuration (Debug / Release / Profile) gets the same id.
src, n_bundle = re.subn(
    r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;",
    f"PRODUCT_BUNDLE_IDENTIFIER = {args.bundle_id};",
    src,
)

# iOS deployment target: project-level and target-level.
src, n_target = re.subn(
    r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[^;]+;",
    f"IPHONEOS_DEPLOYMENT_TARGET = {args.deployment_target};",
    src,
)

# Append the extra build settings right after each bundle-id line, once per
# configuration block. Do it line-wise so we don't disturb pbxproj formatting.
extras = [
    "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;",
    "CODE_SIGNING_ALLOWED = NO;",
    "CODE_SIGNING_REQUIRED = NO;",
    "ENABLE_BITCODE = NO;",
    "CODE_SIGN_IDENTITY = \"\";",
]

out_lines = []
in_build_settings = False
for line in src.splitlines(keepends=True):
    stripped = line.strip()
    if stripped == "buildSettings = {":
        in_build_settings = True
        out_lines.append(line)
        continue
    if in_build_settings and stripped == "};":
        in_build_settings = False
        out_lines.append(line)
        continue

    out_lines.append(line)

    if in_build_settings and "PRODUCT_BUNDLE_IDENTIFIER" in line:
        indent = line[: len(line) - len(line.lstrip())]
        for extra in extras:
            key = extra.split("=")[0].strip()
            # Avoid duplicates when the script is re-run.
            if not re.search(rf"^\s*{re.escape(key)}\s*=", src, re.M):
                out_lines.append(f"{indent}{extra}\n")

open(path, "w", encoding="utf-8").write("".join(out_lines))

print(f"[pbxproj] bundle id replacements : {n_bundle}")
print(f"[pbxproj] deployment target     : {n_target} -> {args.deployment_target}")
if n_bundle == 0:
    print("[pbxproj] WARNING: no PRODUCT_BUNDLE_IDENTIFIER found", file=sys.stderr)
    sys.exit(1)
