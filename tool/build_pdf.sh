#!/usr/bin/env bash
# Renders a docs/ HTML page (A4 landscape pages) to PDF with headless Chrome
# and fails if any page's content overflows (the page sets data-overflow).
#
#   tool/build_pdf.sh docs/guardrails/guardrails_evals_playbook.html [out.pdf]
set -euo pipefail
html="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="${2:-$(dirname "$html")/Guardrails_and_Evals_Playbook.pdf}"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$chrome" ] || chrome="$(command -v google-chrome || command -v chromium)"
overflow="$("$chrome" --headless=new --disable-gpu --virtual-time-budget=4000 \
  --window-size=1123,794 --dump-dom "file://$html" 2>/dev/null |
  sed -n 's/.*data-overflow="\([^"]*\)".*/\1/p')"
if [ -n "$overflow" ]; then echo "pages overflow: $overflow"; exit 1; fi
"$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
  --virtual-time-budget=4000 --print-to-pdf="$out" "file://$html" 2>/dev/null
echo "wrote $out"
