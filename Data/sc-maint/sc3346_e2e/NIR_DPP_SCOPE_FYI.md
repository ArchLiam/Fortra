# SC-3346 / DPP — Authoritative Test-Scope FYI from Nir Kailash

**Source:** Slack, **Nir Kailash → @Liam Jeong**, 2026-06-14 1:48 PM (captured screenshot).
**Authority:** Build owner (Nir). References a prior private conversation (Jun 6th) and a long-standing agreement Marc DeBrey made with Fortra.

---

## Verbatim message

> @Liam Jeong just FYI — For Maintenance Product, we don't have attribute related information specific to **Maintenance Type** from Fortra. Also **Maintenance Product won't be shown on Catalog** — that is expected. There's only **one product on which you can test Derived Pricing**, this was discussed by @Marc DeBrey with Fortra long back as per the correct[ion] that Fortra provided us.
>
> _(quoted, from a private conversation, Jun 6th):_ **"Powertech Identity & Access Manager (BoKS)"** with the Product Code **"PIA-PIA-NRPS-PIAP"**
>
> This is the **only product on which you can do DPP testing**.

---

## What this establishes (authoritative)

1. **DPP / Derived-Pricing testing scope is a SINGLE product:** **`PIA-PIA-NRPS-PIAP`** — "Powertech Identity & Access Manager (BoKS)" (the Perpetual license; its derived maintenance line is `PIA-PIA-RNM-PIAMBK` / RRM `PIA-PIA-RRM-PIAM`). This is the only sanctioned product for Derived Pricing tests.
2. **Maintenance products absent from the Catalog is EXPECTED** — not a defect.
3. **No "Maintenance Type" attribute data is available from Fortra** for maintenance products — so test findings that depend on maintenance-type attributes being populated across the catalog are out of scope.

## Implications for the SC-3346 E2E work (re-scoping)

- ✅ **Our canary IS the right product.** The BoKS canary (quote `00781109`, maintenance line `PIA-PIA-RNM-PIAMBK` derived from `PIA-PIA-NRPS-PIAP`, COLA net **67.38**) is exactly the sanctioned DPP test product. The renewal-commit defect (RN-COLA-COMMIT / RN-PARTNER-DD / MAINT-ONLY / MULTI-ASSET) was found on the correct product — **the functional blocker stands.**
- 🔻 **Cross-family findings are OUT of the sanctioned DPP test scope.** Earlier results across other families (FIM/GS/RPA tiers, the ~3,453-PBE PBEDP coverage gap, the NB-DERIVED-TIER minority tiers like Basic/Premium/Express/Expert) are **not** part of DPP testing per Nir — those products aren't the agreed Derived-Pricing test target.
- 🔻 **"Maintenance not on Catalog" is not a bug** — drop any such concern.
- 🔻 **Sparse Maintenance-Type attributes are expected** (no Fortra data) — not a build defect.

> **Net:** narrow DPP validation to `PIA-PIA-NRPS-PIAP` / its maintenance. The one defect that matters on that product is the **renewal-maintenance commit** (auto-added derived line commits `67.38 × 0.90 = 60.64`/`$0` instead of the computed 67.38; fix = line-creation / de-derive). Everything else flagged on other products is outside the agreed test scope.
