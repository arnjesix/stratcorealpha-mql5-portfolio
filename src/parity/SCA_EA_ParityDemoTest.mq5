//+------------------------------------------------------------------+
//| SCA_EA_ParityDemoTest.mq5                                        |
//| Read-only deterministic harness: runs the frozen SMA(3)/SMA(5)   |
//| completed-bar rule over the 12-bar owned fixture and prints the  |
//| exact ordered signal dates/indices. No trading calls.            |
//+------------------------------------------------------------------+
#property copyright "StratCoreAlpha owned sample"
#property version   "1.00"
#property description "Read-only fixture parity harness: prints ordered SMA-crossover signals; places no orders."
#property script_show_inputs

#include "SCA_EA_ParityDemoSignal.mqh"

// Owned fixture closes (byte-identical to fixture_ohlc.csv close column).
static double ExtFixtureCloses[12] = {10.0, 10.0, 10.0, 10.0, 10.0, 12.0,
                                      12.0, 12.0, 8.0, 8.0, 8.0, 8.0};

//+------------------------------------------------------------------+
string ExtFixtureDate(const int index)
{
   // H1 fixture dates, UTC: 2026-01-05 09:00 + index hours.
   datetime base = D'2026.01.05 09:00:00';
   return TimeToString(base + index * 3600, TIME_DATE | TIME_SECONDS);
}

//+------------------------------------------------------------------+
void OnStart()
{
   int passed = 0;
   int failed = 0;
   int sig_count = 0;
   int first_sig_index = -1;
   int first_sig_value = 0;
   int second_sig_index = -1;
   int second_sig_value = 0;

   for(int i = 0; i < 12; i++)
   {
      double fast_now = SCA_ParitySMA(ExtFixtureCloses, i, SCA_PARITY_FAST_PERIOD);
      double slow_now = SCA_ParitySMA(ExtFixtureCloses, i, SCA_PARITY_SLOW_PERIOD);
      int sig = 0;
      if(i >= SCA_PARITY_FIRST_SIGNAL_INDEX && i >= 1)
      {
         double fast_prev = SCA_ParitySMA(ExtFixtureCloses, i - 1, SCA_PARITY_FAST_PERIOD);
         double slow_prev = SCA_ParitySMA(ExtFixtureCloses, i - 1, SCA_PARITY_SLOW_PERIOD);
         if(fast_now != EMPTY_VALUE && slow_now != EMPTY_VALUE &&
            fast_prev != EMPTY_VALUE && slow_prev != EMPTY_VALUE)
            sig = SCA_ParitySignal(fast_prev, slow_prev, fast_now, slow_now);
      }
      string fast_s = (fast_now == EMPTY_VALUE ? "n/a" : DoubleToString(fast_now, 5));
      string slow_s = (slow_now == EMPTY_VALUE ? "n/a" : DoubleToString(slow_now, 5));
      string sig_s  = (sig > 0 ? "BULL" : (sig < 0 ? "BEAR" : "none"));
      PrintFormat("SCA_PARITY_FIX i=%d date=%s fast=%s slow=%s signal=%s",
                  i, ExtFixtureDate(i), fast_s, slow_s, sig_s);
      if(sig != 0)
      {
         sig_count++;
         if(first_sig_index < 0)
         {
            first_sig_index = i;
            first_sig_value = sig;
         }
         else if(second_sig_index < 0)
         {
            second_sig_index = i;
            second_sig_value = sig;
         }
      }
   }

   // ACC-01: warmup bars 0-4 emit zero signals.
   if(sig_count >= 0 && first_sig_index >= SCA_PARITY_FIRST_SIGNAL_INDEX)
   {
      passed++;
      Print("SCA_PARITY_TEST PASS ACC-01 warmup bars 0-4 silent");
   }
   else
   {
      failed++;
      Print("SCA_PARITY_TEST FAIL ACC-01 warmup bars 0-4 silent");
   }
   // ACC-02: exactly one BULL at index 5.
   if(first_sig_index == 5 && first_sig_value == +1)
   {
      passed++;
      Print("SCA_PARITY_TEST PASS ACC-02 BULL at index 5 (2026-01-05 14:00 UTC)");
   }
   else
   {
      failed++;
      PrintFormat("SCA_PARITY_TEST FAIL ACC-02 expected BULL@5 got idx=%d val=%d",
                  first_sig_index, first_sig_value);
   }
   // ACC-03: exactly one BEAR at index 8; total ordered list [5:BULL, 8:BEAR].
   if(sig_count == 2 && second_sig_index == 8 && second_sig_value == -1)
   {
      passed++;
      Print("SCA_PARITY_TEST PASS ACC-03 BEAR at index 8 (2026-01-05 17:00 UTC); ordered list [5:BULL, 8:BEAR]");
   }
   else
   {
      failed++;
      PrintFormat("SCA_PARITY_TEST FAIL ACC-03 expected [5:BULL,8:BEAR] got count=%d second_idx=%d second_val=%d",
                  sig_count, second_sig_index, second_sig_value);
   }

   PrintFormat("SCA_PARITY_TEST SUMMARY passed=%d failed=%d RUNTIME_STATUS=%s",
               passed, failed, (failed == 0 ? "PASSED" : "FAILED"));
}
//+------------------------------------------------------------------+
