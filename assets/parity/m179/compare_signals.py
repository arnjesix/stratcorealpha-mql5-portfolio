"""M179 Pine vs MT5 H1 signal comparison (48 bars, 2026-09-08..09).

Inputs (immutable, captured 2026-09-25, read relative to this file):
  M179_TradingView_OANDA_EURUSD_H1_20260908-09_bars.csv
    Visible TradingView Table view: 48 H1 bars, time_utc is UTC ISO,
    direction holds the live Pine BULL/BEAR marker on that bar (else empty).
  M179_HolaPrime_EURUSD_H1_20260908-09_bars.csv
    MQL5 script export: 48 H1 broker bars, time_mt5 is broker server UTC+3.
  Corresponding *_signals.csv files are cross-checked (must agree exactly
    with the non-empty direction cells of the bars files).

Frozen rule: SMA(3)/SMA(5) strict crossover on completed-bar closes:
  BULL when fast_prev <= slow_prev and fast_now > slow_now;
  BEAR when fast_prev >= slow_prev and fast_now < slow_now.
Equality on the current bar is never a marker.

Timestamp rule: MT5 timestamps are converted to UTC by subtracting exactly
3 hours (UTC = MT5 - 3h). Raw MT5 stamps are never interpreted as UTC.

OHLC alignment (quantitative, from the supplied 48+48 bars):
  After UTC conversion the two feeds share the identical 48 hourly UTC
  stamps (2026-09-08T00:00Z .. 2026-09-09T23:00Z). OHLC values are close but
  not identical (different feeds: OANDA vs HolaPrime-Server1). Measured on
  the inputs: max abs diff open 0.00042, high 0.00007, low 0.00048,
  close 0.00023; median abs diff per field <= 0.00001. Small feed-level
  OHLC differences are expected and are NOT treated as marker mismatches:
  mismatch status compares observed marker strings only.

Outputs (written next to this file):
  M179_signal_agreement.csv      48 rows: UTC time, both observed markers,
                                 status, OHLC of both feeds, abs close diff.
  M179_signal_discrepancies.csv  one row per true marker mismatch with an
                                 individual close/SMA/feed-grounded reason;
                                 header-only when there are zero mismatches.
  M179_signal_overlay.png        one UTC-x price line plus two visibly
                                 distinct Pine/MT5 marker series.
"""

from __future__ import annotations

import argparse
import base64
import shutil
import struct
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd

BASE = Path(__file__).resolve().parent
TV_BARS = BASE / "M179_TradingView_OANDA_EURUSD_H1_20260908-09_bars.csv"
HP_BARS = BASE / "M179_HolaPrime_EURUSD_H1_20260908-09_bars.csv"
TV_SIG = BASE / "M179_TradingView_OANDA_EURUSD_H1_20260908-09_signals.csv"
HP_SIG = BASE / "M179_HolaPrime_EURUSD_H1_20260908-09_signals.csv"
OUT_AGREE = BASE / "M179_signal_agreement.csv"
OUT_DISC = BASE / "M179_signal_discrepancies.csv"
OUT_PNG = BASE / "M179_signal_overlay.png"

EXPECTED_START_UTC = pd.Timestamp("2026-09-08 00:00:00", tz="UTC")
EXPECTED_END_UTC = pd.Timestamp("2026-09-09 23:00:00", tz="UTC")
EXPECTED_UTC = pd.date_range(EXPECTED_START_UTC, EXPECTED_END_UTC, freq="h")
MT5_OFFSET = pd.Timedelta(hours=3)  # UTC = MT5 - 3h, exactly
VALID_SIGNS = {"BULL", "BEAR"}


def fail(msg: str) -> None:
    print(f"COMPARE_ABORT {msg}", file=sys.stderr)
    raise SystemExit(1)


def norm_sign(v) -> str:
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return ""
    s = str(v).strip().strip('"').strip()
    return s


def check_columns(df: pd.DataFrame, required: list[str], label: str) -> None:
    missing = [c for c in required if c not in df.columns]
    if missing:
        fail(f"{label} missing columns {missing} (have {list(df.columns)})")


def sma(values: pd.Series, period: int) -> pd.Series:
    return values.rolling(period, min_periods=period).mean()


def strict_marker(fast_prev, slow_prev, fast_now, slow_now) -> str:
    if pd.isna(fast_prev) or pd.isna(slow_prev) or pd.isna(fast_now) or pd.isna(slow_now):
        return ""
    if fast_prev <= slow_prev and fast_now > slow_now:
        return "BULL"
    if fast_prev >= slow_prev and fast_now < slow_now:
        return "BEAR"
    return ""


