#!/usr/bin/env bash
# Claude Code PostToolUse hook: formats the edited Dart file.
f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')"
case "$f" in
  *.dart) ;;
  *) exit 0 ;;
esac
cd "$(dirname "$0")/../.." || exit 0
rel="${f#"$PWD"/}"
case "$rel" in
  lib/*|test/*|tool/*|example/lib/*) dart format "$rel" >/dev/null ;;
esac
