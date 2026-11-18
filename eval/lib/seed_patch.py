#!/usr/bin/env python3
"""Builds a task's baseline.patch: the diff from today's tree to a seeded one.

A seeded task starts from a state that does not exist in git (a bug put
back, docs taken out, a refactor undone). Prepare that state in a scratch
directory with the same relative paths, then:

    python3 eval/lib/seed_patch.py eval/tasks/NNN-slug/baseline.patch \
        --seed /tmp/seed lib/src/a.dart test/guardrails/baselines.json \
        --delete lib/src/new_file.dart test/new_file_test.dart

Each listed path is diffed from the working tree (a/) to the seed (b/);
--delete paths are removed by the patch. The result is checked with
`git apply --check` and printed with a summary. Re-run it whenever the files
it touches change, or the patch stops applying (eval/selftest does this).
"""
import argparse
import difflib
import pathlib
import subprocess
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--seed", required=True, help="directory with seeded files")
    ap.add_argument("paths", nargs="*", help="files to diff against the seed")
    ap.add_argument("--delete", nargs="*", default=[], help="files to delete")
    args = ap.parse_args()

    seed = pathlib.Path(args.seed)
    out: list[str] = []
    for path in args.paths:
        before = pathlib.Path(path).read_text().splitlines(keepends=True)
        after = (seed / path).read_text().splitlines(keepends=True)
        diff = list(difflib.unified_diff(before, after, f"a/{path}", f"b/{path}"))
        if not diff:
            print(f"  unchanged: {path}", file=sys.stderr)
            continue
        out.append(f"diff --git a/{path} b/{path}\n")
        out.extend(diff)
    for path in args.delete:
        before = pathlib.Path(path).read_text().splitlines(keepends=True)
        out.append(f"diff --git a/{path} b/{path}\ndeleted file mode 100644\n")
        out.extend(difflib.unified_diff(before, [], f"a/{path}", "/dev/null"))

    text = "".join(out)
    pathlib.Path(args.out).write_text(text)
    check = subprocess.run(["git", "apply", "--check", args.out])
    files = text.count("diff --git ")
    print(f"{args.out}: {files} files, applies: {check.returncode == 0}")
    return check.returncode


if __name__ == "__main__":
    sys.exit(main())
