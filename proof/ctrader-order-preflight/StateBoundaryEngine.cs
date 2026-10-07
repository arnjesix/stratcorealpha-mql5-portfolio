using System;

namespace StratCoreAlpha.CTraderPreflight;

public enum ManagedObjectKind
{
    PendingOrder,
    OpenPosition
}

public enum OutsideSessionPositionPolicy
{
    KeepOpenPositions,
    CloseOwnedPositions
}

public enum BoundaryAction
{
    RejectInvalidInput,
    IgnoreForeignOwner,
    Keep,
    CancelExpiredPendingOrder,
    CancelPendingOrderOutsideSession,
    CloseOwnedPositionOutsideSession
}

public sealed record LifecycleBoundaryInput(
    int CurrentMinuteUtc,
    int SessionStartMinuteUtc,
    int SessionEndMinuteUtc,
    long CurrentBarIndex,
    long CreatedBarIndex,
    int PendingExpiryBars,
    long ExpectedOwnerKey,
    long CandidateOwnerKey,
    ManagedObjectKind ObjectKind,
    OutsideSessionPositionPolicy PositionPolicy);

public sealed record BoundaryDecision(
    BoundaryAction Action,
    string Code,
    string Message)
{
    public bool AllowsMutation => Action is
        BoundaryAction.CancelExpiredPendingOrder or
        BoundaryAction.CancelPendingOrderOutsideSession or
        BoundaryAction.CloseOwnedPositionOutsideSession;
}

public static class LifecycleBoundaryEngine
{
    public static BoundaryDecision Evaluate(LifecycleBoundaryInput input)
    {
        var validation = Validate(input);
        if (validation is not null)
            return validation;

        if (input.CandidateOwnerKey != input.ExpectedOwnerKey)
        {
            return Decision(
                BoundaryAction.IgnoreForeignOwner,
                "FOREIGN_OWNER",
                "The candidate is not owned by this strategy and must not be changed.");
        }

        var sessionOpen = IsInsideSession(
            input.CurrentMinuteUtc,
            input.SessionStartMinuteUtc,
            input.SessionEndMinuteUtc);

        if (input.ObjectKind == ManagedObjectKind.PendingOrder)
        {
            var ageBars = input.CurrentBarIndex - input.CreatedBarIndex;
            if (ageBars >= input.PendingExpiryBars)
            {
                return Decision(
                    BoundaryAction.CancelExpiredPendingOrder,
                    "PENDING_EXPIRED",
                    $"The owned pending order is {ageBars} bars old and reached the {input.PendingExpiryBars}-bar expiry boundary.");
            }

            if (!sessionOpen)
            {
                return Decision(
                    BoundaryAction.CancelPendingOrderOutsideSession,
                    "PENDING_OUTSIDE_SESSION",
                    "The owned pending order is outside the configured half-open session window.");
            }

            return Decision(BoundaryAction.Keep, "PENDING_ACTIVE", "The owned pending order remains active.");
        }

        if (!sessionOpen && input.PositionPolicy == OutsideSessionPositionPolicy.CloseOwnedPositions)
        {
            return Decision(
                BoundaryAction.CloseOwnedPositionOutsideSession,
                "POSITION_OUTSIDE_SESSION",
                "The owned open position is outside the configured session and the explicit close policy is enabled.");
        }

        return Decision(
            BoundaryAction.Keep,
            sessionOpen ? "POSITION_IN_SESSION" : "POSITION_POLICY_KEEP",
            sessionOpen
                ? "The owned position is inside the configured session."
                : "The position remains open because outside-session closing is disabled.");
    }

    public static bool IsInsideSession(int currentMinuteUtc, int startMinuteUtc, int endMinuteUtc)
    {
        if (!IsMinute(currentMinuteUtc) || !IsMinute(startMinuteUtc) || !IsMinute(endMinuteUtc) || startMinuteUtc == endMinuteUtc)
            throw new ArgumentOutOfRangeException(nameof(currentMinuteUtc), "Session minutes must be in 0..1439 and start must differ from end.");

        return startMinuteUtc < endMinuteUtc
            ? currentMinuteUtc >= startMinuteUtc && currentMinuteUtc < endMinuteUtc
            : currentMinuteUtc >= startMinuteUtc || currentMinuteUtc < endMinuteUtc;
    }

