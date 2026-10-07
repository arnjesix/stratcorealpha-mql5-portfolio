using System;

namespace StratCoreAlpha.NinjaTraderProof
{
    public enum BoundaryDecision
    {
        NonMonotonicTime = -2,
        DuplicateSuppressed = -1,
        FirstObservation = 0,
        NextBar = 1,
        NewSession = 2
    }

    public sealed class BarBoundaryEngine
    {
        private bool hasObservation;
        private DateTime lastObservedAt;

        public void Reset()
        {
            hasObservation = false;
            lastObservedAt = default;
        }

        public BoundaryDecision Observe(
            DateTime observedAt,
            bool isFirstBarOfSession = false)
        {
            if (!hasObservation)
            {
                hasObservation = true;
                lastObservedAt = observedAt;
                return BoundaryDecision.FirstObservation;
            }

            if (observedAt < lastObservedAt)
                return BoundaryDecision.NonMonotonicTime;

            if (observedAt == lastObservedAt)
                return BoundaryDecision.DuplicateSuppressed;

            lastObservedAt = observedAt;
            return isFirstBarOfSession
                ? BoundaryDecision.NewSession
                : BoundaryDecision.NextBar;
        }
    }
}