def main() -> None:
    for p in (TV_BARS, HP_BARS, TV_SIG, HP_SIG):
        if not p.is_file():
            fail(f"missing input file {p.name}")

    tv = pd.read_csv(TV_BARS)
    hp = pd.read_csv(HP_BARS)
    tvs = pd.read_csv(TV_SIG)
    hps = pd.read_csv(HP_SIG)

    check_columns(tv, ["time_utc", "open", "high", "low", "close", "direction"], "TV bars")
    check_columns(hp, ["time_mt5", "open", "high", "low", "close", "direction"], "HolaPrime bars")
    check_columns(tvs, ["time_utc", "direction", "open", "high", "low", "close"], "TV signals")
    check_columns(hps, ["time_mt5", "direction", "open", "high", "low", "close"], "HolaPrime signals")

    if len(tv) != 48:
        fail(f"TV bars wrong row count {len(tv)} (want 48)")
    if len(hp) != 48:
        fail(f"HolaPrime bars wrong row count {len(hp)} (want 48)")

    # --- timestamps ---
    try:
        tv_utc = pd.to_datetime(tv["time_utc"], utc=True)
    except Exception as exc:
        fail(f"TV time_utc parse error: {exc}")
    if tv_utc.duplicated().any():
        fail("TV bars contain duplicate time_utc values")
    if list(tv_utc) != list(EXPECTED_UTC):
        miss = [t.isoformat() for t in EXPECTED_UTC if t not in set(tv_utc)]
        extra = [t.isoformat() for t in tv_utc if t not in set(EXPECTED_UTC)]
        fail(f"TV bars wrong time span. missing={miss[:5]} unexpected={extra[:5]}")

    try:
        hp_mt5_raw = pd.to_datetime(hp["time_mt5"], format="%Y.%m.%d %H:%M:%S")
    except Exception as exc:
        fail(f"HolaPrime time_mt5 parse error: {exc}")
    if hp_mt5_raw.duplicated().any():
        fail("HolaPrime bars contain duplicate time_mt5 values")
    exp_mt5 = EXPECTED_UTC.tz_convert(None) + MT5_OFFSET
    if list(hp_mt5_raw) != list(exp_mt5):
        fail(
            "HolaPrime bars wrong MT5 time span "
            f"(want {exp_mt5[0]} .. {exp_mt5[-1]} MT5, got {hp_mt5_raw.iloc[0]} .. {hp_mt5_raw.iloc[-1]})"
        )
    # Convert broker UTC+3 to UTC by subtracting exactly 3 hours.
    hp_utc = (hp_mt5_raw - MT5_OFFSET).dt.tz_localize("UTC")
    if list(hp_utc) != list(EXPECTED_UTC):
        fail("HolaPrime MT5->UTC converted stamps do not match TV UTC stamps")

    # --- observed markers: use only observed values, never invent ---
    tv_sign = [norm_sign(v) for v in tv["direction"].tolist()]
    hp_sign = [norm_sign(v) for v in hp["direction"].tolist()]
    for i, s in enumerate(tv_sign):
        if s not in VALID_SIGNS and s != "":
            fail(f"TV bars row {i} unexpected direction {s!r}")
    for i, s in enumerate(hp_sign):
        if s not in VALID_SIGNS and s != "":
            fail(f"HolaPrime bars row {i} unexpected direction {s!r}")

    # --- signals-file cross-check (bars direction vs signals file) ---
    def check_signal_file(sig_df, time_col, is_mt5, bars_df, bars_sign, label):
        if sig_df[time_col].duplicated().any():
            fail(f"{label} signals file has duplicate times")
        if is_mt5:
            st = pd.to_datetime(sig_df[time_col], format="%Y.%m.%d %H:%M:%S") - MT5_OFFSET
            st = st.dt.tz_localize("UTC")
        else:
            st = pd.to_datetime(sig_df[time_col], utc=True)
        bar_time_map = {}
        utc_list = list(EXPECTED_UTC)
        for i, t in enumerate(utc_list):
            bar_time_map[t] = i
        seen = set()
        for r in range(len(sig_df)):
            t = st.iloc[r]
            d = norm_sign(sig_df["direction"].iloc[r])
            if d not in VALID_SIGNS:
                fail(f"{label} signals row {r} unexpected direction {d!r}")
            if t not in bar_time_map:
                fail(f"{label} signals row {r} unexpected time {sig_df[time_col].iloc[r]!r}")
            idx = bar_time_map[t]
            if t in seen:
                fail(f"{label} signals duplicate entry for {t.isoformat()}")
            seen.add(t)
            if bars_sign[idx] != d:
                fail(
                    f"{label} signal file disagreement at {t.isoformat()}: "
                    f"bars={bars_sign[idx]!r} signals={d!r}"
                )
            for col in ("open", "high", "low", "close"):
                a = float(bars_df[col].iloc[idx])
                b = float(sig_df[col].iloc[r])
                if abs(a - b) > 1e-9:
                    fail(f"{label} OHLC disagreement at {t.isoformat()} col {col}: bars={a} signals={b}")
        for i, s in enumerate(bars_sign):
            if s != "" and utc_list[i] not in seen:
                fail(f"{label} bars marker {s!r} at {utc_list[i].isoformat()} missing from signals file")

    check_signal_file(tvs, "time_utc", False, tv, tv_sign, "TV")
    check_signal_file(hps, "time_mt5", True, hp, hp_sign, "HolaPrime")

    # --- frozen SMA(3)/SMA(5) strict-crossover verification ---
    # Only rows with full in-file history (index>=5) are verifiable; earlier
    # rows depend on pre-window closes not present in the 48-row files.
    for label, df, obs in (("TV", tv, tv_sign), ("HolaPrime", hp, hp_sign)):
        closes = pd.to_numeric(df["close"], errors="coerce")
        if closes.isna().any():
            fail(f"{label} bars non-numeric close")
        f3 = sma(closes, 3)
        f5 = sma(closes, 5)
        for i in range(5, len(df)):
            exp = strict_marker(f3.iloc[i - 1], f5.iloc[i - 1], f3.iloc[i], f5.iloc[i])
            if exp != obs[i]:
                fail(
                    f"{label} frozen SMA(3)/SMA(5) mismatch at "
                    f"{EXPECTED_UTC[i].isoformat()}: observed={obs[i]!r} recomputed={exp!r} "
                    f"(sma3_prev={f3.iloc[i-1]:.5f} sma5_prev={f5.iloc[i-1]:.5f} "
                    f"sma3={f3.iloc[i]:.5f} sma5={f5.iloc[i]:.5f})"
                )

    # --- quantitative feed alignment (documented, not a mismatch) ---
    diffs = {}
    for col in ("open", "high", "low", "close"):
        d = (pd.to_numeric(tv[col]) - pd.to_numeric(hp[col])).abs()
        diffs[col] = d
    print("ALIGN time stamps match exactly: 48/48 hourly UTC bars")
    for col in ("open", "high", "low", "close"):
        d = diffs[col]
        print(f"ALIGN {col}: max_abs_diff={d.max():.5f} mean={d.mean():.5f} nonzero={(d > 0).sum()}/48")

    # --- agreement table (48 rows) ---
    tv_o = pd.to_numeric(tv["open"])
    tv_h = pd.to_numeric(tv["high"])
    tv_l = pd.to_numeric(tv["low"])
    tv_c = pd.to_numeric(tv["close"])
    hp_o = pd.to_numeric(hp["open"])
    hp_h = pd.to_numeric(hp["high"])
    hp_l = pd.to_numeric(hp["low"])
    hp_c = pd.to_numeric(hp["close"])
    tv_f3 = sma(tv_c, 3)
    tv_f5 = sma(tv_c, 5)
    hp_f3 = sma(hp_c, 3)
    hp_f5 = sma(hp_c, 5)

    agree_rows = []
    disc_rows = []
    for i, t in enumerate(EXPECTED_UTC):
        a = tv_sign[i]
        b = hp_sign[i]
        status = "AGREE" if a == b else "MISMATCH"
        cdiff = abs(float(tv_c.iloc[i]) - float(hp_c.iloc[i]))
        agree_rows.append(
            {
                "time_utc": t.isoformat(),
                "tv_signal": a,
                "mt5_signal": b,
                "status": status,
                "tv_open": float(tv_o.iloc[i]),
                "tv_high": float(tv_h.iloc[i]),
                "tv_low": float(tv_l.iloc[i]),
                "tv_close": float(tv_c.iloc[i]),
                "mt5_open": float(hp_o.iloc[i]),
                "mt5_high": float(hp_h.iloc[i]),
                "mt5_low": float(hp_l.iloc[i]),
                "mt5_close": float(hp_c.iloc[i]),
                "close_abs_diff": cdiff,
            }
        )
        if status == "MISMATCH":
            # Individual reason grounded in this bar's own closes/SMAs/feed diffs.
            def side(f, s):
                if pd.isna(f) or pd.isna(s):
                    return "undefined (warmup)"
                if f > s:
                    return "fast-above-slow"
                if f < s:
                    return "fast-below-slow"
                return "equal (no strict cross)"

            reason = (
                f"observed TV={a!r} vs MT5={b!r} at {t.isoformat()}; "
                f"TV close={float(tv_c.iloc[i]):.5f} MT5 close={float(hp_c.iloc[i]):.5f} "
                f"abs_close_diff={cdiff:.5f}; "
                f"TV SMA3={tv_f3.iloc[i]:.5f} SMA5={tv_f5.iloc[i]:.5f} "
                f"({side(tv_f3.iloc[i], tv_f5.iloc[i])}) vs "
                f"MT5 SMA3={hp_f3.iloc[i]:.5f} SMA5={hp_f5.iloc[i]:.5f} "
                f"({side(hp_f3.iloc[i], hp_f5.iloc[i])}); "
                f"feed OHLC gaps O={abs(float(tv_o.iloc[i]) - float(hp_o.iloc[i])):.5f} "
                f"H={abs(float(tv_h.iloc[i]) - float(hp_h.iloc[i])):.5f} "
                f"L={abs(float(tv_l.iloc[i]) - float(hp_l.iloc[i])):.5f}."
            )
            disc_rows.append(
                {
                    "time_utc": t.isoformat(),
                    "tv_signal": a,
                    "mt5_signal": b,
                    "tv_close": float(tv_c.iloc[i]),
                    "mt5_close": float(hp_c.iloc[i]),
                    "close_abs_diff": cdiff,
                    "tv_sma3": float(tv_f3.iloc[i]) if pd.notna(tv_f3.iloc[i]) else "",
                    "tv_sma5": float(tv_f5.iloc[i]) if pd.notna(tv_f5.iloc[i]) else "",
                    "mt5_sma3": float(hp_f3.iloc[i]) if pd.notna(hp_f3.iloc[i]) else "",
                    "mt5_sma5": float(hp_f5.iloc[i]) if pd.notna(hp_f5.iloc[i]) else "",
                    "reason": reason,
                }
            )

    agree_df = pd.DataFrame(
        agree_rows,
        columns=[
            "time_utc",
            "tv_signal",
            "mt5_signal",
            "status",
            "tv_open",
            "tv_high",
            "tv_low",
            "tv_close",
            "mt5_open",
            "mt5_high",
            "mt5_low",
            "mt5_close",
            "close_abs_diff",
        ],
    )
    agree_df.to_csv(OUT_AGREE, index=False)
    disc_cols = [
        "time_utc",
        "tv_signal",
        "mt5_signal",
        "tv_close",
        "mt5_close",
        "close_abs_diff",
        "tv_sma3",
        "tv_sma5",
        "mt5_sma3",
        "mt5_sma5",
        "reason",
    ]
    pd.DataFrame(disc_rows, columns=disc_cols).to_csv(OUT_DISC, index=False)

    n_tv = sum(1 for s in tv_sign if s)
    n_hp = sum(1 for s in hp_sign if s)
    n_agree = int((agree_df["status"] == "AGREE").sum())
    n_misc = int((agree_df["status"] == "MISMATCH").sum())
    print(f"BARS tv=48 hp=48 signals tv={n_tv} hp={n_hp} agree_rows={n_agree} mismatch_rows={n_misc}")
    if n_misc == 0:
        print("MISMATCHES zero: all 48 UTC bars carry identical observed markers (feed OHLC gaps are not mismatches)")
    else:
        print(f"MISMATCHES {n_misc}: see {OUT_DISC.name} for per-bar close/SMA-grounded reasons")

    # --- overlay chart: one price line + two distinct marker series ---
    x = [t.tz_convert(None) for t in EXPECTED_UTC]
    fig, ax = plt.subplots(figsize=(12, 5.2))
    ax.plot(x, tv_c.values, linewidth=1.4, color="#1f4fa3", label="_nolegend_")
    # Distinct vertical placement so coincident markers stay visible.
    pine_bull_x, pine_bull_y, mt5_bull_x, mt5_bull_y = [], [], [], []
    pine_bear_x, pine_bear_y, mt5_bear_x, mt5_bear_y = [], [], [], []
    for i in range(48):
        if tv_sign[i] == "BULL":
            pine_bull_x.append(x[i])
            pine_bull_y.append(float(tv_l.iloc[i]) - 0.00028)
        elif tv_sign[i] == "BEAR":
            pine_bear_x.append(x[i])
            pine_bear_y.append(float(tv_h.iloc[i]) + 0.00028)
        if hp_sign[i] == "BULL":
            mt5_bull_x.append(x[i])
            mt5_bull_y.append(float(hp_l.iloc[i]) - 0.00055)
        elif hp_sign[i] == "BEAR":
            mt5_bear_x.append(x[i])
            mt5_bear_y.append(float(hp_h.iloc[i]) + 0.00055)
    ax.scatter(pine_bull_x, pine_bull_y, marker="^", s=70, color="#0a7a2e", edgecolors="black",
               linewidths=0.6, zorder=4, label="Pine BULL")
    ax.scatter(pine_bear_x, pine_bear_y, marker="v", s=70, color="#c00000", edgecolors="black",
               linewidths=0.6, zorder=4, label="Pine BEAR")
    ax.scatter(mt5_bull_x, mt5_bull_y, marker="o", s=44, color="none", edgecolors="#0a7a2e",
               linewidths=1.6, zorder=5, label="MT5 BULL")
    ax.scatter(mt5_bear_x, mt5_bear_y, marker="X", s=44, color="#c00000",
               linewidths=1.4, zorder=5, label="MT5 BEAR")
    ax.set_title("M179 EURUSD H1 marker overlay — OANDA close with Pine and MT5 markers", fontsize=11)
    ax.set_xlabel("UTC time (hourly)")
    ax.set_ylabel("Price")
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%m-%d %HZ"))
    fig.autofmt_xdate(rotation=30)
    # Signal-only legend (markers only; line is described in the note).
    leg = ax.legend(frameon=True, fontsize=9, loc="upper left", title="Markers")
    leg.get_title().set_fontsize(9)
    fig.text(
        0.01,
        0.01,
        "Line: OANDA close. Sources: TradingView OANDA EURUSD H1 (UTC) + "
        "HolaPrime-Server1 EURUSD H1 (MT5 UTC+3 -> UTC = MT5-3h). "
        "Markers: observed SMA(3)/SMA(5) strict-crossover BULL/BEAR only.",
        fontsize=7.5,
        ha="left",
        va="bottom",
    )
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    fig.savefig(OUT_PNG, dpi=150)
    plt.close(fig)
    print(f"WROTE {OUT_AGREE.name} rows={len(agree_df)}")
    print(f"WROTE {OUT_DISC.name} rows={len(disc_rows)}")
    print(f"WROTE {OUT_PNG.name}")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="M179 Pine vs MT5 H1 signal comparison")
    ap.add_argument(
        "--month",
        default=None,
        help="Fixed calendar-month mode; only '2026-08' is supported "
        "(default: 48-bar 2026-09-08..09 comparison).",
    )
    return ap.parse_args()


