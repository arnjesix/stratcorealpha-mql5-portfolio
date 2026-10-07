using System.Linq;
using StratCoreAlpha.CTraderPreflight;
using Xunit;

namespace StratCoreAlpha.CTraderPreflight.Tests;

public sealed class PreflightEngineTests
{
    [Fact]
    public void RobotSourceMaintainsReadOnlyBoundary()
    {
        var sourcePath = Path.Combine(AppContext.BaseDirectory, "OrderPreflightDiagnostic.cs");
        var source = File.ReadAllText(sourcePath);

        Assert.Contains("AccessRights = AccessRights.None", source, StringComparison.Ordinal);

        string[] forbiddenTradeCalls =
        [
            "ExecuteMarketOrder",
            "ExecuteMarketRangeOrder",
            "PlaceLimitOrder",
            "PlaceStopOrder",
            "PlaceStopLimitOrder",
            "ModifyPosition",
            "ModifyPendingOrder",
            "CancelPendingOrder",
            "ClosePosition",
            "ReversePosition"
        ];

        foreach (var forbiddenCall in forbiddenTradeCalls)
        {
            Assert.False(
                source.Contains(forbiddenCall, StringComparison.Ordinal),
                $"The read-only cBot source contains forbidden trading API '{forbiddenCall}'.");
        }
    }

    [Fact]
    public void ValidInputPassesAllChecks()
    {
        var results = PreflightEngine.Evaluate(Valid());

        Assert.Equal("PASS", PreflightEngine.OverallStatus(results));
        Assert.All(results, result => Assert.Equal(DiagnosticSeverity.Pass, result.Severity));
    }

    [Fact]
    public void MisalignedVolumeFails()
    {
        var results = PreflightEngine.Evaluate(Valid() with { RequestedVolume = 10500, VolumeStep = 1000 });

        Assert.Equal("FAIL", PreflightEngine.OverallStatus(results));
        Assert.Contains(results, result => result.Code == "VOLUME_STEP" && result.Severity == DiagnosticSeverity.Fail);
    }

    [Fact]
    public void ClosedMarketAndCloseOnlyModeFail()
    {
        var results = PreflightEngine.Evaluate(Valid() with { MarketOpen = false, SymbolAllowsNewPositions = false });

        Assert.Equal("FAIL", PreflightEngine.OverallStatus(results));
        Assert.Equal(2, results.Count(result => result.Severity == DiagnosticSeverity.Fail));
    }

    [Fact]
    public void ExcessSpreadFails()
    {
        var results = PreflightEngine.Evaluate(Valid() with { Bid = 1.10000, Ask = 1.10035, MaximumSpreadPips = 2 });

        Assert.Contains(results, result => result.Code == "SPREAD" && result.Severity == DiagnosticSeverity.Fail);
    }

    [Fact]
    public void TooCloseProtectionFails()
    {
        var results = PreflightEngine.Evaluate(Valid() with { RequestedStopLossPips = 4, MinimumStopLossDistance = 5 });

        Assert.Contains(results, result => result.Code == "STOP_DISTANCE" && result.Severity == DiagnosticSeverity.Fail);
    }

    [Fact]
    public void NonPipDistanceProducesManualReviewWarning()
    {
        var results = PreflightEngine.Evaluate(Valid() with { MinimumDistancesArePips = false });

        Assert.Equal("WARN", PreflightEngine.OverallStatus(results));
        Assert.Contains(results, result => result.Code == "DISTANCE_UNIT" && result.Severity == DiagnosticSeverity.Warn);
    }

    private static PreflightInput Valid() => new(
        RequestedVolume: 10000,
        MinimumVolume: 1000,
        MaximumVolume: 10000000,
        VolumeStep: 1000,
        Bid: 1.10000,
        Ask: 1.10010,
        PipSize: 0.0001,
        MaximumSpreadPips: 2,
        MarketOpen: true,
        SymbolAllowsNewPositions: true,
        RequestedStopLossPips: 20,
        RequestedTakeProfitPips: 40,
        MinimumStopLossDistance: 5,
        MinimumTakeProfitDistance: 5,
        MinimumDistancesArePips: true);
}
