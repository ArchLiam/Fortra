# H4-null-group-id-summary-collision — REFUTED (data-forensics lens)

## Claim
After deleting the only group, native code does Map.get(survivor.QuoteLineGroupId=null).toString() -> NPE.

## Decisive live evidence (FortraUAT)
Query 01: 7 quotes have EXACTLY ONE group AND ungrouped survivors (the exact shape H4 needs):
  0Q0WC000003AaoT0AS Draft     (4 ungrp survivors)
  0Q0WC000002Ly1d0AC Denied    (2)
  0Q0WC000002U2020AC Accepted  (2)  <== ONLY ONE REPORTED FAILING
  0Q0WC0000035N0f0AE Ordered   (2)
  0Q0WC0000039E8T0AU Accepted  (2)
  0Q0WC0000027oGf0AI In Review (1)
  0Q0WC0000038GFZ0A2 Draft     (1)

All 7 leave null-group-id ungrouped survivors after deleting their sole group. Only 1 fails.
=> A GENERIC null-group-id Map.get(null) collision would crash all 7 identically. It does not.

Query 03 (group hardware flags): failing quote's group is the ONLY one of the 7 with
  Hardware_Group_Type__c=True AND Hardware__c set. The other 6 are non-hardware groups.

Query 04 (survivor profiles): failing quote's survivors (2x TermDefined, Hardware__c=null, Cfg=Allowed)
  are structurally IDENTICAL to survivors on non-failing twin 0Q0WC0000039E8T0AU (Accepted, 2x TermDefined,
  Hardware__c=null) and 0Q0WC000003AaoT0AS (incl. OneTime+TermDefined mix, all null-group).
  4 of the 6 non-failing twins are in editable status (incl. one Accepted = same lock-state as failing).

## Conclusion
The null-group-id of ungrouped survivors is SHARED by all 7 structural twins; the failure is NOT.
The differentiator is the DELETED group's config (Hardware_Group_Type__c=True + OneTime/TermDefined SM-mix
+ net>>list markup), consistent with Mission E. The thrown key, if a map, is NOT keyed by the survivors'
null group id. H4's specific mechanism is refuted.