# ---------------------------------------------------------------------------
# --month 2026-08 mode: complete fixed calendar month of August 2026 H1.
# ---------------------------------------------------------------------------
#
# Both month inputs are published files read from this directory (BASE), so
# the proof reproduces from a fresh copy of the proof-kit directory alone
# (pandas + matplotlib required); no ignored tmp/ files are needed.
#
# Input A (published source, read from
#   M179_TradingView_OANDA_EURUSD_H1_202608_packed.b64 next to this file):
#   captured through the visible TradingView OANDA:EURUSD H1 UTC Table view
#   on 2026-09-25 (the Basic account's built-in Download action opened a
#   paid-plan prompt, so no native TradingView CSV file download exists).
#   The published Base64 is a lossless transfer of that observed visible
#   table -- NOT a native TradingView CSV: it decodes to a little-endian
#   packed payload of uint32 count, uint32 first UNIX epoch seconds, then
#   count records of exactly 10 bytes: uint8 delta-hours from previous bar
#   (first 0, then 1 or 49 across weekend gaps), 4 x uint16 LE OHLC stored
#   as round(price*100000)-100000, uint8 marker enum (0 empty, 1 BULL,
#   2 BEAR). Observed TradingView markers, never generated. First timestamp
#   is the first row; each later row adds 3600*delta-hours.
# Input B (authoritative, read from
#   M179_HolaPrime_EURUSD_H1_202608_mql5_export_bars.csv and
#   M179_HolaPrime_EURUSD_H1_202608_mql5_export_signals.csv next to this
#   file): DIRECT FileWrite output of the read-only MQL5 script
#   SCA_M179_HolaPrimeSignalExport_202608.mq5, executed in the isolated
#   HolaPrime MT5 terminal on HolaPrime-Server1 (compiled 0 errors /
#   0 warnings, no order/account/position API, AllowLiveTrading=0).
#   507 August H1 broker bars with server-clock time_mt5 labels
#   (UTC = MT5 - 3h exactly) plus the OBSERVED direct MQL5 direction on
#   each bar; the 112-row signals file must match the bars file exactly
#   (time/direction/OHLC). Every MT5 marker in the tables, chart and
#   reasons below is this observed MQL5 script value -- never a local
#   recomputation. A local strict SMA(3)/SMA(5) recomputation over the
#   raw warmup closes is a formula cross-check only: it must equal the
#   observed marker on all 507 month bars, and observed values are never
#   replaced by it. The fixed period (3/5) is unchanged.
# Input C (independent quote cross-check, read from
#   M179_HolaPrime_EURUSD_H1_202608_raw.csv next to this file):
#   read-only MetaTrader5.copy_rates_range output from the installed
#   HolaPrime MT5 terminal on HolaPrime-Server1 (Jul31 03:00 .. Sep1 02:00
#   server clock, 528 rows, 21 pre-window warmup bars), preserved verbatim
#   under its published name. Used ONLY to cross-check that the direct
#   MQL5 export OHLC match the raw API quotes exactly at 5 decimals for
#   all 507 bars, and as the close history (including warmup) for the
#   formula cross-check.
MONTH = "2026-08"
TV_PACKED_FILE = "M179_TradingView_OANDA_EURUSD_H1_202608_packed.b64"
HP_MQL5_BARS_FILE = "M179_HolaPrime_EURUSD_H1_202608_mql5_export_bars.csv"
HP_MQL5_SIGNALS_FILE = "M179_HolaPrime_EURUSD_H1_202608_mql5_export_signals.csv"
HP_RAW_FILE = "M179_HolaPrime_EURUSD_H1_202608_raw.csv"
MT5_OFFSET_H = 3
MARK_ENUM = {0: "", 1: "BULL", 2: "BEAR"}


