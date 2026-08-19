#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SITE_PKGS="$(ls -d "$SELF_DIR"/../lib/python3*/site-packages 2>/dev/null | head -1)"
export PYTHONPATH="$SITE_PKGS${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -m SCons.Script.Main "$@"
