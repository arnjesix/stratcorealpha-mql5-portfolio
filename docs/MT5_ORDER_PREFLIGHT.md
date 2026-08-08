# MT5 Order Preflight

`SCA_MT5OrderPreflight.mq5` is a read-only MetaTrader 5 script for checking a
hypothetical order against the current symbol rules before debugging the same
request inside a larger Expert Advisor.

It does not send, modify or cancel trades.

## Checks

- current Bid and Ask availability;
- symbol trade mode and direction restrictions;
- support for market, limit or stop orders;
- minimum, maximum and step-aligned volume;
- tick-size normalization of a hypothetical pending price;
- pending-order distance against the current stops level;
- stop-loss and take-profit support and minimum distance;
- advertised FOK/IOC/BOC filling modes.

The report distinguishes `PASS`, `WARN` and `FAIL` findings and ends with a
summary. A passing report is useful diagnostic evidence, but it cannot
guarantee that the trade server will accept a later request or that a strategy
will perform.

## Installation

1. Download `src/SCA_MT5OrderPreflight.mq5`.
2. Open MetaTrader 5 and choose `File > Open Data Folder`.
3. Copy the source to `MQL5/Scripts/StratCoreAlpha/`.
4. Open it in MetaEditor and compile it.
5. Refresh `Navigator > Scripts`, then run it on the affected symbol.
6. Select a hypothetical order scenario, volume and distances.

By default the script prints the report in the Experts tab and saves
`SCA_OrderPreflight_<symbol>.txt` in the terminal-wide `Common/Files` folder.

## Safe sharing

The report intentionally excludes account login, owner name, broker server,
balance, equity, positions, orders, history, files, keys and credentials.
Review every text report before sharing it.

For a useful bug request, add the actual trade retcode and the relevant
Experts/Journal lines around the failed request. Keep all credentials and
private account data out of the report.

## Scope boundary

This utility checks a frozen hypothetical order against currently advertised
symbol rules. It is not an execution simulator, strategy optimizer, broker
rating or profitability tool.

For a bounded MQL4/MQL5 diagnosis, see the
[StratCoreAlpha bug-fix service](https://stratcorealpha.com/services/mql5-bug-fix).
