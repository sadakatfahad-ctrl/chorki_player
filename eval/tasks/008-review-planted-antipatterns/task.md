# Review task

The last commit (`git show HEAD`) is a pull request from a new contributor.
Review it against CLAUDE.md. Do not fix anything. Write every problem you
find to `eval_out/review.json` as a JSON list of
`{"file": "lib/...", "line": <int>, "issue": "<one sentence>"}`, using line
numbers in the new version of the file. List only real problems.
