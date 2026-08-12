# MT5 EA Acceptance Harness

`SCA_MT5AcceptanceHarness.mq5` is a non-trading MetaTrader 5 script that makes
an entry-state acceptance contract executable before it is embedded in a full
Expert Advisor. It runs eight deterministic synthetic cases and reports the
expected and actual decision for each one.

The included contract covers:

- one valid completed-bar entry;
- duplicate suppression on the same signal bar;
- rejection of an intrabar signal;
- a three-bar cooldown boundary;
- a no-signal negative case;
- a daily-lock rejection; and
- explicit new-day state reset.

## Run it

1. Open `src/SCA_MT5AcceptanceHarness.mq5` in MetaEditor and compile it.
2. Drag the script onto any MT5 chart. No market connection is required.
3. Read the Experts output or the optional
   `Common\Files\SCA_MT5AcceptanceHarness.txt` report.
4. Treat any failed fixture as a software-contract failure before adding broker
   or order-send behavior.

The script does not read quotes, positions, history, identity, balances or
credentials. It never sends, modifies or closes an order. The synthetic PASS
result proves only the stated state-transition fixtures; it is not evidence of
broker execution, strategy quality, profitability or live-account behavior.

## Verification record

- MetaEditor 5 x64 compile on 2026-08-12: 0 errors and 0 warnings.
- Runtime fixture execution remains deliberately unclaimed until the compiled
  script is run in a terminal and all eight printed decisions are captured.
