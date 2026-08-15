# StratCoreAlpha — MQL4/MQL5 Development Portfolio

Custom Expert Advisors, indicators, dashboards and trade-management tools for
MetaTrader 4 and MetaTrader 5.

[Website](https://stratcorealpha.com/) ·
[Public MQL5 profile](https://www.mql5.com/en/users/stratcorealpha) ·
[Build a free scope brief](https://stratcorealpha.com/tools/trading-bot-scope-builder)

## Services

| Service | Typical starting scope | Details |
| --- | ---: | --- |
| MT5 EA specification audit before development | EUR 39 | [Check scope, ambiguities and acceptance criteria](https://stratcorealpha.com/services/mt5-ea-specification-audit) |
| Authorized MQL4/MQL5 source-code audit | EUR 39 | [Prioritized findings and repair estimate](https://stratcorealpha.com/services/mql-code-audit) |
| MT4/MT5 indicator alert upgrade | from EUR 39 | [Add bounded popup, push, email, sound or chart alerts](https://stratcorealpha.com/services/mt4-mt5-indicator-alerts) |
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
- [MT4 and MT5 indicator alert requirements checklist](https://stratcorealpha.com/guides/mt4-mt5-indicator-alert-requirements)
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
- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/75871)
- [Version 1.0.0 release and direct MQ5 download](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.0.0)
- [Installation and safe-sharing guide](docs/BROKER_ENVIRONMENT_REPORT.md)
- [Tool overview and download](https://stratcorealpha.com/tools/mt5-broker-environment-report)
- [MQL5 bug-fix service](https://stratcorealpha.com/services/mql5-bug-fix)

### MT5 Order Preflight

A read-only script that checks a hypothetical market, limit or stop order
against current symbol trade modes, volume constraints, tick size, pending
distance, protective stops and filling policies. It never sends a trade and
excludes private account data from its report.

- [Source code](src/SCA_MT5OrderPreflight.mq5)
- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/75874)
- [Version 1.1.0 release and direct MQ5 download](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.1.0)
- [Installation, checks and safe-sharing guide](docs/MT5_ORDER_PREFLIGHT.md)
- [Tool overview and download](https://stratcorealpha.com/tools/mt5-order-preflight)
- [MQL5 bug-fix service](https://stratcorealpha.com/services/mql5-bug-fix)

### MT5 Cash Risk Probe

A read-only sizing script that uses the terminal's account-currency profit
calculation, reserves explicit cash for fees/slippage and floors the result to
the broker's volume grid. It includes five deterministic normalization tests,
reports every input and boundary and never sends an order.

- [Source code](src/SCA_MT5CashRiskProbe.mq5)
- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/75981)
- [Version 1.2.0 release and direct MQ5 download](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.2.0)
- [Installation, boundary and limitation guide](docs/MT5_CASH_RISK_PROBE.md)
- [Engineering case study](https://stratcorealpha.com/work/mt5-cash-risk-probe)
- Relevant diagnostic scope: [MT5 EA specification audit](https://stratcorealpha.com/services/mt5-ea-specification-audit)

### MT5 EA Acceptance Harness

A non-trading script that executes eight synthetic entry-state fixtures for
completed-bar timing, duplicate suppression, cooldown, daily lock and new-day
reset. It provides an inspectable PASS/FAIL contract before those rules are
connected to broker or order-send behavior.

- [Source code](src/SCA_MT5AcceptanceHarness.mq5)
- [Official MQL5 CodeBase listing](https://www.mql5.com/en/code/76039)
- [Version 1.3.0 release and direct MQ5 download](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.3.0)
- [Fixture contract and safe-use guide](docs/MT5_EA_ACCEPTANCE_HARNESS.md)
- [Captured MT5 runtime report: 8/8 synthetic cases passed](docs/evidence/SCA_MT5AcceptanceHarness_runtime_2026-08-12.txt)
- [Engineering case study](https://stratcorealpha.com/work/mt5-ea-acceptance-harness)
- Relevant scope: [MT5 EA specification audit](https://stratcorealpha.com/services/mt5-ea-specification-audit)

### MT5 Deal Evidence Toolkit

A read-only MQL5 exporter plus deterministic PowerShell comparison and HTML
report tools for inspecting stored tester-versus-deployment deal differences.
The fixed 19-field contract omits account and broker identity and the source
contains no order path. A synthetic handoff demonstrates exact time, price,
reason, profit and missing-row differences without client data.

- [MQL5 exporter source](src/SCA_MT5DealEvidenceExporter.mq5)
- [Version 1.4.0 release and direct source/report downloads](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/tag/v1.4.0)
- [CSV comparator](tools/Compare-MT5DealEvidence.ps1)
- [Self-contained HTML report builder](tools/New-MT5DealEvidenceReport.ps1)
- [Installation, evidence contract and safe-use guide](docs/MT5_DEAL_EVIDENCE_TOOLKIT.md)
- [Synthetic five-difference report](docs/evidence/MT5_Execution_Reconciliation_Sample.html)
- Relevant diagnostic scope: [MQL code audit](https://stratcorealpha.com/services/mql-code-audit)

## Good first message

Use the browser-local
[trading-bot scope builder](https://stratcorealpha.com/tools/trading-bot-scope-builder)
to produce a copyable first brief without uploading what you type. For a fast
scope check, include:

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
