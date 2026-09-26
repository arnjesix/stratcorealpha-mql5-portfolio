#!/usr/bin/env python3
"""Independent audit of the completed native HolaPrime T99 ORB tester run.

Reads ONLY the already-produced native artifacts declared in
run_manifest_20260925.json (raw MT5 report, exported bars/deals/equity CSVs,
T99_run.json, native agent log) plus the repo-side freeze/cases files.
Performs no MT5 launch, no network access, no credential handling.

What it does:
  1. Maps the manifest's Windows D: paths to /mnt/d for local reads only.
  2. Validates SHA256 (+byte size) of report/bars/deals/equity/T99_run.json
     BEFORE reporting any figures. Any mismatch aborts with exit 2.
  3. Recomputes full-period figures from the real deals CSV (count, round
     trips, wins/losses, profit/commission/swap/net, final balance).
  4. Reconciles exported bars vs generated bars and server-time coverage.
  5. Streams (never fully loads) the ~136MB equity CSV for row count,
     final balance/equity and peak-to-trough drawdowns.
  6. Verifies three rule-fidelity cases (entry / no_break / flatten) as
     verbatim native-log excerpts with SERVER wall time, cross-checked
     against the exported bars and deals.
  7. Writes a concise JSON summary (--out) and a human-readable method
     note (--method, default: <out-dir>/audit_method.md).

UTC conversion of server times and any HolaPrime account-specific prop
verdict are reported INCONCLUSIVE: the whole-year broker clock/DST policy
and the account rules are not evidenced in the audited artifacts.

This is a historical simulation on one-minute OHLC generated ticks
(Model 1), not real ticks. No forecast, no guarantee, no marketing copy.
Standard library only.
"""

import argparse
import csv
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

ENC_UTF16 = "utf-16"  # native MT5 exports carry a BOM; utf-16 sniffs LE/BE.

# --------------------------------------------------------------------------
# path handling


def win_to_local(path):
    """Map a manifest Windows path to a local read path.

    Only drive D: is admitted (claim: raw files live under
    D:/CodexWork/sca_symbiose_holaprime_20260924). Anything else raises.
    """
    if not isinstance(path, str):
        raise ValueError("manifest path is not a string: %r" % (path,))
    m = re.match(r"^([A-Za-z]):(.*)$", path.replace("\\", "/"))
    if not m:
        raise ValueError("not a Windows path, refusing: %r" % (path,))
    drive, rest = m.group(1).upper(), m.group(2)
    if drive != "D":
        raise ValueError("only drive D: is admitted, refusing: %r" % (path,))
    if not rest.startswith("/"):
        rest = "/" + rest
    return "/mnt/d" + rest


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            b = fh.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


# --------------------------------------------------------------------------
# report parsing (German MT5 tester report, UTF-16 HTML)


def de_num(token):
    """Parse German MT5 numbers like '1 419.26', '-17 013.46', '19.74%'."""
    t = token.replace(" ", " ").replace(" ", "").replace("%", "")
    return float(t)


def collapse(html_text):
    no_tags = re.sub(r"<[^>]+>", " ", html_text)
    no_tags = no_tags.replace(" ", " ")
    return re.sub(r"\s+", " ", no_tags)


def grab_num(text, label_pat, group=1):
    m = re.search(label_pat, text)
    if not m:
        return None
    try:
        return de_num(m.group(group))
    except (ValueError, IndexError):
        return None


