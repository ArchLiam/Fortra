# SC-3350 — Live Data Snapshot

Captured 2026-06-10T17:13:07Z from FortraUAT (read-only). Reference tables for the dossier.

## A. COLA_Uplift_Rules__mdt (active rate table)
```
 MASTERLABEL                SOLUTION_CATEGORY__C                       DEFAULT_UPLIFT_PERCENT__C IS_ACTIVE__C 
 ────────────────────────── ────────────────────────────────────────── ───────────────────────── ──────────── 
 Brand Protection           Brand Protection                           5                         true         
 Business Intelligence      Business Intelligence                      7.85                      true         
 Capacity Management        Capacity Management                        4.7                       true         
 Cloud Data Protection      Cloud Data Protection                      5                         true         
 Core IGA                   Core IGA                                   4.7                       true         
 Cybersecurity              Cybersecurity                              7.85                      true         
 Data Protection            Data Protection                            4.7                       true         
 Doc Management             Doc Management                             7.85                      true         
 Email Security             Email Security                             5                         true         
 File Integrity Monitoring  File Integrity Monitoring                  5                         true         
 Fortra Platform            Fortra Platform                            0                         true         
 Globalscape                Globalscape                                7.85                      true         
 GoAnywhere                 GoAnywhere                                 7.85                      true         
 Human Risk Management      Human Risk Management                      5                         true         
 IPP                        IPP                                        0                         true         
 Network Monitoring         Network Monitoring                         7.85                      true         
 Offensive Security         Offensive Security                         6.2                       true         
 Powertech IAM BoKS         Powertech IAM BoKS                         7.85                      true         
 TEMP BoKS IAM ProductCat   Powertech Identity & Access Manager (BoKS) 7.85                      true         
 Robotic Process Automation Robotic Process Automation                 9.85                      true         
 Systems Management         Systems Management                         7.85                      true         
 Vulnerability Management   Vulnerability Management                   6.2                       true         
Total number of records retrieved: 22.
```

## B. MyCAP_Rules__mdt (out-year)
```
 MASTERLABEL DEFAULT_OUT_YEAR_UPLIFT_PERCENT__C MINIMUM_OUT_YEAR_UPLIFT_PERCENT__C IS_ACTIVE__C 
 ─────────── ────────────────────────────────── ────────────────────────────────── ──────────── 
 Global      3                                  3                                  true         
Total number of records retrieved: 1.
```

## C. Current Apex coverage (post Marc 2026-06-10 rework)
```
 APEXCLASSORTRIGGER.NAME       NUMLINESCOVERED NUMLINESUNCOVERED 
 ───────────────────────────── ─────────────── ───────────────── 
 COLAUpliftHandler             168             15                
 AssetContractQueryHelper      37              6                 
 COLAUpliftPrehook             398             132               
 QLDescriptionGeneratorPrehook 208             52                
Total number of records retrieved: 4.
```

## D. COLA class edit timestamps today (Marc DeBrey)
```
 NAME                          LASTMODIFIEDDATE             LASTMODIFIEDBY.NAME 
 ───────────────────────────── ──────────────────────────── ─────────────────── 
 COLAUpliftPrehook             2026-06-10T16:58:15.000+0000 Marc DeBrey         
 COLAUpliftTest                2026-06-10T16:58:15.000+0000 Marc DeBrey         
 COLAUpliftHandler             2026-06-10T16:29:57.000+0000 Marc DeBrey         
 QLDescriptionGeneratorPrehook 2026-06-10T14:41:27.000+0000 Marc DeBrey         
 AssetContractQueryHelperTest  2026-06-10T14:00:38.000+0000 Marc DeBrey         
 AssetContractQueryHelper      2026-06-10T14:00:37.000+0000 Marc DeBrey         
Total number of records retrieved: 6.
```

## E. Defect #1 repro line (still broken)
```
 ID                 LISTPRICE UNITPRICE PRE_COLA_PRICE__C COLA_UPLIFT_PERCENT__C COLA_SOURCE__C 
 ────────────────── ───────── ───────── ───────────────── ────────────────────── ────────────── 
 0QLWC000003bHpl4AE 10000     10000     null              null                   null           
Total number of records retrieved: 1.
```
