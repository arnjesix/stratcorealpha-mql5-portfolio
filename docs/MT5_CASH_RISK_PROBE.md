# MT5 Cash Risk Probe

`SCA_MT5CashRiskProbe.mq5` is a read-only MetaTrader 5 script for inspecting
cash-risk sizing before order logic is implemented. It never sends, modifies
or closes an order.

The probe uses `OrderCalcProfit()` to estimate the stop-distance loss for one
lot in the account deposit currency. It subtracts an explicit cash reserve for
fees or slippage, divides the remaining budget by the one-lot loss and rounds
the result down to the broker's volume step. It then recalculates the loss at
the final volume and reports the complete boundary.

## Safe use

1. Open `SCA_MT5CashRiskProbe.mq5` in MetaEditor and compile it.
2. In MT5, choose a symbol and set a hypothetical entry, stop, side and maximum
   cash loss.
3. Drag the script onto a chart. Leaving entry at zero uses the current Ask for
   a buy or Bid for a sell.
4. Read the chart comment and Experts log. `order_sent=false` is always printed
   in a successful result.

The default cash value is denominated in the account deposit currency shown in
the output. It is not automatically a USD cap on a non-USD account. A real EA
must freeze the account-currency contract, fee/slippage policy, portfolio
exposure and directional `SYMBOL_VOLUME_LIMIT` handling before order sending.

## Deterministic boundaries

The optional startup self-test verifies five pure volume-normalization cases:

- ordinary step flooring (`0.137` to `0.13` on a `0.01` step);
- below-minimum rejection;
- maximum-volume capping;
- non-cent step flooring (`0.39` to `0.30` on a `0.10` step);
- a volume grid whose minimum is not an integer multiple of its step (`0.20`
  to `0.19` for minimum `0.10` and step `0.03`).

The broker-dependent result then blocks missing or wrong-side stops, invalid
cash/reserve values, unavailable ticks, invalid volume metadata, failed profit
calculation and a budget below minimum volume.

## Verification record

- MetaEditor compile: 0 errors and 0 warnings.
- Runtime smoke test on 2026-08-11: all five deterministic self-tests passed
  in two separate MT5 installations.
- The broker-dependent calculation then blocked because the test terminals had
  no valid broker authorization. This is the intended fail-closed result, not
  evidence of a successful connected-account calculation.

This utility is software-engineering evidence, not trading advice or a
performance claim. A passing calculation does not guarantee fill price,
commission, slippage, margin availability or broker acceptance.
