# Getestet #2 native 12-month run — report v1.2 (canonical, genuine MT5 evidence)

Rules: `scripts/repositioning/getestet2/RULES_london_breakout_v1.2.md` (frozen
SERVER-clock proxy: range [10:00,11:00), entry [11:00,14:00), flat at the
first modelled tick at-or-after 19:00 server; NOT claimed London wall time).
EA: `scripts/repositioning/getestet2/ea/SCA_Getestet2_LondonBreakout_v12.mq5`
(tester-only, fixed 0.01 lot, `g2_lb12_` exports). Manifest (hashes/paths/
coverage): `assets/proof-kit/getestet2/run_manifest_native_v12.json`.
Compact evidence subset: `assets/proof-kit/getestet2/native-v12/` (original
tester HTML + four PNGs, bars/deals/events CSV, run JSON, tester ini,
compile log; the 65 MB per-tick equity CSV stays on D:, hashed in the
manifest — not copied).

v1.1 (`report_native_12m_v11.md`, `run_manifest_native_v11.json`) is retained
as prior exploratory evidence but SUPERSEDED: its text said time exit at the
close of the first completed bar with OPEN >= 19:00 while the EA enforced the
first tick at/after 19:00. v1.2 freezes the wording to the executable logic;
trading decisions and 0.01 lot are unchanged. Byte comparison confirms it:
v1.2 bars/deals/equity exports are byte-identical to v1.1 (only the init
`rules=v1.2` tag and report title differ).

## Run facts

- Terminal: isolated `D:/CodexWork/sca_symbiose_holaprime_20260924/`
  (`terminal64.exe`, portable, own ini `g2_lb12_tester.ini`, spawned PID
  19668, hidden, `ShutdownTerminal=1`; exited cleanly, exit code 0). Server
  HolaPrime-Server1.
- Window (server): 2025-09-01 → 2026-09-01. Symbol EURUSD, M15, Model=1
  (one-minute OHLC), deposit USD 10000, leverage 1:100, no cloud, no
  optimization, no live, no DLL. History quality 100%.
- Compile: 0 errors, 0 warnings, first attempt (own log `g2_lb12_compile.log`).
- Coverage: 24,864 M15 bars, 1,482,897 modelled ticks, 1,482,899 equity rows,
  462 own-magic deals (231 IN / 231 OUT), 1,002 events. Span 2025-09-01
  00:00 → 2026-08-31 23:59:59 server. 260 server dates with bars, 259
  range-complete days, 231 signals/fills, 28 implicit no-signal days
  (range row without signal), 0 degenerate days, max 1 fill per server date
  (verified from deal history).

## Bounded result (one window, one size, one model — nothing more)

- Net: **-USD 59.26 (-0.59%)**, final balance USD 9,940.74. Gross +163.64 /
  -222.90, profit factor 0.73, expected payoff -0.26/trade, commission
  total -13.86 (0.03/deal × 462), swap 0.00.
- Exits: 27 time exits (`exit` rows), 204 SL/TP exits; 103 positive / 127
  negative / 1 zero closes (by deal profit). 252 post-exit re-signals
  correctly blocked by the one-a-day cap (`skip` rows).
- Drawdown: max balance DD 70.88 (0.71%), max equity DD 71.12 (0.71%),
  min equity 9,931.05. Recovery factor -0.83, Sharpe -5.00.
- Cross-checks (independent audit script `/tmp/g2_audit_native_v12.py`,
  scratch): deals net = report net (-59.26); fills = IN deals (231);
  IN/OUT balanced; bar seq monotonic; own magic only; fixed 0.01 lot;
  equity DD = report DD. All true (12/12 checks).

## Limits (binding — read before quoting any figure)

1. Losing window at 0.01 lot; currency outcome scales with size and proves
   no rule edge. No out-of-sample, no multi-symbol/TF evidence.
2. Model=1 generated ticks, not real ticks: intrabar SL/TP ordering is
   modelled, not observed.
3. Server-clock proxy: no London-session alignment is established or claimed.
4. Prop verdict: **INCONCLUSIVE** — full equity series exists, but HolaPrime
   firm rules (daily/max drawdown, consistency, lot caps) are not in
   evidence, so no pass/fail can be derived.
5. No forecast, no prop-pass claim, no customer result. The terminal's own
   `.htm` graph is the only chart; no explanatory chart is offered as proof.

Raw evidence stays in `D:/CodexWork/muse-getestet2-20260927/`
(`g2_lb12_bars/deals/equity/events.csv`, `g2_lb12_run.json`,
`g2_lb12_12m_eurusd_m15.htm` + four PNGs, `g2_lb12_compile.log`,
`g2_lb12_tester.ini`) and in `Tester/Agent-127.0.0.1-3000/MQL5/Files/`
(equity source). First-pass synthetic artefacts (fixture, synthetic
metrics/explainer chart) are retained and remain labelled SYNTHETIC —
not market evidence.
