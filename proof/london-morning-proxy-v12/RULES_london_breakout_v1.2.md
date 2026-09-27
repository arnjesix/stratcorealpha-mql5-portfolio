# Getestet #2 — London Breakout, frozen rules v1.2 (SERVER-clock proxy, first-tick exit)

Status: FROZEN 2026-09-27. Binding for the native MT5 pass in this turn.
v1.0 (`RULES_london_breakout_v1.0.md` / `.json`) is UNCHANGED and remains the
London-wall definition. v1.1 is RETAINED as prior exploratory evidence but
SUPERSEDED by this v1.2 due to a documented text/code ambiguity: v1.1 text
said time exit at the CLOSE of the first completed bar whose OPEN >= 19:00,
while the EA actually enforces at the first modelled tick at/after 19:00
SERVER (including the OnTick no-new-bar path). v1.2 resolves the wording to
match the executable logic. No trading decision other than this wording
clarification changes; fixed 0.01 lot unchanged.

## 0. Why v1.2 exists (caveat, read first)

The native MT5 Strategy Tester evaluates bars on the HolaPrime SERVER clock
(`HH:MM` server time). No proven year-round server→London offset exists for
the 12-month window 2025-09-01→2026-09-01, so v1.0's Europe/London windows
cannot be transferred 1:1 into EA inputs. v1.2 therefore freezes a FIXED
SERVER-clock morning proxy:

- Range window: server OPEN time in **[10:00, 11:00)** — the four M15 bars
  opening at 10:00, 10:15, 10:30, 10:45 server.
- Entry window: server OPEN time in **[11:00, 14:00)** — first strict close
  outside the range; earliest signal candidate is the 11:00 bar.
- Time exit (flat): first modelled tick at-or-after **19:00** SERVER on the
  same server date, at market (`exit_reason=time_exit`). The flat leg runs
  every tick once server time is >= 19:00 while a position is open,
  including the OnTick no-new-bar path. It does NOT wait for the close of
  the 19:00 bar.

**This proxy is NOT established exact London wall time.** It is a fixed,
auditable server grid chosen before the run. No London-session alignment is
claimed. The run manifest records the tester server times; any
server→London offset mapping happens offline later under an explicitly
frozen broker-offset policy, never assumed here.

## 1. Instrument and bar basis

- Symbol: EURUSD. Timeframe: M15.
- Only COMPLETED M15 bars (shift >= 1) are used for range, signal, stop,
  and target derivation. The forming bar is never read for those decisions.
  The time-exit flat leg additionally runs on every modelled tick at/after
  19:00 SERVER (see §5).
- The trade date is the SERVER calendar date of the signal bar's OPEN time.
  Bars from any other server date are never mixed into a day's range or scan.

## 2. Range window (conservative, fixed, server clock)

- Range high = max(high) of the four completed 10:xx bars.
  Range low = min(low) of those four completed bars.
- The range is complete only when all four bars are present.
  A day missing any range bar is a NO-TRADE day (`reason=range_incomplete`).
- Degenerate guard: range width must be >= 3.0 pips (0.00030).
  A narrower or zero-width range is a NO-TRADE day
  (`reason=range_degenerate`).

## 3. Entry window and signal (strict, completed-bar, server clock)

- Entry window: server OPEN time in **[11:00, 14:00)**.
- The signal scan starts only AFTER the range window is complete
  (no lookahead: the 11:00 bar is the earliest signal candidate).
- Signal = the FIRST completed M15 bar in the entry window whose CLOSE is
  strictly outside the range:
  - close > range high → BUY signal;
  - close < range low → SELL signal;
  - close == range edge → NO signal (equality never triggers).

## 4. One entry per day (hard cap, restart-safe)

- Maximum ONE fill per SERVER calendar date.
- Counted by reconstructing the day's own-magic ENTRY deals from deal
  history, so a terminal restart cannot reset the cap. A `HistorySelect`
  failure fails CLOSED (cap treated as reached, no extra trade).
- No second entry after a fill, even if the trade closes inside the same
  entry window. No pyramiding: no new signal while an own-magic position
  is open.

## 5. Stop, target, time exit (first-tick SERVER flat)

- BUY: stop = range low. SELL: stop = range high.
- Risk distance = |entry − stop|. Must be > 0 and must clear
  `SYMBOL_TRADE_STOPS_LEVEL`, or the signal is rejected (NO-TRADE).
- Target = entry ± 1.0 × risk distance (1R):
  BUY target = entry + risk; SELL target = entry − risk.
- Time exit: if neither stop nor target is hit first, the position is
  closed at the first modelled tick with server time >= 19:00 on the same
  server date, at market (`exit_reason=time_exit`). This is enforced on
  every tick (OnTick no-new-bar path) and re-checked on each new completed
  bar. It does NOT wait for the 19:00 bar's close.
- Overnight positions do not exist by construction (flat leg runs every
  tick once server time is >= 19:00 while a position is open).

## 6. Sizing (FROZEN: fixed 0.01 lot)

- Fixed volume **0.01 lot** for every signal (`InpFixedLot = 0.01`).
- The 0.01 lot is clamped to the symbol's volume min/max/step: rounded DOWN
  to the volume step, NEVER forced up to the minimum — a below-minimum
  size skips the trade (logged, `reason=lot_below_min`).
