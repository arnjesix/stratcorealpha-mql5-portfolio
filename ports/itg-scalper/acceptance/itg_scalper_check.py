#!/usr/bin/env python3
"""Acceptance fixture for ITG_Scalper_Complector_MT5.mq5.

Line-for-line Python mirror of the Pine v4 -> MQL5 transcription in
ITG_Scalper_Complector_MT5.mq5 (same branch order, chrono oldest -> newest):

  EMA(x, p): alpha = 2/(p+1), seeded from the first non-na value,
  defined from the first available bar (Pine ema())
  fast = EMA(close, 12); slow = EMA(close, 26)
  macd = fast - slow; signal = SMA(macd, 9)
  e1 = EMA(close, T); e2 = EMA(e1, T); e3 = EMA(e2, T)
  TEMA = 3 * (e1 - e2) + e3            (Pine default T = 14)
  trend up  <=> TEMA >= TEMA[1] (down otherwise)
  last_tran persistent bool, initially false; long branch first:
    long  if up and not last_tran and (macd >= signal or filter off)
          -> last_tran = True
    short if down and last_tran and (macd < signal or filter off)
          -> last_tran = False

Validates the TRANSCRIBED CALCULATION and SIGNAL STATE MACHINE on
positive / negative / boundary inputs. It does not compare against
live TradingView output (see README).

Run:  python3 itg_scalper_check.py
Exit 0 + "ALL CHECKS PASSED" on success, nonzero otherwise.
"""
import sys

NAN = float("nan")


def isna(x):
    return x != x


def ema_series(values, period):
    """Pine ema(): seed is the first non-na value, then alpha recursion."""
    out = []
    ema, init = 0.0, False
    alpha = 2.0 / (period + 1.0)
    for x in values:
        if isna(x):
            out.append(NAN)
            continue
        if not init:
            ema, init = x, True
            out.append(ema)
        else:
            ema = alpha * x + (1.0 - alpha) * ema
            out.append(ema)
    return out


def sma_series(values, period):
    out = []
    for j in range(len(values)):
        if j - period + 1 < 0:
            out.append(NAN)
            continue
        w = values[j - period + 1:j + 1]
        out.append(NAN if any(isna(v) for v in w) else sum(w) / period)
    return out


def tema_series(close, period):
    e1 = ema_series(close, period)
    e2 = ema_series(e1, period)
    e3 = ema_series(e2, period)
    return [NAN if any(isna(v) for v in (a, b, c)) else 3.0 * (a - b) + c
            for a, b, c in zip(e1, e2, e3)]


def run_events(tema, macd, signal, filter_on=True):
    """Transcribed last_tran state machine. Returns (buys, sells) bar lists."""
    buys, sells = [], []
    last_tran = False
    for j in range(len(tema)):
        if isna(tema[j]) or j == 0 or isna(tema[j - 1]):
            continue
        up = tema[j] >= tema[j - 1]
        mok = not isna(macd[j]) and not isna(signal[j])
        long_gate = (not filter_on) or (mok and macd[j] >= signal[j])
        short_gate = (not filter_on) or (mok and macd[j] < signal[j])
        if up and not last_tran and long_gate:
            buys.append(j)
            last_tran = True
        elif not up and last_tran and short_gate:
            sells.append(j)
            last_tran = False
    return buys, sells


def full_mirror(close, tema_p=14, fast=12, slow=26, siglen=9, filter_on=True):
    f = ema_series(close, fast)
    s = ema_series(close, slow)
    m = [NAN if (isna(a) or isna(b)) else a - b for a, b in zip(f, s)]
    sg = sma_series(m, siglen)
    t = tema_series(close, tema_p)
    buys, sells = run_events(t, m, sg, filter_on)
    return {"fast": f, "slow": s, "macd": m, "signal": sg,
            "tema": t, "buys": buys, "sells": sells}


def check(name, cond, detail=""):
    print(("PASS" if cond else "FAIL") + " | " + name +
          ((" | " + str(detail)) if detail and not cond else ""))
    return cond