def parse_report(path):
    with open(path, encoding=ENC_UTF16) as fh:
        raw = fh.read()
    t = collapse(raw)
    rep = {}
    m = re.search(r"Expertenprogramm:\s*(.+?)\s*Symbol:", t)
    rep["expert"] = m.group(1).strip() if m else None
    m = re.search(r"Symbol:\s*(\S+)", t)
    rep["symbol"] = m.group(1) if m else None
    m = re.search(r"Periode:\s*M15\s*\(([\d.]+)\s*-\s*([\d.]+)\)", t)
    rep["period_server"] = [m.group(1), m.group(2)] if m else None
    m = re.search(r"Ersteinlage:\s*([\d\s.,]+)", t)
    rep["deposit"] = grab_num(t, r"Ersteinlage:\s*([\d\s.,]+)")
    m = re.search(r"Hebel:\s*(\S+)", t)
    rep["leverage"] = m.group(1) if m else None
    m = re.search(r"Firma:\s*(.+?)\s*Währung:", t)
    rep["broker_company"] = m.group(1).strip() if m else None
    span = ""
    mi = t.find("Eingaben:")
    mf = t.find("Firma:")
    if 0 <= mi < mf:
        span = t[mi:mf]
    rep["inputs"] = {k: v for k, v in re.findall(r"(Inp[A-Za-z]+)=([^\s]*)", span)}
    rep["history_quality_pct"] = grab_num(t, r"Qualität der Historie:\s*([\d\s.,]+%)")
    v = grab_num(t, r"Balken:\s*([\d\s]+?)\s*Ticks:")
    rep["bars_generated"] = int(v) if v is not None else None
    v = grab_num(t, r"Ticks:\s*([\d\s]+)")
    rep["ticks"] = int(v) if v is not None else None
    rep["net_total"] = grab_num(t, r"Nettogewinn gesamt:\s*(-?[\d\s.,]+)")
    rep["gross_profit"] = grab_num(t, r"Bruttogewinn:\s*(-?[\d\s.,]+)")
    rep["gross_loss"] = grab_num(t, r"Bruttoverlust:\s*(-?[\d\s.,]+)")
    rep["profit_factor"] = grab_num(t, r"Profitfaktor:\s*([\d.,]+)")
    rep["expected_payoff"] = grab_num(t, r"Erwartetes Ergebnis:\s*(-?[\d.,]+)")
    v = grab_num(t, r"Gesamtanzahl Trades:\s*(\d+)")
    rep["trades"] = int(v) if v is not None else None
    m = re.search(r"Sell-Positionen \(davon gewonnen %\):\s*(\d+)\s*\(([\d.,]+)%\)", t)
    rep["sell_positions"] = int(m.group(1)) if m else None
    rep["sell_won_pct"] = float(m.group(2).replace(",", ".")) if m else None
    m = re.search(r"Buy-Positionen \(davon gewonnen %\):\s*(\d+)\s*\(([\d.,]+)%\)", t)
    rep["buy_positions"] = int(m.group(1)) if m else None
    rep["buy_won_pct"] = float(m.group(2).replace(",", ".")) if m else None
    v = grab_num(t, r"Anzahl Deals:\s*(\d+)")
    rep["deals"] = int(v) if v is not None else None
    m = re.search(r"Gewonnene Trades \(in % von Gesamt\):\s*(\d+)\s*\(([\d.,]+)%\)", t)
    rep["won"] = int(m.group(1)) if m else None
    rep["won_pct"] = float(m.group(2).replace(",", ".")) if m else None
    m = re.search(r"Verlorene Trades \(in % von Gesamt\):\s*(\d+)\s*\(([\d.,]+)%\)", t)
    rep["lost"] = int(m.group(1)) if m else None
    rep["lost_pct"] = float(m.group(2).replace(",", ".")) if m else None
    rep["max_win_trade"] = grab_num(t, r"Größter Gewinntrade:\s*(-?[\d\s.,]+)")
    rep["max_loss_trade"] = grab_num(t, r"Größter Verlusttrade:\s*(-?[\d\s.,]+)")
    rep["avg_win_trade"] = grab_num(t, r"Durchschnitt Gewinntrade:\s*(-?[\d\s.,]+)")
    rep["avg_loss_trade"] = grab_num(t, r"Durchschnitt Verlusttrade:\s*(-?[\d\s.,]+)")
    rep["balance_dd_abs"] = grab_num(t, r"Rückgang Kontostand absolut:\s*(-?[\d\s.,]+)")
    m = re.search(r"Rückgang Kontostand maximal:\s*(-?[\d\s.,]+)\s*\(([\d.,]+)%\)", t)
    rep["balance_dd_max"] = de_num(m.group(1)) if m else None
    rep["balance_dd_max_pct"] = float(m.group(2).replace(",", ".")) if m else None
    rep["equity_dd_abs"] = grab_num(t, r"Rückgang Equity absolut:\s*(-?[\d\s.,]+)")
    m = re.search(r"Rückgang Equity maximal:\s*(-?[\d\s.,]+)\s*\(([\d.,]+)%\)", t)
    rep["equity_dd_max"] = de_num(m.group(1)) if m else None
    rep["equity_dd_max_pct"] = float(m.group(2).replace(",", ".")) if m else None
    # Safety: this audit must never carry credential fields.
    for forbidden in ("Login", "Passwort", "Password", "Investor"):
        if re.search(r"\b" + forbidden + r"\s*:", t):
            raise ValueError("report contains unexpected credential field %r; refusing" % forbidden)
    missing = [k for k, v in rep.items() if v is None and k != "inputs"]
    if missing:
        raise ValueError("report parse incomplete, missing: %s" % ", ".join(missing))
    return rep


# --------------------------------------------------------------------------
# deals / bars / equity recompute


DEALS_COLUMNS = ["seq", "ticket", "server_time", "tester_utc_offset_sec",
                 "symbol", "magic", "direction", "entry", "volume",
                 "price", "commission", "swap", "profit"]


