# Spec (SC-3350 canonical User Story mapping table, keyed by Solution Category)
spec = {
 "Vulnerability Management": 6.20,
 "File Integrity Management": 5.00,   # spec category string
 "Email Security": 5.00,
 "Brand Protection": 5.00,
 "Human Risk Management": 5.00,
 "Data Protection": 4.70,
 "Cloud Data Protection": 5.00,
 "Fortra Platform": 0.0,
 "Offensive Security": 6.20,
 "Robotic Process Automation": 9.85,
 "Core IGA": 4.70,
 "Network Monitoring": 7.85,
 "Powertech Identity & Access Manager": 7.85,  # spec category string
 "Capacity Management": 4.70,
 "GoAnywhere": 7.85,
 "Globalscape": 7.85,
 "Business Intelligence": 7.85,
 "Doc Management": 7.85,
 "Systems Management": 12.00,
 "Cybersecurity": 4.70,
 "IPP": 0.0,
}

# Live COLA_Uplift_Rules__mdt keyed by Solution_Category__c (from SOQL)
live = {
 "Brand Protection": 5,
 "Business Intelligence": 7.85,
 "Capacity Management": 4.7,
 "Cloud Data Protection": 5,
 "Core IGA": 4.7,
 "Cybersecurity": 7.85,
 "Data Protection": 4.7,
 "Doc Management": 7.85,
 "Email Security": 5,
 "File Integrity Monitoring": 5,           # live category string differs
 "Fortra Platform": 0,
 "Globalscape": 7.85,
 "GoAnywhere": 7.85,
 "Human Risk Management": 5,
 "IPP": 0,
 "Network Monitoring": 7.85,
 "Offensive Security": 6.2,
 "Powertech IAM BoKS": 7.85,               # DEAD permanent (0 products)
 "Powertech Identity & Access Manager (BoKS)": 7.85,  # TEMP, live BoKS
 "Robotic Process Automation": 9.85,
 "Systems Management": 7.85,
 "Vulnerability Management": 6.2,
}

# Category-string normalization map (spec -> live key)
alias = {
 "File Integrity Management": "File Integrity Monitoring",
 "Powertech Identity & Access Manager": "Powertech Identity & Access Manager (BoKS)",
}

print("=== RATE MATCH (spec vs live), by spec category ===")
mismatches=[]
keymismatches=[]
for cat, srate in spec.items():
    lkey = alias.get(cat, cat)
    if lkey not in live:
        keymismatches.append((cat,lkey,srate,"NO LIVE RULE"))
        print(f"  [NO-RULE] spec '{cat}' (->'{lkey}') rate {srate} : NO matching live rule")
        continue
    lrate = live[lkey]
    status = "OK" if abs(float(srate)-float(lrate))<1e-9 else "MISMATCH"
    note = "" if cat==lkey else f" (key-aliased '{cat}'->'{lkey}')"
    if status=="MISMATCH":
        mismatches.append((cat,lkey,srate,lrate))
    print(f"  [{status}] {cat:42s} spec={srate:<6} live={lrate}{note}")

print("\n=== RATE MISMATCHES ===")
for m in mismatches: print("  ", m)
print("\n=== SPEC CATS WITH NO LIVE RULE (key) ===")
for m in keymismatches: print("  ", m)

# Live rules not in spec
print("\n=== LIVE RULES NOT IN SPEC (by string/alias) ===")
spec_live_keys=set(alias.get(c,c) for c in spec)
for lk in live:
    if lk not in spec_live_keys:
        print(f"  EXTRA live rule '{lk}' rate {live[lk]}")
