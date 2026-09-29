#!/usr/bin/env python3
"""Acceptance fixture for SALMA_RedK_MT5.mq5.

Line-for-line Python mirror of the Pine v5 -> MQL5 transcription in
SALMA_RedK_MT5.mq5 (same branch order, chrono oldest -> newest input):

  baseline = WMA(price, sd_len)
  dev      = mult * STDEV_POP(price, sd_len)   # Pine population stdev
  upper/lower = baseline +/- dev
  cprice   = clip(price, lower, upper)
  REMA     = WMA(WMA(cprice, length), smooth)
  green    = REMA > REMA[1] (strict; red otherwise)
  SwingUp  = green and not green[1]; SwingDn = not green and green[1]

Validates the TRANSCRIBED CALCULATION on positive / negative / boundary
inputs. It does not compare against live TradingView output (see README).

Run:  python3 salma_check.py
Exit 0 + "ALL CHECKS PASSED" on success, nonzero otherwise.
"""
import math
import sys

NAN = float("nan")


def isna(x):
    return x != x


def wma(values, j, length):
    """Pine ta.wma at chrono index j (most recent weight = length)."""
    if j - length + 1 < 0:
        return NAN
    window = values[j - length + 1:j + 1]
    if any(isna(v) for v in window):
        return NAN
    norm = length * (length + 1) / 2.0
    return sum(v * (k + 1) for k, v in enumerate(window)) / norm


def stdev_pop(values, j, length):
    """Pine ta.stdev (population, biased) at chrono index j."""
    if j - length + 1 < 0:
        return NAN
    window = values[j - length + 1:j + 1]
    if any(isna(v) for v in window):
        return NAN
    mean = sum(window) / length
    return math.sqrt(sum((v - mean) ** 2 for v in window) / length)


def run_mirror(price, length=10, smooth=3, mult=0.3, sd_len=5):
    """price: oldest -> newest. Returns dict of chrono series."""
    n = len(price)
    base, cprice, inner, rema = [], [], [], []
    for j in range(n):
        b = wma(price, j, sd_len)
        s = stdev_pop(price, j, sd_len)
        base.append(b)
        if isna(b) or isna(s):
            cprice.append(NAN)
        else:
            upper, lower = b + mult * s, b - mult * s
            p = price[j]
            cprice.append(upper if p > upper else (lower if p < lower else p))
    for j in range(n):
        inner.append(wma(cprice, j, length))
    for j in range(n):
        rema.append(wma(inner, j, smooth))
    green, swing_up, swing_dn = [], [], []
    for j in range(n):
        g = (not isna(rema[j]) and j > 0 and not isna(rema[j - 1])
             and rema[j] > rema[j - 1])
        green.append(g)
        gp = green[j - 1] if j > 0 else False
        swing_up.append(g and not gp and j > 0 and not isna(rema[j - 1]))
        swing_dn.append((not g) and gp and j > 0 and not isna(rema[j - 1]))
    # First defined bar: prev undefined -> not green prev; keep formula
    # result but never signal on bar 0 itself.
    if n:
        swing_up[0] = swing_dn[0] = False
    return {"base": base, "cprice": cprice, "inner": inner, "rema": rema,
            "green": green, "up": swing_up, "dn": swing_dn}


def check(name, cond, detail=""):
    print(("PASS" if cond else "FAIL") + " | " + name +
          ((" | " + str(detail)) if detail and not cond else ""))
    return cond


def main():
    ok = True

    # --- A. WMA unit: weights rise toward the newest bar ---------------
    got = wma([10.0, 20.0, 30.0], 2, 3)
    ok &= check("A: wma([10,20,30],3) = 140/6",
                abs(got - 140.0 / 6.0) < 1e-12, got)
    ok &= check("A: wma incomplete window is na",
                isna(wma([10.0, 20.0], 1, 3)))

    # --- B. population stdev unit (classic example, sigma = 2.0) -------
    classic = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
    got = stdev_pop(classic, 7, 8)
    ok &= check("B: stdev_pop = 2.0 (biased, /N)",
                abs(got - 2.0) < 1e-12, got)
    sample = math.sqrt(sum((v - 5.0) ** 2 for v in classic) / 7)
    ok &= check("B: sample stdev differs (guards /N vs /(N-1))",
                abs(sample - 2.0) > 0.05, sample)

    # --- C. clipping: spike is lazy-capped at the band -----------------
    r = run_mirror([100.0] * 5 + [110.0], sd_len=5, mult=0.3)
    b, cp = r["base"][5], r["cprice"][5]
    ok &= check("C: clipped price <= raw spike",
                not isna(cp) and cp < 110.0, (b, cp))
    ok &= check("C: clipped price within [lower, upper]",
                b - 0.3 * stdev_pop([100.0] * 5 + [110.0], 5, 5) - 1e-9
                <= cp <=
                b + 0.3 * stdev_pop([100.0] * 5 + [110.0], 5, 5) + 1e-9,
                (b, cp))

    # --- D. rising feed: REMA defined after warmup, green, one SwingUp -
    bars = [100.0 + 0.5 * j for j in range(30)]
    r = run_mirror(bars)
    first = next(j for j in range(30) if not isna(r["rema"][j]))
    ok &= check("D: REMA warmup = (sd_len-1)+(length-1)+(smooth-1)",
                first == (5 - 1) + (10 - 1) + (3 - 1), first)
    ok &= check("D: rising feed stays green once defined",
                all(r["green"][first + 1:]))
    ups = [j for j in range(30) if r["up"][j]]
    ok &= check("D: exactly one SwingUp at first green bar",
                ups == [first + 1], ups)
    ok &= check("D: no SwingDn on rising feed",
                not any(r["dn"]))

    # --- E. flat feed: equal REMA -> red (strict >), no swings ---------
    r = run_mirror([50.0] * 30)
    ok &= check("E: flat feed never green",
                not any(r["green"]))
    ok &= check("E: flat feed has no swings",
                not any(r["up"]) and not any(r["dn"]))
    ok &= check("E: flat REMA equals the level once defined",
                all(abs(v - 50.0) < 1e-9 for v in r["rema"]
                    if not isna(v)))

    # --- F. reversal: SwingDn fires once when REMA turns down ----------
    rev = [100.0 + 0.5 * j for j in range(20)] + \
        [110.0 - 2.0 * j for j in range(1, 11)]
    r = run_mirror(rev)
    dns = [j for j in range(len(rev)) if r["dn"][j]]
    ok &= check("F: exactly one SwingDn on reversal",
                len(dns) == 1, dns)
    ok &= check("F: SwingDn bar is red and REMA falls there",
                (not r["green"][dns[0]]) and
                r["rema"][dns[0]] < r["rema"][dns[0] - 1] if dns else False,
                dns)

    print("ALL CHECKS PASSED" if ok else "CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
