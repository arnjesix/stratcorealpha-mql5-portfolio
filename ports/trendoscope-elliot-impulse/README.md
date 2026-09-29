# Elliot Wave Impulse (Trendoscope) — MT5 indicator port

Original: [Elliot Wave Impulse by Trendoscope (HeWhoMustNotBeNamed)](https://www.tradingview.com/script/TgF24VYW-Elliot-Wave-Impulse/).
MPL-2.0 per the Pine source header; see `CREDITS.md`. This folder contains
an **original MQL5 INDICATOR** (`ElliotWaveImpulse_Trendoscope.mq5`), not an
EA, under the same license (`LICENSE`). No Pine Script text was copied; the
port was written from the algorithm summary below. `original.pine` is the
read-only byte-for-byte reference copy and must not be edited.

This indicator is a pattern-visualization tool. Nothing here is trading
advice, and this folder makes **no win-rate or P&L claims**.

## Files

- `ElliotWaveImpulse_Trendoscope.mq5` — the indicator (install: copy to
  `MQL5/Indicators/`, compile in MetaEditor, attach to a chart).
- `original.pine` — read-only reference copy of the Pine v4 source.
- `acceptance/ew_impulse_check.py` — deterministic algorithm check
  (positive / negative / boundary states). Run:
  `python3 acceptance/ew_impulse_check.py`.
- `README.md` — this file.
- `CREDITS.md` — author citation, source URL, license basis.
- `LICENSE` — verbatim MPL-2.0 text.

## Ported algorithm (from the Pine v4 source)

Inputs: `zigzagLength = 10`, `errorPercent = 5`, `entryPercent = 30`;
constants `waitForConfirmation = true`, `showZigZag = true`,
`zigzagColor = black`, `max_pivot_size = 10`. (`source = input(close)` is
declared in Pine but never used — there is no MQL5 equivalent.)

- `pivots(length)`: a high pivot when the current bar holds the highest high
  of the last `length` bars; a low pivot for the lowest low. Direction
  persists: high-only → `1`, low-only → `-1`, otherwise the previous value.
- `zigzag()`: on a pivot bar, if direction did not change, the newest stored
  pivot is removed and replaced by whichever extreme is further out
  (`value*pivotdir < pivot*pivotdir ? pivot : value`, bar follows the kept
  extreme). If ≥ 2 pivots remain, the direction doubles (`dir*2`) when the
  new pivot extends past the pivot before last. Newest pivot stored at index
  0; lists capped at 10 (oldest popped).
- `ew_impulse()`: with confirmation, uses pivots 1..3 (skips the newest);
  `W1 = |P1-P0|`, `W2 = |P2-P1|`, `r2 = W2/W1`. A pattern matches when `r2`
  is within ±`errorPercent` of any of `0.50 / 0.618 / 0.764 / 0.854` AND the
  stored dirs are `(P1=2, P2=-1)` or `(P1=-2, P2=1)`. A repeated triple
  (any of P0/P1/P2 equal to the last drawn wave) is ignored.
- On match: wave legs P0→P1, P1→P2; levels `entry = P2 ± entry%·W2`,
  `stop = P0`, `tstop = P2 ∓ entry%·W2`, targets at `1.618 / 2.0 / 2.618 /
  3.236 × W2` from P2; bullish/bearish counters; `waveFound` alert.

## Input mapping

| Pine | MQL5 | Notes |
|---|---|---|
| `zigzagLength` (10) | `InpZigzagLength` (10) | must be ≥ 1 (Pine allows 0; 0 has no usable window here) |
| `errorPercent` (5, 2..20) | `InpErrorPercent` (5.0) | range enforced in `OnInit` |
| `entryPercent` (30, 10..100) | `InpEntryPercent` (30.0) | range enforced in `OnInit` |
| `waitForConfirmation` (true const) | `InpWaitForConfirmation` (true) | false → use pivots 0..2 (unconfirmed, repaints more) |
| `showZigZag` (true const) | `InpShowZigZag` (true) | hides the zigzag plot |
| `zigzagWidth/Style/Color` | — | fixed dotted black zigzag; MQL5 `STYLE_DOT` |
| stats table | `InpShowDashboard` (true) | `Comment()` counts, see D3 |
| `alertcondition(waveFormed)` | `InpEnableAlerts` (false) | `Alert()` on last closed signal bar, see D4 |

## Feature parity checklist

| # | Pine output | MQL5 implementation | Status |
|---|---|---|---|
| 1 | Zigzag pivots, dotted black | `DRAW_ZIGZAG` (buffers `ZigZag`), `STYLE_DOT`, black | Implemented; comparison pending |
| 2 | Wave legs W1/W2, green/red | `OBJ_TREND` objects (`EWI_W_<time>_1/2`), newest 100 signals | Implemented; comparison pending |
| 3 | Entry/Stop/T.Stop/Target1-4 lines + labels | 7 `OBJ_HLINE` objects for the latest signal + Data Window buffers `Entry/Stop/TStop/Target1-4` | Partial — see D1 |
| 4 | Bullish/bearish pattern counts table | `Comment()` counts | Partial — see D3 |
| 5 | New-impulse alert | `Alert()` behind `InpEnableAlerts` | Partial — see D4 |
| 6 | Buy/sell-side entry levels | `Buy`/`Sell` arrow buffers at the entry price on the signal bar | Addition (Pine draws no arrows); levels identical |

### Known divergences (no "full parity" claimed)

- **T1 — level lines are infinite HLINEs, unlabeled.** Pine draws finite
  segments from the signal bar ~10 bars forward with text labels
  (`Entry : <price>` …). MQL5 draws full-width dotted HLINEs for the latest
  signal only; exact prices are in the Data Window (`Entry/Stop/TStop/
  Target1-4` buffers). Object labels are not drawn.
- **T2 — zigzag rendering.** Pine connects consecutive stored pivots with
  line segments. MQL5 `DRAW_ZIGZAG` connects alternating non-empty buffer
  values; consecutive same-side pivots (extension legs) render as connected
  segments, which can look slightly different at doubled pivots.
- **T3 — dashboard.** Pine draws a top-right stats table; here counts are
  shown with `Comment()`. Same numbers, different surface.
- **T4 — closed-bar signals only.** Pine evaluates (and alerts) on the
  forming bar too. Here arrows/levels/objects update only for closed bars
  (`i >= 1`); the forming-bar zigzag leg still displays. A signal that Pine
  shows intrabar appears here on bar close instead.
- **T5 — repaint is preserved, not hidden.** The Pine zigzag replaces the
  newest pivot as extremes extend, so historical signals can vanish on both
  platforms. Full oldest→newest recompute each tick reproduces Pine's
  confirmed-history state; it does not promise signals never disappear.
- **T6 — tie-break.** When several bars share the extreme high/low, the most
  recent bar wins (strict `>` scan). Pine's `highestbars`/`lowestbars`
  tie-break is not stated in the source; confirm during chart comparison.
- **T7 — early history.** Bars before a full `zigzagLength` window produce no
  pivots here; Pine's behavior on the first `length-1` bars is not specified
  in the source.
- **T8 — dead code omitted.** The Pine tail block
  `if(existing0 == Point0 and ...) and waveFound[1]` can never execute
  (such triples are already `ignore`d); it is not reproduced.
- **T9 — wave-leg cap.** Pine keeps up to 500 lines/labels; here wave legs
  are kept for the newest 100 signals, levels only for the latest.

## Reproducible same-feed comparison steps

1. TradingView: attach "Elliot Wave - Impulse", defaults
   (`zigzagLength` 10, `errorPercent` 5, `entryPercent` 30). Pick a symbol /
   timeframe with ≥ 60 bars. Record, from the Data Window on closed bars,
   each impulse signal bar time (UTC), its P0/P1/P2 and entry/stop/target
   label values, plus the bullish/bearish counts.
2. MT5: same broker feed (cross-venue feeds differ). Copy the `.mq5` to
   `MQL5/Indicators/`, compile, attach with defaults.
3. MT5: read buffers `Buy/Sell/Entry/Stop/TStop/Target1-4/SigP0-2` on the
   same closed-bar times; compare counts in the `Comment()` readout.
4. Pass criteria: signal bar times identical; levels match to quote
   precision; counts equal. Modulo T1–T2 rendering.
5. On mismatch, record broker, symbol, timeframe, bar time (UTC), TV value,
   MT5 value, and which divergence (T1–T9) was ruled out. Do not fabricate
   numbers — report the blocker instead.

## Verification state (2026-09-29)

- Acceptance fixture (transcription check, not Pine equality):
  `python3 acceptance/ew_impulse_check.py` → `ALL CHECKS PASSED`
  (21 checks: crafted 13-bar series yields exactly one bullish signal on bar
  11 with entry 105.674 / stop 100 / tstop 101.966 / targets per 1.618–3.236
  multiples; vertical mirror yields one bearish signal; flat series yields
  none; strict band-edge boundaries 0.475/0.525 in/out).
- Windows compile in the isolated HolaPrime MetaEditor (v1.01):
  `Result: 0 errors, 0 warnings, 575 ms elapsed, cpu='X64 Regular'`.
  No `.ex5` is stored in the repository.
- Genuine OANDA TradingView and HolaPrime MT5 EURUSD M15 captures are in
  [COMPARISON.md](COMPARISON.md). The MT5 chart visibly draws wave legs,
  markers and levels. Counts are not comparable because the loaded chart
  histories differ; no paired-feed signal or numerical parity is claimed.
