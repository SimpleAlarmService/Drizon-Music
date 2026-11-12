#!/usr/bin/env bash
# One-time (and after-update) setup of the embedded Python/yt-dlp runtime. Run on a Mac:
#
#   ./ios/scripts/setup_python.sh
#
# 1. downloads BeeWare's Python-Apple-support (CPython built for iOS) -> ios/Python.xcframework
# 2. installs yt-dlp + the matching yt-dlp-ejs + certifi (all pure Python) -> ios/PythonApp/app_packages
# 3. wires everything into Runner.xcodeproj (idempotent)
#
# Env overrides: PY_MINOR (default 3.13; yt-dlp needs >= 3.11), SUPPORT_URL (direct tarball URL).
set -euo pipefail
cd "$(dirname "$0")/.."   # -> ios/

PY_MINOR="${PY_MINOR:-3.13}"
PACKAGES_DIR="PythonApp/app_packages"

if [ ! -d Python.xcframework ]; then
  URL="${SUPPORT_URL:-}"
  if [ -z "$URL" ]; then
    echo "→ Looking up latest Python ${PY_MINOR} iOS support package…"
    URL=$(curl -fsSL "https://api.github.com/repos/beeware/Python-Apple-support/releases?per_page=30" |
      PY_MINOR="$PY_MINOR" python3 -c '
import json, os, re, sys
pat = re.compile(r"Python-%s-iOS-support\..*\.tar\.gz" % re.escape(os.environ["PY_MINOR"]))
for release in json.load(sys.stdin):
    for asset in release["assets"]:
        if pat.fullmatch(asset["name"]):
            print(asset["browser_download_url"]); sys.exit(0)
sys.exit("No matching iOS support package found; set SUPPORT_URL")')
  fi
  echo "→ Downloading $URL"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fL "$URL" -o "$TMP/support.tar.gz"
  tar -xzf "$TMP/support.tar.gz" -C "$TMP"
  mv "$TMP/Python.xcframework" Python.xcframework
else
  echo "→ Python.xcframework already present, skipping download"
fi

echo "→ Installing yt-dlp into $PACKAGES_DIR"
mkdir -p "$PACKAGES_DIR"
python3 -m pip install --quiet --upgrade --no-deps --target "$PACKAGES_DIR" yt-dlp certifi

# yt-dlp pins the exact yt-dlp-ejs (JS challenge solver scripts) it was tested with.
EJS_PIN=$(python3 - "$PACKAGES_DIR" <<'PY'
import importlib.metadata as md, sys
for dist in md.distributions(path=[sys.argv[1]]):
    if dist.metadata["Name"].lower().replace("_", "-") == "yt-dlp":
        for req in dist.requires or []:
            if req.startswith("yt-dlp-ejs==") and "extra == 'default'" in req:
                print(req.split(";")[0].strip())
PY
)
python3 -m pip install --quiet --upgrade --no-deps --target "$PACKAGES_DIR" "${EJS_PIN:-yt-dlp-ejs}"

# pip drops console scripts and bytecode we neither need nor want in the bundle.
rm -rf "$PACKAGES_DIR/bin"
find "$PACKAGES_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} +

echo "→ Patching Runner.xcodeproj"
ruby scripts/patch_xcodeproj.rb

echo
echo "Done. Next:  flutter pub get && flutter run   (real device or simulator)"
