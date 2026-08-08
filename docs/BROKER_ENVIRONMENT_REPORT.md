# MT5 Broker Environment Report

`SCA_BrokerEnvironmentReport.mq5` creates a text report containing the broker,
account-mode and symbol properties that often explain why an Expert Advisor
compiles but does not trade as expected.

It is designed for safe first-line diagnosis. The script intentionally does
not collect:

- account login or owner name;
- broker server name;
- balance, equity or profit;
- open positions, pending orders or history;
- files, API keys, passwords or credentials.

Always read the generated text before sharing it.

## Installation

1. Download [`SCA_BrokerEnvironmentReport.mq5`](../src/SCA_BrokerEnvironmentReport.mq5).
2. In MetaTrader 5, choose **File → Open Data Folder**.
3. Copy the file to `MQL5/Scripts/StratCoreAlpha/`.
4. Open MetaEditor and compile the script.
5. In MT5, attach it from **Navigator → Scripts** to the affected symbol.

## Output

The report is printed to the Experts tab. By default it is also saved to the
shared terminal folder:

`Terminal/Common/Files/SCA_BrokerEnvironment_<symbol>.txt`

The report includes:

- terminal and MQL5 build;
- account margin mode, leverage and deposit currency;
- symbol currencies, digits, point, tick size and contract size;
- trade, calculation, order, filling and expiration modes;
- stop and freeze levels;
- volume minimum, maximum, step and directional limit;
- tick values for general, profit and loss calculations.

## When requesting a fix

Send the reviewed report together with:

1. editable MQ4/MQ5 source and required includes;
2. exact current and expected behaviour;
3. shortest reproduction steps;
4. relevant Experts and Journal lines;
5. one acceptance test that proves the repair.

[MQL5 bug-fix scope and boundaries](https://stratcorealpha.com/services/mql5-bug-fix)

This utility is engineering support software. It does not assess strategy
profitability or guarantee broker, prop-firm or trading outcomes.
