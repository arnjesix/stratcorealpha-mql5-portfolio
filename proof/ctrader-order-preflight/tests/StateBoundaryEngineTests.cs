using StratCoreAlpha.CTraderPreflight;
using Xunit;

namespace StratCoreAlpha.CTraderPreflight.Tests;

public sealed class StateBoundaryEngineTests
{
    [Fact]
    public void BoundarySourceContainsNoTradingApi()
    {
        var sourcePath = Path.Combine(AppContext.BaseDirectory, "StateBoundaryEngine.cs.source");
        var source = File.ReadAllText(sourcePath);

        Assert.DoesNotContain("cAlgo.API", source, StringComparison.Ordinal);

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
            Assert.DoesNotContain($"{forbiddenCall}(", source, StringComparison.Ordinal);
    }

    [Fact]
    public void SessionUsesInclusiveStartAndExclusiveEnd()
    {
        Assert.True(LifecycleBoundaryEngine.IsInsideSession(420, 420, 600));
        Assert.True(LifecycleBoundaryEngine.IsInsideSession(599, 420, 600));
        Assert.False(LifecycleBoundaryEngine.IsInsideSession(600, 420, 600));
    }

    [Fact]
    public void OvernightSessionWrapsAcrossMidnight()
    {
        Assert.True(LifecycleBoundaryEngine.IsInsideSession(1380, 1320, 120));
        Assert.True(LifecycleBoundaryEngine.IsInsideSession(60, 1320, 120));
        Assert.False(LifecycleBoundaryEngine.IsInsideSession(720, 1320, 120));
    }

    [Fact]
    public void ForeignOwnerIsNeverMutated()
    {
        var decision = LifecycleBoundaryEngine.Evaluate(ValidPending() with
        {
            CandidateOwnerKey = 999,
            CurrentMinuteUtc = 900,
            CurrentBarIndex = 500
        });

        Assert.Equal(BoundaryAction.IgnoreForeignOwner, decision.Action);
        Assert.False(decision.AllowsMutation);
    }

    [Fact]
    public void PendingOrderExpiresExactlyAtNBarBoundary()
    {
        var before = LifecycleBoundaryEngine.Evaluate(ValidPending() with { CurrentBarIndex = 109 });
        var atBoundary = LifecycleBoundaryEngine.Evaluate(ValidPending() with { CurrentBarIndex = 110 });

        Assert.Equal(BoundaryAction.Keep, before.Action);
        Assert.Equal(BoundaryAction.CancelExpiredPendingOrder, atBoundary.Action);
        Assert.True(atBoundary.AllowsMutation);
    }

    [Fact]
    public void OwnedPendingOrderIsCancelledOutsideSession()
    {
        var decision = LifecycleBoundaryEngine.Evaluate(ValidPending() with { CurrentMinuteUtc = 1000 });

        Assert.Equal(BoundaryAction.CancelPendingOrderOutsideSession, decision.Action);
    }

    [Fact]
    public void OpenPositionStaysOpenWithoutExplicitClosePolicy()
    {
        var decision = LifecycleBoundaryEngine.Evaluate(ValidPending() with
        {
            ObjectKind = ManagedObjectKind.OpenPosition,
            CurrentMinuteUtc = 1000,
            PositionPolicy = OutsideSessionPositionPolicy.KeepOpenPositions
        });

        Assert.Equal(BoundaryAction.Keep, decision.Action);
        Assert.Equal("POSITION_POLICY_KEEP", decision.Code);
    }

    [Fact]
    public void ExplicitPolicyClosesOnlyOwnedPositionOutsideSession()
    {
        var decision = LifecycleBoundaryEngine.Evaluate(ValidPending() with
        {
            ObjectKind = ManagedObjectKind.OpenPosition,
            CurrentMinuteUtc = 1000,
            PositionPolicy = OutsideSessionPositionPolicy.CloseOwnedPositions
        });

        Assert.Equal(BoundaryAction.CloseOwnedPositionOutsideSession, decision.Action);
        Assert.True(decision.AllowsMutation);
    }

