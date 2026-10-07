# cTrader order preflight: source and build proof

An order can be rejected because its volume, spread or stop distance does not
fit the symbol. This owned, read-only cBot checks one hypothetical order and
prints `PASS`, `WARN` or `FAIL` with the reason. It does not send, change or
cancel an order.

## Verified on 7 October 2026

- Managed Release build: **0 errors, 2 warnings**. The warnings are two missing
  local `LIB` search paths; they are kept in the [actual build output](evidence/build.txt).
- **22 tests passed, 0 failed, 0 skipped**, in the [actual test output](evidence/tests.txt).
- The tests cover volume limits and step, open/closed market, trading mode,
  spread, protection distances and unknown distance units. Additional pure
  state-policy checks cover ownership, session boundaries and restart baselines.
- Source hashes and SDK version are in [the manifest](evidence/manifest.json).
  The published source is byte-for-byte the source used for these checks.
  Only local repository and NuGet-home prefixes were redacted from the logs.

## Source and repeatable checks

[OrderPreflightDiagnostic.cs](OrderPreflightDiagnostic.cs) is the cTrader adapter.
[PreflightEngine.cs](PreflightEngine.cs) contains the checks;
[StateBoundaryEngine.cs](StateBoundaryEngine.cs) contains the separate pure policy sample.

```powershell
dotnet build StratCoreAlpha.CTraderPreflight.csproj -c Release --no-incremental
dotnet test tests/StratCoreAlpha.CTraderPreflight.Tests.csproj -c Release
```

The adapter targets .NET 6 and `cTrader.Automate` 1.0.19; the tests target .NET 8.
Both runtimes and a suitable SDK are needed to repeat the checks.

## Limits

This is a source/build demonstration, not a completed customer case. No native
cTrader demo run, broker connection, market-data observation or independent
positions/orders/history comparison is claimed. Unit inputs are synthetic.
Passing the source-level no-order guard does not prove native runtime behaviour.

`AccessRights.None` is declared. A preflight `PASS` only means that the checked
inputs satisfy the coded conditions; it does not promise an accepted order,
execution quality, profit or challenge passing. A non-pip minimum-distance unit
produces `WARN` instead of a guessed conversion.

No `.algo` package is distributed here. The generic NuGet build is not the
official cBot packaging step. The official Spotware CLI metadata and a separate
authorized demo-runtime check are needed before calling a package runtime-validated.