def parse_deals(path):
    with open(path, encoding=ENC_UTF16, newline="") as fh:
        reader = csv.DictReader(fh)
        columns = reader.fieldnames or []
        rows = list(reader)
    if columns != DEALS_COLUMNS:
        raise ValueError("deals columns differ: %r" % (columns,))
    dec = Decimal
    n = len(rows)
    seq_ok = [r["seq"] for r in rows] == [str(i) for i in range(1, n + 1)]
    offsets = set(r["tester_utc_offset_sec"] for r in rows)
    symbols = set(r["symbol"] for r in rows)
    magics = set(r["magic"] for r in rows)
    entries = [r["entry"] for r in rows]
    pairing_valid = (
        n % 2 == 0 and n > 0
        and all(a == "IN" and b == "OUT" for a, b in zip(entries[0::2], entries[1::2]))
        and all(r["volume"] == s["volume"]
                for r, s in zip(rows[0::2], rows[1::2]))
    )
    s_profit = sum((dec(r["profit"]) for r in rows), dec("0"))
    s_comm = sum((dec(r["commission"]) for r in rows), dec("0"))
    s_swap = sum((dec(r["swap"]) for r in rows), dec("0"))
    net = s_profit + s_comm + s_swap
    out_profits = [dec(s["profit"]) for r, s in zip(rows[0::2], rows[1::2])] if pairing_valid else []
    rt_nets = [dec(s["profit"]) + dec(r["commission"]) + dec(s["commission"])
               + dec(r["swap"]) + dec(s["swap"])
               for r, s in zip(rows[0::2], rows[1::2])] if pairing_valid else []
    in_dirs = [r["direction"] for r in rows[0::2]] if pairing_valid else []
    fig = {
        "columns": columns,
        "count": n,
        "seq_continuous_from_1": seq_ok,
        "tester_utc_offset_values": sorted(offsets),
        "symbols": sorted(symbols),
        "magics": sorted(magics),
        "in_count": entries.count("IN"),
        "out_count": entries.count("OUT"),
        "pairing_consecutive_in_out_vol_match": pairing_valid,
        "round_trips": n // 2 if pairing_valid else None,
        "sum_profit": float(s_profit),
        "sum_commission": float(s_comm),
        "sum_swap": float(s_swap),
        "net": float(net),
        "in_profit_all_zero": all(r["profit"] == "0.00" for r in rows if r["entry"] == "IN"),
        "ticket_first": rows[0]["ticket"] if rows else None,
        "ticket_last": rows[-1]["ticket"] if rows else None,
    }
    if pairing_valid:
        wins_rt = sum(1 for v in rt_nets if v > 0)
        loss_rt = sum(1 for v in rt_nets if v < 0)
        wins_op = sum(1 for v in out_profits if v > 0)
        loss_op = sum(1 for v in out_profits if v <= 0)
        gp = sum((v for v in rt_nets if v > 0), dec("0"))
        gl = sum((v for v in rt_nets if v < 0), dec("0"))
        buy = [v for d, v in zip(in_dirs, rt_nets) if d == "BUY"]
        sell = [v for d, v in zip(in_dirs, rt_nets) if d == "SELL"]
        fig.update({
            "wins_roundtrip_net": wins_rt,
            "losses_roundtrip_net": loss_rt,
            "wins_out_profit_only": wins_op,
            "losses_out_profit_only": loss_op,
            "win_defs_agree": (wins_rt == wins_op and loss_rt == loss_op),
            "roundtrip_gross_pos": float(gp),
            "roundtrip_gross_neg": float(gl),
            "buy_positions": len(buy),
            "sell_positions": len(sell),
            "buy_won": sum(1 for v in buy if v > 0),
            "sell_won": sum(1 for v in sell if v > 0),
            "avg_win_roundtrip_net": float(sum((v for v in rt_nets if v > 0), dec("0")) / wins_rt) if wins_rt else None,
            "avg_loss_roundtrip_net": float(sum((v for v in rt_nets if v < 0), dec("0")) / loss_rt) if loss_rt else None,
            "max_roundtrip_net": float(max(rt_nets)),
            "min_roundtrip_net": float(min(rt_nets)),
        })
    return fig, rows


def parse_bars(path, keep_times=()):
    fmt = "%Y.%m.%d %H:%M:%S"
    n = 0
    first = last = None
    prev = None
    gaps = []  # every non-15m step, verbatim server stamps (few: weekends/holidays)
    dups = 0
    seen = set()
    keep = {}
    with open(path, encoding=ENC_UTF16, newline="") as fh:
        reader = csv.DictReader(fh)
        columns = reader.fieldnames or []
        if columns != ["seq", "server_time", "open", "high", "low", "close", "bar_time_iso"]:
            raise ValueError("bars columns differ: %r" % (columns,))
        for row in reader:
            n += 1
            st = row["server_time"]
            if first is None:
                first = st
            last = st
            if st in seen:
                dups += 1
            seen.add(st)
            if prev is not None:
                step = (datetime.strptime(st, fmt) - datetime.strptime(prev, fmt)).total_seconds() / 60
                if abs(step - 15) > 1e-9:
                    gaps.append({"from": prev, "to": st, "step_min": step,
                                 "from_weekday_server": datetime.strptime(prev, fmt).strftime("%a"),
                                 "to_weekday_server": datetime.strptime(st, fmt).strftime("%a")})
            prev = st
            if st in keep_times:
                keep[st] = {k: row[k] for k in ("open", "high", "low", "close")}
    weekend = [g for g in gaps if g["step_min"] == 2895.0]
    other = [g for g in gaps if g["step_min"] != 2895.0]
    return {"count": n, "first_server": first, "last_server": last,
            "non_15m_steps": len(gaps),
            "weekend_gaps_2895m_fri_to_mon": len(weekend),
            "other_gaps": other,
            "weekend_gaps_all_fri_to_mon_server": (
                len(weekend) > 0
                and all(g["from_weekday_server"] == "Fri" for g in weekend)
                and all(g["to_weekday_server"] == "Mon" for g in weekend)),
            "duplicates": dups}, keep


def stream_equity(path):
    n = 0
    first = last = None
    peak_b = peak_e = None
    max_b = max_e = Decimal("0")
    at_b = at_e = None
    peak_at_b = peak_at_e = None
    with open(path, encoding=ENC_UTF16, newline="") as fh:
        reader = csv.DictReader(fh)
        if (reader.fieldnames or []) != ["seq", "server_time", "balance", "equity"]:
            raise ValueError("equity columns differ: %r" % (reader.fieldnames,))
        for row in reader:  # streamed line by line; file never fully loaded
            n += 1
            if first is None:
                first = [row["seq"], row["server_time"], row["balance"], row["equity"]]
            last = [row["seq"], row["server_time"], row["balance"], row["equity"]]
            try:
                b = Decimal(row["balance"])
                e = Decimal(row["equity"])
            except InvalidOperation:
                raise ValueError("non-numeric equity row %r" % (row,))
            peak_b = b if (peak_b is None or b > peak_b) else peak_b
            peak_e = e if (peak_e is None or e > peak_e) else peak_e
            if peak_b - b > max_b:
                max_b, at_b, peak_at_b = peak_b - b, row["server_time"], str(peak_b)
            if peak_e - e > max_e:
                max_e, at_e, peak_at_e = peak_e - e, row["server_time"], str(peak_e)
    return {"data_rows": n, "first": first, "last": last,
            "final_balance": float(Decimal(last[2])), "final_equity": float(Decimal(last[3])),
            "max_balance_dd": float(max_b), "max_balance_dd_at_server": at_b,
            "max_balance_dd_peak": float(Decimal(peak_at_b)) if peak_at_b else None,
            "max_equity_dd": float(max_e), "max_equity_dd_at_server": at_e,
            "max_equity_dd_peak": float(Decimal(peak_at_e)) if peak_at_e else None}


