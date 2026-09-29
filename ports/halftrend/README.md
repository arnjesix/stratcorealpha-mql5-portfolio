# HalfTrend (everget) — MT5 indicator port

Original: [HalfTrend [everget] by Alex Orekhov](https://www.tradingview.com/script/U1SJ8ubc-HalfTrend-everget/)
(`U1SJ8ubc`). GPL-3.0 per the Pine v6 source header visible on 2026-09-28;
see `CREDITS.md`. This folder contains an **original MQL5 INDICATOR**
(`HalfTrend_Everget_MT5.mq5`), not an EA, under the same license
(`LICENSE`). No Pine Script text was copied; the port was written from the
algorithm summary below.

This indicator is a trend-visualization tool. Nothing here is trading advice,
and this folder makes **no win-rate or P&L claims**.

## Files

- `HalfTrend_Everget_MT5.mq5` — the indicator (install: copy to
  `MQL5/Indicators/`, compile in MetaEditor, attach to a chart).
- `README.md` — this file.
- `CREDITS.md` — author citation, source URL, license basis.
- `LICENSE` — verbatim GPL-3.0 text (copy of the official system text).

## Ported algorithm (from the current Pine source)

Inputs: `amplitude = 2`, `channelDeviation = 2`, `showArrows / showChannels /
showLabels = true`.

- State: `trend = 0`, `nextTrend = 0`, `maxLowPrice = nz(low[1], low)`,
  `minHighPrice = nz(high[1], high)`, `up`/`down` start at 0.
- `atr2 = ta.atr(100)/2`; `dev = channelDeviation * atr2`.
- `highPrice`/`lowPrice` = highest high / lowest low over `amplitude` bars;
  `highma`/`lowma` = SMA(high/low, `amplitude`).
- `nextTrend == 1`: ratchet `maxLowPrice` up; flip to `trend = 1` when
  `highma < maxLowPrice and close < low[1]`, setting
  `minHighPrice = highPrice`. Else: ratchet `minHighPrice` down; flip to
  `trend = 0` when `lowma > minHighPrice and close > high[1]`, setting
  `maxLowPrice = lowPrice`.
- `trend == 0`: on a 1→0 transition `up` takes the previous `down` and a buy
  triangle anchors at `up - atr2`; otherwise `up = max(maxLowPrice, up[1])`;
  channels `up ± dev`. Mirror for `trend == 1` with `down + atr2` sell anchor.
- `ht = trend == 0 ? up : down`, blue in uptrend, red in downtrend; ATR
  high/low channels, fill ribbons, buy/sell triangles plus Buy/Sell labels at
  the arrow anchors on transitions; buy/sell alertconditions.

## Feature parity checklist

| # | Pine output | MQL5 implementation | Status |
|---|-------------|---------------------|--------|
| 1 | Inputs amplitude / channelDeviation | `InpAmplitude` (int, 2), `InpChannelDeviation` (double, 2.0) | Implemented; comparison pending |
| 2 | `showArrows` toggle | `InpShowArrows` (hides both arrow plots via `DRAW_NONE`) | Implemented; comparison pending |
| 3 | `showChannels` toggle | `InpShowChannels` (hides both channel plots) | Implemented; comparison pending |
| 4 | `showLabels` toggle | `InpShowLabels` (skips label objects; purges on init/deinit) | Implemented; comparison pending |
| 5 | HT line, blue/red | `DRAW_COLOR_LINE`, colors `C'41,98,255'` / `C'255,82,82'` (= Pine `color.blue` #2962FF / `color.red` #FF5252), width 2 | Implemented; comparison pending |
| 6 | ATR high/low channels, dotted-circle style | Two `DRAW_COLOR_LINE` plots with `STYLE_DOT`, width 1 | Partial — see D1 |
| 7 | Fill ribbons between HT and channels | Four `DRAW_FILLING` plots (up-high, up-low blue; dn-high, dn-low red), EMPTY-gapped by trend | Partial — see D2 |
| 8 | Buy/sell triangles on transitions | `DRAW_ARROW` codes 233/234 at `up-atr2` / `down+atr2` (matches the Feb-2021 switch to built-in triangles) | Implemented; comparison pending |
| 9 | Buy/Sell text labels at arrow anchors | `OBJ_TEXT` chart objects (`HT_Everget_Buy/Sell_<bar epoch>`), same anchor prices, blue/red | Partial — see D3 |
| 10 | `alertcondition` buy/sell | `Alert()` on the last closed signal bar, behind `InpEnableAlerts` (default false) | Partial — see D4 |
| 11 | Wilder `ta.atr(100)` seeding | RMA seeded with SMA of first 100 TRs | Implemented; comparison pending — see D5 |
| 12 | Extra MQL5-only toggle `InpShowFills` (default true) | Lets users disable fills (opaque in MQL5) without touching Pine parity defaults | Addition, documented |

### Known divergences (no false "full parity" claimed)

- **D1 — channel markers.** Pine draws the ATR channels with a dotted/circle
  plot style. MQL5 line plots offer `STYLE_DOT` but no circle-marker line
  style, so channels render as dotted lines without markers.
- **D2 — fill opacity.** Pine `fill()` is translucent; MQL5 `DRAW_FILLING` is
  opaque, so ribbons can cover candles more heavily. Colors follow the trend
  (blue up / red down) as in Pine. Set `InpShowFills = false` for a bare-line
  chart.
- **D3 — labels are chart objects, not plot buffers.** MQL5 indicator buffers
  are numeric only, so Buy/Sell text is drawn as `OBJ_TEXT` objects at the
  exact arrow prices (buy anchored below at `atrLow`-side anchor, sell above).
  Objects are created incrementally, refreshed on recalc, the forming-bar
  object is removed if its signal vanishes, and all are deleted in `OnDeinit`.
  They do not appear in the Data Window; arrows (buffers 6/7) do.
- **D4 — alerts are opt-in.** Pine `alertcondition()` is always armed;
  here `Alert()` fires only with `InpEnableAlerts = true`, once per closed
  signal bar. MT5 alert routing (popup/push/email) follows the client setup.
- **D5 — warmup.** Bars before the ATR(100) warmup complete show HT without
  channels/arrows; signals on the first 100 bars are suppressed by
  construction (arrow math needs `atr2`). First-cycle line seeding uses
  `maxLowPrice`/`minHighPrice` where Pine's `nz` fallbacks are not observable
  from the summary; after the first full trend cycle the state machine is
  exactly the summary logic. Rolling high/low ties resolve to the most recent
  bar (Pine tie-break not specified in the summary).
- **D6 — channel color.** The summary states HT is blue/red but does not
  specify channel colors; channels here follow the trend color. Confirm
  against the live TradingView chart during comparison.

## Reproducible same-feed comparison steps

1. TradingView: open the underlying, attach "HalfTrend [everget]", set
   amplitude `2`, channelDeviation `2`, all three show-toggles on. Pick a
   timeframe with ≥ 150 bars of history. Record symbol/venue/timeframe and,
   via the Data Window, the last ~20 **closed** bars: time (UTC), HT value,
   ATR-high, ATR-low, and every Buy/Sell bar time.
2. MT5: use the **same broker feed** (cross-venue feeds differ, so
   same-symbol numbers from another venue are not expected to tick-match).
   Copy `HalfTrend_Everget_MT5.mq5` to `MQL5/Indicators/`, compile, attach
   with defaults (`InpShowFills` may be set false for readability — it does
   not change numeric buffers).
3. MT5: open the Data Window (Ctrl+D) and read buffers `HalfTrend`,
   `ATR High`, `ATR Low`, `Buy`, `Sell` on the same closed-bar times.
4. Pass criteria: HT/ATR-high/ATR-low match to the quote precision on all
   compared closed bars except possibly the first 100 bars of chart history
   (ATR seeding, D5); Buy/Sell bar times identical; colors/ribbons visually
   equivalent modulo D1–D3.
5. On mismatch, record: broker, symbol, timeframe, bar time (UTC), TV value,
   MT5 value, and which divergence (D1–D6) was ruled out. Do not fabricate
   numbers — report the blocker instead.

## Verification state (2026-09-29, v1.01)

- Root cause fixed (v1.01): `OnCalculate` price/time arrays arrive
  **non-series** (index 0 = oldest) per official MQL5 semantics, while the
  indicator buffers were set **series** (`0` = newest) in `OnInit`. The loop
  uses series `i / i+1 / i+j` lookbacks, so without alignment the state
  machine ran time-reversed with future leak and suppressed arrows (the
  deterministic mirror below shows 0 arrows before the fix on a feed where
  the fixed logic fires). The fix forces the used `time/high/low/close`
  arrays to series at the top of `OnCalculate`; the loop itself is unchanged.
- Deterministic logic mirror (throwaway `/tmp/w7_halftrend_mirror.py`, not
  shipped; 400-bar synthetic trending feed, seed 42): fixed logic gives
  `HT 400/400, HI/LO 301/400 (= 400 − 99 ATR warmup), BUY 1 SELL 1`,
  `HI ≥ HT ≥ LO` violations `0`; pre-fix mirrored logic gives `BUY 0 SELL 0`
  on the same feed. This checks the transcription, not Pine equality.
- Windows compile in the isolated HolaPrime MetaEditor (v1.01):
  `Result: 0 errors, 0 warnings, 1018 ms elapsed, cpu='X64 Regular'` (log:
  `C:\Users\arnje\AppData\Local\Temp\w7-halftrend-fix.log`).
  This confirms syntax/build only.
- Live buffer probe on real HolaPrime EURUSD H1 history (throwaway EA
  `W7_HT_Probe` via `iCustom`, no trades/orders; tester `Model=1`):
  - Oct 2024 (`2024.10.01–2024.10.31`): `copied 489/489/489/489/489`,
    `HT 489/489, HI 390, LO 390 (= 489 − 99 warmup), BUY 9, SELL 8`,
    `checked 390, viol 0`, last closed `HT 1.08550, HI 1.08650, LO 1.08450`.
  - Sep 2026 (`2026.09.01–2026.09.29`): `copied 1000/1000/1000/1000/1000`,
    `HT 1000/1000, HI 1000, LO 1000, BUY 22, SELL 22`,
    `checked 1000, viol 0`, last closed `HT 1.13705, HI 1.13805, LO 1.13605`.
  - `viol` = bars with defined channels where `HI ≥ HT ≥ LO` fails.
    Tester reports `w7_ht_probe_202410.htm` / `w7_ht_probe_202609.htm` and
    agent log `W7_HT_PROBE RESULT` lines sit with the isolated portable
    clone (outside this repo); the probe EA itself is throwaway and not
    shipped here. Buffers are genuinely non-empty on real data (not just
    compile success); arrows fire on both periods.
- Genuine TradingView and HolaPrime MT5 screenshots are paired in
  [COMPARISON.md](COMPARISON.md). This proves visible chart output after the
  fix, not cross-feed numeric or signal-time parity.
- Live re-check on an open chart (the running terminal still holds the old
  `.ex5` in memory; re-attach v1.01 first): Data Window (Ctrl+D) on EURUSD H1
  must show `HalfTrend`, `ATR High`, `ATR Low` numeric (not `empty`) on
  closed bars past the first ~100 bars of history, plus `Buy`/`Sell` values
  only on transition bars; or run a `CopyBuffer(handle, 0/2/4/6/7, …)` script
  and require `HT > 0` non-empty with `HI ≥ HT ≥ LO` wherever channels exist.
