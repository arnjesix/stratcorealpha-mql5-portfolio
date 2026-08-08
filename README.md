# StratCoreAlpha — MQL4/MQL5 Development Portfolio

Custom Expert Advisors, indicators, dashboards and trade-management tools for
MetaTrader 4 and MetaTrader 5.

[Website](https://stratcorealpha.com/) ·
[Public MQL5 profile](https://www.mql5.com/en/users/stratcorealpha) ·
[Request a scope check](mailto:contact@stratcorealpha.com)

## Services

| Service | Typical starting scope | Details |
| --- | ---: | --- |
| MQL5 Expert Advisor development from explicit rules | from EUR 249 | [Scope and boundaries](https://stratcorealpha.com/services/mql5-developer) |
| One bounded MQL4/MQL5 bug fix or modification | from EUR 89 | [Scope and boundaries](https://stratcorealpha.com/services/mql5-bug-fix) |
| Authorized Pine Script to MT5 conversion | from EUR 179 | [Scope and boundaries](https://stratcorealpha.com/services/pine-script-to-mt5) |

Every fixed scope starts by freezing entry, exit, risk, timing and acceptance
rules. Deliverables can include editable MQ4/MQ5 source, the compiled build,
documented inputs, setup notes and reproducible test cases.

## Public MQL5 engineering proof

The following projects are published on the official MQL5 CodeBase. They are
implementation examples, not trading-performance claims.

### PropGuard MT5 drawdown risk dashboard

A chart-based monitor that visualizes where configured daily-loss or overall-
drawdown limits would be reached using account equity and open exposure.

- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/68087)
- [Engineering case study](https://stratcorealpha.com/work/propguard-risk-dashboard)

### Multi-symbol wick rejection scanner

An MT5 dashboard that scans multiple symbols and timeframes for wick-based
rejection candles, with strength, signal age, markers and alerts.

- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/68101)
- [Engineering case study](https://stratcorealpha.com/work/wick-rejection-scanner)

### Modern dark-mode one-click trade panel

An on-chart MT5 execution panel with one-click buy/sell controls, automatic pip
calculation and persistent per-symbol settings.

- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/68038)
- [Engineering case study](https://stratcorealpha.com/work/one-click-trade-panel)

Additional public CodeBase work is available on the
[StratCoreAlpha MQL5 publications page](https://www.mql5.com/en/users/stratcorealpha/publications).

## Free client preparation guides

- [MT5 Expert Advisor specification checklist](https://stratcorealpha.com/guides/mt5-ea-specification-checklist)
- [MQL5 Expert Advisor bug report checklist](https://stratcorealpha.com/guides/mql5-bug-report-checklist)
- [Why an MT5 EA works on one broker but not another](https://stratcorealpha.com/guides/why-mt5-ea-works-on-one-broker)
- [Pine Script to MT5 conversion checklist](https://stratcorealpha.com/guides/pine-script-to-mt5-conversion-checklist)

These guides show the information needed for a useful feasibility check and a
bounded quote. They can be used before contacting any developer.

## Open-source diagnostic utility

### MT5 Broker Environment Report

A privacy-conscious MQL5 script that records the symbol, volume, order,
filling, stop/freeze and account-mode properties needed to reproduce many EA
execution problems. It deliberately excludes account identity, balances,
positions, history and credentials.

- [Source code](src/SCA_BrokerEnvironmentReport.mq5)
- [Version 1.0.0 release and direct MQ5 download](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.0.0)
- [Installation and safe-sharing guide](docs/BROKER_ENVIRONMENT_REPORT.md)
- [Tool overview and download](https://stratcorealpha.com/tools/mt5-broker-environment-report)
- [MQL5 bug-fix service](https://stratcorealpha.com/services/mql5-bug-fix)

## Good first message

For a fast scope check, include:

1. MetaTrader 4, MetaTrader 5 or TradingView/Pine Script.
2. Editable source code you own, or explicit written trading rules.
3. Symbol, timeframe, broker and account mode.
4. Current behaviour and expected behaviour.
5. At least one should-trade and one should-not-trade example.
6. Required delivery date and realistic budget.

Email: [contact@stratcorealpha.com](mailto:contact@stratcorealpha.com)

For a non-confidential first check, you can also open the public
[scope-request template](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/issues/new?template=scope-request.yml).
Do not paste proprietary source code, credentials, account numbers or private
strategy details into a public GitHub issue.

## Scope boundaries

- No guaranteed profit, win rate, drawdown or prop-firm result.
- No protected-code extraction or EX4/EX5 decompilation.
- No claim that TradingView and broker data will be identical.
- Strategy invention, optimization and additional features are separate from a
  bounded implementation or repair.

StratCoreAlpha is operated by Arnold Holm in Germany.

The source code in this repository is licensed under the [MIT License](LICENSE).
