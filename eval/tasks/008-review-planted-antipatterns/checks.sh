# Scores the review against planted.json. Recall/precision >= 0.99 pass;
# the exact ratios are printed for the results file.
python3 - "$EVAL_ROOT/eval/tasks/008-review-planted-antipatterns/planted.json" <<'PY'
import json, sys
planted = json.load(open(sys.argv[1]))
try:
    found = json.load(open("eval_out/review.json"))
except Exception as e:
    # No review written: nothing was done, so the whole run scores 0.
    print(f"FAIL made_changes no eval_out/review.json ({e})")
    print("FAIL recall"); print("FAIL precision"); sys.exit()
print("PASS made_changes")
def hit(f, p): return f.get("file") == p["file"] and abs(int(f.get("line", -99)) - p["line"]) <= 3
recall = sum(any(hit(f, p) for f in found) for p in planted) / len(planted)
precision = (sum(any(hit(f, p) for p in planted) for f in found) / len(found)) if found else 0
print(("PASS" if recall >= 0.99 else "FAIL") + f" recall {recall:.2f}")
print(("PASS" if precision >= 0.99 else "FAIL") + f" precision {precision:.2f}")
PY
if [ -z "$(git status --porcelain -- . ':!eval_out' ':!test/eval_hidden')" ]; then echo "PASS no_edits"; else echo "FAIL no_edits"; fi
