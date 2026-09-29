# ITG Scalper (Complector) — MT5 indicator port

Original: [ITG Scalper by Complector](https://www.tradingview.com/script/AcrZjl6Q-ITG-Scalper/)
(`AcrZjl6Q`). Pine v4, page source header states Mozilla Public License
2.0; see `CREDITS.md`. This folder contains an **original MQL5
INDICATOR** (`ITG_Scalper_Complector_MT5.mq5`), not an EA, under the same
license (`LICENSE`). No Pine Script text was copied; the port was written
from the algorithm summary below. No protected or hidden script was
retrieved for this port.

This indicator is a trend-visualization tool. Nothing here is trading
advice, and this folder makes **no win-rate, profit, or P&L claims** and
**no full-parity claim** against the TradingView script.

## Files

- `ITG_Scalper_Complector_MT5.mq5` — the indicator (install: copy to
  `MQL5/Indicators/`, compile in MetaEditor, attach to a chart).
- `README.md` — this file.
- `CREDITS.md` — author citation, source URL, license basis.
- `LICENSE` — verbatim MPL-2.0 text.
- `acceptance/itg_scalper_check.py` — deterministic Python mirror of the
  ported calculation and signal state machine; run with
  `python3 acceptance/itg_scalper_check.py`.

## Ported algorithm (from the Pine description)

Inputs: TEMA period `14`; filter fast `EMA(close, 12)`, slow
`EMA(close, 26)`, signal `SMA(MACD, 9)`; noise filter on; use-current-TF
for filter `true`; alternate filter timeframe 60 minutes.

- `EMA1 = EMA(close, T)`, `EMA2 = EMA(EMA1, T)`, `EMA3 = EMA(EMA2, T)`
  (Pine `ema()`: `alpha = 2/(T+1)`, seeded from the first non-`na`
  source value, defined from the first available bar — no SMA seed,
  no `T`-bar `na` prefix).
- `TEMA = 3 * (EMA1 - EMA2) + EMA3`.
- Trend: up when `TEMA >= TEMA[1]`, down otherwise (flat reads up).
- Persistent `last_tran` bool, initially `false`; evaluated oldest to
  newest, long branch first (branches are mutually exclusive):
  - long (buy) when trend is up, `last_tran` is false, and
    (`MACD >= signal` or the filter is off); then `last_tran := true`,
    `buyprice := close`.
  - short (sell) when trend is down, `last_tran` is true, and
    (`MACD < signal` or the filter is off); then `last_tran := false`,
    `sellprice := close`.
- Plot: TEMA line, lime when up / red when down (aqua while the colour
  shift is disabled); buy/sell arrows and Buy/Sell text labels with
  toggles.

## Input mapping

| Pine input | MQL5 input | Default |
|---|---|---|
| TEMA period | `InpTemaPeriod` | `14` |
| noise filter on/off | `InpFilterOn` | `true` |
| fast / slow / signal lengths | `InpFastLen` / `InpSlowLen` / `InpSignalLen` | `12` / `26` / `9` |
| use current TF for filter | `InpUseCurrentTF` | `true` |
| alternate filter TF | `InpAlternateTF` | `PERIOD_H1` (reserved, see L1) |
| colour shift on/off | `InpUseColorChange` | `true` (off = aqua line) |
| arrows / labels toggles | `InpShowArrows` / `InpShowLabels` | `true` / `true` |
| alert() buy/sell | `Alert()` behind `InpEnableAlerts` | `false` (opt-in) |

## Known differences / explicit limitations (no false "full port" claimed)

- **L1 — chart-timeframe filter only.** The Pine script can evaluate the
  MACD filter on an alternate 60-minute timeframe. This port evaluates
  the filter on the **chart timeframe only**: `InpAlternateTF` is kept
  visible as a reserved input documenting the Pine default, but it is
  currently unused, and `InpUseCurrentTF = false` falls back to the chart
  timeframe. The MTF filter is therefore an explicit exclusion, not a full
  port of that option.
- **P1 — percent label excluded.** The optional percent label was omitted
  as permitted (resource/time); arrows + Buy/Sell text labels cover the
  signal marking. Documented here rather than silently dropped.
- **D1 — arrow/label anchors.** Buy arrows anchor at the bar low, sell
  arrows at the bar high; text labels sit at the same anchors (Pine anchor
  prices were not specified in the description).
- **D2 — colors are approximations.** TEMA lime/red/aqua render as
  `C'0,255,0'` / `C'255,0,0'` / `C'0,255,255'`; exact Pine shades may
  differ slightly.
- **D3 — `buyprice`/`sellprice` are internal state.** They latch the signal
  bar close exactly as in Pine but are not exposed as buffers; signal bars
  are marked by the arrow buffers (Data Window) and label objects.
- **D4 — alerts are opt-in.** Pine `alert()` calls are always armed; here
  `Alert()` fires only with `InpEnableAlerts = true`, once per newly
  closed signal bar. MT5 alert routing follows the client setup.
- **D5 — warmup.** The TEMA/MACD EMAs are first-value seeded, so they
  are defined from the first bar; only the signal `SMA(MACD, 9)` imposes
  a hard `na` warmup (9 MACD bars), and trend needs one prior TEMA bar.
  Early TEMA/MACD values are still in seed transient, so same-feed
  comparisons should allow settling past roughly `3*(T-1)` bars before
  judging parity. Forming-bar signals can vanish on the live bar —
  alerts and comparisons use closed bars only.
- **D6 — Pine `ema()` edge behavior unverified.** The first-value seed
  plus `alpha = 2/(len+1)` recursion above follows the task-quoted Pine
  `ema()` rule (`ema1 = ema(realC, len)` triple smoothing, current-TF
  close as source). No Pine source file is vendored in this folder, so
  `na`-propagation subtleties beyond the gap-skip (gaps stay empty,
  never reset the seed) are a stated unknown, not a parity claim.

## Reproducible same-feed comparison protocol

1. TradingView: attach "ITG Scalper", set TEMA `14`, filter on with
   `12 / 26 / 9`, current-timeframe filter, colour shift on, arrows and
   labels on. Pick a symbol/timeframe with ample history. Record
   symbol/venue/timeframe and, via the Data Window, the last ~20 **closed**
   bars: time (UTC), TEMA value, TEMA color, and every buy/sell bar time.
2. MT5: use the **same broker feed** (cross-venue feeds differ, so
   same-symbol numbers from another venue are not expected to tick-match).
   Copy `ITG_Scalper_Complector_MT5.mq5` to `MQL5/Indicators/`, compile,
   attach with matching inputs (leave `InpAlternateTF` reserved).
3. MT5: open the Data Window (Ctrl+D) and read buffers `ITG TEMA`,
   `Buy`, `Sell` on the same closed-bar times.
4. Pass criteria: TEMA matches to the quote precision on all compared
   closed bars past the D5 warmup; buy/sell bar times identical; colors
   visually equivalent modulo D2.
5. On mismatch, record: broker, symbol, timeframe, bar time (UTC), TV value,
   MT5 value, and which limitation (L1, P1, D1–D6) was ruled out. Do not
   fabricate numbers — report the blocker instead.

## Verification state (2026-09-29, v1.00)

- Deterministic logic mirror (`acceptance/itg_scalper_check.py`, 15
  checks): EMA first-value seeding + alpha steps + gap-skip, TEMA
  identity on constants from the first bar with no `na` warmup,
  first-buy-at-bar-1 plus one-buy-then-one-sell latch on rise/fall,
  filter ON blocking vs OFF allowing, no-sell-without-prior-long
  (`last_tran` init), chop alternation, flat-TEMA `>=` boundary,
  signal `SMA(9)` `na` for the first 8 bars only. Run command and output:
  `python3 assets/strategy-ports/itg-scalper/acceptance/itg_scalper_check.py`
  → `ALL CHECKS PASSED`, exit 0. This checks the transcription, not Pine
  equality.
- Series-index guard: `OnCalculate` forces the used price/time arrays to
  series at the top (index 0 = newest), matching the series indicator
  buffers from `OnInit` — the same time-reversal class as the prior
  HalfTrend bug. Full oldest→newest recompute keeps `last_tran`
  deterministic.
- MT5 compilation: compiled in the isolated HolaPrime MetaEditor on
  2026-09-29 with `0 errors, 0 warnings`. Compilation does not establish
  cross-platform signal parity.
