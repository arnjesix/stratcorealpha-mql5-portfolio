# MT5 Position and Order Ownership Audit

`SCA_MT5OwnershipAudit.mq5` is a read-only MetaTrader 5 script for one narrow
question: which currently open positions and active pending orders match the
magic number an EA is supposed to manage?

It is useful before repairing a trade manager, trailing-stop module, partial
close routine or restart-recovery path. Those components should not modify
manual trades or positions belonging to another EA.

## Use

1. Save the source in `MQL5/Scripts/StratCoreAlpha/` and compile it.
2. Attach it to the relevant chart.
3. Enter the EA's expected magic number.
4. Keep `Current symbol` for the narrowest audit, or deliberately select
   `All symbols`.
5. Review every `FOREIGN` row before enabling automated management logic.

The report is printed to the Experts log. When file output is enabled, it is
also saved under the terminal's shared `Common/Files` directory.

## Interpretation

- `OWNED` means the observed magic number exactly equals the configured value.
- `FOREIGN` means it does not.
- Magic `0` often includes manually opened trades, so an expected value of
  zero is inherently ambiguous and needs further review.
- Matching magic numbers do not prove which source code created a trade.

The script deliberately omits account identity, login, balance, equity,
ticket IDs, volume, price and profit. Symbol and magic-number rows may still
be sensitive; review them before sharing a report.

## Safety boundary

The source contains no order-send, modify or close path. It does not claim
that a clean audit guarantees correct EA behaviour or trading results. It is
diagnostic evidence for freezing an ownership rule before implementation.

For a bounded repair or ownership-state review, use the
[StratCoreAlpha MQL5 bug-fix service](https://stratcorealpha.com/services/mql5-bug-fix).
