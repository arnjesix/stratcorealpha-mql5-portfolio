# T99 native run audit — method

Reproduction command (from the workspace root):

    python3 scripts/repositioning/t99/audit_native_run.py --manifest assets/proof-kit/t99-rehearsal/native/run_manifest_20260925.json --out assets/proof-kit/t99-rehearsal/analysis/audit_summary.json --method assets/proof-kit/t99-rehearsal/analysis/audit_method.md

Provenance: `/mnt/c/Users/arnje/Documents/VS-Code/stratcorealpha/assets/proof-kit/t99-rehearsal/native/run_manifest_20260925.json`, freeze `/mnt/c/Users/arnje/Documents/VS-Code/stratcorealpha/assets/proof-kit/t99-rehearsal/native/freeze.json`, cases `/mnt/c/Users/arnje/Documents/VS-Code/stratcorealpha/assets/proof-kit/t99-rehearsal/native/cases_20260925.txt`.

## File hashes (validated before any figure was reported)

| artifact | bytes | sha256 (prefix) | status |
| --- | ---: | --- | --- |
| report | 541410 | bd99dfcd45e5dbec… | PASS |
| bars | 3906244 | e39be9700ca194d5… | PASS |
| deals | 88046 | 118cf4ebd5b91072… | PASS |
| equity | 136406936 | c52c4707939c1fbd… | PASS |
| run_json | 718 | b77a7555f91463d7… | PASS |

## Interpretation

Full-period neutral facts, recomputed from the hash-verified deals CSV: 518 deals forming 259 IN/OUT round trips; net = profit 3100.94 + commission -1681.68 + swap 0.00 = 1419.26 on 10000.00 deposit (final 11419.26).
Wins/losses 107/152 agree under both natural counting conventions; buy/sell split 128/131.
Bars: 24863 exported (2025.09.01 00:00:00 → 2026.08.31 23:30:00 server) vs 24864 generated; the last bar completes at the exclusive ToDate boundary.
Equity (streamed, 1482899 rows): final balance/equity 11419.26/11419.26; max balance drawdown 2342.43, max equity drawdown 2566.37 — both reproduce the report.
Equity row metadata: the original capture manifest records rows=2965800, which is stale; the verified actual data-row count is 1482899 (hash-verified T99_equity.csv, streamed count). The capture manifest is left unchanged; its original error is preserved for the audit trail.
Three native-log cases (entry / no_break / flatten) are present verbatim with SERVER wall time. Each case is parsed from its actual native log line (entry/sl/tp/range, close/range, flatten deal) and cross-checked against the exported bars and the exact deal CSV row; a missing log value or any mismatch yields False, never a constant True.

## Boundaries

Historical Model-1 simulation (one-minute OHLC generated ticks), not real ticks. UTC conversion and any HolaPrime account-specific prop verdict are INCONCLUSIVE. No forecast, no guarantee, no cherry-picked period.
