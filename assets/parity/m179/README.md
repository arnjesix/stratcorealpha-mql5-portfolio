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
fixture](../../proof/trading/ea-parity-demo/README.md) separately verifies
the identical input case (`5:BULL`, `8:BEAR`). No claim is made that these two
market feeds are identical or that other symbols, periods, or rules match.

## August 2026 month mode (`--month 2026-08`)

The same frozen rule over the complete fixed calendar month of August 2026
EURUSD H1: all 507 observed trading hours (2026-08-02T21:00Z through
2026-08-31T23:00Z; weekends naturally absent, four 49-hour gaps). No dates
were cherry-picked and no equity, P&L, or performance is computed.

**Provenance.** Both month inputs are published files in this directory, so the
month proof reproduces from a fresh copy of the proof-kit directory alone (no
ignored `tmp/` files). Input A is
[M179_TradingView_OANDA_EURUSD_H1_202608_packed.b64](M179_TradingView_OANDA_EURUSD_H1_202608_packed.b64)
(6772 Base64 chars, captured through the visible TradingView OANDA:EURUSD H1
UTC Table view on 2026-09-25; the Basic account's built-in Download action
opened a paid-plan prompt, so no native TradingView CSV file download exists).
The published Base64 is a lossless transfer of that observed visible table,
not a native TradingView CSV: it decodes to little-endian uint32 count (507),
uint32 first epoch, then 507 ten-byte records (uint8 delta-hours 0/1/49, 4x
uint16 OHLC as `round(price*100000)-100000`, uint8 marker 0/1/2). The script
verifies payload length `8+10*count`, every delta/marker, OHLC consistency,
and distinct timestamps, then writes [507 TV bars](M179_TradingView_OANDA_EURUSD_H1_202608_bars.csv)
(`time_utc,open,high,low,close,direction`, five decimals) and [116 signal
rows](M179_TradingView_OANDA_EURUSD_H1_202608_signals.csv) (58 BULL, 58 BEAR).
These are observed TradingView markers, not generated. Input B (authoritative)
is the DIRECT `FileWrite` output of the read-only MQL5 script
[SCA_M179_HolaPrimeSignalExport_202608.mq5](SCA_M179_HolaPrimeSignalExport_202608.mq5),
executed in the isolated HolaPrime MT5 terminal on `HolaPrime-Server1`
(compiled with 0 errors and 0 warnings, no order/account/position API,
`AllowLiveTrading=0`):
[M179_HolaPrime_EURUSD_H1_202608_mql5_export_bars.csv](M179_HolaPrime_EURUSD_H1_202608_mql5_export_bars.csv)
(507 August H1 bars, server-clock `time_mt5`, OHLC, observed direction) and
[M179_HolaPrime_EURUSD_H1_202608_mql5_export_signals.csv](M179_HolaPrime_EURUSD_H1_202608_mql5_export_signals.csv)
(112 signal rows). Execution evidence is the
[terminal ChartScreenShot with marked signals](M179_HolaPrime_EURUSD_H1_202608_chart.png)
(view is the last several August days) and the
[original filtered log excerpt](M179_HolaPrime_export_log_excerpt_202608.txt)
(final `bars=507 signals=112 screenshot=true server=HolaPrime-Server1`).
Input C is
[M179_HolaPrime_EURUSD_H1_202608_raw.csv](M179_HolaPrime_EURUSD_H1_202608_raw.csv)
(528 rows from read-only `MetaTrader5.copy_rates_range` on the installed
HolaPrime MT5 terminal, `HolaPrime-Server1`, Jul31 03:00 through Sep1 02:00
server clock), preserved verbatim under its published name. Its `time_mt5`
values are server-clock labels (UTC = MT5 − 3h exactly); the first 21 rows
(Jul31 00:00–20:00Z) are pre-window warmup. Input C is an independent quote
cross-check only, never the marker source.

**Method.** MT5 markers in every table, chart and reason are the OBSERVED
direct MQL5 script values (server labels converted UTC = MT5 − 3h exactly) —
never a local recomputation; the fixed SMA(3)/SMA(5) period is unchanged, and
TV markers remain the observed visible Table rows from the packed source. The
script fails unless all 112 direct signal rows match their bar rows
(time/direction/OHLC), all 507 direct-export bars align the TV stamps in the
same order, direct-export OHLC equal the raw API quotes exactly at 5 decimals
on all 507 bars, and the local strict SMA(3)/SMA(5) recomputation over the raw
closes including warmup equals the observed marker on all 507 month bars
(formula cross-check: observed values are never replaced by it). It also fails
unless every TV observed marker with at least 5 in-file preceding bars equals
its local recomputation. The first 5 month bars have no pre-window TV warmup,
so their `tv_rule_check` is `UNVERIFIABLE-NO-PREWINDOW`: observed values are
preserved, never invented.

**Numbers.** [507-row agreement table](M179_signal_agreement_202608.csv):
491 `AGREE`, 16 `MISMATCH`. TV self-check: observed == recomputed on 502
verifiable bars. Observed MQL5 script signals: 112 (56 BULL, 56 BEAR).
Formula cross-check: observed MQL5 script == local strict SMA(3)/SMA(5)
recompute (raw warmup) on 507/507 month bars. Feed OHLC gaps over the month:
max abs diff open 0.00056, high 0.00017, low 0.00047, close 0.00065. Each of
the [16 discrepancies](M179_signal_discrepancies_202608.csv) carries its bar's
own closes, preceding and current SMA(3)/SMA(5) values per feed, and an
individual reason stating the observed MQL5 marker plus the feed-threshold
mechanism: 12 form six timing-shifted single crossings (the same BULL/BEAR
event fires one bar apart, e.g. Aug-04 23:00Z MQL5-BULL vs Aug-05 00:00Z
Pine-BULL; Aug-13 20:00Z Pine-BULL vs Aug-13 23:00Z MQL5-BULL), and 4 form two
TV-feed-only BEAR-then-BULL whipsaws (Aug-11/12, Aug-19) where the observed
MQL5 feed never places fast strictly below slow so neither leg triggers. In
every case the TV-observed marker equals the TV-recomputed marker and the
observed MQL5 script marker equals the local SMA recomputation, so these are
feed-threshold effects (strict `>`/`<` margins of ~0.00001–0.00020), not Pine
live-vs-completed marker issues and not script-vs-recompute differences. The
[overlay](M179_signal_overlay_202608.png) plots the OANDA close against bar
index (weekends absent) with observed Pine triangles and observed MQL5 script
circles/crosses.

**Limitations.** The MQL5 execution covers the August bars; pre-window warmup
history for the formula cross-check comes from the raw API extract. TV warmup
bars 1–5 are unverifiable; feeds differ at quote level (see gaps above); no
orders, equity, or performance claim. Reproduce from this directory with `python
compare_signals.py --month 2026-08` (published sources in this directory only,
no `tmp/` files needed);
`python compare_signals.py` alone still runs the original 48-bar comparison
(outputs bit-identical). The month overlay x-axis shows about every third UTC
calendar day with no duplicate labels; data and marker positions are unchanged.
