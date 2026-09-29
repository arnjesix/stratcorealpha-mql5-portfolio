# SALMA (RedKTrader) — MT5 indicator port

Original: [RedK Smooth And Lazy Moving Average (SALMA) by RedKTrader](https://www.tradingview.com/script/JWdrXD3I-RedK-Smooth-And-Lazy-Moving-Average-SALMA/)
(`JWdrXD3I`). Pine v5, page source header states Mozilla Public License 2.0;
see `CREDITS.md`. This folder contains an **original MQL5 INDICATOR**
(`SALMA_RedK_MT5.mq5`), not an EA, under the same license (`LICENSE`).
No Pine Script text was copied; the port was written from the algorithm
summary below. No protected or hidden script was retrieved for this port.

This indicator is a price-smoothing visualization tool. Nothing here is
trading advice, and this folder makes **no win-rate, profit, or P&L claims**
and **no full-parity claim** against the TradingView script.

## Files

- `SALMA_RedK_MT5.mq5` — the indicator (install: copy to
  `MQL5/Indicators/`, compile in MetaEditor, attach to a chart).
- `README.md` — this file.
- `CREDITS.md` — author citation, source URL, license basis.
- `LICENSE` — verbatim MPL-2.0 text.
- `acceptance/salma_check.py` — deterministic Python mirror of the ported
  calculation; run with `python3 acceptance/salma_check.py`.

## Ported algorithm (from the Pine description)

Inputs: `price = close`, `length = 10`, `smooth = 3`, `mult = 0.3`,
`sd_len = 5`.

- `baseline = ta.wma(price, sd_len)`; `dev = mult * ta.stdev(price, sd_len)`
  with Pine's **population** (biased, `/N`) stdev.
- `upper / lower = baseline ± dev`; `cprice = clip(price, lower, upper)`
  (the "lazy" clamp: out-of-band prices are pulled to the band edge).
- `REMA = ta.wma(ta.wma(cprice, length), smooth)` (double WMA).
- Color: green when `REMA > REMA[1]` (strict), red otherwise (flat or
  falling reads red).
- `SwingUp` when green now and not green on the previous bar; `SwingDn`
  for the inverse transition. Undefined predecessors read as not-green.
- Optional overlays, hidden by default: MA1 (SMA/EMA/WMA of close,
  length 50, purple) and MA2 (same, length 100, blue).

## Input mapping

| Pine input | MQL5 input | Default |
|---|---|---|
| `price` | `InpPrice` (`ENUM_APPLIED_PRICE`) | `PRICE_CLOSE` |
| `length` | `InpLength` | `10` |
| `smooth` | `InpSmooth` | `3` |
| `mult` | `InpMult` | `0.3` |
| `sd_len` | `InpSdLen` | `5` |
| MA1 show / type / length | `InpShowMA1` / `InpMA1Method` / `InpMA1Length` | `false` / SMA / `50` |
| MA2 show / type / length | `InpShowMA2` / `InpMA2Method` / `InpMA2Length` | `false` / SMA / `100` |
| SwingUp/SwingDn alertconditions | `Alert()` behind `InpEnableAlerts` | `false` (opt-in) |

## Known differences / explicit exclusions (no false "full port" claimed)

- **E1 — MTF source/timeframe option excluded.** The Pine script exposes an
  optional multi-timeframe source/timeframe. It is **not ported**: MTF
  `request.security` semantics could not be soundly verified in this
  timebox, so the indicator runs on the chart timeframe only.
- **D1 — MA overlay source fixed to close.** The Pine overlays use source
  close; the port keeps that (no per-MA source selector).
- **D2 — MA1/MA2 method default.** Pine offers SMA/EMA/WMA choice; the port
  offers the same three choices and defaults to SMA.
- **D3 — colors are approximations.** REMA green/red render as
  `C'76,175,80'` / `C'255,82,82'`; MA1 purple `C'128,0,128'`, MA2 blue.
  Exact Pine palette shades may differ slightly.
- **D4 — swing markers.** `SwingUp`/`SwingDn` render as triangle arrows
  anchored at the REMA value on the signal bar (Pine marker style/offset
  was not specified in the description).
- **D5 — alerts are opt-in.** Pine `alertcondition()` is always armed; here
  `Alert()` fires only with `InpEnableAlerts = true`, once per newly closed
  swing bar. MT5 alert routing (popup/push/email) follows the client setup.
- **D6 — warmup.** Bars before `(sd_len-1)+(length-1)+(smooth-1)` completed
  windows show no REMA (Pine shows `na` there too); no swings fire there.
  MA overlays appear only after their own length warmup.

## Reproducible same-feed comparison protocol

1. TradingView: attach "RedK Smooth And Lazy Moving Average (SALMA)", set
   `price = close`, `length = 10`, `smooth = 3`, `mult = 0.3`, `sd_len = 5`,
   MA1/MA2 hidden. Pick a symbol/timeframe with ample history. Record
   symbol/venue/timeframe and, via the Data Window, the last ~20 **closed**
   bars: time (UTC), REMA value, REMA color, and every SwingUp/SwingDn bar
   time. If MA overlays are compared, enable them with documented
   type/length first.
2. MT5: use the **same broker feed** (cross-venue feeds differ, so
   same-symbol numbers from another venue are not expected to tick-match).
   Copy `SALMA_RedK_MT5.mq5` to `MQL5/Indicators/`, compile, attach with
   matching inputs.
3. MT5: open the Data Window (Ctrl+D) and read buffers `SALMA REMA`,
   `MA1`, `MA2`, `SwingUp`, `SwingDn` on the same closed-bar times.
4. Pass criteria: REMA matches to the quote precision on all compared
   closed bars past the D6 warmup; SwingUp/SwingDn bar times identical;
   colors visually equivalent modulo D3.
5. On mismatch, record: broker, symbol, timeframe, bar time (UTC), TV value,
   MT5 value, and which difference (D1–D6) was ruled out. Do not fabricate
   numbers — report the blocker instead.

## Verification state (2026-09-29, v1.00)

- Deterministic logic mirror (`acceptance/salma_check.py`, 15 checks):
  WMA weighting, population-vs-sample stdev guard, band clipping, REMA
  warmup length, rising-feed green + single SwingUp, flat-feed red with no
  swings, reversal single SwingDn. Run command and output:
  `python3 assets/strategy-ports/salma/acceptance/salma_check.py` →
  `ALL CHECKS PASSED`, exit 0. This checks the transcription, not Pine
  equality.
- Series-index guard: `OnCalculate` forces the used price/time arrays to
  series at the top (index 0 = newest), matching the series indicator
  buffers from `OnInit` — the same time-reversal class as the prior
  HalfTrend bug. Full oldest→newest recompute keeps windowed state
  deterministic.
- MT5 compilation: compiled in the isolated HolaPrime MetaEditor on
  2026-09-29 with `0 errors, 0 warnings`. A visible TradingView chart is
  captured separately; this compilation is not a cross-platform parity test.
