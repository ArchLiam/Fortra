#!/usr/bin/env python3
# Normalizer for snapshot.sh — reads CSV on stdin, writes a diffable TSV.
#   argv: <outfile> <obj> <recordId>
# Rounds numerics to 4dp (kills float noise); preserves SOQL ORDER BY row order.
import sys, csv
out, obj, rid = sys.argv[1], sys.argv[2], sys.argv[3]
rows = list(csv.reader(sys.stdin))
if len(rows) <= 1:
    open(out, 'w').write(f"# EMPTY snapshot  {obj} {rid}\n"); print(f"0 lines -> {out}"); sys.exit(0)
hdr, body = rows[0], rows[1:]
def norm(v):
    v = (v or '').strip()
    try: return f"{float(v):.4f}".rstrip('0').rstrip('.')
    except (ValueError, TypeError): return v
body = [[norm(c) for c in r] for r in body]
with open(out, 'w', newline='') as fh:
    w = csv.writer(fh, delimiter='\t'); w.writerow(hdr); w.writerows(body)
print(f"{len(body)} lines -> {out}")
