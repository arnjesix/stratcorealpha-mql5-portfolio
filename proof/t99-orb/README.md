# ORB-v1.0 historical MT5 rehearsal

This is one fixed-rule EURUSD M15 Strategy Tester run on HolaPrime broker bars,
from 2025-09-01 through 2026-09-01 (exclusive end, broker server time).
The tester used one-minute OHLC generated ticks. It did not use recorded real
ticks and it was not a funded customer or prop-challenge result.

The [rule freeze](freeze.json) sets the 09:00–09:30 opening range, later
completed-bar breakout, one entry per server day, stated 1% risk, 2R target
and 17:00 flatten. [EA source](SCA_T99_ORB_TestEA.mq5) and its
[included library](SCA_T99_RuleLib.mqh) are the exact files from the isolated
tester run. The EA refuses to trade outside the Strategy Tester. The
[native compile receipt](compile-corrected_20260925.txt) reports zero errors
and warnings.

The [original run manifest](run_manifest_20260925.json) records the tester
settings, source and output hashes, the initial staging misfire, and the
corrected run. The [audit method](audit_method.md),
[audit script](audit_native_run.py) and [audit summary](audit_summary.json)
document the full-period reconciliation. The [native tester chart](mt5-report-chart_20250901_20260901.png)
and [verbatim case excerpts](cases_20260925.txt) come from the actual run.

The manifest preserves local paths for provenance. The large raw broker-bar,
deal and equity exports and full tester logs remain in the private run
workspace. Their hashes are in the manifest and audit. This public bundle
lets a reader inspect the frozen rules, source, native chart and audit result;
re-running the audit from raw data requires access to those original exports.

The audit is historical. Broker server times have not been converted to UTC
for the full year, and the applicable prop-account rule set was not
verified. No future outcome or challenge result follows from this run.