def main():
    ok = True

    # --- A. EMA unit: first-value seed, alpha recursion ---------------
    e = ema_series([10.0, 20.0, 30.0, 40.0], 3)
    ok &= check("A: EMA seeds from first value: e[0] == 10",
                abs(e[0] - 10.0) < 1e-12, e)
    ok &= check("A: EMA steps with alpha=1/2: 15, 22.5, 31.25",
                abs(e[1] - 15.0) < 1e-12 and
                abs(e[2] - 22.5) < 1e-12 and
                abs(e[3] - 31.25) < 1e-12, e)
    g = ema_series([10.0, NAN, 20.0], 3)
    ok &= check("A: na gap stays na, seed kept: [10, na, 15]",
                abs(g[0] - 10.0) < 1e-12 and isna(g[1]) and
                abs(g[2] - 15.0) < 1e-12, g)

    # --- B. TEMA identity on a constant series --------------------------
    t = tema_series([7.0] * 60, 14)
    defined = [v for v in t if not isna(v)]
    ok &= check("B: constant series TEMA == level from the first bar",
                len(defined) == 60 and
                all(abs(v - 7.0) < 1e-9 for v in defined),
                (len(defined), defined[:3]))
    ok &= check("B: first-value seeding leaves no na warmup",
                sum(1 for v in t if isna(v)) == 0,
                sum(1 for v in t if isna(v)))

    # --- C. trend + latch: one buy on rise, one sell on fall ------------
    close = [100.0 + float(j) for j in range(60)] + \
            [159.0 - 2.0 * j for j in range(1, 31)]
    r = full_mirror(close, filter_on=False)
    ok &= check("C: first buy fires at bar 1 (no SMA warmup)",
                r["buys"] == [1], r["buys"])
    ok &= check("C: exactly one buy on the rise (no repeats)",
                len(r["buys"]) == 1, r["buys"])
    ok &= check("C: exactly one sell after the fall",
                len(r["sells"]) == 1, r["sells"])
    ok &= check("C: sell bar is after buy bar",
                r["sells"] and r["buys"] and r["sells"][0] > r["buys"][0],
                (r["buys"], r["sells"]))

    # --- D. filter gating with injected MACD/signal ----------------------
    tema = [NAN, NAN] + [float(j) for j in range(2, 20)]  # strict rise
    macd_lo = [NAN, NAN] + [-1.0] * 18                   # macd < signal
    sig_hi = [NAN, NAN] + [1.0] * 18
    b_on, s_on = run_events(tema, macd_lo, sig_hi, filter_on=True)
    b_off, _ = run_events(tema, macd_lo, sig_hi, filter_on=False)
    ok &= check("D: filter ON blocks the long when macd < signal",
                b_on == [], b_on)
    ok &= check("D: filter OFF allows the long on trend alone",
                b_off == [3], b_off)

    # --- E. short needs last_tran: fall from start gives no sell ---------
    fall = [NAN, NAN] + [100.0 - float(j) for j in range(18)]
    mz = [NAN, NAN] + [0.0] * 18
    sz = [NAN, NAN] + [0.0] * 18
    b, s = run_events(fall, mz, sz, filter_on=False)
    ok &= check("E: no sell without a prior long (last_tran starts false)",
                b == [] and s == [], (b, s))

    # --- F. alternating trend flips the latch each way -------------------
    alt = [NAN, NAN] + [1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 1.0, 0.0, -1.0]
    mz = [NAN, NAN] + [0.0] * 9
    sz = [NAN, NAN] + [0.0] * 9
    b, s = run_events(alt, mz, sz, filter_on=False)
    ok &= check("F: chop alternates the latch every bar",
                b == [3, 5, 7] and s == [4, 6, 8], (b, s))

    # --- G. equal TEMA counts as up (>=), boundary -----------------------
    eq = [NAN, NAN, 5.0, 5.0, 5.0]
    b, s = run_events(eq, mz[:5], sz[:5], filter_on=False)
    ok &= check("G: flat TEMA is trend-up (>=), buys once",
                b == [3], (b, s))

    # --- H. signal SMA warmup is preserved ------------------------------
    rf = full_mirror(close, filter_on=True)
    ok &= check("H: signal SMA(9) is na for the first 8 bars only",
                all(isna(v) for v in rf["signal"][:8]) and
                not isna(rf["signal"][8]),
                rf["signal"][:10])

    print("ALL CHECKS PASSED" if ok else "CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