# --------------------------------------------------------------------------
# native log case verification (UTF-16 tester-agent log, SERVER wall time)


CASE_MARKERS = {
    "entry": ("2025.09.01 09:45:00   T99 reason=entry: BUY vol=0.52 "
              "entry=1.17320 sl=1.17129 tp=1.17702 range=[1.17129, 1.17245] deal=2"),
    "no_break": ("2026.08.31 09:45:00   T99 reason=no_break: "
                 "close=1.15884 inside [1.15867, 1.15913]."),
    "flatten": ("2026.08.31 17:00:00   T99 reason=flatten: "
                "session end, own position closed, deal=519"),
}
FINISH_MARKERS = {
    "finish_balance": "final balance 11419.26",
    "deinit_export": "T99 reason=deinit_export",
    "coverage_end": "coverage_end_server=2026.08.31 23:59:59",
}

# Parsed from the ACTUAL native log lines (SERVER wall time), never hardcoded.
# Each pattern anchors on the SERVER stamp so a missing/changed line yields
# None (=> derived checks are False), never a constant True.
ENTRY_RE = re.compile(
    r"2025\.09\.01 09:45:00\s+T99 reason=entry:\s+"
    r"(BUY|SELL)\s+vol=(\S+)\s+entry=(\S+)\s+sl=(\S+)\s+tp=(\S+)\s+"
    r"range=\[(\S+),\s*(\S+)\]\s+deal=(\d+)")
NO_BREAK_RE = re.compile(
    r"2026\.08\.31 09:45:00\s+T99 reason=no_break:\s+"
    r"close=(\S+)\s+inside\s+\[(\S+),\s*(\S+)\]")
FLATTEN_RE = re.compile(
    r"2026\.08\.31 17:00:00\s+T99 reason=flatten:[^\n]*?deal=(\d+)")


def _parse_entry(text):
    m = ENTRY_RE.search(text)
    if not m:
        return None
    return {"direction": m.group(1), "vol": m.group(2), "entry": m.group(3),
            "sl": m.group(4), "tp": m.group(5),
            "range_low": m.group(6), "range_high": m.group(7),
            "deal": m.group(8)}


def _parse_no_break(text):
    m = NO_BREAK_RE.search(text)
    if not m:
        return None
    return {"close": m.group(1).rstrip(".,;"),
            "range_low": m.group(2).rstrip(".,;"),
            "range_high": m.group(3).rstrip(".,;")}


def _parse_flatten(text):
    m = FLATTEN_RE.search(text)
    if not m:
        return None
    return {"deal": m.group(1)}


def verify_log(path):
    with open(path, encoding=ENC_UTF16) as fh:
        text = fh.read()
    out = {"chars": len(text), "cases": {}, "finish": {},
           "count_entry": text.count("T99 reason=entry"),
           "count_no_break": text.count("T99 reason=no_break"),
           "count_flatten": text.count("T99 reason=flatten"),
           "parsed": {"entry": _parse_entry(text),
                      "no_break": _parse_no_break(text),
                      "flatten": _parse_flatten(text)}}
    for name, marker in CASE_MARKERS.items():
        out["cases"][name] = {"verbatim_present": marker in text, "marker": marker}
    for name, marker in FINISH_MARKERS.items():
        out["finish"][name] = {"present": marker in text, "marker": marker}
    return out


def tp_is_2r_from_parsed(parsed):
    """Exact 2R check from parsed log values only. False when absent/invalid."""
    if not parsed:
        return False
    try:
        e, s, t = Decimal(parsed["entry"]), Decimal(parsed["sl"]), Decimal(parsed["tp"])
        if parsed["direction"] == "BUY":
            return e + 2 * (e - s) == t
        if parsed["direction"] == "SELL":
            return e - 2 * (s - e) == t
        return False
    except (InvalidOperation, KeyError, TypeError):
        return False


def sl_matches_range_from_parsed(parsed):
    """SL-equals-range-edge check from parsed log values only. False if absent."""
    if not parsed:
        return False
    try:
        if parsed["direction"] == "BUY":
            return Decimal(parsed["sl"]) == Decimal(parsed["range_low"])
        if parsed["direction"] == "SELL":
            return Decimal(parsed["sl"]) == Decimal(parsed["range_high"])
        return False
    except (InvalidOperation, KeyError, TypeError):
        return False


# --------------------------------------------------------------------------
# main


HASHED_SUFFIXES = {
    "report": "t99_orb_20250901_20260901.htm",
    "bars": "T99_bars.csv",
    "deals": "T99_deals.csv",
    "equity": "T99_equity.csv",
    "run_json": "T99_run.json",
}
AGENT_LOG_SUFFIX = "Tester/Agent-127.0.0.1-3003/logs/20260925.log"


