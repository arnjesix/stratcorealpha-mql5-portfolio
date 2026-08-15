# MT5 Deal Evidence Toolkit

The toolkit exports selected MetaTrader 5 deal-history facts, compares two
exports under explicit tolerances and generates a self-contained HTML
difference report. It is intended for execution debugging and acceptance work,
not strategy evaluation or account operation.

## Components

- [`src/SCA_MT5DealEvidenceExporter.mq5`](../src/SCA_MT5DealEvidenceExporter.mq5)
  is the read-only MT5 script.
- [`tools/Compare-MT5DealEvidence.ps1`](../tools/Compare-MT5DealEvidence.ps1)
  validates the CSV contract and reports field differences.
- [`tools/New-MT5DealEvidenceReport.ps1`](../tools/New-MT5DealEvidenceReport.ps1)
  produces one self-contained HTML handoff.
- [`tests/fixtures/mt5-deal-evidence/`](../tests/fixtures/mt5-deal-evidence/)
  contains synthetic match and drift examples.
- [Synthetic reconciliation report](evidence/MT5_Execution_Reconciliation_Sample.html)
  demonstrates five intentional differences without client or account data.
- [Toolkit ZIP](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/releases/download/v1.4.0/StratCoreAlpha_MT5_Deal_Evidence_Toolkit_v1.4.0.zip)
  contains exactly these public tools, guide, tests, fixtures and the MIT
  license; SHA-256
  `1C89645A8BB0C44C04633A87C24C4C9F8553FC4C2111814F4ED29D1C677DF2E9`.

## Safety and privacy boundary

The MQL5 source selects history and writes a CSV. It does not calculate a
signal, send or modify an order, open or close a position, connect to an
external service or change account state.

The CSV deliberately omits account login, account name, broker/server identity,
credentials, external deal IDs and free-text comments. It includes deal, order
and position identifiers because those can be necessary to trace execution
state. Review every generated file before sharing it.

## Exported contract

The 19 columns are fixed and ordered:

```text
event_index,server_time,time_msc,symbol,deal_type,entry_type,reason,volume,price,sl,tp,commission,fee,swap,profit,magic,deal_ticket,order_ticket,position_id
```

`EVT-000001` is a local row key for one export. It is not a claim that two
independent runs already match.

## Exporter inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `InpFrom` | `2026.01.01 00:00:00` | Inclusive start in terminal server time |
| `InpTo` | `0` | Uses current server time only after terminal connection; otherwise fails closed after ten seconds. An explicit value supports a bounded offline export |
| `InpSymbol` | empty | Exact symbol filter; empty includes every selected symbol |
| `InpMagic` | `-1` | Exact magic filter; negative includes every magic number |
| `InpIncludeBalanceOperations` | `false` | Excludes deposits, withdrawals and other non-buy/sell rows by default |
| `InpUseCommonFolder` | `false` | Writes under the current terminal's Files directory unless enabled |
| `InpFilePrefix` | `SCA_MT5_DealEvidence` | Sanitized output filename prefix |

## Compile and run

1. Open `SCA_MT5DealEvidenceExporter.mq5` in MetaEditor and compile it.
2. Freeze the source/SET identity, MT5 build, symbol properties, date window,
   server timezone, costs and account/test mode for the evidence being studied.
3. Attach the script to a chart in the authorized terminal and set the exact
   filters. Keep balance operations excluded unless they are explicitly needed
   and safe to review.
4. After the one-shot run, open the terminal data directory and review the CSV
   under `MQL5/Files`, or the common Files directory only when that option was
   intentionally enabled.

The source published here has SHA-256
`9D894D572437946F361F69576679D92290A92109C17DCB31565EB669CD04AF77`.
It was compiled locally with MetaEditor 5, X64 Regular, with zero errors and
zero warnings. In one isolated authorized simulated run with live trading and
DLL imports disabled, it selected 158 history records, exported 157 buy/sell
rows and skipped one non-trade operation. Those are bounded engineering facts,
not a trading result or cross-broker compatibility claim.

## Compare two exports

```powershell
.\tools\Compare-MT5DealEvidence.ps1 `
  -ReferencePath .\tester.csv `
  -CandidatePath .\demo.csv `
  -PriceTolerance 0.00001 `
  -MoneyTolerance 0.01 `
  -TimeToleranceMilliseconds 1000 `
  -DifferenceReportPath .\differences.csv
```

The comparator validates all 19 columns before comparing rows by ordinal
position. It checks symbol, deal/entry type, reason and magic exactly, and
applies explicit tolerances to time, volume, price, SL/TP, commission, fee,
swap and realized profit. A row-count difference is reported separately.

Deal, order and position identifiers are ignored by default because independent
runs can allocate new tickets. Add `-CompareIdentifiers` only when identifier
equality is an approved acceptance rule. Add `-FailOnDifference` for process
exit code `2` when any difference is found.

An early inserted or missing event can shift all later ordinal rows. The tool
does not guess a realignment or infer the signal that should have existed.

## Build the HTML handoff

```powershell
.\tools\New-MT5DealEvidenceReport.ps1 `
  -ReferencePath .\tester.csv `
  -CandidatePath .\demo.csv `
  -OutputPath .\reconciliation.html `
  -ReferenceLabel 'Tester build A' `
  -CandidateLabel 'Demo build A' `
  -PriceTolerance 0.00001 `
  -TimeToleranceMilliseconds 1000
```

The report embeds input SHA-256 hashes, tolerances, summary counts and exact
field differences. It contains no script, external asset, local input path,
account identity or broker identity. It still displays deal-level values, so it
must be reviewed before distribution.

## Claim boundary

This toolkit can document stored deal-history differences under a frozen
contract. It cannot reconstruct unfilled signals, prove a historical fill was
executable, establish that two runs used identical software or data, guarantee
broker parity, determine that a strategy is correct or support a profit,
win-rate, drawdown or future-performance claim.

The repository is licensed under the [MIT License](../LICENSE).
