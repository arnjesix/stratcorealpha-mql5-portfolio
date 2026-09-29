# ICT Turtle Soup (Flux Charts) — MT5 indicator port

Original: [ICT Turtle Soup | Flux Charts by fluxchart](https://www.tradingview.com/script/b67pK4jN-ICT-Turtle-Soup-Flux-Charts/).
MPL-2.0 per the Pine source header; see `CREDITS.md`. This folder contains
an **original MQL5 INDICATOR** (`TurtleSoup_FluxCharts.mq5`), not an EA (it
places no orders), under the same license (`LICENSE`). No Pine Script text
was copied; the port was written from the algorithm summary below.
`original.pine` is the read-only byte-for-byte reference copy and must not
be edited.

This indicator is a pattern-visualization tool. Nothing here is trading
advice, and this folder makes **no win-rate or P&L claims**.

## Files

- `TurtleSoup_FluxCharts.mq5` — the indicator (install: copy to
  `MQL5/Indicators/`, compile in MetaEditor, attach to a chart).
- `original.pine` — read-only reference copy of the Pine v5 source.
- `acceptance/turtle_soup_check.py` — deterministic algorithm check
  (positive / negative / boundary states). Run:
  `python3 acceptance/turtle_soup_check.py`.
- `README.md` — this file.
- `CREDITS.md` — author citation, source URL, license basis.
- `LICENSE` — verbatim MPL-2.0 text.

## Ported algorithm (from the Pine v5 source)

One active setup at a time. Each bar (within the last 4900, Pine
`maxDistanceToLastBar`), a fresh setup is created once the previous one
exited, snapshotting the rolling range (`ta.highest/lowest` over
`HTF minutes / chart minutes` bars) and its start bar.

- **Liquidity sweep** (sellside checked first): Wick mode breaks when
  `low < range low` (sellside → Classic Long) or `high > range high`
  (buyside → Classic Short). Adaptive mode flips the side using the
  `highBreaks/lowBreaks` counters (+1 per take-profit, −1 per stop-loss,
  can go negative).
- **MSS execution** (next bar onward): Short when price breaks below the
  lowest low of the prior `mssOffset` bars (`lowMSS[1]`); Long above
  `highMSS[1]`. Wick entries fill at the MSS level, Close entries at close.
- **TP/SL**: Fixed mode uses `±tpPercent/slPercent` of entry. Dynamic mode:
  `SL = swing extreme ± ATR(5) × risk multiplier`
  (Highest 10 / High 6.5 / Normal 5.5 / Low 3.5 / Lowest 1.15),
  `TP = entry ± |entry − SL| × 0.9`. Exit branches run in Pine's exact
  order (TP pair, then SL pair), so a same-bar TP+SL hit ends as Stop Loss.
- Dashboard counts wins/losses/profit with Pine's formulas (open trades
  count as losses).

## Input mapping

| Pine | MQL5 | Notes |
|---|---|---|
| `mssOffset` (10) | `InpMssSwingLen` (10) | ≥ 1 |
| `higherTimeframe` ("60") | `InpHigherTimeframeMin` (60) | minutes; must exceed chart TF or the indicator stops with a log message (Pine `runtime.error` equivalent) |
| `breakoutMethod` (Wick) | `InpBreakoutMethod` ("Wick") | Close\|Wick |
| `entryMethod` (Classic) | `InpEntryMethod` ("Classic") | Classic\|Adaptive (faithful counter logic) |
| `showHL` (false) | `InpShowLiqZones` (false) | liquidity-zone rectangles |
| `showLiqGrabs` (true) | `InpShowLiqGrabs` (true) | sweep arrow buffers |
| `showTPSL` (true) | `InpShowTPSL` (true) | TP/SL drawings |
| `tpslMethod` (Dynamic) | `InpTpslMethod` ("Dynamic") | Dynamic\|Fixed |
| `riskAmount` (Low) | `InpRisk` ("Low") | Highest\|High\|Normal\|Low\|Lowest → 10/6.5/5.5/3.5/1.15 |
| `tpPercent` (0.3), `slPercent` (0.4) | `InpTpPercent`, `InpSlPercent` | Fixed mode |
| `RR` (0.9 const) | `InpRiskReward` (0.9) | Dynamic TP distance factor |
| `TP / SL Layout` (Default) | `InpTpslLayout` ("Default") | Default (dashed lines) \| Alternative (boxes) |
| Buy/Sell/TP/SL alert toggles | `InpAlertBuy/Sell/TP/SL` (all true) | plus master `InpEnableAlerts` (false), see F4 |
| Buy/Sell/Text colors | chart-color inputs | same defaults (green/red/white/blue) |
| Backtesting dashboard toggles | `InpShowDashboard` (true) | `Comment()` readout, see F3 |
| `DEBUG`/`maxTPLastHour`/label-size/debug inputs | — | constants folded in (`DEBUG=false`, `maxTPLastHour=false`), see F6 |