def decode_tv_packed(payload: bytes):
    if len(payload) < 8:
        fail(f"TV packed payload too short ({len(payload)} bytes)")
    count = struct.unpack("<I", payload[0:4])[0]
    first = struct.unpack("<I", payload[4:8])[0]
    if len(payload) != 8 + 10 * count:
        fail(f"TV packed length {len(payload)} != 8+10*{count}={8 + 10 * count}")
    if count == 0:
        fail("TV packed count is zero")
    rows = []
    ts = first
    off = 8
    for i in range(count):
        delta = payload[off]
        o, h, l, c = struct.unpack("<HHHH", payload[off + 1 : off + 9])
        m = payload[off + 9]
        if i == 0:
            if delta != 0:
                fail(f"TV packed first record delta must be 0, got {delta}")
        else:
            if delta not in (1, 49):
                fail(f"TV packed record {i} bad delta-hours {delta} (want 1 or 49)")
            ts += 3600 * delta
        if m not in MARK_ENUM:
            fail(f"TV packed record {i} bad marker enum {m}")
        prices = [(v + 100000) / 100000 for v in (o, h, l, c)]
        for p in prices:
            if not (1.0 < p < 2.0):
                fail(f"TV packed record {i} implausible price {p:.5f}")
        op, hp_, lp, cp = prices
        if not (lp <= op <= hp_ and lp <= cp <= hp_ and lp <= hp_):
            fail(f"TV packed record {i} inconsistent OHLC {prices}")
        rows.append((ts, op, hp_, lp, cp, MARK_ENUM[m]))
        off += 10
    if len({r[0] for r in rows}) != len(rows):
        fail("TV packed timestamps are not distinct")
    return rows


def side_label(f, s) -> str:
    if pd.isna(f) or pd.isna(s):
        return "undefined (warmup)"
    if f > s:
        return "fast-above-slow"
    if f < s:
        return "fast-below-slow"
    return "equal (no strict cross)"


