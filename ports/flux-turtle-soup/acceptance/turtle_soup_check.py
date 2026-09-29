#!/usr/bin/env python3
"""Acceptance fixture for TurtleSoup_FluxCharts.mq5.

Line-for-line Python mirror of the Pine v5 -> MQL5 transcription:
per-bar setup creation, sellside-first liquidity sweep, MSS execution,
fixed/dynamic TP/SL exits in Pine's exact branch order (SL overwrites TP
on the same bar), highBreaks/lowBreaks, dashboard formulas.

Validates the TRANSCRIBED ALGORITHM on positive / negative / boundary
inputs. It does not compare against live TradingView output (see README).

Run:  python3 turtle_soup_check.py
Exit 0 + "ALL CHECKS PASSED" on success, nonzero otherwise.
"""
import sys

WAIT_LIQ, WAIT_EXEC, IN_TRADE = 0, 1, 2


def run_mirror(bars, mss=3, bar_length=4, breakout="Wick",
               entry_method="Classic", tpsl="Dynamic", risk_mult=3.5,
               tp_pct=0.3, sl_pct=0.4, rr=0.9, max_bars=4900):
    """bars: list of (high, low, close) oldest -> newest chrono order."""
    n = len(bars)
    use_close = (breakout == "Close")
    classic = (entry_method == "Classic")
    fixed = (tpsl == "Fixed")
    setups = []
    high_breaks = low_breaks = 0
    events = []  # (bar_j, kind, price)
    trs = []

    def highest(j0, j1):
        return max(b[0] for b in bars[j0:j1 + 1])

    def lowest(j0, j1):
        return min(b[1] for b in bars[j0:j1 + 1])

    for j, (h, l, c) in enumerate(bars):
        # --- Wilder ATR(5), SMA-seeded
        if j == 0:
            tr = h - l
        else:
            pc = bars[j - 1][2]
            tr = max(h - l, abs(h - pc), abs(l - pc))
        trs.append(tr)
        if j < 4:
            atr, atr_valid = 0.0, False
        elif j == 4:
            atr, atr_valid = sum(trs) / 5.0, True
        else:
            atr, atr_valid = (prev_atr * 4 + tr) / 5.0, True
        if atr_valid:
            prev_atr = atr
        # --- windows over available history (Pine ta.highest/lowest)
        rl = min(bar_length, j + 1)
        high12 = highest(j - rl + 1, j)
        low12 = lowest(j - rl + 1, j)
        ml = min(mss, j + 1)
        high_mss = highest(j - ml + 1, j)
        low_mss = lowest(j - ml + 1, j)
        lag = min(mss, j)
        lag_ok = lag >= 1
        high_mss1 = highest(j - lag, j - 1) if lag_ok else None
        low_mss1 = lowest(j - lag, j - 1) if lag_ok else None
        last_hour = (j - bar_length) if j >= bar_length else None

        if j > n - 1 - max_bars:  # Pine: bar_index > last_bar_index - maxDistance
            # --- session start: new setup per bar once last exited
            if not setups or setups[-1]["has_exit"]:
                setups.append({"state": WAIT_LIQ, "start": j,
                               "hh": high12, "ll": low12, "last_hour": last_hour,
                               "sweep": None, "etype": 0, "entry": None,
                               "sl": None, "tp": None, "exit": None,
                               "exit_is_tp": None})
            s = setups[-1]
            # --- liquidity break, sellside first
            if s["state"] == WAIT_LIQ and j > s["start"]:
                sell_trig = c if use_close else l
                buy_trig = c if use_close else h
                if sell_trig < s["ll"]:
                    s["sweep"] = ("sell", s["ll"])
                    s["etype"] = (+1 if (classic or
                                         high_breaks > low_breaks) else -1)
                    s["state"] = WAIT_EXEC
                    s["sweep_bar"] = j
                    events.append((j, "sweep_lo", s["ll"]))
                elif buy_trig > s["hh"]:
                    s["sweep"] = ("buy", s["hh"])
                    s["etype"] = (-1 if (classic or
                                         high_breaks <= low_breaks) else +1)
                    s["state"] = WAIT_EXEC
                    s["sweep_bar"] = j
                    events.append((j, "sweep_hi", s["hh"]))
            # --- MSS execution
            if s["state"] == WAIT_EXEC and j > s["sweep_bar"]:
                if s["etype"] == -1:
                    trig = c if use_close else l
                    if lag_ok and trig < low_mss1:
                        ep = c if use_close else low_mss1
                        if fixed:
                            sl, tp = ep * (1 + sl_pct / 100), ep * (1 - tp_pct / 100)
                        else:
                            sl = high_mss + atr * risk_mult if atr_valid else None
                            tp = (ep - abs(ep - sl) * rr) if sl is not None else None
                        if sl is not None and tp is not None:
                            s.update(entry=ep, sl=sl, tp=tp, state=IN_TRADE,
                                     entry_bar=j)
                            events.append((j, "sell", ep))
                else:
                    trig = c if use_close else h
                    if lag_ok and trig > high_mss1:
                        ep = c if use_close else high_mss1
                        if fixed:
                            sl, tp = ep * (1 - sl_pct / 100), ep * (1 + tp_pct / 100)
                        else:
                            sl = low_mss - atr * risk_mult if atr_valid else None
                            tp = (ep + abs(ep - sl) * rr) if sl is not None else None
                        if sl is not None and tp is not None:
                            s.update(entry=ep, sl=sl, tp=tp, state=IN_TRADE,
                                     entry_bar=j)
                            events.append((j, "buy", ep))
            # --- exits in Pine's exact branch order
            if s["state"] == IN_TRADE:
                e = s["entry"]
                fired = False
                if fixed:
                    if s["etype"] == +1 and (h / e - 1) * 100 >= tp_pct:
                        s.update(exit=e * (1 + tp_pct / 100), exit_is_tp=True,
                                 exit_bar=j)
                        high_breaks += 1
                        fired = True
                    if s["etype"] == -1 and (l / e - 1) * 100 <= -tp_pct:
                        s.update(exit=e * (1 - tp_pct / 100), exit_is_tp=True,
                                 exit_bar=j)
                        low_breaks += 1
                        fired = True
                    if s["etype"] == +1 and (l / e - 1) * 100 <= -sl_pct:
                        s.update(exit=e * (1 - sl_pct / 100), exit_is_tp=False,
                                 exit_bar=j)
                        high_breaks -= 1
                        fired = True
                    if s["etype"] == -1 and (h / e - 1) * 100 >= sl_pct:
                        s.update(exit=e * (1 + sl_pct / 100), exit_is_tp=False,
                                 exit_bar=j)
                        low_breaks -= 1
                        fired = True
                else:
                    if s["etype"] == +1 and h >= s["tp"]:
                        mx, mn = max(s["hh"], s["tp"]), min(s["hh"], s["tp"])
                        s.update(exit=(mx if h >= mx else mn), exit_is_tp=True,
                                 exit_bar=j)
                        high_breaks += 1
                        fired = True
                    if s["etype"] == -1 and l <= s["tp"]:
                        mn, mx = min(s["ll"], s["tp"]), max(s["ll"], s["tp"])
                        s.update(exit=(mn if l <= mn else mx), exit_is_tp=True,
                                 exit_bar=j)
                        low_breaks += 1
                        fired = True
                    if s["etype"] == +1 and l <= s["sl"]:
                        s.update(exit=s["sl"], exit_is_tp=False, exit_bar=j)
                        high_breaks -= 1
                        fired = True
                    if s["etype"] == -1 and h >= s["sl"]:
                        s.update(exit=s["sl"], exit_is_tp=False, exit_bar=j)
                        high_breaks -= 1
                        fired = True
                if fired:
                    s["has_exit"] = True
                    # Pine renders one marker from the FINAL state
                    events.append((j, "tp" if s["exit_is_tp"] else "sl",
                                   s["exit"]))
            if "has_exit" not in s:
                s["has_exit"] = False
    # --- dashboard (Pine formulas; open trades count as losses)
    wins = losses = 0
    total = 0.0
    for s in setups:
        if s["entry"] is None:
            continue
        succ = False
        if s["exit"] is not None:
            if (s["etype"] == +1 and s["exit"] > s["entry"]) or \
               (s["etype"] == -1 and s["exit"] < s["entry"]):
                total += abs((s["entry"] - s["exit"]) / s["exit"] * 100.0)
                succ = True
            else:
                total -= abs((s["entry"] - s["exit"]) / s["exit"] * 100.0)
        wins, losses = wins + succ, losses + (not succ)
    return {"events": events, "setups": setups, "wins": wins,
            "losses": losses, "total": total,
            "high_breaks": high_breaks, "low_breaks": low_breaks}