    [Fact]
    public void AmbiguousSessionFailsClosed()
    {
        var decision = LifecycleBoundaryEngine.Evaluate(ValidPending() with
        {
            SessionStartMinuteUtc = 500,
            SessionEndMinuteUtc = 500
        });

        Assert.Equal(BoundaryAction.RejectInvalidInput, decision.Action);
        Assert.False(decision.AllowsMutation);
    }

    [Fact]
    public void LifecycleDecisionIsRestartDeterministic()
    {
        var frozenInput = ValidPending() with { CurrentBarIndex = 110 };

        Assert.Equal(
            LifecycleBoundaryEngine.Evaluate(frozenInput),
            LifecycleBoundaryEngine.Evaluate(frozenInput));
    }

    [Fact]
    public void PersistedRiskBaselineRemainsAuthoritativeWithinTolerance()
    {
        var decision = RiskBaselineReconciler.Reconcile(new(
            PersistedStartOfSessionEquity: 10000m,
            ReconstructedStartOfSessionEquity: 9999.99m,
            MaximumAllowedDifference: 0.02m,
            Authority: RiskBaselineAuthority.PersistedStartOfSession));

        Assert.Equal(RiskReconciliationStatus.Pass, decision.Status);
        Assert.Equal(10000m, decision.AuthoritativeEquity);
    }

    [Fact]
    public void ReconstructedRiskBaselineCanBeConfiguredAsAuthoritative()
    {
        var decision = RiskBaselineReconciler.Reconcile(new(
            PersistedStartOfSessionEquity: 10000m,
            ReconstructedStartOfSessionEquity: 10000.01m,
            MaximumAllowedDifference: 0.02m,
            Authority: RiskBaselineAuthority.ReconstructedFromHistory));

        Assert.Equal(RiskReconciliationStatus.Pass, decision.Status);
        Assert.Equal(10000.01m, decision.AuthoritativeEquity);
    }

    [Fact]
    public void RiskBaselineMismatchFailsClosed()
    {
        var decision = RiskBaselineReconciler.Reconcile(new(
            PersistedStartOfSessionEquity: 10000m,
            ReconstructedStartOfSessionEquity: 9950m,
            MaximumAllowedDifference: 0.02m,
            Authority: RiskBaselineAuthority.PersistedStartOfSession));

        Assert.Equal(RiskReconciliationStatus.Fail, decision.Status);
        Assert.Equal("BASELINE_MISMATCH", decision.Code);
        Assert.Null(decision.AuthoritativeEquity);
    }

    [Fact]
    public void MissingComparisonSourceWarnsWithoutChangingAuthority()
    {
        var decision = RiskBaselineReconciler.Reconcile(new(
            PersistedStartOfSessionEquity: 10000m,
            ReconstructedStartOfSessionEquity: null,
            MaximumAllowedDifference: 0.02m,
            Authority: RiskBaselineAuthority.PersistedStartOfSession));

        Assert.Equal(RiskReconciliationStatus.Warn, decision.Status);
        Assert.Equal(10000m, decision.AuthoritativeEquity);
    }

    [Fact]
    public void MissingAuthoritativeBaselineFailsClosed()
    {
        var decision = RiskBaselineReconciler.Reconcile(new(
            PersistedStartOfSessionEquity: null,
            ReconstructedStartOfSessionEquity: 10000m,
            MaximumAllowedDifference: 0.02m,
            Authority: RiskBaselineAuthority.PersistedStartOfSession));

        Assert.Equal(RiskReconciliationStatus.Fail, decision.Status);
        Assert.Equal("AUTHORITATIVE_BASELINE_MISSING", decision.Code);
    }

    private static LifecycleBoundaryInput ValidPending() => new(
        CurrentMinuteUtc: 500,
        SessionStartMinuteUtc: 420,
        SessionEndMinuteUtc: 600,
        CurrentBarIndex: 105,
        CreatedBarIndex: 100,
        PendingExpiryBars: 10,
        ExpectedOwnerKey: 54845848,
        CandidateOwnerKey: 54845848,
        ObjectKind: ManagedObjectKind.PendingOrder,
        PositionPolicy: OutsideSessionPositionPolicy.KeepOpenPositions);
}