def month_main() -> None:
    packed_path = BASE / TV_PACKED_FILE
    mql5_bars_path = BASE / HP_MQL5_BARS_FILE
    mql5_signals_path = BASE / HP_MQL5_SIGNALS_FILE
    raw_path = BASE / HP_RAW_FILE
    if not packed_path.is_file():
        fail(f"missing month input {TV_PACKED_FILE}")
    if not mql5_bars_path.is_file():
        fail(f"missing month input {HP_MQL5_BARS_FILE}")
    if not mql5_signals_path.is_file():
        fail(f"missing month input {HP_MQL5_SIGNALS_FILE}")
    if not raw_path.is_file():
        fail(f"missing month input {HP_RAW_FILE}")

    b64 = packed_path.read_text(encoding="utf-8").strip()
    print(f"MONTH input A: {TV_PACKED_FILE} base64_chars={len(b64)}")
    try:
        payload = base64.b64decode(b64, validate=True)
    except Exception as exc:
        fail(f"TV packed Base64 decode error: {exc}")
    tv_rows = decode_tv_packed(payload)
    print(f"MONTH decoded TV payload: bytes={len(payload)} count={len(tv_rows)}")

    tv_df = pd.DataFrame(tv_rows, columns=["epoch", "open", "high", "low", "close", "direction"])
    tv_df["time_utc"] = pd.to_datetime(tv_df["epoch"], unit="s", utc=True)
    tv_utc = list(tv_df["time_utc"])
    print(f"MONTH TV span: {tv_utc[0].isoformat()} .. {tv_utc[-1].isoformat()}")
    months = {t.strftime("%Y-%m") for t in tv_utc}
    if months != {"2026-08"}:
        fail(f"TV bars leave August 2026: {sorted(months)}")
    gaps = [tv_utc[i] for i in range(1, len(tv_utc)) if (tv_utc[i] - tv_utc[i - 1]) == pd.Timedelta(hours=49)]
    print(f"MONTH TV weekend gaps (49h): {len(gaps)}")
    if len(tv_rows) != 507:
        fail(f"TV August wrong bar count {len(tv_rows)} (want 507)")

    # --- Input B (authoritative): direct MQL5 script export ---
    hp_mql5_bars = pd.read_csv(mql5_bars_path)
    hp_mql5_sigs = pd.read_csv(mql5_signals_path)
    check_columns(hp_mql5_bars, ["time_mt5", "open", "high", "low", "close", "direction"],
                  "MQL5 direct bars")
    check_columns(hp_mql5_sigs, ["time_mt5", "direction", "open", "high", "low", "close"],
                  "MQL5 direct signals")
    if len(hp_mql5_bars) != 507:
        fail(f"MQL5 direct bars wrong row count {len(hp_mql5_bars)} (want 507)")
    if len(hp_mql5_sigs) != 112:
        fail(f"MQL5 direct signals wrong row count {len(hp_mql5_sigs)} (want 112)")
    print(f"MONTH input B (authoritative observed MQL5 script): {HP_MQL5_BARS_FILE} "
          f"bars={len(hp_mql5_bars)} + {HP_MQL5_SIGNALS_FILE} signals={len(hp_mql5_sigs)}")
    try:
        mql5_mt5 = pd.to_datetime(hp_mql5_bars["time_mt5"], format="%Y.%m.%d %H:%M:%S")
    except Exception as exc:
        fail(f"MQL5 direct bars time_mt5 parse error: {exc}")
    if mql5_mt5.duplicated().any():
        fail("MQL5 direct bars contain duplicate time_mt5 values")
    if hp_mql5_sigs["time_mt5"].duplicated().any():
        fail("MQL5 direct signals contain duplicate time_mt5 values")
    # Server-clock labels (UTC+3) -> UTC by subtracting exactly 3 hours.
    mql5_utc = (mql5_mt5 - pd.Timedelta(hours=MT5_OFFSET_H)).dt.tz_localize("UTC")

    # Observed MQL5 directions: use only observed values, never invent.
    mql5_obs = [norm_sign(v) for v in hp_mql5_bars["direction"].tolist()]
    for i, s in enumerate(mql5_obs):
        if s not in VALID_SIGNS and s != "":
            fail(f"MQL5 direct bars row {i} unexpected direction {s!r}")

    # --- direct signals-file cross-check: every signal row must match its
    # --- bar row's time/direction/OHLC, and every bar marker must be listed.
    try:
        pd.to_datetime(hp_mql5_sigs["time_mt5"], format="%Y.%m.%d %H:%M:%S")
    except Exception as exc:
        fail(f"MQL5 direct signals time_mt5 parse error: {exc}")
    bar_by_time: dict[str, int] = {}
    for i, t in enumerate(hp_mql5_bars["time_mt5"]):
        bar_by_time[t] = i
    seen_sig = set()
    for r in range(len(hp_mql5_sigs)):
        t = hp_mql5_sigs["time_mt5"].iloc[r]
        d = norm_sign(hp_mql5_sigs["direction"].iloc[r])
        if d not in VALID_SIGNS:
            fail(f"MQL5 direct signals row {r} unexpected direction {d!r}")
        if t not in bar_by_time:
            fail(f"MQL5 direct signals row {r} unexpected time {t!r}")
        if t in seen_sig:
            fail(f"MQL5 direct signals duplicate entry for {t!r}")
        seen_sig.add(t)
        idx = bar_by_time[t]
        if mql5_obs[idx] != d:
            fail(f"MQL5 signal/bars direction disagreement at {t!r}: bars={mql5_obs[idx]!r} signals={d!r}")
        for col in ("open", "high", "low", "close"):
            a = float(hp_mql5_bars[col].iloc[idx])
            b = float(hp_mql5_sigs[col].iloc[r])
            if abs(a - b) > 1e-9:
                fail(f"MQL5 signal/bars OHLC disagreement at {t!r} col {col}: bars={a} signals={b}")
    for i, s in enumerate(mql5_obs):
        if s != "" and hp_mql5_bars["time_mt5"].iloc[i] not in seen_sig:
            fail(f"MQL5 bars marker {s!r} at {hp_mql5_bars['time_mt5'].iloc[i]!r} missing from signals file")
    print(f"MONTH signals cross-check: {len(seen_sig)}/{len(seen_sig)} direct signal rows match "
          f"bar rows (time/direction/OHLC)")

    aug_start = pd.Timestamp("2026-08-01", tz="UTC")
    sep_start = pd.Timestamp("2026-09-01", tz="UTC")
    if mql5_utc.iloc[0] != pd.Timestamp("2026-08-02 21:00:00", tz="UTC"):
        fail(f"MQL5 direct bars wrong first UTC bar {mql5_utc.iloc[0].isoformat()} (want 2026-08-02T21:00Z)")
    if mql5_utc.iloc[-1] != pd.Timestamp("2026-08-31 23:00:00", tz="UTC"):
        fail(f"MQL5 direct bars wrong last UTC bar {mql5_utc.iloc[-1].isoformat()} (want 2026-08-31T23:00Z)")

    # --- hard alignment: every TV August stamp must exist exactly once in
    # --- the observed direct MQL5 export, in the same chronological order ---
    tv_set = set(tv_utc)
    hp_set = set(mql5_utc)
    if tv_set != hp_set:
        miss = sorted(tv_set - hp_set)[:5]
        extra = sorted(hp_set - tv_set)[:5]
        fail(f"observed MQL5 August UTC bars do not match TV: "
             f"missing={[t.isoformat() for t in miss]} extra={[t.isoformat() for t in extra]}")
    if list(mql5_utc) != list(tv_utc):
        fail("observed MQL5 UTC order does not match TV order")
    print(f"MONTH alignment: {len(tv_set)}/{len(tv_set)} August UTC stamps match exactly (TV vs observed MQL5)")

    # --- Input C: raw broker CSV as an independent quote cross-check only ---
    hp_raw = pd.read_csv(raw_path)
    check_columns(hp_raw, ["time_mt5", "open", "high", "low", "close"], "HolaPrime raw")
    try:
        hp_mt5 = pd.to_datetime(hp_raw["time_mt5"], format="%Y.%m.%d %H:%M:%S")
    except Exception as exc:
        fail(f"HolaPrime raw time_mt5 parse error: {exc}")
    if hp_mt5.duplicated().any():
        fail("HolaPrime raw contains duplicate time_mt5 values")
    hp_raw["time_utc"] = (hp_mt5 - pd.Timedelta(hours=MT5_OFFSET_H)).dt.tz_localize("UTC")
    print(f"MONTH input C (independent quote cross-check): {HP_RAW_FILE} rows={len(hp_raw)} "
          f"utc_span={hp_raw['time_utc'].iloc[0].isoformat()}..{hp_raw['time_utc'].iloc[-1].isoformat()}")
    warm = hp_raw[hp_raw["time_utc"] < aug_start]
    hp_aug_raw = hp_raw[(hp_raw["time_utc"] >= aug_start) & (hp_raw["time_utc"] < sep_start)]
    print(f"MONTH warmup pre-window bars: {len(warm)} "
          f"({warm['time_utc'].iloc[0].isoformat()}..{warm['time_utc'].iloc[-1].isoformat()})")
    if len(warm) != 21:
        fail(f"HolaPrime raw warmup wrong row count {len(warm)} (want 21)")
    if len(hp_aug_raw) != 507:
        fail(f"HolaPrime raw August window wrong row count {len(hp_aug_raw)} (want 507)")

    # --- direct export OHLC must match the raw API quotes exactly at
    # --- 5 decimals for all 507 bars (matched on the server-clock label) ---
    raw_by_time: dict[str, int] = {}
    for i, t in enumerate(hp_raw["time_mt5"]):
        raw_by_time[t] = i
    worst = 0.0
    for i, t in enumerate(hp_mql5_bars["time_mt5"]):
        if t not in raw_by_time:
            fail(f"direct MQL5 bar {t!r} missing from raw API extract")
        j = raw_by_time[t]
        for col in ("open", "high", "low", "close"):
            a = float(hp_mql5_bars[col].iloc[i])
            b = float(hp_raw[col].iloc[j])
            worst = max(worst, abs(a - b))
            if f"{a:.5f}" != f"{b:.5f}":
                fail(f"direct/raw 5-decimal OHLC disagreement at {t!r} col {col}: direct={a:.5f} raw={b:.5f}")
    print("MONTH raw cross-check: direct MQL5 OHLC == raw API at 5 decimals on 507/507 bars "
          f"(max abs diff {worst:.5f})")

    # --- formula cross-check: local strict SMA(3)/SMA(5) over the raw
    # --- closes INCLUDING warmup must equal the observed MQL5 marker on
    # --- every month bar. Observed markers are never replaced by this. ---
    hp_close = pd.to_numeric(hp_raw["close"], errors="coerce")
    if hp_close.isna().any():
        fail("HolaPrime raw non-numeric close")
    hp_f3_full = sma(hp_close, 3)
    hp_f5_full = sma(hp_close, 5)
    recomputed_all = []
    for i in range(len(hp_raw)):
        if i < 1:
            recomputed_all.append("")
        else:
            recomputed_all.append(strict_marker(
                hp_f3_full.iloc[i - 1], hp_f5_full.iloc[i - 1], hp_f3_full.iloc[i], hp_f5_full.iloc[i]
            ))
    hp_raw["recomputed"] = recomputed_all
    aug_mask = (hp_raw["time_utc"] >= aug_start) & (hp_raw["time_utc"] < sep_start)
    # Raw August rows are chronological like the direct export; verify
    # label-by-label so the cross-check compares the same bars.
    aug_labels = hp_raw[aug_mask].reset_index(drop=True)
    if list(aug_labels["time_mt5"]) != list(hp_mql5_bars["time_mt5"]):
        fail("raw August server-clock labels do not match direct MQL5 export order")
    n_formula_bad = 0
    for k in range(507):
        if aug_labels["recomputed"].iloc[k] != mql5_obs[k]:
            n_formula_bad += 1
            if n_formula_bad <= 5:
                print(f"MONTH formula cross-check mismatch at {aug_labels['time_mt5'].iloc[k]!r}: "
                      f"observed={mql5_obs[k]!r} recomputed={aug_labels['recomputed'].iloc[k]!r}",
                      file=sys.stderr)
    if n_formula_bad:
        fail(f"MQL5 observed/recomputed formula cross-check failed on {n_formula_bad}/507 month bars")
    print("MONTH formula cross-check: observed MQL5 script == strict SMA(3)/SMA(5) recompute "
          "(raw warmup) on 507/507 month bars")
    hp_aug_f3 = hp_f3_full[aug_mask].reset_index(drop=True)
    hp_aug_f5 = hp_f5_full[aug_mask].reset_index(drop=True)

    # --- August MT5 frame from the OBSERVED direct export (TV order) ---
    for col in ("open", "high", "low", "close"):
        vals = pd.to_numeric(hp_mql5_bars[col], errors="coerce")
        if vals.isna().any():
            fail(f"MQL5 direct bars non-numeric {col}")
    hp_aug = pd.DataFrame({
        "time_mt5": list(hp_mql5_bars["time_mt5"]),
        "time_utc": list(mql5_utc),
        "open": pd.to_numeric(hp_mql5_bars["open"]).tolist(),
        "high": pd.to_numeric(hp_mql5_bars["high"]).tolist(),
        "low": pd.to_numeric(hp_mql5_bars["low"]).tolist(),
        "close": pd.to_numeric(hp_mql5_bars["close"]).tolist(),
        "direction": mql5_obs,
    })

    # --- TV observed markers vs local recompute (in-file history only) ---
    tv_close = pd.to_numeric(tv_df["close"], errors="coerce")
    if tv_close.isna().any():
        fail("TV bars non-numeric close")
    tv_f3 = sma(tv_close, 3)
    tv_f5 = sma(tv_close, 5)
    tv_recomputed = []
    for i in range(len(tv_df)):
        if i < 1:
            tv_recomputed.append("")
        else:
            tv_recomputed.append(strict_marker(tv_f3.iloc[i - 1], tv_f5.iloc[i - 1], tv_f3.iloc[i], tv_f5.iloc[i]))
    tv_obs = tv_df["direction"].tolist()
    for i, s in enumerate(tv_obs):
        if s not in VALID_SIGNS and s != "":
            fail(f"TV bars row {i} unexpected direction {s!r}")
    verifiable = 0
    for i in range(len(tv_df)):
        if i >= 5:  # at least 5 in-file preceding bars; no pre-window TV warmup exists
            verifiable += 1
            if tv_recomputed[i] != tv_obs[i]:
                fail(f"TV observed/recomputed mismatch at {tv_utc[i].isoformat()}: "
                     f"observed={tv_obs[i]!r} recomputed={tv_recomputed[i]!r}")
    print(f"MONTH TV self-check: observed==recomputed on {verifiable}/{len(tv_df)} verifiable bars "
          f"(first 5 need pre-window closes: UNVERIFIABLE, never invented)")

    # --- write source bars/signals CSVs (_202608 suffix; 48-bar originals untouched) ---
    tv_bars_p = BASE / "M179_TradingView_OANDA_EURUSD_H1_202608_bars.csv"
    tv_sig_p = BASE / "M179_TradingView_OANDA_EURUSD_H1_202608_signals.csv"
    hp_bars_p = BASE / "M179_HolaPrime_EURUSD_H1_202608_bars.csv"
    hp_sig_p = BASE / "M179_HolaPrime_EURUSD_H1_202608_signals.csv"
    hp_raw_p = BASE / "M179_HolaPrime_EURUSD_H1_202608_raw.csv"

    tv_bars = pd.DataFrame({
        "time_utc": [t.strftime("%Y-%m-%dT%H:%M:%SZ") for t in tv_utc],
        "open": [f"{v:.5f}" for v in tv_df["open"]],
        "high": [f"{v:.5f}" for v in tv_df["high"]],
        "low": [f"{v:.5f}" for v in tv_df["low"]],
        "close": [f"{v:.5f}" for v in tv_df["close"]],
        "direction": tv_obs,
    })
    tv_bars.to_csv(tv_bars_p, index=False)
    tv_sig_rows = tv_bars[tv_bars["direction"] != ""].copy()
    tv_sig_rows = tv_sig_rows[["time_utc", "direction", "open", "high", "low", "close"]]
    tv_sig_rows.to_csv(tv_sig_p, index=False)

    hp_bars = pd.DataFrame({
        "time_mt5": hp_aug["time_mt5"],
        "time_utc": [t.strftime("%Y-%m-%dT%H:%M:%SZ") for t in hp_aug["time_utc"]],
        "open": [f"{v:.5f}" for v in pd.to_numeric(hp_aug["open"])],
        "high": [f"{v:.5f}" for v in pd.to_numeric(hp_aug["high"])],
        "low": [f"{v:.5f}" for v in pd.to_numeric(hp_aug["low"])],
        "close": [f"{v:.5f}" for v in pd.to_numeric(hp_aug["close"])],
        "direction": hp_aug["direction"].tolist(),
    })
    hp_bars.to_csv(hp_bars_p, index=False)
    hp_sig_rows = hp_bars[hp_bars["direction"] != ""].copy()
    hp_sig_rows[["time_mt5", "time_utc", "direction", "open", "high", "low", "close"]].to_csv(hp_sig_p, index=False)

    # The raw broker extract is itself the published source file: keep it
    # byte-identical in place (only copy when input and output differ).
    if raw_path.resolve() != hp_raw_p.resolve():
        shutil.copyfile(raw_path, hp_raw_p)

    # --- agreement + discrepancy tables ---
    hp_sign = hp_aug["direction"].tolist()
    hp_o = pd.to_numeric(hp_aug["open"])
    hp_h = pd.to_numeric(hp_aug["high"])
    hp_l = pd.to_numeric(hp_aug["low"])
    hp_c = pd.to_numeric(hp_aug["close"])
    tv_o = pd.to_numeric(tv_df["open"])
    tv_h = pd.to_numeric(tv_df["high"])
    tv_l = pd.to_numeric(tv_df["low"])

    # Mirror-pairing: two mismatch bars form one timing-shifted crossing event
    # when each shows what the other lacks (used at most once, nearest first).
    n = len(tv_utc)
    mis = [k for k in range(n) if tv_obs[k] != hp_sign[k]]
    mis_set = set(mis)
    pair_of: dict[int, int] = {}
    for d in (1, 2, 3):
        for k in mis:
            if k in pair_of:
                continue
            for q in (k - d, k + d):
                if q in mis_set and q not in pair_of:
                    if tv_obs[q] == hp_sign[k] and hp_sign[q] == tv_obs[k]:
                        pair_of[k] = q
                        pair_of[q] = k
                        break

    def nearest_other_marker(k: int, want: str, other: list[str]) -> int | None:
        for d in (1, 2, 3):
            for q in (k - d, k + d):
                if 0 <= q < n and other[q] == want:
                    return q
        return None

    agree_rows = []
    disc_rows = []
    for k, t in enumerate(tv_utc):
        a = tv_obs[k]
        b = hp_sign[k]
        status = "AGREE" if a == b else "MISMATCH"
        cdiff = abs(float(tv_close.iloc[k]) - float(hp_c.iloc[k]))
        check = "UNVERIFIABLE-NO-PREWINDOW" if k < 5 else ("AGREE" if tv_recomputed[k] == a else "MISMATCH")
        agree_rows.append({
            "time_utc": t.isoformat(),
            "tv_signal": a,
            "mt5_signal": b,
            "status": status,
            "tv_recomputed": tv_recomputed[k],
            "tv_rule_check": check,
            "tv_open": float(tv_o.iloc[k]),
            "tv_high": float(tv_h.iloc[k]),
            "tv_low": float(tv_l.iloc[k]),
            "tv_close": float(tv_close.iloc[k]),
            "mt5_open": float(hp_o.iloc[k]),
            "mt5_high": float(hp_h.iloc[k]),
            "mt5_low": float(hp_l.iloc[k]),
            "mt5_close": float(hp_c.iloc[k]),
            "close_abs_diff": cdiff,
        })
        if status == "MISMATCH":
            # Paired mirror = one timing-shifted crossing event. Unpaired rows
            # get the nearest same-direction marker on the other feed as plain
            # context (with that bar's own markers), never claimed as counterpart.
            counterpart = ""
            context = ""
            if k in pair_of:
                q = pair_of[k]
                dk = q - k
                if a != "":
                    counterpart = (f"same-direction {a} counterpart observed on the MQL5 script feed at "
                                   f"{tv_utc[q].isoformat()} ({dk:+d} bar(s))")
                else:
                    counterpart = (f"same-direction {b} counterpart observed on Pine feed at "
                                   f"{tv_utc[q].isoformat()} ({dk:+d} bar(s))")
            else:
                bits = []
                if a != "":
                    q = nearest_other_marker(k, a, hp_sign)
                    if q is None:
                        bits.append(f"no {a} marker within +-3 bars on the observed MQL5 feed")
                    else:
                        qs = "AGREE" if tv_obs[q] == hp_sign[q] else "MISMATCH"
                        bits.append(f"nearest observed-MQL5-{a} at {tv_utc[q].isoformat()} ({q - k:+d} bar(s)), "
                                    f"that bar Pine={tv_obs[q]!r} MQL5={hp_sign[q]!r} ({qs}), not its mirror pair")
                if b != "":
                    q = nearest_other_marker(k, b, tv_obs)
                    if q is None:
                        bits.append(f"no {b} marker within +-3 bars on the Pine feed")
                    else:
                        qs = "AGREE" if tv_obs[q] == hp_sign[q] else "MISMATCH"
                        bits.append(f"nearest Pine-{b} at {tv_utc[q].isoformat()} ({q - k:+d} bar(s)), "
                                    f"that bar Pine={tv_obs[q]!r} MQL5={hp_sign[q]!r} ({qs}), not its mirror pair")
                context = "; ".join(bits)
            prev_txt = (f"TV prev SMA3={tv_f3.iloc[k-1]:.6f} SMA5={tv_f5.iloc[k-1]:.6f} "
                        f"({side_label(tv_f3.iloc[k-1], tv_f5.iloc[k-1])}); "
                        f"MQL5 prev SMA3={hp_aug_f3.iloc[k-1]:.6f} SMA5={hp_aug_f5.iloc[k-1]:.6f} "
                        f"({side_label(hp_aug_f3.iloc[k-1], hp_aug_f5.iloc[k-1])}, formula cross-check)"
                        if k >= 1 else "prev SMAs undefined at first month bar")
            cur_txt = (f"TV cur SMA3={tv_f3.iloc[k]:.6f} SMA5={tv_f5.iloc[k]:.6f} "
                       f"({side_label(tv_f3.iloc[k], tv_f5.iloc[k])}); "
                       f"MQL5 cur SMA3={hp_aug_f3.iloc[k]:.6f} SMA5={hp_aug_f5.iloc[k]:.6f} "
                       f"({side_label(hp_aug_f3.iloc[k], hp_aug_f5.iloc[k])}, formula cross-check)")
            hist = max(abs(float(tv_close.iloc[q]) - float(hp_c.iloc[q]))
                       for q in range(max(0, k - 4), k + 1))
            mechanism = ""
            if counterpart:
                mechanism = (f"Timing-shifted single crossing event straddling the strict threshold: "
                             f"{counterpart}. Feed OHLC differences (this-bar close diff "
                             f"{cdiff:.5f}, max 5-bar-window close diff {hist:.5f}) move one feed's "
                             f"fast/slow pair across the strict >/< boundary one bar earlier/later. "
                             f"The observed MQL5 script marker equals the local SMA recomputation on "
                             f"both bars (formula cross-check passes 507/507), so this is a "
                             f"feed-threshold effect, not a script-vs-recompute difference.")
            else:
                mechanism = (f"No mirror-pair crossing within +-3 bars ({context}): the Pine feed "
                             f"crosses the strict threshold here while the observed MQL5 script feed keeps "
                             f"{side_label(hp_aug_f3.iloc[k], hp_aug_f5.iloc[k])} "
                             f"(feed OHLC differences: this-bar close diff {cdiff:.5f}, max 5-bar-window "
                             f"close diff {hist:.5f}). The observed MQL5 script marker equals the local "
                             f"SMA recomputation here (formula cross-check passes 507/507), and "
                             f"TV-observed matches TV-recomputed, so this is a feed-threshold effect, "
                             f"not a Pine live-vs-completed marker issue.")
            reason = (f"observed Pine={a!r} vs observed MQL5 script={b!r} at {t.isoformat()}; "
                      f"TV close={float(tv_close.iloc[k]):.5f} MQL5 close={float(hp_c.iloc[k]):.5f} "
                      f"abs_close_diff={cdiff:.5f}; {prev_txt}; {cur_txt}. {mechanism}")
            disc_rows.append({
                "time_utc": t.isoformat(),
                "tv_signal": a,
                "mt5_signal": b,
                "tv_close": float(tv_close.iloc[k]),
                "mt5_close": float(hp_c.iloc[k]),
                "close_abs_diff": cdiff,
                "tv_sma3_prev": f"{tv_f3.iloc[k-1]:.6f}" if k >= 1 else "",
                "tv_sma5_prev": f"{tv_f5.iloc[k-1]:.6f}" if k >= 1 else "",
                "tv_sma3": f"{tv_f3.iloc[k]:.6f}",
                "tv_sma5": f"{tv_f5.iloc[k]:.6f}",
                "mt5_sma3_prev": f"{hp_aug_f3.iloc[k-1]:.6f}" if k >= 1 else "",
                "mt5_sma5_prev": f"{hp_aug_f5.iloc[k-1]:.6f}" if k >= 1 else "",
                "mt5_sma3": f"{hp_aug_f3.iloc[k]:.6f}",
                "mt5_sma5": f"{hp_aug_f5.iloc[k]:.6f}",
                "reason": reason,
            })

    out_agree = BASE / "M179_signal_agreement_202608.csv"
    out_disc = BASE / "M179_signal_discrepancies_202608.csv"
    out_png = BASE / "M179_signal_overlay_202608.png"
    pd.DataFrame(agree_rows).to_csv(out_agree, index=False)
    pd.DataFrame(disc_rows, columns=[
        "time_utc", "tv_signal", "mt5_signal", "tv_close", "mt5_close", "close_abs_diff",
        "tv_sma3_prev", "tv_sma5_prev", "tv_sma3", "tv_sma5",
        "mt5_sma3_prev", "mt5_sma5_prev", "mt5_sma3", "mt5_sma5", "reason",
    ]).to_csv(out_disc, index=False)

    n_tv = sum(1 for s in tv_obs if s)
    n_hp = sum(1 for s in hp_sign if s)
    n_agree = sum(1 for r in agree_rows if r["status"] == "AGREE")
    n_misc = sum(1 for r in agree_rows if r["status"] == "MISMATCH")
    print(f"MONTH bars tv=507 hp_aug=507 signals tv_obs={n_tv} mt5_observed={n_hp} "
          f"agree={n_agree} mismatch={n_misc}")
    diffs = {}
    for col, tv_s, hp_s in (("open", tv_o, hp_o), ("high", tv_h, hp_h), ("low", tv_l, hp_l), ("close", tv_close, hp_c)):
        d = (pd.to_numeric(tv_s.reset_index(drop=True)) - pd.to_numeric(hp_s.reset_index(drop=True))).abs()
        diffs[col] = d
        print(f"MONTH-ALIGN {col}: max_abs_diff={d.max():.5f} mean={d.mean():.5f} nonzero={(d > 0).sum()}/507")

    # --- overlay: OANDA closes vs bar index (weekends absent), distinct markers ---
    x = list(range(len(tv_utc)))
    fig, ax = plt.subplots(figsize=(16, 6))
    ax.plot(x, pd.to_numeric(tv_close).values, linewidth=0.9, color="#1f4fa3", label="_nolegend_")
    pine_bull_x, pine_bull_y, mt5_bull_x, mt5_bull_y = [], [], [], []
    pine_bear_x, pine_bear_y, mt5_bear_x, mt5_bear_y = [], [], [], []
    for k in range(len(tv_utc)):
        if tv_obs[k] == "BULL":
            pine_bull_x.append(x[k])
            pine_bull_y.append(float(tv_l.iloc[k]) - 0.00045)
        elif tv_obs[k] == "BEAR":
            pine_bear_x.append(x[k])
            pine_bear_y.append(float(tv_h.iloc[k]) + 0.00045)
        if hp_sign[k] == "BULL":
            mt5_bull_x.append(x[k])
            mt5_bull_y.append(float(hp_l.iloc[k]) - 0.00085)
        elif hp_sign[k] == "BEAR":
            mt5_bear_x.append(x[k])
            mt5_bear_y.append(float(hp_h.iloc[k]) + 0.00085)
    ax.scatter(pine_bull_x, pine_bull_y, marker="^", s=26, color="#0a7a2e", edgecolors="black",
               linewidths=0.5, zorder=4, label="Pine BULL (observed)")
    ax.scatter(pine_bear_x, pine_bear_y, marker="v", s=26, color="#c00000", edgecolors="black",
               linewidths=0.5, zorder=4, label="Pine BEAR (observed)")
    ax.scatter(mt5_bull_x, mt5_bull_y, marker="o", s=20, color="none", edgecolors="#0a7a2e",
               linewidths=1.2, zorder=5, label="MQL5 BULL (observed MQL5 script)")
    ax.scatter(mt5_bear_x, mt5_bear_y, marker="X", s=20, color="#c00000",
               linewidths=1.0, zorder=5, label="MQL5 BEAR (observed MQL5 script)")
    ax.set_title("M179 EURUSD H1 August 2026 marker overlay — OANDA close with Pine (observed) "
                 "and MQL5 (observed) markers", fontsize=11)
    ax.set_xlabel("August 2026 trading bar (UTC; weekends naturally absent)")
    ax.set_ylabel("Price")
    # One tick about every third calendar day: daily labels overlap at this
    # width (notably around Aug 03-04, Aug 20-21, Aug 31). First bar index
    # of each distinct UTC date, thinned to every third day -- unique by
    # construction, data and marker positions unchanged.
    day_first: list[int] = []
    seen_days: set = set()
    for k, t in enumerate(tv_utc):
        d = t.date()
        if d not in seen_days:
            seen_days.add(d)
            day_first.append(k)
    tick_idx = day_first[::3]
    ax.set_xticks(tick_idx)
    ax.set_xticklabels([tv_utc[k].strftime("%b %d") for k in tick_idx], rotation=0, fontsize=9)
    leg = ax.legend(frameon=True, fontsize=9, loc="upper left", title="Markers")
    leg.get_title().set_fontsize(9)
    fig.text(
        0.01,
        0.01,
        "Line: OANDA close (507 August trading bars). Pine markers: observed TradingView Table-view output.\n"
        "MQL5 markers: observed direct MQL5 script FileWrite output (HolaPrime-Server1, UTC = MT5-3h). "
        "Local SMA(3)/SMA(5) recompute over raw warmup matches observed 507/507 "
        "(formula cross-check; observed markers never replaced).",
        fontsize=7.5,
        ha="left",
        va="bottom",
    )
    fig.tight_layout(rect=(0, 0.07, 1, 1))
    fig.savefig(out_png, dpi=150)
    plt.close(fig)
    print(f"WROTE {tv_bars_p.name} rows={len(tv_bars)}")
    print(f"WROTE {tv_sig_p.name} rows={len(tv_sig_rows)}")
    print(f"WROTE {hp_bars_p.name} rows={len(hp_bars)}")
    print(f"WROTE {hp_sig_p.name} rows={len(hp_sig_rows)}")
    print(f"WROTE {hp_raw_p.name} rows={len(hp_raw)}")
    print(f"WROTE {out_agree.name} rows={len(agree_rows)}")
    print(f"WROTE {out_disc.name} rows={len(disc_rows)}")
    print(f"WROTE {out_png.name}")


if __name__ == "__main__":
    args = parse_args()
    if args.month is None:
        main()
    elif args.month == MONTH:
        month_main()
    else:
        fail(f"unsupported --month {args.month!r} (only '2026-08' supported)")
