# NinjaTrader bar-boundary inspector: source and build proof

The same bar can reach an indicator more than once. This owned, read-only
NinjaScript sample makes that decision visible: first bar, next bar, duplicate,
out-of-order timestamp or a native session boundary. It contains no order,
account, position or broker-connection operation.

## Verified on 7 October 2026

- **8 deterministic checks passed**: [actual output](evidence/tests.txt).
- The adapter compiled against local **NinjaTrader 8.1.8.1** Core, GUI and
  Custom assemblies, with **0 errors and 2 local LIB-path warnings**:
  [actual build output](evidence/build.txt).
- The existing safety check passed: no transaction/account APIs, no external
  I/O APIs, native `Bars.IsFirstBarOfSession` input and no guessed UTC conversion:
  [actual check output](evidence/safety-check.txt).
- [Source and assembly hashes](evidence/manifest.json) identify what was checked.
  Source bytes are unchanged; only the repository path in the logs is redacted.
  Proprietary NinjaTrader assemblies are not included.

## Eight checked decisions

| Input | Expected decision |
| --- | --- |
| First observation | FirstObservation |
| Increasing timestamp | NextBar |
| Same timestamp | DuplicateSuppressed |
| Same timestamp with session marker | DuplicateSuppressed |
| Decreasing timestamp | NonMonotonicTime |
| Decreasing timestamp with session marker | NonMonotonicTime |
| Increasing first bar of a native session | NewSession |
| First observation after reset | FirstObservation |

## Source and repeatable checks

[BarBoundaryEngine.cs](src/BarBoundaryEngine.cs) contains the pure decisions.
[StratCoreBarBoundaryInspector.cs](src/StratCoreBarBoundaryInspector.cs) is the adapter.

```powershell
dotnet run --project tests/BarBoundaryEngineProof.csproj -c Release
dotnet build NinjaTraderCompileProof.csproj -c Release --no-incremental
```

The compile project targets .NET Framework 4.8. It requires an authorized local
NinjaTrader installation and the assembly paths listed in the project. Set
`NinjaTraderInstallDir` if the installation uses another directory. The adapter
retains its existing `VendorLicense(2211)` call; this build does not test licensing.

## Limits

This sample has not been imported into a NinjaTrader chart, exercised with
market data, reloaded in a native session or connected to a broker. The eight
checks use synthetic timestamps. Build success proves source/API compatibility
with the listed assemblies, not native session behaviour or production use.

This is not a completed customer case, trading strategy, performance result or
challenge-pass claim. Native import, chart/session and reload checks remain open.
