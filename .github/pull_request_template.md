## What and why

<!-- One paragraph: the change and the reason. Link the issue. -->

## Proof

- [ ] `tool/check.sh` passes locally. Paste the last lines:

```
<paste the tail of tool/check.sh>
```

- [ ] Behaviour change → a test or a scenario (`test/scenarios/*.yaml`) that
      fails without the change. Names:
- [ ] Bug fix → a regression scenario/test **and** a mutant in
      `tool/mutants.yaml`; `dart run tool/mutation_smoke.dart <id>` kills it.
- [ ] Public API change → `test/guardrails/goldens/public_api.txt` diff is
      intended and every changed symbol is in `CHANGELOG.md`.
- [ ] Deprecations follow the policy (`Use X. Removed in 2.0.0.`) and are
      listed under `### Deprecated`.
- [ ] Docs: dartdoc on new public members, README excerpts updated in
      `example/lib/readme/`, CHANGELOG section.
- [ ] No new `guardrail:allow` without a reason; baselines only shrank.
- [ ] UI change → tried on a device (which, what was checked):
