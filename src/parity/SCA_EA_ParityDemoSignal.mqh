//+------------------------------------------------------------------+
//| SCA_EA_ParityDemoSignal.mqh                                      |
//| Owned sample: pure two-SMA crossover signal, no trading calls.   |
//| Shared by the EA and the read-only test script so both run the   |
//| identical rule path.                                             |
//+------------------------------------------------------------------+
#property copyright "StratCoreAlpha owned sample"
#property version   "1.00"

// Frozen rule parameters (must match README, Pine script and fixture):
//   FAST_PERIOD = 3, SLOW_PERIOD = 5, warmup = first eligible bar index 5.
#define SCA_PARITY_FAST_PERIOD 3
#define SCA_PARITY_SLOW_PERIOD 5
#define SCA_PARITY_FIRST_SIGNAL_INDEX 5

// Returns +1 (BULL cross), -1 (BEAR cross) or 0 (no signal).
// All four SMA values must already be computed from completed-bar closes.
// Strict crossing: equality on the current bar is NOT a signal.
int SCA_ParitySignal(const double fast_prev, const double slow_prev,
                     const double fast_now, const double slow_now)
{
   bool bull = (fast_prev <= slow_prev && fast_now > slow_now);
   bool bear = (fast_prev >= slow_prev && fast_now < slow_now);
   if(bull && !bear)
      return +1;
   if(bear && !bull)
      return -1;
   return 0;
}

// Simple mean of the last 'period' values ending at 'end' (inclusive).
// Returns EMPTY_VALUE when fewer than 'period' values are available.
double SCA_ParitySMA(const double &closes[], const int end, const int period)
{
   if(end + 1 < period)
      return EMPTY_VALUE;
   double sum = 0.0;
   for(int k = end - period + 1; k <= end; k++)
      sum += closes[k];
   return sum / period;
}
//+------------------------------------------------------------------+