    private static BoundaryDecision? Validate(LifecycleBoundaryInput input)
    {
        if (!IsMinute(input.CurrentMinuteUtc) || !IsMinute(input.SessionStartMinuteUtc) || !IsMinute(input.SessionEndMinuteUtc))
            return Invalid("SESSION_MINUTE", "Session and current minutes must be in the inclusive range 0..1439.");

        if (input.SessionStartMinuteUtc == input.SessionEndMinuteUtc)
            return Invalid("SESSION_RANGE", "Equal session boundaries are ambiguous; represent a 24-hour policy explicitly outside this engine.");

        if (input.CurrentBarIndex < 0 || input.CreatedBarIndex < 0 || input.CurrentBarIndex < input.CreatedBarIndex)
            return Invalid("BAR_SEQUENCE", "Bar indexes must be non-negative and current must not precede creation.");

        if (input.PendingExpiryBars <= 0)
            return Invalid("EXPIRY_BARS", "Pending-order expiry must be greater than zero bars.");

        if (input.ExpectedOwnerKey == 0)
            return Invalid("OWNER_KEY", "The strategy owner key must be non-zero so manual objects cannot be claimed accidentally.");

        return null;
    }

    private static bool IsMinute(int value) => value is >= 0 and <= 1439;

    private static BoundaryDecision Invalid(string code, string message) =>
        Decision(BoundaryAction.RejectInvalidInput, code, message);

    private static BoundaryDecision Decision(BoundaryAction action, string code, string message) =>
        new(action, code, message);
}

public enum RiskBaselineAuthority
{
    PersistedStartOfSession,
    ReconstructedFromHistory
}

public enum RiskReconciliationStatus
{
    Pass,
    Warn,
    Fail
}

public sealed record RiskBaselineInput(
    decimal? PersistedStartOfSessionEquity,
    decimal? ReconstructedStartOfSessionEquity,
    decimal MaximumAllowedDifference,
    RiskBaselineAuthority Authority);

public sealed record RiskBaselineDecision(
    RiskReconciliationStatus Status,
    string Code,
    decimal? AuthoritativeEquity,
    string Message);

public static class RiskBaselineReconciler
{
    public static RiskBaselineDecision Reconcile(RiskBaselineInput input)
    {
        if (input.MaximumAllowedDifference < 0)
            return Fail("NEGATIVE_TOLERANCE", "The reconciliation tolerance cannot be negative.");

        var preferred = input.Authority == RiskBaselineAuthority.PersistedStartOfSession
            ? input.PersistedStartOfSessionEquity
            : input.ReconstructedStartOfSessionEquity;
        var secondary = input.Authority == RiskBaselineAuthority.PersistedStartOfSession
            ? input.ReconstructedStartOfSessionEquity
            : input.PersistedStartOfSessionEquity;

        if (!IsValidEquity(preferred))
            return Fail("AUTHORITATIVE_BASELINE_MISSING", "The configured authoritative baseline is missing or non-positive.");

        if (!secondary.HasValue)
        {
            return new(
                RiskReconciliationStatus.Warn,
                "SINGLE_BASELINE_SOURCE",
                preferred,
                "Only the authoritative baseline is available; preserve it and record the missing comparison source.");
        }

        if (!IsValidEquity(secondary))
            return Fail("SECONDARY_BASELINE_INVALID", "The comparison baseline is non-positive.");

        var difference = Math.Abs(preferred!.Value - secondary.Value);
        if (difference > input.MaximumAllowedDifference)
        {
            return Fail(
                "BASELINE_MISMATCH",
                $"Persisted and reconstructed baselines differ by {difference}, above tolerance {input.MaximumAllowedDifference}.");
        }

        return new(
            RiskReconciliationStatus.Pass,
            "BASELINE_RECONCILED",
            preferred,
            "The configured authoritative baseline is preserved and the comparison source is within tolerance.");
    }

    private static bool IsValidEquity(decimal? value) => value.HasValue && value.Value > 0;

    private static RiskBaselineDecision Fail(string code, string message) =>
        new(RiskReconciliationStatus.Fail, code, null, message);
}
