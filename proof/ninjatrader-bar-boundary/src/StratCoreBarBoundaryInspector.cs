using System.Windows.Media;
using NinjaTrader.NinjaScript;
using StratCoreAlpha.NinjaTraderProof;

namespace NinjaTrader.NinjaScript.Indicators
{
    public class StratCoreBarBoundaryInspector : Indicator
    {
        private BarBoundaryEngine engine;

        public StratCoreBarBoundaryInspector()
        {
            VendorLicense(2211);
        }

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Description = "Read-only bar timestamp and session boundary inspector.";
                Name = "StratCoreBarBoundaryInspector";
                Calculate = Calculate.OnBarClose;
                IsOverlay = false;
                IsSuspendedWhileInactive = true;
                AddPlot(Brushes.DodgerBlue, "BoundaryCode");
            }
            else if (State == State.DataLoaded)
            {
                engine = new BarBoundaryEngine();
            }
        }

        protected override void OnBarUpdate()
        {
            Value[0] = (double)engine.Observe(
                Time[0],
                Bars.IsFirstBarOfSession);
        }
    }
}
