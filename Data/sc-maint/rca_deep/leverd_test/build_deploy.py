#!/usr/bin/env python3
"""
Drift-safe builder for the lever-d (H5) procedure-commit test.

The Rev_Mgmt_Default_Pricing_Procedure is CO-OWNED (Marc/Nir) and churns daily.
Deploying a stale 3.4MB snapshot would REVERT concurrent edits. So instead of
shipping the old deploy_v4 blindly, this script injects ONLY the self-contained
RenMaintCOLA element group (element_group.xml) into a FRESH live retrieve.

Usage:
  python3 build_deploy.py <fresh_retrieve.expressionSetDefinition> <element_group.xml> <out_dir>

Produces <out_dir>/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition
+ package.xml, ready for: sf project deploy start --metadata-dir <out_dir> --api-version 67 ...

Aborts if the fresh retrieve ALREADY contains RenMaintCOLA (means a prior deploy
already landed it — re-confirm active-version state before proceeding).
"""
import sys, os, re, shutil

PROC = "Rev_Mgmt_Default_Pricing_Procedure"

def main(fresh, snippet_path, out_dir):
    x = open(fresh, encoding="utf-8").read()
    snippet = open(snippet_path, encoding="utf-8").read()

    if "RenMaintCOLA" in x:
        sys.exit("ABORT: fresh retrieve ALREADY contains RenMaintCOLA. "
                 "A prior deploy landed it — confirm the ACTIVE version state and whether it is inert before re-deploying.")

    # Deterministic anchor: append the group at the END of the <steps> sibling list, i.e. immediately
    # after the LAST </steps>. Execution order is governed by sequenceNumber/parentStep (the group is a
    # self-contained ListGroup at seq 41), NOT file position — so end-of-list is correct and unique.
    close = "</steps>"
    last = x.rfind(close)
    if last < 0:
        sys.exit("ABORT: no </steps> found — not a recognizable expressionSetDefinition.")
    insert_at = last + len(close)
    # consume the trailing newline after the last </steps> so indentation stays clean
    if x[insert_at:insert_at+1] == "\n":
        insert_at += 1

    snip = snippet if snippet.endswith("\n") else snippet + "\n"
    rebuilt = x[:insert_at] + snip + x[insert_at:]

    # sanity: exactly the 4 new steps were added
    if rebuilt.count("<steps>") != x.count("<steps>") + 4:
        sys.exit("ABORT: injected step count != +4; refusing to write a malformed package.")
    for nm in ("RenMaintCOLACommit", "RenMaintCOLAFilter", "RenMaintCOLAInput", "RenMaintCOLANet"):
        if rebuilt.count(f"<name>{nm}</name>") != 1:
            sys.exit(f"ABORT: element {nm} not present exactly once after injection.")

    esd = os.path.join(out_dir, "expressionSetDefinition")
    os.makedirs(esd, exist_ok=True)
    open(os.path.join(esd, f"{PROC}.expressionSetDefinition"), "w", encoding="utf-8").write(rebuilt)
    open(os.path.join(out_dir, "package.xml"), "w", encoding="utf-8").write(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        f'    <types><members>{PROC}</members><name>ExpressionSetDefinition</name></types>\n'
        '    <version>67.0</version>\n</Package>\n')
    print(f"OK: wrote {esd}/{PROC}.expressionSetDefinition")
    print(f"    base steps={x.count('<steps>')}  ->  rebuilt steps={rebuilt.count('<steps>')} (+4)")
    print(f"    appended group at end of steps list (byte {insert_at})")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