## Feature parity checklist

| # | Pine output | MQL5 implementation | Status |
|---|---|---|---|
| 1 | Sweep → MSS entry sequencing | identical state machine, sellside-first, same-bar entry+exit allowed | Implemented; comparison pending |
| 2 | Fixed/Dynamic TP/SL exits, SL-overwrites-TP order | identical branch order, single final-state marker | Implemented; comparison pending |
| 3 | Entry Buy/Sell labels, TP (× blue) / SL (● red) markers | arrow buffers `Buy/Sell/TakeProfit/StopLoss` + `OBJ_TEXT` entry labels | Implemented; comparison pending |
| 4 | Sweep circle labels | `SweepHigh`/`SweepLow` arrow buffers at sweep price | Partial — see F2 |
| 5 | Target-liquidity boxes, TP/SL dashed lines + TP/SL labels (Default) | `OBJ_RECTANGLE` / `OBJ_TREND` / `OBJ_TEXT` for newest 125 setups | Implemented; comparison pending |
| 6 | Alternative TP/SL box layout | `OBJ_RECTANGLE` around TP/SL ± ATR/3 | Implemented; comparison pending |
| 7 | Backtest table (entries/wins/losses/winrate/avg/total) | `Comment()` with identical formulas | Partial — see F3 |
| 8 | Buy/Sell/TP/SL alerts | `Alert()` behind per-type toggles + master switch | Partial — see F4 |

### Known divergences (no "full parity" claimed)

- **F1 — closed-bar output.** Pine evaluates intrabar; here all markers and
  levels are written from closed-bar values only. A signal Pine shows
  intrabar appears here on bar close instead. No look-ahead either way.
- **F2 — sweep/entry label anchors.** Pine positions sweep circles at the
  *current redraw bar's* high/low and entry labels at the *current* close
  (a quirk of its redraw loop). Here sweep markers sit at the sweep-bar
  price and entry labels at the stored entry-bar close — a deliberate,
  documented fix; expect these anchors to differ from screenshots.
- **F3 — dashboard surface.** Pine draws a positioned table; here the same
  six numbers (including "open trades count as losses") are shown with
  `Comment()`. Position/background options have no equivalent.
- **F4 — alerts are opt-in and bootstrap-skipped.** Pine arms `alert()`
  after history bootstrap; here `Alert()` additionally requires
  `InpEnableAlerts = true` and skips the bootstrap bar (the `initRun`
  equivalent). MT5 routing (popup/push/email) follows the client setup.
- **F5 — drawing opacity/text.** Pine boxes/labels are translucent with
  text; MQL5 rectangles are opaque and carry no text (level prices are in
  the Data Window buffers `EntryPrice/StopLevel/TakeProfitLevel`).
  `OBJPROP_BACK` keeps them behind candles.
- **F6 — folded constants.** `DEBUG=false` (label size fixed small),
  `maxTPLastHour=false` (Dynamic TP uses `tpTarget`; the dead branch is
  kept visible in code comments), `customSLATRMult`/`atrLen=5`/
  `maxDistanceToLastBar=4900` fixed as in Pine. `dayEndedBeforeExit` is
  never assigned in Pine — omitted.