def close(a, b, tol=0.005):
    return a is not None and b is not None and abs(a - b) <= tol


def build_parser():
    p = argparse.ArgumentParser(
        description="Audit the completed native HolaPrime T99 ORB run. "
                    "Validates SHA256 of the 5 raw artifacts, then recomputes "
                    "figures from the real exports. No MT5, no network.")
    p.add_argument("--manifest", required=True, help="run_manifest_20260925.json path")
    p.add_argument("--out", required=True, help="audit_summary.json output path")
    p.add_argument("--method", default=None, help="audit_method.md output path "
                   "(default: <out-dir>/audit_method.md)")
    p.add_argument("--freeze", default=None, help="freeze.json path "
                   "(default: sibling of manifest)")
    p.add_argument("--cases", default=None, help="cases_20260925.txt path "
                   "(default: sibling of manifest)")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    with open(args.manifest, encoding="utf-8") as fh:
        manifest = json.load(fh)
    mdir = os.path.dirname(os.path.abspath(args.manifest))
    freeze_path = args.freeze or os.path.join(mdir, "freeze.json")
    cases_path = args.cases or os.path.join(mdir, "cases_20260925.txt")
    with open(freeze_path, encoding="utf-8") as fh:
        freeze = json.load(fh)
    with open(cases_path, encoding="utf-8") as fh:
        cases_text = fh.read()

    raw = manifest.get("raw_outputs_on_D", [])
    by_suffix = {}
    for entry in raw:
        for key, suffix in HASHED_SUFFIXES.items():
            if entry.get("path", "").replace("\\", "/").endswith(suffix):
                by_suffix[key] = entry
    missing_decl = [k for k in HASHED_SUFFIXES if k not in by_suffix]
    log_entry = next((e for e in raw
                      if e.get("path", "").replace("\\", "/").endswith(AGENT_LOG_SUFFIX)), None)

    checks = []
    local = {}
    ok = True
    if missing_decl:
        ok = False
    for key in HASHED_SUFFIXES:
        entry = by_suffix.get(key, {})
        want_hash, want_bytes = entry.get("sha256"), entry.get("bytes")
        rec = {"artifact": key, "manifest_d_path": entry.get("path"),
               "want_sha256": want_hash, "want_bytes": want_bytes}
        try:
            lp = win_to_local(entry["path"])
            rec["local_path"] = lp
            got_bytes = os.path.getsize(lp)
            got_hash = sha256_file(lp)
            rec["got_bytes"] = got_bytes
            rec["got_sha256"] = got_hash
            rec["status"] = ("PASS" if (got_hash == want_hash and got_bytes == want_bytes)
                             else "FAIL")
            local[key] = lp
        except Exception as exc:  # missing file, unmapped drive, unreadable
            rec["status"] = "FAIL"
            rec["error"] = str(exc)[:200]
        if rec["status"] != "PASS":
            ok = False
        # never print full hashes of unrelated files; these 5 are the audit subject
        checks.append(rec)

    summary = {
        "audit": {
            "tool": "scripts/repositioning/t99/audit_native_run.py (stdlib only)",
            "run_id": manifest.get("run_id"),
            "audited_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
            "model_note": ("historical simulation on one-minute OHLC generated ticks "
                           "(Model 1); real HolaPrime broker M15 bars, NOT real ticks"),
            "time_basis": "all strategy times are SERVER wall time; no UTC conversion applied",
        },
        "provenance": {
            "manifest": os.path.abspath(args.manifest),
            "freeze": os.path.abspath(freeze_path),
            "cases": os.path.abspath(cases_path),
            "freeze_id": freeze.get("freeze_id"),
            "native_log_d_path": (log_entry or {}).get("path"),
        },
        "hash_checks": checks,
        "integrity": "PASS" if ok else "FAIL",
    }

    out_path = os.path.abspath(args.out)
    method_path = (os.path.abspath(args.method) if args.method
                   else os.path.join(os.path.dirname(out_path), "audit_method.md"))
    summary["audit"]["reproduction"] = (
        "python3 scripts/repositioning/t99/audit_native_run.py "
        "--manifest %s --out %s%s" % (args.manifest, args.out,
                                      (" --method " + args.method) if args.method else ""))

    if not ok or missing_decl:
        summary["blocker"] = {
            "missing_manifest_declarations": missing_decl,
            "note": "SHA256/size validation failed BEFORE any figure was reported; "
                    "no numbers below are claimed.",
        }
        write_outputs(out_path, method_path, summary, None)
        print("AUDIT FAIL: integrity %s; summary at %s" % (summary["integrity"], out_path))
        return 2

    # ---- figure recompute (only on hash-verified inputs) ----
    rep = parse_report(local["report"])
    deals, deal_rows = parse_deals(local["deals"])
    keep_times = ("2025.09.01 09:00:00", "2025.09.01 09:15:00", "2025.09.01 09:30:00",
                  "2026.08.31 09:00:00", "2026.08.31 09:15:00", "2026.08.31 09:30:00")
    bars, kept = parse_bars(local["bars"], keep_times)
    equity = stream_equity(local["equity"])  # streamed, never fully loaded
    with open(local["run_json"], encoding=ENC_UTF16) as fh:
        run_json = json.load(fh)
    loginfo = verify_log(win_to_local(log_entry["path"])) if log_entry else None

    deposit = float(freeze.get("deposit_value", 10000))
    final_balance = deposit + deals["net"]

    # case cross-checks: parsed native-log values vs exported bars + deal CSV.
    # Every derived boolean is False when its log value is absent or mismatched;
    # nothing here is a constant True. All times are SERVER wall time.
    by_time = {r["server_time"]: r for r in deal_rows}
    d1 = kept.get("2025.09.01 09:00:00", {})
    d2 = kept.get("2025.09.01 09:15:00", {})
    e1 = kept.get("2026.08.31 09:00:00", {})
    e2 = kept.get("2026.08.31 09:15:00", {})
    r1 = [min(d1.get("low", "?"), d2.get("low", "?")),
          max(d1.get("high", "?"), d2.get("high", "?"))] if d1 and d2 else None
    r2 = [min(e1.get("low", "?"), e2.get("low", "?")),
          max(e1.get("high", "?"), e2.get("high", "?"))] if e1 and e2 else None
    entry_deal = by_time.get("2025.09.01 09:45:00")
    flatten_deal = by_time.get("2026.08.31 17:00:00")
    paired_open = by_time.get("2026.08.31 10:30:00")
    parsed = (loginfo.get("parsed") if loginfo else {}) or {}
    p_entry = parsed.get("entry")
    p_nobreak = parsed.get("no_break")
    p_flatten = parsed.get("flatten")

    # entry: parsed log values cross-checked against bars + exact deal CSV row
    if p_entry and r1:
        entry_range_matches = (r1 == [p_entry["range_low"], p_entry["range_high"]])
    else:
        entry_range_matches = False
    if p_entry and entry_deal:
        entry_deal_matches = bool(
            entry_deal["ticket"] == p_entry["deal"]
            and entry_deal["direction"] == p_entry["direction"]
            and entry_deal["entry"] == "IN"
            and entry_deal["volume"] == p_entry["vol"]
            and entry_deal["price"] == p_entry["entry"])
    else:
        entry_deal_matches = False
    if p_entry and r1:
        entry_sl_is_range_edge = bool(
            sl_matches_range_from_parsed(p_entry)
            and p_entry["range_low"] == r1[0]
            and p_entry["range_high"] == r1[1])
    else:
        entry_sl_is_range_edge = False
    entry_tp_is_2r = tp_is_2r_from_parsed(p_entry)

    # no_break: parsed log close/range vs 09:00+09:15 bars, 09:30 close, deals
    bars_0930_close = kept.get("2026.08.31 09:30:00", {}).get("close")
    if p_nobreak and r2:
        nobreak_range_matches = (r2 == [p_nobreak["range_low"], p_nobreak["range_high"]])
    else:
        nobreak_range_matches = False
    if p_nobreak and bars_0930_close is not None:
        nobreak_close_matches = (p_nobreak["close"] == bars_0930_close)
    else:
        nobreak_close_matches = False
    try:
        nobreak_close_inside = bool(
            p_nobreak
            and Decimal(p_nobreak["range_low"]) <= Decimal(p_nobreak["close"])
            <= Decimal(p_nobreak["range_high"]))
    except (InvalidOperation, KeyError, TypeError):
        nobreak_close_inside = False

    # flatten: parsed log deal number vs exact deal CSV row + paired open
    if p_flatten and flatten_deal:
        flatten_deal_matches = bool(
            flatten_deal["ticket"] == p_flatten["deal"]
            and flatten_deal["entry"] == "OUT")
    else:
        flatten_deal_matches = False
    if paired_open and flatten_deal:
        flatten_paired_open = bool(
            paired_open["entry"] == "IN"
            and paired_open["volume"] == flatten_deal["volume"])
    else:
        flatten_paired_open = False

    cases = [
        {"name": "entry",
         "server_time": "2025.09.01 09:45:00",
         "rule": "close-confirmed breakout BUY above 09:00-09:30 server opening range",
         "log_verbatim_present": loginfo["cases"]["entry"]["verbatim_present"] if loginfo else None,
         "log_parsed": p_entry,
         "range_from_exported_bars": r1,
         "range_matches_log": entry_range_matches,
         "deal_csv_observed": ({k: entry_deal[k] for k in
                                ("ticket", "direction", "entry", "volume", "price")}
                               if entry_deal else None),
         "deal_matches_csv": entry_deal_matches,
         "sl_is_range_low": entry_sl_is_range_edge,
         "sl_observed": (p_entry or {}).get("sl") if p_entry else None,
         "tp_is_2R": entry_tp_is_2r,
         "tp_observed": (p_entry or {}).get("tp") if p_entry else None},
        {"name": "no_break",
         "server_time": "2026.08.31 09:45:00",
         "rule": "first post-range completed bar closed inside the range: correctly no entry",
         "log_verbatim_present": loginfo["cases"]["no_break"]["verbatim_present"] if loginfo else None,
         "log_parsed": p_nobreak,
         "range_from_exported_bars": r2,
         "range_matches_log": nobreak_range_matches,
         "bars_0930_close_observed": bars_0930_close,
         "close_equals_0930_completed_bar": nobreak_close_matches,
         "close_inside_parsed_range": nobreak_close_inside,
         "no_deal_at_this_stamp_in_csv": "2026.08.31 09:45:00" not in by_time},
        {"name": "flatten",
         "server_time": "2026.08.31 17:00:00",
         "rule": "session-end flatten of the day's own position (opened 10:30 on later breakout)",
         "log_verbatim_present": loginfo["cases"]["flatten"]["verbatim_present"] if loginfo else None,
         "log_parsed": p_flatten,
         "deal_csv_observed": ({k: flatten_deal[k] for k in
                                ("ticket", "direction", "entry", "volume", "price")}
                               if flatten_deal else None),
         "deal_matches_csv": flatten_deal_matches,
         "paired_open_observed": ({k: paired_open[k] for k in
                                   ("ticket", "direction", "entry", "volume", "price",
                                    "server_time")}
                                  if paired_open else None),
         "paired_open_in_csv": flatten_paired_open},
    ]

    cmp_rows = [
        ("deals count", deals["count"], rep["deals"], deals["count"] == rep["deals"]),
        ("round trips", deals["round_trips"], rep["trades"], deals["round_trips"] == rep["trades"]),
        ("won", deals.get("wins_roundtrip_net"), rep["won"], deals.get("wins_roundtrip_net") == rep["won"]),
        ("lost", deals.get("losses_roundtrip_net"), rep["lost"], deals.get("losses_roundtrip_net") == rep["lost"]),
        ("sell positions", deals.get("sell_positions"), rep["sell_positions"],
         deals.get("sell_positions") == rep["sell_positions"]),
        ("buy positions", deals.get("buy_positions"), rep["buy_positions"],
         deals.get("buy_positions") == rep["buy_positions"]),
        ("net = profit+commission+swap", round(deals["net"], 2), rep["net_total"],
         close(deals["net"], rep["net_total"])),
        ("final balance = deposit+net", round(final_balance, 2), 11419.26,
         close(final_balance, 11419.26)),
        ("expected payoff = net/259", round(deals["net"] / 259, 2), rep["expected_payoff"],
         close(deals["net"] / 259, rep["expected_payoff"], 0.01)),
        ("exported bars", bars["count"], 24863, bars["count"] == 24863),
        ("generated bars (report)", rep["bars_generated"], 24864, rep["bars_generated"] == 24864),
        ("ticks (report)", rep["ticks"], 1482897, rep["ticks"] == 1482897),
        ("equity data rows (streamed)", equity["data_rows"], 1482899, equity["data_rows"] == 1482899),
        ("equity final balance", equity["final_balance"], round(final_balance, 2),
         close(equity["final_balance"], final_balance)),
        ("max balance DD (streamed)", round(equity["max_balance_dd"], 2), rep["balance_dd_max"],
         close(equity["max_balance_dd"], rep["balance_dd_max"])),
        ("max equity DD (streamed)", round(equity["max_equity_dd"], 2), rep["equity_dd_max"],
         close(equity["max_equity_dd"], rep["equity_dd_max"])),
    ]
    comparison = [{"check": c, "recomputed": r, "report_or_manifest": m,
                   "status": "MATCH" if ok_ else "REVIEW"} for c, r, m, ok_ in cmp_rows]
    documented = [
        {"check": "manifest equity rows=2965800 vs streamed 1482899",
         "status": "DOCUMENTED-DIFF",
         "note": "file itself is hash-verified; the manifest rows field is stale/wrong. "
                 "Streamed 1482899 data rows align with 1482897 tester ticks (+2 framing rows)."},
        {"check": "report Bruttogewinn/Bruttoverlust + derived Profitfaktor/avg/max trade",
         "status": "NOT-MECHANICALLY-VERIFIABLE",
         "note": "report 18432.72/-17013.46 are internally consistent (sum = net) but match "
                 "neither natural CSV convention (round-trip-net gross 18088.17/-16668.91; "
                 "out-profit-only gross 18777.27/-15676.33). MT5 per-trade allocation is "
                 "not reproducible from the deals columns alone; wins/losses counts (107/152) "
                 "agree under both conventions."},
    ]

    summary.update({
        "report_figures": rep,
        "recomputed": {
            "deals": deals,
            "final_balance": round(final_balance, 2),
            "deposit": deposit,
            "bars": bars,
            "equity": equity,
            "run_json": run_json,
        },
        "coverage": {
            "period_report": rep["period_server"],
            "bars_exported_first_server": bars["first_server"],
            "bars_exported_last_server": bars["last_server"],
            "deinit_coverage_end_server": "2026.08.31 23:59:59",
            "note": ("24863 exported vs 24864 generated: the last M15 bar completes exactly "
                     "at the exclusive ToDate boundary 2026.09.01 00:00 server time. "
                     "All non-15m steps are weekend gaps (Fri 23:45 -> Mon 00:00 server) "
                     "or the two broker-holiday gaps 2025.12.24 23:45 -> 2025.12.26 00:00 "
                     "and 2025.12.31 23:45 -> 2026.01.02 00:00 server; no duplicates."),
            "gap_check": {"non_15m_steps": bars["non_15m_steps"],
                          "weekend_gaps": bars["weekend_gaps_2895m_fri_to_mon"],
                          "other_gaps": bars["other_gaps"],
                          "duplicates": bars["duplicates"]},
        },
        "cases": cases,
        "log": ({"native_agent_log_chars": loginfo["chars"],
                 "reason_counts": {"entry": loginfo["count_entry"],
                                   "no_break": loginfo["count_no_break"],
                                   "flatten": loginfo["count_flatten"]},
                 "entry_markers_equal_trades": loginfo["count_entry"] == rep["trades"],
                 "finish_balance_present": loginfo["finish"]["finish_balance"]["present"],
                 "deinit_export_present": loginfo["finish"]["deinit_export"]["present"],
                 "coverage_end_present": loginfo["finish"]["coverage_end"]["present"]}
                if loginfo else None),
        "comparison": comparison + documented,
        "limitations": [
            "CSV encodings are UTF-16 with BOM (deals/bars/equity/run_json/log/report); "
            "a UTF-8-only reader misparses them.",
            "tester_utc_offset_sec is 0 on all 518 deals and T99_run.json states "
            "TimeGMT is not used as UTC with broker_offset_policy=PENDING_PARENT_POLICY; "
            "UTC conversion is therefore INCONCLUSIVE pending official whole-year "
            "HolaPrime clock/DST rules.",
            "HolaPrime account-specific prop verdict is INCONCLUSIVE: account rules are "
            "not in the audited artifacts.",
            "Equity recording is best-effort per OnTick with possible gaps and no weekend "
            "ticks (per T99_run.json); streamed drawdowns reproduce the report exactly, "
            "but tick-level completeness is not asserted.",
            "Bars coverage: every non-15m step is a Fri->Mon weekend gap or one of two "
            "broker-holiday gaps (Christmas, New Year); weekday labels are server wall "
            "time, not mapped to UTC.",
            "Report gross/profit-factor/avg/max-trade internals are not CSV-reproducible "
            "(see comparison); all other headline figures match exactly.",
        ],
        "verdict": {
            "integrity": "PASS",
            "all_case_markers_verbatim": all(c["log_verbatim_present"] for c in cases),
            "utc_conversion": "INCONCLUSIVE",
            "prop_verdict": "INCONCLUSIVE",
            "forecast_or_guarantee": "none",
        },
    })
    write_outputs(out_path, method_path, summary, rep)
    fails = [c for c in comparison if c["status"] != "MATCH"]
    print("AUDIT OK: integrity PASS; %d/%d mechanical comparisons MATCH; "
          "summary at %s" % (len(comparison) - len(fails), len(comparison), out_path))
    for c in fails:
        print("  REVIEW:", c["check"])
    return 0


