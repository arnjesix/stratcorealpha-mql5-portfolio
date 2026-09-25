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


if __name__ == "__main__":
    main()
