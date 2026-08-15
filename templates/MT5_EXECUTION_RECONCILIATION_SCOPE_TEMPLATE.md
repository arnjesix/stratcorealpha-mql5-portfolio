# MT5 Execution Reconciliation Scope Template

Use this template to freeze a tester-versus-demo or owner-reviewed live-history
comparison before requesting a quote. Complete it with non-confidential facts
only. Do not paste or attach source code, SET files, account numbers, account
names, broker logins, passwords, private strategy rules or full history exports
in a public issue.

## 1. Evidence ownership

- I own or am authorized to use both software versions and evidence sets: Yes / No
- The first comparison pair is: Tester vs demo / Tester vs owner-reviewed live history / Other

## 2. Reference identity

- EA version label or SHA-256 prefix:
- SET/configuration label or SHA-256 prefix:
- MT5 build:
- Evidence format: 19-field toolkit CSV / reviewed MT5 report or export

## 3. Candidate identity

- EA version label or SHA-256 prefix:
- SET/configuration label or SHA-256 prefix:
- MT5 build:
- Evidence format: 19-field toolkit CSV / reviewed MT5 report or export

## 4. Frozen environment

- Symbol including suffix:
- Timeframe:
- Date window:
- Server timezone:
- Account mode: hedging / netting
- Tick/data model:
- Spread assumption:
- Commission assumption:
- Swap assumption:
- Slippage/execution assumption:

## 5. Comparison contract

- Time tolerance in milliseconds:
- Price tolerance:
- Volume tolerance:
- Commission/fee/swap/profit tolerance:
- Compare deal, order and position identifiers: Yes / No
- Matching rule: ordinal rows / separately agreed rule

## 6. One event that should match

- Redacted event label:
- Expected reference behavior:
- Expected candidate behavior:
- Why equality is required under the frozen contract:

## 7. One suspected divergence

- Redacted event label:
- Reference value or behavior:
- Candidate value or behavior:
- Observed field: time / direction / entry type / reason / volume / price / SL / TP / cost / row presence / other
- Do not state a cause unless it is already proven by separate evidence.

## 8. Bounded first milestone

- Maximum rows:
- Number of reference/candidate pairs:
- Maximum prioritized divergences:
- Required delivery format: difference CSV / PDF findings / HTML handoff
- Required completion date and timezone:
- Budget range:

## 9. Claim and handling confirmation

- I will keep private source, SET files, history exports and account/broker identity off public GitHub: Yes / No
- I understand that a detected difference is not automatically a software defect: Yes / No
- I understand that this comparison does not prove historical fillability, broker parity, profitability or future performance: Yes / No
- I understand that EA repair is a separate scope after a reproducible defect and acceptance case are frozen: Yes / No

For a public non-confidential scope check, paste only the safe fields into the
[MT5 execution reconciliation form](https://github.com/arnjesix/stratcorealpha-mql5-portfolio/issues/new?template=mt5-execution-reconciliation.yml).

