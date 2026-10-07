using System;
using System.Collections.Generic;
using System.Globalization;

namespace StratCoreAlpha.CTraderPreflight;

public enum DiagnosticSeverity
{
    Pass,
    Warn,
    Fail
}

public sealed record DiagnosticResult(
    string Code,
    DiagnosticSeverity Severity,
    string Message);

public sealed record PreflightInput(
    double RequestedVolume,
    double MinimumVolume,
    double MaximumVolume,
    double VolumeStep,
    double Bid,
    double Ask,
    double PipSize,
    double MaximumSpreadPips,
    bool MarketOpen,
    bool SymbolAllowsNewPositions,
    double RequestedStopLossPips,
    double RequestedTakeProfitPips,
    double MinimumStopLossDistance,
    double MinimumTakeProfitDistance,
    bool MinimumDistancesArePips);

public static class PreflightEngine
{
    private const double Epsilon = 1e-8;

    public static IReadOnlyList<DiagnosticResult> Evaluate(PreflightInput input)
    {
        var results = new List<DiagnosticResult>();

        ValidateVolume(input, results);
        ValidateMarketState(input, results);
        ValidateSpread(input, results);
        ValidateProtectionDistances(input, results);

        return results;
    }

    public static string OverallStatus(IReadOnlyList<DiagnosticResult> results)
    {
        foreach (var result in results)
        {
            if (result.Severity == DiagnosticSeverity.Fail)
                return "FAIL";
        }

        foreach (var result in results)
        {
            if (result.Severity == DiagnosticSeverity.Warn)
                return "WARN";
        }

        return "PASS";
    }

    private static void ValidateVolume(PreflightInput input, ICollection<DiagnosticResult> results)
    {
        if (!IsPositiveFinite(input.RequestedVolume) ||
            !IsPositiveFinite(input.MinimumVolume) ||
            !IsPositiveFinite(input.MaximumVolume) ||
            !IsPositiveFinite(input.VolumeStep))
        {
            results.Add(Fail("VOLUME_DATA", "Volume values must be finite and greater than zero."));
            return;
        }

        if (input.RequestedVolume < input.MinimumVolume - Epsilon)
        {
            results.Add(Fail("VOLUME_MIN", $"Requested volume {F(input.RequestedVolume)} is below minimum {F(input.MinimumVolume)}."));
            return;
        }

        if (input.RequestedVolume > input.MaximumVolume + Epsilon)
        {
            results.Add(Fail("VOLUME_MAX", $"Requested volume {F(input.RequestedVolume)} exceeds maximum {F(input.MaximumVolume)}."));
            return;
        }

        var steps = (input.RequestedVolume - input.MinimumVolume) / input.VolumeStep;
        var stepDelta = Math.Abs(steps - Math.Round(steps));
        var stepTolerance = Math.Max(Epsilon, Epsilon * Math.Abs(steps));

        results.Add(stepDelta <= stepTolerance
            ? Pass("VOLUME_STEP", $"Requested volume {F(input.RequestedVolume)} matches min/step constraints.")
            : Fail("VOLUME_STEP", $"Requested volume {F(input.RequestedVolume)} is not aligned to step {F(input.VolumeStep)} from minimum {F(input.MinimumVolume)}."));
    }

    private static void ValidateMarketState(PreflightInput input, ICollection<DiagnosticResult> results)
    {
        results.Add(input.MarketOpen
            ? Pass("MARKET_HOURS", "The symbol market session is currently open.")
            : Fail("MARKET_HOURS", "The symbol market session is currently closed."));

        results.Add(input.SymbolAllowsNewPositions
            ? Pass("TRADING_MODE", "The symbol trading mode allows new positions.")
            : Fail("TRADING_MODE", "The symbol trading mode does not allow new positions."));
    }

    private static void ValidateSpread(PreflightInput input, ICollection<DiagnosticResult> results)
    {
        if (!IsPositiveFinite(input.Bid) || !IsPositiveFinite(input.Ask) || input.Ask < input.Bid || !IsPositiveFinite(input.PipSize))
        {
            results.Add(Fail("SPREAD_DATA", "Bid, ask or pip-size data is invalid."));
            return;
        }

        var spreadPips = (input.Ask - input.Bid) / input.PipSize;
        if (!IsPositiveFinite(input.MaximumSpreadPips))
        {
            results.Add(Warn("SPREAD_LIMIT", $"Current spread is {F(spreadPips)} pips; no positive comparison limit was supplied."));
            return;
        }

        results.Add(spreadPips <= input.MaximumSpreadPips + Epsilon
            ? Pass("SPREAD", $"Current spread {F(spreadPips)} pips is within limit {F(input.MaximumSpreadPips)}.")
            : Fail("SPREAD", $"Current spread {F(spreadPips)} pips exceeds limit {F(input.MaximumSpreadPips)}."));
    }

    private static void ValidateProtectionDistances(PreflightInput input, ICollection<DiagnosticResult> results)
    {
        if (!input.MinimumDistancesArePips)
        {
            results.Add(Warn("DISTANCE_UNIT", "Broker minimum distances are not expressed in pips; raw values are reported for manual interpretation."));
            return;
        }

        ValidateDistance("STOP_DISTANCE", "stop-loss", input.RequestedStopLossPips, input.MinimumStopLossDistance, results);
        ValidateDistance("TAKE_DISTANCE", "take-profit", input.RequestedTakeProfitPips, input.MinimumTakeProfitDistance, results);
    }

    private static void ValidateDistance(
        string code,
        string label,
        double requested,
        double minimum,
        ICollection<DiagnosticResult> results)
    {
        if (!double.IsFinite(requested) || requested < 0 || !double.IsFinite(minimum) || minimum < 0)
        {
            results.Add(Fail(code, $"The requested or minimum {label} distance is invalid."));
            return;
        }

        if (requested == 0)
        {
            results.Add(Warn(code, $"No {label} distance was requested."));
            return;
        }

        results.Add(requested + Epsilon >= minimum
            ? Pass(code, $"Requested {label} {F(requested)} pips meets minimum {F(minimum)}.")
            : Fail(code, $"Requested {label} {F(requested)} pips is below minimum {F(minimum)}."));
    }

    private static bool IsPositiveFinite(double value) => double.IsFinite(value) && value > 0;

    private static string F(double value) => value.ToString("0.########", CultureInfo.InvariantCulture);

    private static DiagnosticResult Pass(string code, string message) => new(code, DiagnosticSeverity.Pass, message);
    private static DiagnosticResult Warn(string code, string message) => new(code, DiagnosticSeverity.Warn, message);
    private static DiagnosticResult Fail(string code, string message) => new(code, DiagnosticSeverity.Fail, message);
}
