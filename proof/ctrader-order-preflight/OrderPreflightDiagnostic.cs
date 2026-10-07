using System;
using cAlgo.API;

namespace cAlgo.Robots;

[Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
public sealed class OrderPreflightDiagnostic : Robot
{
    [Parameter("Requested volume (units)", DefaultValue = 10000, MinValue = 1, Group = "Hypothetical order")]
    public double RequestedVolumeInUnits { get; set; }

    [Parameter("Stop loss (pips)", DefaultValue = 20, MinValue = 0, Group = "Hypothetical order")]
    public double RequestedStopLossPips { get; set; }

    [Parameter("Take profit (pips)", DefaultValue = 40, MinValue = 0, Group = "Hypothetical order")]
    public double RequestedTakeProfitPips { get; set; }

    [Parameter("Maximum spread (pips)", DefaultValue = 2.0, MinValue = 0.1, Group = "Diagnostic limits")]
    public double MaximumSpreadPips { get; set; }

    protected override void OnStart()
    {
        var distancesArePips = Symbol.MinDistanceType == SymbolMinDistanceType.Pips;
        var input = new StratCoreAlpha.CTraderPreflight.PreflightInput(
            RequestedVolumeInUnits,
            Symbol.VolumeInUnitsMin,
            Symbol.VolumeInUnitsMax,
            Symbol.VolumeInUnitsStep,
            Symbol.Bid,
            Symbol.Ask,
            Symbol.PipSize,
            MaximumSpreadPips,
            Symbol.MarketHours.IsOpened(),
            Symbol.TradingMode == SymbolTradingMode.FullAccess,
            RequestedStopLossPips,
            RequestedTakeProfitPips,
            Symbol.MinStopLossDistance,
            Symbol.MinTakeProfitDistance,
            distancesArePips);

        var results = StratCoreAlpha.CTraderPreflight.PreflightEngine.Evaluate(input);

        Print("SCA_PREFLIGHT|VERSION=0.1.0|NO_TRADE=true|SYMBOL={0}|SERVER_UTC={1:O}", SymbolName, TimeInUtc);
        Print("SCA_CONTEXT|ACCOUNT_TYPE={0}|ACCOUNT_ENV={1}|RUNNING_MODE={2}|BROKER={3}",
            Account.AccountType,
            Account.IsLive ? "LIVE" : "DEMO",
            RunningMode,
            Account.BrokerName);
        Print("SCA_SYMBOL|BID={0}|ASK={1}|PIP_SIZE={2}|TICK_SIZE={3}|MIN_VOLUME={4}|MAX_VOLUME={5}|STEP={6}|TRADING_MODE={7}|DISTANCE_TYPE={8}|MIN_SL={9}|MIN_TP={10}",
            Symbol.Bid,
            Symbol.Ask,
            Symbol.PipSize,
            Symbol.TickSize,
            Symbol.VolumeInUnitsMin,
            Symbol.VolumeInUnitsMax,
            Symbol.VolumeInUnitsStep,
            Symbol.TradingMode,
            Symbol.MinDistanceType,
            Symbol.MinStopLossDistance,
            Symbol.MinTakeProfitDistance);

        foreach (var result in results)
            Print("SCA_CHECK|{0}|{1}|{2}", result.Severity.ToString().ToUpperInvariant(), result.Code, result.Message);

        Print("SCA_RESULT|{0}|CHECKS={1}", StratCoreAlpha.CTraderPreflight.PreflightEngine.OverallStatus(results), results.Count);
        Print("SCA_NOTICE|Read-only diagnostic. No order was sent, modified or cancelled.");

        Stop();
    }
}