- **F7 — HTF mapping.** Pine `input.timeframe` accepts any timeframe; here
  the higher timeframe is minutes (`InpHigherTimeframeMin`) and the range
  length is integer-truncated (`HTF/chart`, same as Pine's `int` cast).
  Non-minute timeframes (D/W/M) have no direct equivalent.
- **F8 — na-guards.** Pine would lock a setup forever if a Dynamic SL came
  out `na` (early-history ATR seeding); here entry is deferred until ATR
  and swing windows are valid. Behavior differs only in the first ~5 bars
  of chart history.
- **F9 — performance.** Full oldest→newest recompute each tick is
  O(bars × (HTF window + MSS window)); the 4900-bar machine window caps
  history. Very large HTF/chart ratios (e.g. H1 HTF on M1) are slow —
  prefer equal-or-close timeframe ratios for live use.

## Reproducible same-feed comparison steps

1. TradingView: attach "ICT Turtle Soup | Flux Charts", set MSS 10, HTF
   matching your chart (e.g. 60 on a 5-minute chart), Wick/Classic/Dynamic/
   Low risk. Record closed-bar Buy/Sell/TP/SL times (UTC) and dashboard
   totals over the same bar window.
2. MT5: same broker feed (cross-venue feeds differ). Copy the `.mq5` to
   `MQL5/Indicators/`, compile, attach with the mapped inputs above.
3. MT5: read buffers `Buy/Sell/TakeProfit/StopLoss/SweepHigh/SweepLow` and
   the `Comment()` dashboard on the same closed-bar times.
4. Pass criteria: event bar times identical; entry/exit prices match to
   quote precision; dashboard entries/wins/losses equal. Modulo F1–F2
   anchors and F5 rendering.
5. On mismatch, record broker, symbol, timeframe, bar time (UTC), TV value,
   MT5 value, and which divergence (F1–F9) was ruled out. Do not fabricate
   numbers — report the blocker instead.

## Verification state (2026-09-29, v1.02)

- Acceptance fixtures (transcription checks, not Pine equality):
  `python3 acceptance/turtle_soup_check.py` → `ALL CHECKS PASSED`
  (17 checks: long sweep→MSS entry→TP with exact levels; flat market
  silent; same-bar TP+SL resolves to SL only with `highBreaks` net 0;
  short Dynamic SL/TP exact numbers 146.0/58.6; open trade counts as
  dashboard loss).
  `python3 acceptance/series_guard_check.py` → `SERIES GUARD PASSED`.
  `python3 acceptance/window_guard_check.py` → `WINDOW GUARD PASSED`
  (new in v1.02: asserts the machine gate keeps the newest 4900 bars,
  `bool inWindow = (i < TSF_MAXBARS)`, plus a 6000-bar mirror run proving
  a recent sweep→entry→TP pattern produces recent-window events).
- v1.02 root-cause fix: v1.01 gated the machine on `k < TSF_MAXBARS`
  (`k` = age from the oldest bar), keeping the oldest 4900 bars. On any
  symbol with >4900 bars of history (clone EURUSD M15 holds multi-year
  history: `Bases/HolaPrime-Server1/history/EURUSD/2024..2026.hcc`,
  tens of MB) every live bar was skipped, all nine buffers stayed
  `EMPTY_VALUE`, and the chart showed no markers while the indicator
  still loaded. Pine (`bar_index > last_bar_index - 4900`) and the
  Python mirror (`j > n - 1 - max_bars`) both keep the newest bars.
  One-token fix plus version bump to 1.02; ATR seeding and rolling
  windows still use full history (`k`-based), matching `ta.atr` /
  `ta.highest` / `ta.lowest`.
- Windows compile in the isolated HolaPrime MetaEditor (v1.02):
  `Result: 0 errors, 0 warnings, 771 ms elapsed, cpu='X64 Regular'`.
- Genuine OANDA TradingView and HolaPrime MT5 EURUSD M15 captures are in
  [COMPARISON.md](COMPARISON.md). The MT5 chart visibly draws sweep, entry,
  TP and SL markers in the 22–29 September window. This verifies rendering,
  not paired-feed signal or numerical parity.
