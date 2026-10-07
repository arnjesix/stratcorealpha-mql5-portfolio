using System;
using StratCoreAlpha.NinjaTraderProof;

internal static class BarBoundaryEngineProof
{
    private static int checks;

    private static void Expect(
        BoundaryDecision actual,
        BoundaryDecision expected,
        string name)
    {
        checks++;
        if (actual != expected)
            throw new InvalidOperationException(
                $"{name}: expected {expected}, observed {actual}");
    }

    public static void Main()
    {
        var engine = new BarBoundaryEngine();
        var start = new DateTime(2026, 8, 14, 8, 0, 0);

        Expect(engine.Observe(start, true), BoundaryDecision.FirstObservation,
            "first observation suppresses initial session marker");
        Expect(engine.Observe(start.AddMinutes(1)), BoundaryDecision.NextBar,
            "next bar");
        Expect(engine.Observe(start.AddMinutes(1)),
            BoundaryDecision.DuplicateSuppressed, "duplicate timestamp");
        Expect(engine.Observe(start.AddMinutes(1), true),
            BoundaryDecision.DuplicateSuppressed,
            "duplicate timestamp suppresses repeated session marker");
        Expect(engine.Observe(start), BoundaryDecision.NonMonotonicTime,
            "decreasing timestamp");
        Expect(engine.Observe(start, true),
            BoundaryDecision.NonMonotonicTime,
            "decreasing timestamp rejects session marker");
        Expect(engine.Observe(start.AddMinutes(2), true),
            BoundaryDecision.NewSession, "new native session");
        engine.Reset();
        Expect(engine.Observe(start), BoundaryDecision.FirstObservation,
            "first observation after reset");

        Console.WriteLine($"PASS: {checks} deterministic boundary checks");
    }
}
