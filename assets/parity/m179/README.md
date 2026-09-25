# M179 · genuine Pine/MT5 signal comparison

**Scope:** owned SMA(3)/SMA(5) strict crossover on completed EURUSD H1 bars,
2026-09-08 00:00 through 2026-09-09 23:00 UTC. BULL is fast crossing above
slow; BEAR is fast crossing below. This is a signal check only: no orders,
equity, profit, client result, or trading-performance claim.

## Original platform evidence

| Platform | Real screenshot | Original data |
|---|---|---|
| TradingView, OANDA:EURUSD H1, authenticated `stratcorealpha` chart with the [Pine source](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/blob/main/src/parity/sca_ea_parity_demo.pine) | [Chart with BULL/BEAR markers](M179_TradingView_OANDA_EURUSD_H1_chart_20260925.png) and [native Table view with OHLC and Pine output columns](M179_TradingView_OANDA_EURUSD_H1_table_20260925.png) | [48 visible Table-view bars](M179_TradingView_OANDA_EURUSD_H1_20260908-09_bars.csv), [16 signal rows](M179_TradingView_OANDA_EURUSD_H1_20260908-09_signals.csv) |
| HolaPrime MT5, `HolaPrime-Server1` EURUSD H1, read-only [MQL5 export script](SCA_M179_HolaPrimeSignalExport.mq5) using the shared [signal include](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/blob/main/src/parity/SCA_EA_ParityDemoSignal.mqh) | [ChartScreenShot from the actual terminal with green/red signal arrows](M179_HolaPrime_EURUSD_H1_chart_20260925.png) | [48 CopyRates bars](M179_HolaPrime_EURUSD_H1_20260908-09_bars.csv), [16 signal rows](M179_HolaPrime_EURUSD_H1_20260908-09_signals.csv), [original Experts-log excerpt](M179_HolaPrime_export_log_excerpt_20260925.txt) |

The TradingView CSV was transcribed programmatically from **the visible native
Table view** on 2026-09-25. The Basic account's built-in Download action opened
a paid-plan prompt, so the CSV is not represented as a native TradingView file
download. The screenshot shows the actual OHLC and `Live BULL/BEAR cross`
columns; structured browser controls read 48 displayed rows. No feed values or
signals were generated to fill gaps. The MT5 CSV is the script's direct
`CopyRates`/`FileWrite` output from the isolated HolaPrime terminal, compiled
with 0 errors and 0 warnings; it placed no orders. The export log records
`bars=48 signals=16 screenshot=true server=HolaPrime-Server1`. The original
installed HolaPrime process was left running; no Funding Pips terminal was used.

## Reproduce the comparison

From this directory, run `python compare_signals.py` with pandas and
matplotlib installed. It validates both source tables and the separate
signal-only exports, converts the observed HolaPrime server times from UTC+3
to UTC, checks the frozen crossover rule on bars with a complete in-file SMA
history, then writes [the 48-bar agreement table](M179_signal_agreement.csv),
[individual signal discrepancies](M179_signal_discrepancies.csv) and [the
price/marker overlay](M179_signal_overlay.png). The discrepancy CSV is
header-only because there were **zero signal mismatches**: 16 BULL/BEAR
markers on each side on the same UTC bars, 48/48 bar statuses `AGREE`.

The feeds do have different OHLC values; the maximum absolute close gap in
these 48 bars is 0.00023. These are observed feed differences, not signal
discrepancies. The chart line uses OANDA closes and overlays separate Pine and
MT5 markers; it is a data visualization, whereas the two platform screenshots
are the execution evidence. The first five in-window bars need earlier closes
for an independent SMA recomputation, so the script verifies the later bars
and cross-checks all 48 observed platform markers. The earlier [12-bar shared
fixture](../../../docs/EA_PARITY_HOLAPRIME_TRADINGVIEW_PROOF.md) separately verifies
the identical input case (`5:BULL`, `8:BEAR`). No claim is made that these two
market feeds are identical or that other symbols, periods, or rules match.

