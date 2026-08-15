# Before You Pay for an MT5 Live-vs-Backtest Fix

Two MT5 result curves can look similar while the stored executions behind them
are different. A developer cannot diagnose that difference responsibly from a
balance chart, a trade count or the sentence "live is worse than backtest."

The first useful deliverable is an execution reconciliation: a frozen,
event-by-event comparison that shows where two runs agree and where they stop
agreeing. Only then is it possible to decide whether the next paid scope should
be a configuration correction, evidence repair, EA code fix or a new test.

## Freeze the comparison before sharing files

Record these facts for both runs:

1. EA source/binary version and SET identity or hash.
2. MT5 build, symbol including suffix, timeframe and account mode.
3. Exact date window and server timezone.
4. Spread, commission, swap, slippage and execution assumptions.
5. Allowed differences for time, price, volume and cash fields.
6. Whether deal, order and position tickets should match or remain run-specific.

Do not silently change inputs after seeing a mismatch. If a new setting is
needed, it belongs in a new comparison pair with its own evidence identity.

## Five differences that lead to different investigations

The public synthetic sample contains five intentional divergences:

| Difference | What it tells you | What it does not prove |
|---|---|---|
| One event is 1,000 ms later | Timing differs under a zero-time tolerance | The timing difference is a code defect |
| Entry price differs by 0.00004 | The stored price differs under a zero-price tolerance | Either price was historically fillable |
| Exit reason changes from stop loss to client | MT5 recorded a different exit owner/reason | Why that owner changed |
| Realized profit differs by 0.12 | Costs or execution outcome differ | The strategy is or is not profitable |
| One candidate event is missing | The ordinal deal sequences no longer match | An unfilled signal existed |

Those are evidence findings, not automatic diagnoses. A one-second shift can
come from decision-bar timing, delayed data, order processing, restart state or
an intentionally different rule. A missing deal row can reflect a skipped
signal, rejection, filtered history, different ownership or a shifted event
sequence. The evidence contract prevents those causes from being guessed away.

## What to send for a useful quote

Start with a redacted scope, not credentials:

- the two version identities;
- the frozen environment facts above;
- one event that should match;
- one event that appears to diverge;
- your proposed tolerances;
- confirmation that you own or are authorized to use the software and evidence.

Keep account numbers, account names, broker logins, passwords, private strategy
rules and full history exports off public GitHub. Private evidence should move
only through the approved funded project route after scope and handling terms
are agreed.

## A bounded first milestone

A useful first milestone should state the maximum rows, number of run pairs,
symbol/timeframe, tolerance contract and number of prioritized divergences. It
should deliver:

1. validated evidence inputs;
2. a machine-readable field-difference table;
3. evidence hashes and exact comparison settings;
4. a short findings report;
5. a bounded retest matrix.

EA repair is separate. If the reconciliation isolates a reproducible source
defect, the repair can be quoted against one exact positive case, one negative
case and the relevant restart/failure path. This keeps a small evidence task
from turning into unlimited strategy research.

## Inspect the public sample

- [Three-page synthetic proof PDF](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/download/v1.4.0/StratCoreAlpha_MT5_Execution_Reconciliation_Proof.pdf)
- [Complete MT5 Deal Evidence Toolkit release](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.4.0)
- [Public safe-scope form](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/issues/new?template=mt5-execution-reconciliation.yml)

The toolkit records stored MT5 deal history. It has no order path and omits
account/broker identity. It cannot reconstruct an unfilled signal, prove
historical fillability or broker parity, validate a strategy, or support any
profit, win-rate, drawdown or future-performance claim.

This guide concerns software verification and evidence design. It is not
investment advice.

