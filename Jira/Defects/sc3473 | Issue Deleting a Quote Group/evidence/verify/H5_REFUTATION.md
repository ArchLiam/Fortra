# H5-hardware-group-software-semantics — REFUTED (data-forensics lens, FortraUAT live)

## Claim
Group is HW-type (Hardware_Group_Type__c=True) with Hardware__c stamped onto SOFTWARE member lines
(Model__c=null, Hardware_Pricing_Applied=False); native HW-group teardown looks up a hardware-derived
key (group hardware / P-group / group-number) that is absent for software lines -> Map.get(key).toString() NPE.

## Decisive live queries (FortraUAT, read-only)
Q1 H5_all_hwtype_groups_keys.json: 25 QuoteLineGroup rows with Hardware_Group_Type__c=True.
   - Group_Number_List__c = NULL on ALL 25 (incl. failing Test HW1). The "GrpNum null while line says Group 700"
     mismatch H5 leans on is UNIVERSAL, not unique. Cannot be the discriminating null.
   - P_Group_List__c varies (P05/P10/P20/P40/P60/None); failing=P20 is unremarkable, shared shape with others.
   - Many HW-type groups are Accepted (same lock-state as failing quote).

Q2 H5_hwgroup_member_lines.json (member QLIs of all HW-type groups, 17 groups have lines):
   - The H5 condition "HW-type group + Hardware__c stamped on a software line, Model__c=null,
     Hardware_Pricing_Applied=False" is present on >=9 OTHER groups:
       7Gsr (Accepted, OneTime, 5250 Integrator), 091GD (Accepted, OneTime, Powertech SIEM),
       093WX (Accepted, OneTime, 5250 Integrator), 096J7 (Accepted, TermDefined x4, Powertech Authority),
       096fh (Accepted, TermDefined), 096iv (Accepted, TermDefined),
       077ZR (Draft, TermDefined, Abstract), 090IX (Draft, TermDefined), 092Qn (Draft, TermDefined x2).
   - If the native HW-key-lookup NPE were the cause, these Accepted HW-stamped groups would fail identically.
   - The ONLY thing unique to failing group 097of "Test HW1": mixed selling-model set
     {OneTime, TermDefined} WITHIN the group. Every other HW-stamped group is single-SM (all-OneTime OR
     all-TermDefined). => the HARDWARE dimension is held constant across the comparison set and does not
     discriminate; the SM-MIX does (supports H1, not H5).

Q3 qli_attrmappings.txt (SalesTransactionContextExt_v2 QLI node, live): the only hardware fields mapped
   into the native pricing context are QLI.Hardware__c (Id) and QLI.Hardware_ID__c -- present on the
   failing AND the comparison lines alike. The group-level Hardware.P_Group_List__c / Group_Number_List__c
   that H5's mechanism keys on are NOT mapped into the context at all (nodes_custom.txt: 0 custom nodes;
   quote_nodemappings.txt: no hardware mapping at group/quote node). The native engine has no plumbing to
   build a teardown map keyed on the group's P-group/group-number. Hardware__c is a CUSTOM object the
   native RLM engine does not model.

Q4 Mission C AUTOMATION_MAP.md (live triggers): QuoteLineGroupTrigger is after-update ONLY (dormant on
   delete); custom hardware Apex (QLITriggerHandler.handleHardwareLinking) only fires when QuoteLineGroupId
   CHANGES on a line and is null-guarded. No custom hardware code runs on the grouped-line DELETE path, so
   the custom hardware layer cannot emit the Java Map NPE either.

## Limitation (honest)
None of the Accepted HW-stamped comparison quotes have ungrouped survivors
(H5_comparison_quote_lines.json: ungrouped=0 for all), so none is a FULL delete+survivor-reprice twin.
H5's mechanism is teardown-of-the-group-itself (fires regardless of survivors), so this does not rescue H5,
but a 100% identical delete repro twin (HW-stamped + ungrouped survivors + single SM) does not exist in the
data to slam the door by reproduction. Settling that requires a live group-delete with debug log (DML, out of scope).

## Verdict
REFUTED. The hardware-group/software-stamping condition is necessary-but-not-sufficient and is shared by
>=9 other groups (several Accepted). Group_Number_List__c=null is universal. The group's hardware key fields
are not even mapped into the native context. The unique discriminator is the in-group OneTime+TermDefined
selling-model MIX, not the hardware dimension. H5's specific Java-Map-on-hardware-key mechanism is unsupported.
