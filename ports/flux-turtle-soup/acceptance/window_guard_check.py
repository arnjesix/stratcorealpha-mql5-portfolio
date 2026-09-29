#!/usr/bin/env python3
"""Window-direction regression guard for TurtleSoup_FluxCharts.mq5 (v1.02).

Pine runs its state machine on the NEWEST maxDistanceToLastBar bars:
    if bar_index > last_bar_index - maxDistanceToLastBar
v1.01 gated the MQL5 loop on k (age from the oldest bar), keeping the
OLDEST 4900 bars instead. On any symbol with >4900 bars of history (e.g.
clone EURUSD M15 multi-year history) every live bar was skipped, buffers
stayed EMPTY_VALUE, and the chart showed no markers at all while the
indicator still loaded fine. The gate must use the series index i
(0 = newest):  bool inWindow = (i < TSF_MAXBARS);

Run:  python3 window_guard_check.py
Exit 0 + "WINDOW GUARD PASSED" on success, nonzero otherwise.
"""
import pathlib
import re
import sys

SRC = pathlib.Path(__file__).resolve().parents[1] / "TurtleSoup_FluxCharts.mq5"
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from turtle_soup_check import run_mirror


def main():
    text = SRC.read_text(encoding="utf-8", errors="replace")
    calc = text.split("int OnCalculate", 1)
    if len(calc) != 2:
        print("WINDOW GUARD FAILED: OnCalculate not found")
        return 1
    body = calc[1]
    failures = []
    if not re.search(r"bool\s+inWindow\s*=\s*\(\s*i\s*<\s*TSF_MAXBARS\s*\)", body):
        failures.append("OnCalculate must gate on newest bars: bool inWindow = (i < TSF_MAXBARS)")
    if re.search(r"bool\s+inWindow\s*=\s*\(\s*k\s*<\s*TSF_MAXBARS\s*\)", body):
        failures.append("inverted oldest-bars gate still present: (k < TSF_MAXBARS)")

    # Spec-level behavior the gate must match: a sweep->entry->TP pattern in
    # the newest bars of a >4900-bar history must produce recent events under
    # the Pine (newest-4900) window used by the mirror.
    n, maxb = 6000, 4900
    bars = [(110, 100, 105)] * 5990 + [
        (110, 99, 104), (110.2, 109.8, 110), (111, 109.7, 110.5),
        (110, 100, 105)] + [(110, 100, 105)] * 6
    res = run_mirror(bars, tpsl="Fixed", max_bars=maxb)
    recent = [e for e in res["events"] if e[0] >= n - maxb]
    if len(recent) == 0:
        failures.append("mirror finds no recent events; fixture pattern broken")

    if failures:
        print("WINDOW GUARD FAILED:")
        for failure in failures:
            print(" - " + failure)
        return 1
    print("WINDOW GUARD PASSED (recent-window events=%d)" % len(recent))
    return 0


if __name__ == "__main__":
    sys.exit(main())
