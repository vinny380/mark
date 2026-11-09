#!/bin/bash
# Shrinks the bundled Geist fonts to the characters Mark needs (Latin + punctuation, currency, arrows).
# Anything else (CJK, emoji, symbols) falls back to the system font automatically.
# Needs fonttools at build time only: python3 -m venv /tmp/v && /tmp/v/bin/pip install fonttools
# Usage: PYFTSUBSET=/tmp/v/bin/pyftsubset scripts/subset-fonts.sh   (safe to re-run)
set -euo pipefail
cd "$(dirname "$0")/../Resources/Fonts"
UNICODES="U+0020-007E,U+00A0-017F,U+0192,U+02C6-02DD,U+2000-206F,U+20A0-20BF,U+2100-2122,U+2190-2199,U+2200-2265"
for f in *.otf; do
  "${PYFTSUBSET:-pyftsubset}" "$f" --unicodes="$UNICODES" --layout-features='*' --no-hinting --output-file="$f.tmp"
  mv "$f.tmp" "$f"
done
ls -l *.otf