def check(name, cond, detail=""):
    print(("PASS" if cond else "FAIL") + " | " + name +
          ((" | " + str(detail)) if detail and not cond else ""))
    return cond


RANGE = [(110, 100, 105)] * 5  # j0..j4 flat 110/100


def main():
    ok = True
    # --- A. positive long, Fixed/Wick/Classic: sweep, entry, TP --------
    bars_a = RANGE + [(110, 99, 104),   # j5 sweep (sellside, ll=100)
                      (110.2, 109.8, 110),  # j6 MSS entry @110
                      (111, 109.7, 110.5)]  # j7 TP @110.33 (low avoids SL)
    ra = run_mirror(bars_a, tpsl="Fixed")
    ev = ra["events"]
    ok &= check("A: sweep_lo @100 on j5", (5, "sweep_lo", 100) in ev, ev)
    ok &= check("A: buy @110 on j6", (6, "buy", 110) in ev, ev)
    ok &= check("A: tp @110.33 on j7",
                any(k == "tp" and j == 7 and abs(p - 110.33) < 1e-9
                    for (j, k, p) in ev), ev)
    ok &= check("A: dashboard 1 win / 0 losses",
                (ra["wins"], ra["losses"]) == (1, 0), (ra["wins"], ra["losses"]))
    ok &= check("A: total = |110-110.33|/110.33*100",
                abs(ra["total"] - abs((110 - 110.33) / 110.33 * 100.0)) < 1e-9,
                ra["total"])

    # --- B. negative: flat range, nothing happens ----------------------
    rb = run_mirror(RANGE + [(110, 100, 105)] * 7, tpsl="Fixed")
    ok &= check("B: no events on flat market", rb["events"] == [], rb["events"])
    ok &= check("B: dashboard zeros",
                (rb["wins"], rb["losses"], rb["total"]) == (0, 0, 0.0),
                (rb["wins"], rb["losses"], rb["total"]))

    # --- C. boundary: same-bar TP+SL -> SL wins, single SL marker ------
    bars_c = RANGE + [(110, 99, 104),      # j5 sweep
                      (110.2, 109.8, 110),  # j6 entry @110
                      (111, 109, 110)]      # j7 TP and SL both hit
    rc = run_mirror(bars_c, tpsl="Fixed")
    evc = rc["events"]
    ok &= check("C: only sl marker on j7 (no tp)",
                (7, "sl", 109.56) in evc and
                not any(k == "tp" for (_, k, _) in evc), evc)
    s_c = [s for s in rc["setups"] if s["entry"] is not None][0]
    ok &= check("C: exit is SL @109.56",
                s_c["exit_is_tp"] is False and
                abs(s_c["exit"] - 109.56) < 1e-9, (s_c["exit"], s_c["exit_is_tp"]))
    ok &= check("C: highBreaks net 0 (+1 then -1)",
                rc["high_breaks"] == 0, rc["high_breaks"])
    ok &= check("C: dashboard 0 wins / 1 loss, total -|diff|",
                (rc["wins"], rc["losses"]) == (0, 1) and
                abs(rc["total"] + abs((110 - 109.56) / 109.56 * 100.0)) < 1e-9,
                (rc["wins"], rc["losses"], rc["total"]))

    # --- D. short Dynamic: exact SL/TP numbers, stays open -------------
    bars_d = RANGE + [(111, 100, 106),     # j5 buyside sweep (hh=110)
                      (109, 99.8, 105),     # j6 short entry @ lowMSS1=100
                      (100, 99, 99.5)]      # j7 still open
    rd = run_mirror(bars_d, tpsl="Dynamic")
    evd = rd["events"]
    ok &= check("D: sweep_hi @110 on j5", (5, "sweep_hi", 110) in evd, evd)
    ok &= check("D: sell @100 (MSS level) on j6", (6, "sell", 100) in evd, evd)
    s_d = [s for s in rd["setups"] if s["entry"] is not None][0]
    ok &= check("D: dynamic SL = 111 + 10.0*3.5 = 146",
                abs(s_d["sl"] - 146.0) < 1e-9, s_d["sl"])
    ok &= check("D: dynamic TP = 100 - 46.0*0.9 = 58.6",
                abs(s_d["tp"] - 58.6) < 1e-9, s_d["tp"])
    ok &= check("D: no exit events", not any(k in ("tp", "sl")
                                             for (_, k, _) in evd), evd)
    ok &= check("D: open trade counts as dashboard loss",
                (rd["wins"], rd["losses"]) == (0, 1), (rd["wins"], rd["losses"]))

    print("ALL CHECKS PASSED" if ok else "CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