- No risk-percent sizing, no compounding, no martingale. Currency results
  come only from the broker's own tester fills, never from an offline model.

## 7. Native fills, spread, commission (explicit)

- Entries/exits execute at REAL tester fills (ask for BUY, bid for SELL).
  No offline spread assumption is applied inside the EA.
- The offline v1.0 1.0-pip entry-worsening assumption belongs to the
  offline engine only and is NOT replicated natively; native friction is
  whatever the tester models (recorded in the run manifest: `Model=1`,
  one-minute OHLC generated ticks).
- Commission/swap: whatever the HolaPrime tester applies (expected 0.0
  intraday; recorded from deal history, never assumed).

## 8. Intrabar ambiguity (tester-resolved, flagged offline)

- Stop/target are held as REAL SL/TP on the position where the broker
  accepts them; otherwise they are evaluated per completed bar AFTER the
  signal bar in chronological order.
- Bars spanning both levels would be resolved stop-first in the offline
  model; natively the tester's own fill order governs and the exported
  deals show which leg filled. No ambiguity is hidden: bars, deals, and
  events are all exported.

## 9. Missing data, weekends, holidays

- No interpolation, no forward-fill, no synthetic bars — ever.
- Days with an incomplete range are NO-TRADE (`range_incomplete`).
- The entry scan walks only present completed bars; gaps (weekend,
  holiday, missing history) simply yield fewer candidates.
- A day with a complete range but no qualifying close is NO-TRADE
  (`no_signal`).

## 10. Tester-only, no live path

- The EA unconditionally refuses to run outside the strategy tester
  (`MQLInfoInteger(MQL_TESTER)` gate; `INIT_PARAMETERS_INCORRECT` off-tester).
- `AllowLiveTrading=0`, `AllowDllImport=0` in the tester ini. No DLL, no
  cloud (`UseCloud=0`), no optimization (`Optimization=0`).

## 11. Exports (audit sufficiency, `g2_lb12_` basename)

All exports land in the tester Files directory under the `g2_lb12_` prefix
(never a T99 name, never the v1.1 `g2_lb_` prefix), then are copied to the
worker's own run directory:

- `g2_lb12_bars.csv` — seq,server_time,open,high,low,close,bar_time_iso
  (one row per COMPLETED bar).
- `g2_lb12_equity.csv` — seq,server_time,balance,equity (init snapshot, then
  every tester tick best-effort, then deinit snapshot).
- `g2_lb12_deals.csv` — seq,ticket,server_time,symbol,magic,direction,
  entry,volume,price,commission,swap,profit (own-magic deals on deinit scan).
- `g2_lb12_events.csv` — seq,server_time,event,detail (range/signal/skip/
  fill/exit/flat decisions with rule + values).
- `g2_lb12_run.json` — tester start/end server times, symbol/timeframe,
  frozen inputs, file row counts, tick-recording limits, rules file hashes.

TIME HONESTY: in the tester `TimeGMT()` equals the modeled server time, so
it is NEVER exported as UTC. All exports carry explicit SERVER timestamps
plus a per-row seq. UTC conversion happens OFFLINE later under a frozen
broker-offset policy.

## 12. What changes require a new version

Any change to: range/entry windows, server-vs-London basis, strict-vs-touch
semantics, one-a-day cap, stop/target multiple, time-exit hour or
tick-vs-bar semantics, sizing rule, ambiguity handling, degenerate guard,
or bar basis (completed vs forming) = new `RULES_london_breakout_vX.Y` +
fresh manifest + re-run. There is no "small tweak" path.

## 13. Frozen parameter table (v1.2)

| Parameter | Value |
|---|---|
| symbol | EURUSD |
| timeframe | M15, completed bars for range/signal/stop/target; tick leg for flat |
| clock basis | SERVER time (fixed proxy; NOT claimed London wall time) |
| range window (server open) | [10:00, 11:00) — 4 bars (600 <= t < 660) |
| entry window (server open) | [11:00, 14:00) — first strict close outside (660 <= t < 840) |
| max fills / server date | 1 (own-magic deal-history cap, restart-safe) |
| stop | opposite range edge (>= STOPS_LEVEL) |
| target | 1.0R from real fill |
| time exit | first modelled tick server time >= 19:00 (t >= 1140), at market |
| sizing | FIXED 0.01 lot (clamped to volume grid, never forced up) |
| tester | Model=1, deposit USD10000, leverage 1:100, no cloud, no opt, no DLL, no live |
| window (server) | 2025-09-01 through 2026-09-01 |
| degenerate guard | range width >= 3.0 pips |
| units | broker-native fills + offline pips/R mirror |

Minutes verification (auditable): 10:00 = 600, 11:00 = 660, 14:00 = 840,
19:00 = 1140. Range opens {600, 615, 630, 645} = exactly 4 M15 bars.
Entry opens 660..825 = 12 candidate bars. Flat threshold 1140 (tick time).

SHA-freeze: the native run manifest records the SHA-256 of this file and of
`RULES_london_breakout_v1.2.json`.
