# SC-3346 Maintenance (Derived) Pricing — Test Corpus (Discovery)
Org: FortraUAT. Compiled 2026-06-13. All Draft unless noted; read-only on non-Draft.

## A. New-business AUTO-ADD first-year maintenance (license + derived maint, ListPrice=0)
| Quote | Id | Status | Lines | Symptom |
|---|---|---|---|---|
| 00780964 | 0Q0WC000003735t0AA | Draft | Perpetual PIA-PIA-NRPS-PIAP (List355/Net301.75) + New-Maint PIA-PIA-RNM-PIAMBK (List0/Net0/Base=355) | CANONICAL clean pair; derived child Net=0 |
| 00781057 | 0Q0WC0000037rFZ0AY | Draft | 10x PIA-PIA-NRPS-PIAP + 10x New-Maint PIA-PIA-RNM-PIAMBK (Net=71) + 12x HRM subs | batch/multi-line |
| 00781030 | 0Q0WC0000037SsH0AU | Draft | Perpetual GS-GSE-NRPS-E8CP + New-Maint GS-GSE-RNM-EFT8 + Services OS-COS-NRST-CIICS | mixed w/ Services |

## B. Renewal-maintenance COLA path (Base_Price + COLACalculatedPrice stamped) — ALL show SC-3404
| Quote | Id | Status | Product | Net | COLA | Base | Src | Symptom |
|---|---|---|---|---|---|---|---|---|
| 00781109 (CANARY) | 0Q0WC0000038aXd0AI | Draft | PIA-PIA-RRM-PIAM | 60.64 | 67.38 | 71 | 355 | SC-3404; maint-only => MissingContributor |
| 00781084 | 0Q0WC00000382MH0AY | Draft | PIA-PIA-RRM-PIAM (+HRM-HRM-RSL-10L50CS sub) | 60.64 | 67.38 | 71 | 355 | SC-3404; has contributor |
| 00781053 | 0Q0WC0000037muD0AQ | Draft | PIA-PIA-RRM-PIAM (+VM-BSL-RSL-BESECB sub) | 54.58 | 60.64 | 71 | 355 | SC-3404; MULTI-ASSET renewal |
| 00781043 | 0Q0WC0000037XvB0AU | Draft | PIA-PIA-RRM-PIAM | 0 | 67.38 | 71 | 355 | SC-3404 $0 variant |
| 00780982 | 0Q0WC0000037AKH0A2 | Draft | PIA-PIA-RRM-PIAM | 0 | (null) | 71 | 355 | $0; COLA NOT stamped (path not applied) |

## C. Maintenance-only renewal (MissingContributor) = 00781109 (only the RRM line on cart, no license/sub)
## D. Multi-asset renewal (license + maintenance both renewed) = 00781053 (RRM + BESECB sub), 00781084 (RRM + 10L50CS sub)
## E. Legacy renewal maint (NON-derived path, non-zero ListPrice; NOT SC-3346) = 00780458 (CS-ISPF-MAINT-RNW List18500)

## F. Orders with decomposed / derived maintenance lines
| Order | Id | Status | Product | Unit | Base | COLA | Src | Note |
|---|---|---|---|---|---|---|---|---|
| 00095427 | 801WC00000kRhcqYAC | Activated | New-Maint PIA-PIA-RNM-PIAMBK | 62.48 | 71 | - | 355 | clean auto-add maint (order) |
| 00095455 | 801WC00000kTmV5YAK | Activated | New-Maint PIA-PIA-RNM-PIAMBK | 62.48 | 71 | - | 355 | dup of above |
| 00095468 | 801WC00000kXyMIYA0 | Activated | New-Maint PIA-PIA-RNM-PIAMBK | 62.48 | 71 | - | 355 | dup |
| 00095472 | 801WC00000kZELqYAO | Activated | New-Maint PIA-PIA-RNM-PIAMBK | 62.48 | 71 | - | 355 | dup |
| 00095470 | 801WC00000kYmw8YAC | Order Complete | 10x New-Maint PIA-PIA-RNM-PIAMBK (Unit71/Base71/Src355) + HRM subs | 71 | 71 | - | 355 | LARGEST multi-line maint order |
| 00095475 | 801WC00000kaGBpYAM | Activated | Renewal-Maint PIA-PIA-RRM-PIAM | 60.64 | 71 | 67.38 | - | SC-3404 ON ORDER SIDE |
| 00095394 | 801WC00000kNla1YAC | Draft | New-Maint FIM-FIM-RNM-VEMENM | 0 | 29537.5 | - | 34750 | large $0 new-maint commit |
| 00095473 | 801WC00000kZEFQYA4 | Order Complete | BI-ABS-RSS-ABSTSU | 49.611 | - | 49.61 | - | COLA MATCH (order side) |
| 00004807 | 801WC00000gGlXVYA0 | Draft | RPA-AUD-RSS-AUPS | 8041.02 | - | 8041.02 | - | older COLA-stamped (match) |
| 00004808 | 801WC00000gH1KVYA0 | Draft | DM-WCU-RSS-5250SU | 6539.75 | - | 6539.75 | - | older COLA-stamped (match) |

## DO NOT TOUCH
- 00781068 (Accepted) — RRM line Net=60.64/COLA=67.38; read-only reference of SC-3404 on an Accepted quote.

## Notes
- Genuine COLA-path Draft quotes = ONLY the 4 canary set (00781109/84/53/43); build is recent so corpus is small.
- 00407375 has COLACalculatedPrice=0 (not a real COLA computation) — exclude.
- Contributor linkage NOT via ParentQuoteLineItemId/RelatedQuoteLineItemId (all null on these); contributor = on-cart license/sub mapping to the maint product. Maint-only cart => MissingContributor.
- orig=Y OrderItems on 00004756/00004822/00095316/00095351 etc = quantity-splits (same product parent/child), NOT maintenance decomposition.
