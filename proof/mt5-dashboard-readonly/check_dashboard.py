"""Offline acceptance sketch for a read-only MT5 dashboard, Python 3.

Synthetic inputs only. This does not connect to a terminal, broker or account.
No trading functions, credentials or third-party source are included.
"""
from decimal import Decimal
import json
from pathlib import Path


def view(account, positions, deals, *, now, received_at, connected):
    """Preserve a snapshot while explicitly marking loss of freshness."""
    return {
        "login": account["login"],
        "currency": account["currency"],
        "balance": account["balance"],
        "equity": account["equity"],
        "margin": account["margin"],
        "free_margin": account["margin_free"],
        "positions": positions,
        "closed_net": str(sum(
            (sum((Decimal(str(d.get(k, 0))) for k in
                  ("profit", "commission", "swap", "fee")), Decimal(0))
             for d in deals), Decimal(0))),
        "state": "CURRENT" if connected and now - received_at <= 30 else "STALE",
        "age_seconds": now - received_at,
    }


def run():
    account = dict(login=10001, currency="USD", balance="1000.00",
                   equity="995.00", margin="100.00", margin_free="895.00")
    positions = [dict(ticket=101, symbol="XAUUSD", side="BUY", volume="0.01",
                      price_open="2600.00", price_current="2595.00", profit="-5.00")]
    deals = [dict(ticket=201, profit="10.00", commission="-2.00", swap="-1.00", fee="-0.50")]
    current = view(account, positions, deals, now=105, received_at=100, connected=True)
    assert current["balance"] == "1000.00" and current["free_margin"] == "895.00"
    assert len(current["positions"]) == 1 and current["positions"][0]["ticket"] == 101
    assert current["state"] == "CURRENT"
    assert current["closed_net"] == "6.50"
    stale = view(account, positions, deals, now=140, received_at=100, connected=False)
    assert stale["state"] == "STALE" and stale["balance"] == current["balance"]
    result = dict(kind="synthetic offline model", snapshot=current, disconnected=stale,
                  cases=["PASS account fields and open position", "PASS net includes commission, swap and fee",
                         "PASS disconnected data remains visible and marked STALE"],
                  limits="No MT5 runtime, live feed, multi-account synchronization or broker test.")
    Path(__file__).with_name("result.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return result


if __name__ == "__main__":
    run()
