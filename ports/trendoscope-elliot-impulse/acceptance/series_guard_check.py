#!/usr/bin/env python3
"""Series-orientation regression guard for ElliotWaveImpulse_Trendoscope.mq5 (v1.01).

OnCalculate price/time arrays arrive non-series (0 = oldest) while the
indicator buffers are set series in OnInit (0 = newest). The oldest->newest
loop (i = rates_total-1 .. 0, k = rates_total-1-i) and the newest-signal scan
only read the correct bars when the inputs are forced to series. Without the
guard the zigzag runs time-reversed and signals land on wrong bars.

Run:  python3 series_guard_check.py
Exit 0 + "SERIES GUARD PASSED" on success, nonzero otherwise.
"""
import pathlib
import re
import sys

SRC = (pathlib.Path(__file__).resolve().parents[1]
       / "ElliotWaveImpulse_Trendoscope.mq5")


def main():
    text = SRC.read_text(encoding="utf-8", errors="replace")
    calc = text.split("int OnCalculate", 1)
    if len(calc) != 2:
        print("SERIES GUARD FAILED: OnCalculate not found")
        return 1
    body = calc[1]
    failures = []
    for arr in ("time", "open", "high", "low", "close"):
        if not re.search(r"ArraySetAsSeries\s*\(\s*" + arr + r"\s*,\s*true\s*\)", body):
            failures.append("OnCalculate missing ArraySetAsSeries(%s, true)" % arr)
    for buf in ("ExtBuy", "ExtSell", "ExtEntry", "ExtStop", "ExtTStop",
                "ExtT1", "ExtT2", "ExtT3", "ExtT4",
                "ExtZZUp", "ExtZZDn",
                "ExtSigP0", "ExtSigP1", "ExtSigP2",
                "ExtSigT0", "ExtSigT1", "ExtSigT2"):
        if not re.search(r"ArraySetAsSeries\s*\(\s*" + buf + r"\s*,\s*true\s*\)", text):
            failures.append("OnInit missing ArraySetAsSeries(%s, true)" % buf)
    if failures:
        print("SERIES GUARD FAILED:")
        for failure in failures:
            print(" - " + failure)
        return 1
    print("SERIES GUARD PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
