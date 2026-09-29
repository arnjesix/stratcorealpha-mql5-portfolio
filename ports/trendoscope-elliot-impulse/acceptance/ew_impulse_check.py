#!/usr/bin/env python3
"""Acceptance fixture for ElliotWaveImpulse_Trendoscope.mq5.

Line-for-line Python mirror of the Pine v4 -> MQL5 transcription
(pivots persistence, zigzag replace-or-keep + extension doubling,
ew_impulse ratio/dir matching with start=1). Validates the TRANSCRIBED
ALGORITHM on positive / negative / boundary inputs. It does not compare
against live TradingView output (see README for the manual same-feed
comparison procedure).

Run:  python3 ew_impulse_check.py
Exit 0 + "ALL CHECKS PASSED" on success, nonzero otherwise.
"""
import sys

RATIOS = (0.50, 0.618, 0.764, 0.854)
MAX_PIVOTS = 10


def run_mirror(bars, zigzag_length=10, error_percent=5.0,
               entry_percent=30.0, start=1):
    """bars: list of (high, low) oldest -> newest. Returns per-bar signals."""
    err_min = (100.0 - error_percent) / 100.0
    err_max = (100.0 + error_percent) / 100.0
    entry_range = entry_percent / 100.0
    n = len(bars)
    pdir = 0
    pdir_prev = 0
    zz_p, zz_b, zz_d = [], [], []  # newest first
    have_last = False
    last_p = (None, None, None)
    signals = []  # (bar_idx, side, entry, stop, tstop, t1..t4, P0,P1,P2)

    for i, (h, l) in enumerate(bars):
        k = i  # bar age: 0 = oldest
        win_full = k >= zigzag_length - 1
        is_phigh = is_plow = False
        if win_full:
            mx, mn = h, l
            off_h = off_l = 0
            for j in range(1, zigzag_length):
                if i - j < 0:
                    break
                # strict '>' keeps the most recent bar on ties (as in .mq5)
                if bars[i - j][0] > mx:
                    mx, off_h = bars[i - j][0], j
                if bars[i - j][1] < mn:
                    mn, off_l = bars[i - j][1], j
            is_phigh = off_h == 0
            is_plow = off_l == 0
        if is_phigh and not is_plow:
            pdir = 1
        elif is_plow and not is_phigh:
            pdir = -1
        dir_changed = pdir != pdir_prev
        pdir_prev = pdir

        if is_phigh or is_plow:
            value = h if pdir == 1 else l
            bar = i
            if not dir_changed and len(zz_p) >= 1:
                pivot, pdir0 = zz_p.pop(0), zz_d.pop(0)
                pivot_bar = zz_b.pop(0)
                # Pine: value := value*pdir0 < pivot*pdir0 ? pivot : value
                if value * pdir0 < pivot * pdir0:
                    value, bar = pivot, pivot_bar
            if len(zz_p) >= 2:
                if pdir * value > pdir * zz_p[1]:
                    pdir = pdir * 2
            zz_p.insert(0, value)
            zz_b.insert(0, bar)
            zz_d.insert(0, pdir)
            if len(zz_p) > MAX_PIVOTS:
                zz_p.pop()
                zz_b.pop()
                zz_d.pop()

        if len(zz_p) >= 3 + start:
            p2, p1, p0 = zz_p[start], zz_p[start + 1], zz_p[start + 2]
            d2, d1 = zz_d[start], zz_d[start + 1]
            w1, w2 = abs(p1 - p0), abs(p2 - p1)
            if w1 > 0.0:
                r2 = w2 / w1
                matched = any(rr * err_min < r2 < rr * err_max
                              for rr in RATIOS)
                dir_ok = (d1 == 2 and d2 == -1) or (d1 == -2 and d2 == 1)
                ignore = have_last and (last_p[0] == p0 or
                                        last_p[1] == p1 or
                                        last_p[2] == p2)
                if matched and dir_ok and not ignore:
                    direction = -1 if p0 > p1 else 1
                    entry = p2 + direction * entry_range * w2
                    stop = p0
                    tstop = p2 - direction * entry_range * w2
                    t = [p2 + direction * m * w2
                         for m in (1.618, 2.0, 2.618, 3.236)]
                    side = "bull" if direction == 1 else "bear"
                    signals.append((i, side, entry, stop, tstop) +
                                   tuple(t) + (p0, p1, p2))
                    have_last = True
                    last_p = (p0, p1, p2)
    return signals


