# SC-3423 — UAT Test Records

Org: `https://fortra--uat.sandbox.my.salesforce.com` (FortraUAT). Fix deployed 2026-06-18.

## 🎯 Primary repro — big account (>200 Hardware), this is what was broken
- **Account:** Fortra, LLC - Test (`001WC00000XiZP4YAN`) — **236 Hardware** (228 blank `Hardware_ID__c` + 8 real-ID)
- **Quote:** `00781181` "Q-Wren - Test Currencies2-2026-06-17" (Draft) → https://fortra--uat.sandbox.my.salesforce.com/0Q0WC000003ASz10AG
- **Backup:** `00781182` → `/0Q0WC000003AaoT0AS`
- 8 real-ID hardware on this account (appear at top of Available list after the fix): `123`, `123456`, `12123`, `HW000013`, `HW000030`, `HW000031`, `HW000032`, `HW000033`

## ✅ Regression — small account (<200 Hardware), must still work
- **Account:** AB Test Account (`001WC00000QBhaXYAT`) — **8 Hardware**
- **Quote:** `00781115` (Draft) → https://fortra--uat.sandbox.my.salesforce.com/0Q0WC0000038zZF0AY

## Steps
1. Open the quote → **Quote Line Flex Panel** → **Hardware Groups**.
2. **Create New Hardware Group** → check **"Assign or change hardware"**.
3. **Create New Hardware** → Cross Platform: Hardware Name, Platform=Cross Platform, Hostname, Hardware ID (e.g. `TEST-3423-01`), Operating System.
4. **Create & Select**.

### Pass criteria
- Toast: "Hardware created and selected successfully".
- New record shown as **Selected Hardware**.
- **Create Group** button **enabled** (not greyed).
- Create Group → group created, modal closes.
- (Companion) Available Hardware list shows the 8 real-ID rows at the top.

### Also cover
- Small-account quote (no regression).
- One **iSeries** create (Serial Number + iSeries Model) → record selects + auto-Partition `<HardwareID>-P1` created.
- Negative/honesty check: if a create ever can't be selected, you should now get a **Warning** ("could not be selected automatically") and the form stays open — never a false success.

> Each successful create adds a `Quoting` Hardware (+ Partition); Create Group adds a QuoteLineGroup. Clean up with the orphan batch later if desired.
