#!/usr/bin/env bash
# Builds the standalone Element X app with xtool on Linux (or macOS): resources bundle, then `xtool dev build`.
# Extra arguments go to xtool (e.g. --sign --ipa --udid <UDID>). ACTOOL / XTOOL_ACTOOL: the asset catalog compiler.
set -euo pipefail
cd "$(dirname "$0")"
../Tools/Scripts/build-resources-bundle.sh .resources
# XTOOL may be a command with arguments (e.g. a wrapper environment and the xtool binary).
exec ${XTOOL:-xtool} dev build "$@"
