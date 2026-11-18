#!/usr/bin/env bash
# Opt-in: run the quick gate before every commit (skip once with --no-verify).
set -euo pipefail
cd "$(dirname "$0")/.."
hook=.git/hooks/pre-commit
cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
exec tool/check.sh --quick
HOOK
chmod +x "$hook"
echo "Installed $hook"
