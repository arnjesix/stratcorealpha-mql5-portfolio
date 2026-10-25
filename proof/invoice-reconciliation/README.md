# Invoice reconciliation: synthetic control sample

Run `python check.py`. The three executed checks cover an exact Decimal total, a missing quantity, and a one-cent total mismatch. The source retains all supplied items and multiline descriptions. Results are in `results.json`.

This is a small validation-control example, not a delivered invoice extraction project. It does not parse a PDF, create an Excel workbook, or verify a supplier layout. All data are invented. The example rounds tax per line to two decimals. Actual invoice rounding and currencies must follow the source invoice, with ambiguity flagged instead of guessed.
