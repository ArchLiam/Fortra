#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# Golden-snapshot diff — the wave EXIT-GATE check.
#   Usage:  diff.py <baseline.tsv> <candidate.tsv> [--ignore ColA,ColB]
#   Exit 0 = GATE PASS (0 delta) · Exit 1 = GATE FAIL (delta or line add/remove)
#
# Use --ignore for columns you EXPECT to change (an approved intended delta);
# leave everything else in so an unexpected regression can never hide.
# ─────────────────────────────────────────────────────────────────────────────
import sys, csv

if len(sys.argv) < 3:
    print("usage: diff.py <baseline.tsv> <candidate.tsv> [--ignore col1,col2]"); sys.exit(2)
base, cand = sys.argv[1], sys.argv[2]
ignore = set()
if '--ignore' in sys.argv:
    ignore = set(sys.argv[sys.argv.index('--ignore') + 1].split(','))

def load(p):
    rows = list(csv.reader(open(p), delimiter='\t'))
    if not rows or rows[0][0].startswith('#'):
        return [], []          # empty/marker snapshot
    return rows[0], rows[1:]

hb, rb = load(base)
hc, rc = load(cand)
if hb != hc:
    print("GATE FAIL — HEADER MISMATCH"); print("  baseline:", hb); print("  candidate:", hc); sys.exit(1)

deltas = []
for i in range(max(len(rb), len(rc))):
    lb = rb[i] if i < len(rb) else None
    lc = rc[i] if i < len(rc) else None
    if lb is None: deltas.append((i + 1, "LINE ADDED", " | ".join(lc))); continue
    if lc is None: deltas.append((i + 1, "LINE REMOVED", " | ".join(lb))); continue
    for j, col in enumerate(hb):
        if col in ignore: continue
        vb = lb[j] if j < len(lb) else ''
        vc = lc[j] if j < len(lc) else ''
        if vb != vc: deltas.append((i + 1, col, f"{vb!r} -> {vc!r}"))

if not deltas:
    print(f"GATE PASS — 0 delta  ({len(rb)} lines, {len(hb)} cols)"); sys.exit(0)
print(f"GATE FAIL — {len(deltas)} delta(s)  [ignored cols: {sorted(ignore) or 'none'}]")
for ln, col, d in deltas[:80]:
    print(f"  line {ln:>2}  {col}: {d}")
if len(deltas) > 80: print(f"  … +{len(deltas) - 80} more")
sys.exit(1)
