//+------------------------------------------------------------------+
//| SCA_T99_RuleLib.mqh — T99 rule building blocks (rehearsal scaffold)|
//| TEST ONLY scaffolding. NOT compiled/verified in a terminal yet:  |
//| the parent compiles and runs the real HolaPrime MT5 check later. |
//+------------------------------------------------------------------+
//| BAR-TIMING DEFINITIONS (binding for every block below):          |
//|  - bar 0 = forming bar (NEVER used for signals).                 |
//|  - bar 1 = last COMPLETED bar. All signals evaluate at the open  |
//|    of bar 0 using completed-bar values with shift >= 1 only.     |
//|  - A "swing high at bar s" is confirmed only when the caller's   |
//|    evaluation bar is >= s + right (no lookahead: right-side bars |
//|    must already be completed).                                   |
//|  - CopyRates/CopyBuffer callers must pass arrays set as series   |
//|    (ArraySetAsSeries) so index 1 = last completed bar.           |
//+------------------------------------------------------------------+
#property strict

//--- Swing high on completed bars only. Returns true when bar s (shift
//--- counting from the evaluation point, s >= right+1 in caller terms) is
//--- strictly higher than `left` bars before and `right` bars after it,
//--- where all 1+left+right bars are completed (shift >= 1). No lookahead:
//--- the function never reads shift 0.
bool T99_SwingHigh(const double &high[], int s, int left, int right)
  {
   if(s < 1 || left < 1 || right < 1)
      return(false);
   double hs = high[s];
   for(int i = s - right; i <= s + left; i++)
     {
      if(i < 1)
         return(false);           // incomplete history: fail closed
      if(i == s)
         continue;
      if(high[i] >= hs)
         return(false);           // strict: equal highs are NOT a swing
     }
   return(true);
  }

//--- Session range over completed bars: high/low of bars whose server time
//--- falls in [sess_start, sess_end). Times are "HH:MM" server clock.
//--- Returns false when no completed bar falls in the window.
bool T99_SessionRange(const datetime &time[], const double &high[],
                      const double &low[], int bars,
                      string sess_start, string sess_end,
                      double &range_high, double &range_low)
  {
   range_high = -DBL_MAX;
   range_low  =  DBL_MAX;
   int found = 0;
   for(int i = 1; i < bars; i++)  // shift>=1: completed bars only
     {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      string hm = StringFormat("%02d:%02d", dt.hour, dt.min);
      bool inside = (sess_start <= sess_end)
                    ? (hm >= sess_start && hm < sess_end)
                    : (hm >= sess_start || hm < sess_end);
      if(!inside)
         continue;
      if(high[i] > range_high)
         range_high = high[i];
      if(low[i] < range_low)
         range_low = low[i];
      found++;
     }
   return(found > 0);
  }

//--- Bullish FVG on completed bars: bar c-1 low > bar c+1 high with the
//--- displacement bar c between them (all shifts >= 1). Bearish mirrored.
//--- evaluated_triplet is the newest completed bar that can host the
//--- pattern without lookahead, i.e. shift 3 (needs c-1, c, c+1 all >= 1).
bool T99_FvgBull(const double &high[], const double &low[])
  {
   return(low[1] > high[3]);   // bars 1(newest) and 3 with bar 2 between
  }
bool T99_FvgBear(const double &high[], const double &low[])
  {
   return(high[1] < low[3]);
  }

//--- Strict MA cross on completed bars: fast crosses above slow exactly at
//--- bar 1 (fast[2] <= slow[2] and fast[1] > slow[1]). Bearish mirrored.
//--- Strict inequalities: equality never counts as a cross (boundary = no).
bool T99_MaCrossBull(const double &fast[], const double &slow[])
  {
   return(fast[2] <= slow[2] && fast[1] > slow[1]);
  }
bool T99_MaCrossBear(const double &fast[], const double &slow[])
  {
   return(fast[2] >= slow[2] && fast[1] < slow[1]);
  }

//--- RSI threshold on the last completed bar: long zone when rsi[1] <
//--- oversold (strict), flat/exit when rsi[1] > overbought (strict).
//--- Equality with the threshold is the boundary: no signal.
bool T99_RsiLongZone(double rsi_completed, double oversold)
  {
   return(rsi_completed < oversold);
  }
bool T99_RsiExitZone(double rsi_completed, double overbought)
  {
   return(rsi_completed > overbought);
  }
//+------------------------------------------------------------------+