def ew_direct(p0, p1, p2, d1, d2, error_percent=5.0, entry_percent=30.0):
    """Single-triple check used for boundary tests."""
    err_min = (100.0 - error_percent) / 100.0
    err_max = (100.0 + error_percent) / 100.0
    w1, w2 = abs(p1 - p0), abs(p2 - p1)
    if w1 <= 0.0:
        return None
    r2 = w2 / w1
    matched = any(rr * err_min < r2 < rr * err_max for rr in RATIOS)
    dir_ok = (d1 == 2 and d2 == -1) or (d1 == -2 and d2 == 1)
    if not (matched and dir_ok):
        return None
    direction = -1 if p0 > p1 else 1
    entry = p2 + direction * (entry_percent / 100.0) * w2
    return ("bull" if direction == 1 else "bear", entry, r2)


def check(name, cond, detail=""):
    print(("PASS" if cond else "FAIL") + " | " + name +
          ((" | " + str(detail)) if detail and not cond else ""))
    return cond


def main():
    ok = True
    # --- end-to-end positive: crafted 12-bar series, L=3 -----------------
    bull_bars = [
        (100, 99), (101, 100), (105, 102), (103, 100.5),
        (104, 100), (106, 102), (110, 105), (108, 106),
        (107, 103.82), (105, 104), (106.5, 104.5), (109, 107),
        (108, 106),
    ]
    sigs = run_mirror(bull_bars, zigzag_length=3)
    ok &= check("e2e: exactly one signal", len(sigs) == 1, sigs)
    if len(sigs) == 1:
        idx, side, entry, stop, tstop, t1, t2, t3, t4, p0, p1, p2 = sigs[0]
        ok &= check("e2e: signal on bar 11", idx == 11, idx)
        ok &= check("e2e: bullish", side == "bull", side)
        ok &= check("e2e: pivots P0/P1/P2", (p0, p1, p2) == (100, 110, 103.82),
                    (p0, p1, p2))
        ok &= check("e2e: entry=103.82+0.3*6.18",
                    abs(entry - 105.674) < 1e-9, entry)
        ok &= check("e2e: stop=100", stop == 100, stop)
        ok &= check("e2e: tstop", abs(tstop - 101.966) < 1e-9, tstop)
        ok &= check("e2e: t1=103.82+1.618*6.18",
                    abs(t1 - 113.81924) < 1e-6, t1)
        ok &= check("e2e: t4=103.82+3.236*6.18",
                    abs(t4 - 123.81848) < 1e-6, t4)

    # --- end-to-end negative: flat range, no pivots pattern ---------------
    flat = [(100 + (i % 3) * 0.1, 99 - (i % 2) * 0.1) for i in range(40)]
    ok &= check("e2e: flat market, no signals",
                run_mirror(flat, zigzag_length=10) == [],
                run_mirror(flat, zigzag_length=10))

    # --- direct negative: r2 far from any ratio ---------------------------
    ok &= check("direct: r2=1.0 no signal",
                ew_direct(100, 110, 120, 2, -1) is None)
    ok &= check("direct: dirs (1,-1) no signal",
                ew_direct(100, 110, 103.82, 1, -1) is None)
    ok &= check("direct: W1=0 no signal",
                ew_direct(100, 100, 100, 2, -1) is None)

    # --- direct boundary: strict band edges at 0.50 +/-5% -----------------
    # band = (0.475, 0.525); r2 = W2/W1 with W1=10
    ok &= check("boundary: r2=0.5249 matches",
                ew_direct(100, 110, 104.751, 2, -1) is not None)
    ok &= check("boundary: r2=0.525 excluded (strict <)",
                ew_direct(100, 110, 104.75, 2, -1) is None)
    r = ew_direct(100, 110, 105.25, 2, -1)  # r2 = 0.475 exactly
    ok &= check("boundary: r2=0.475 exactly excluded", r is None, r)
    r = ew_direct(100, 110, 105.251, 2, -1)  # r2 = 0.4749 inside
    ok &= check("boundary: r2=0.4749 below band excluded",
                r is None, r)
    r = ew_direct(100, 110, 104.75001, 2, -1)  # just inside upper edge
    ok &= check("boundary: just inside upper edge matches", r is not None, r)

    # --- bearish vertical mirror of the positive case (same time order) --
    bear_bars = [(200 - l, 200 - h) for (h, l) in bull_bars]
    bsigs = run_mirror(bear_bars, zigzag_length=3)
    ok &= check("e2e: mirrored series gives one bear signal",
                len(bsigs) == 1 and bsigs[0][1] == "bear", bsigs)
    if len(bsigs) == 1:
        ok &= check("e2e: bear pivots P0/P1/P2",
                    bsigs[0][9:12] == (100, 90, 96.18), bsigs[0][9:12])

    print("ALL CHECKS PASSED" if ok else "CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