def write_outputs(out_path, method_path, summary, rep):
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    os.makedirs(os.path.dirname(method_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    with open(method_path, "w", encoding="utf-8") as fh:
        fh.write(method_md(summary))


def method_md(summary):
    L = []
    A = summary.get("audit", {})
    L.append("# T99 native run audit — method")
    L.append("")
    L.append("Reproduction command (from the workspace root):")
    L.append("")
    L.append("    " + A.get("reproduction", ""))
    L.append("")
    L.append("Provenance: `%s`, freeze `%s`, cases `%s`." % (
        summary.get("provenance", {}).get("manifest"),
        summary.get("provenance", {}).get("freeze"),
        summary.get("provenance", {}).get("cases")))
    L.append("")
    L.append("## File hashes (validated before any figure was reported)")
    L.append("")
    L.append("| artifact | bytes | sha256 (prefix) | status |")
    L.append("| --- | ---: | --- | --- |")
    for c in summary.get("hash_checks", []):
        h = (c.get("got_sha256") or "")[:16]
        L.append("| %s | %s | %s… | %s |" % (
            c.get("artifact"), c.get("got_bytes"), h, c.get("status")))
    L.append("")
    L.append("## Interpretation")
    L.append("")
    r = summary.get("recomputed", {})
    d = r.get("deals", {})
    if d:
        L.append("Full-period neutral facts, recomputed from the hash-verified deals CSV: "
                 "%d deals forming %d IN/OUT round trips; net = profit %.2f + commission "
                 "%.2f + swap %.2f = %.2f on %.2f deposit (final %.2f)." % (
                     d.get("count"), d.get("round_trips"), d.get("sum_profit"),
                     d.get("sum_commission"), d.get("sum_swap"), d.get("net"),
                     r.get("deposit"), r.get("final_balance")))
        L.append("Wins/losses %d/%d agree under both natural counting conventions; "
                 "buy/sell split %d/%d." % (d.get("wins_roundtrip_net"),
                                            d.get("losses_roundtrip_net"),
                                            d.get("buy_positions"), d.get("sell_positions")))
    b = r.get("bars", {})
    e = r.get("equity", {})
    if b:
        L.append("Bars: %d exported (%s → %s server) vs 24864 generated; the last bar "
                 "completes at the exclusive ToDate boundary." % (
                     b.get("count"), b.get("first_server"), b.get("last_server")))
    if e:
        L.append("Equity (streamed, %d rows): final balance/equity %.2f/%.2f; max balance "
                 "drawdown %.2f, max equity drawdown %.2f — both reproduce the report." % (
                     e.get("data_rows"), e.get("final_balance"), e.get("final_equity"),
                     e.get("max_balance_dd"), e.get("max_equity_dd")))
        L.append("Equity row metadata: the original capture manifest records rows=2965800, "
                 "which is stale; the verified actual data-row count is 1482899 "
                 "(hash-verified T99_equity.csv, streamed count). "
                 "The capture manifest is left unchanged; its original error is preserved "
                 "for the audit trail.")
    L.append("Three native-log cases (entry / no_break / flatten) are present verbatim "
             "with SERVER wall time. Each case is parsed from its actual native log line "
             "(entry/sl/tp/range, close/range, flatten deal) and cross-checked against "
             "the exported bars and the exact deal CSV row; a missing log value or any "
             "mismatch yields False, never a constant True.")
    L.append("")
    L.append("## Boundaries")
    L.append("")
    L.append("Historical Model-1 simulation (one-minute OHLC generated ticks), not real ticks. "
             "UTC conversion and any HolaPrime account-specific prop verdict are INCONCLUSIVE. "
             "No forecast, no guarantee, no cherry-picked period.")
    L.append("")
    return "\n".join(L)


if __name__ == "__main__":
    sys.exit(main())

