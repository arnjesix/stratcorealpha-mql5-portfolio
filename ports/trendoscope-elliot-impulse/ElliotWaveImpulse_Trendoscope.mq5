//+------------------------------------------------------------------+
//|                                     ElliotWaveImpulse_Trendoscope.mq5 |
//| MQL5 INDICATOR port of "Elliot Wave - Impulse" (Pine Script v4)  |
//| by TradingView user HeWhoMustNotBeNamed (Trendoscope).           |
//| Original: https://www.tradingview.com/script/TgF24VYW-Elliot-Wave-Impulse/ |
//|                                                                  |
//| This Source Code Form is subject to the terms of the Mozilla     |
//| Public License, v. 2.0. If a copy of the MPL was not distributed |
//| with this folder, you can obtain one at https://mozilla.org/MPL/2.0/ |
//|                                                                  |
//| This MQL5 file is ORIGINAL code written from the Pine algorithm  |
//| summarized in README.md. No Pine Script text is copied into it,  |
//| and no text is taken from any other (closed or invite-only)      |
//| script. Original Pine concept (c) HeWhoMustNotBeNamed. MQL5 port  |
//| (c) 2026 stratcorealpha contributor (muse-spark-1.3, 2026-09-29).|
//+------------------------------------------------------------------+
#property copyright   "Original Pine (c) HeWhoMustNotBeNamed; MQL5 port MPL-2.0"
#property link        "https://www.tradingview.com/script/TgF24VYW-Elliot-Wave-Impulse/"
#property version     "1.01"
#property description "Elliot Wave Impulse (Trendoscope) port for MT5. See README.md / CREDITS.md."
#property description "Zigzag pivots + W1/W2 retracement-ratio impulse detector with entry/stop/targets."
#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots   16

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'76,175,80'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'255,82,82'
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "Entry"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Stop"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "TStop"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "Target1"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "Target2"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "Target3"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "Target4"
#property indicator_type9   DRAW_NONE

#property indicator_label10 "ZigZag"
#property indicator_type10  DRAW_ZIGZAG
#property indicator_color10 C'0,0,0'
#property indicator_style10 STYLE_DOT
#property indicator_width10 1

#property indicator_label11 "SigP0"
#property indicator_type11  DRAW_NONE
#property indicator_label12 "SigP1"
#property indicator_type12  DRAW_NONE
#property indicator_label13 "SigP2"
#property indicator_type13  DRAW_NONE
#property indicator_label14 "SigT0"
#property indicator_type14  DRAW_NONE
#property indicator_label15 "SigT1"
#property indicator_type15  DRAW_NONE
#property indicator_label16 "SigT2"
#property indicator_type16  DRAW_NONE

//--- inputs mirroring the Pine script
input int    InpZigzagLength        = 10;    // Zigzag pivot length (Pine: zigzagLength)
input double InpErrorPercent        = 5.0;   // Ratio tolerance % (Pine: errorPercent, 2..20)
input double InpEntryPercent        = 30.0;  // Entry offset % of W2 (Pine: entryPercent, 10..100)
input bool   InpWaitForConfirmation = true;  // Skip newest pivot (Pine: waitForConfirmation=true const)
input bool   InpShowZigZag          = true;  // Show zigzag (Pine: showZigZag=true const)
//--- MQL5-side extras (Pine always shows its table / always arms alertcondition)
input bool   InpShowDashboard       = true;  // Comment() with bullish/bearish counts (Pine: stats table)
input bool   InpEnableAlerts        = false; // Alert() on a newly closed signal bar (Pine: alertcondition)

//--- indicator buffers
double ExtBuy[];    // 0: entry price on bullish closed-bar signal, else EMPTY
double ExtSell[];   // 1: entry price on bearish closed-bar signal, else EMPTY
double ExtEntry[];  // 2: entry level on signal bar
double ExtStop[];   // 3: stop level (Point0) on signal bar
double ExtTStop[];  // 4: trailing-stop level on signal bar
double ExtT1[];     // 5: target 1 (1.618*W2) on signal bar
double ExtT2[];     // 6: target 2 (2.0*W2) on signal bar
double ExtT3[];     // 7: target 3 (2.618*W2) on signal bar
double ExtT4[];     // 8: target 4 (3.236*W2) on signal bar
double ExtZZUp[];   // 9: zigzag high pivots (DRAW_ZIGZAG leg 1)
double ExtZZDn[];   // 10: zigzag low pivots (DRAW_ZIGZAG leg 2)
double ExtSigP0[];  // 11: signal pivot P0 price (wave-leg objects)
double ExtSigP1[];  // 12: signal pivot P1 price
double ExtSigP2[];  // 13: signal pivot P2 price
double ExtSigT0[];  // 14: signal pivot P0 bar time (as double)
double ExtSigT1[];  // 15: signal pivot P1 bar time (as double)
double ExtSigT2[];  // 16: signal pivot P2 bar time (as double)

#define EWI_OBJ_PREFIX "EWI_"
#define EWI_MAX_PIVOTS 10
#define EWI_ARROW_BUY  233
#define EWI_ARROW_SELL 234
#define EWI_MAX_WAVELINES 100

//+------------------------------------------------------------------+
//| Indicator initialization.                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpZigzagLength < 1)
     {
      Print("ElliotWaveImpulse_Trendoscope: InpZigzagLength must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpErrorPercent < 2.0 || InpErrorPercent > 20.0)
     {
      Print("ElliotWaveImpulse_Trendoscope: InpErrorPercent must be 2..20.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpEntryPercent < 10.0 || InpEntryPercent > 100.0)
     {
      Print("ElliotWaveImpulse_Trendoscope: InpEntryPercent must be 10..100.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0,  ExtBuy,   INDICATOR_DATA);
   SetIndexBuffer(1,  ExtSell,  INDICATOR_DATA);
   SetIndexBuffer(2,  ExtEntry,  INDICATOR_DATA);
   SetIndexBuffer(3,  ExtStop,   INDICATOR_DATA);
   SetIndexBuffer(4,  ExtTStop,  INDICATOR_DATA);
   SetIndexBuffer(5,  ExtT1,     INDICATOR_DATA);
   SetIndexBuffer(6,  ExtT2,     INDICATOR_DATA);
   SetIndexBuffer(7,  ExtT3,     INDICATOR_DATA);
   SetIndexBuffer(8,  ExtT4,     INDICATOR_DATA);
   SetIndexBuffer(9,  ExtZZUp,   INDICATOR_DATA);
   SetIndexBuffer(10, ExtZZDn,   INDICATOR_DATA);
   SetIndexBuffer(11, ExtSigP0,  INDICATOR_DATA);
   SetIndexBuffer(12, ExtSigP1,  INDICATOR_DATA);
   SetIndexBuffer(13, ExtSigP2,  INDICATOR_DATA);
   SetIndexBuffer(14, ExtSigT0,  INDICATOR_DATA);
   SetIndexBuffer(15, ExtSigT1,  INDICATOR_DATA);
   SetIndexBuffer(16, ExtSigT2,  INDICATOR_DATA);

   ArraySetAsSeries(ExtBuy, true);
   ArraySetAsSeries(ExtSell, true);
   ArraySetAsSeries(ExtEntry, true);
   ArraySetAsSeries(ExtStop, true);
   ArraySetAsSeries(ExtTStop, true);
   ArraySetAsSeries(ExtT1, true);
   ArraySetAsSeries(ExtT2, true);
   ArraySetAsSeries(ExtT3, true);
   ArraySetAsSeries(ExtT4, true);
   ArraySetAsSeries(ExtZZUp, true);
   ArraySetAsSeries(ExtZZDn, true);
   ArraySetAsSeries(ExtSigP0, true);
   ArraySetAsSeries(ExtSigP1, true);
   ArraySetAsSeries(ExtSigP2, true);
   ArraySetAsSeries(ExtSigT0, true);
   ArraySetAsSeries(ExtSigT1, true);
   ArraySetAsSeries(ExtSigT2, true);

   PlotIndexSetInteger(0, PLOT_ARROW, EWI_ARROW_BUY);
   PlotIndexSetInteger(1, PLOT_ARROW, EWI_ARROW_SELL);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 0);

   for(int p = 0; p < 16; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!InpShowZigZag)
      PlotIndexSetInteger(9, PLOT_DRAW_TYPE, DRAW_NONE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("EW Impulse Trendoscope (%d, %.1f, %.0f)",
                                   InpZigzagLength, InpErrorPercent, InpEntryPercent));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Indicator deinitialization: remove our chart objects.            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, EWI_OBJ_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Draw one horizontal level object (Pine f_drawLinesWithLabels end).|
//+------------------------------------------------------------------+
void EwiHLine(const string name, const double price, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
  }

//+------------------------------------------------------------------+
//| Draw one wave-leg trend object (Pine w1/w2 lines).                |
//+------------------------------------------------------------------+
void EwiWaveLine(const string name, const double t1, const double p1,
                 const double t2, const double p2, const color clr)
  {
   datetime dt1 = (datetime)((long)t1);
   datetime dt2 = (datetime)((long)t2);
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, dt1, p1, dt2, p2))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, (long)dt1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, (long)dt2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
     }
  }

//+------------------------------------------------------------------+
//| Main calculation. Mirrors the Pine v4 script bar by bar, oldest  |
//| -> newest: pivots() persistence, zigzag() replace-or-keep plus   |
//| extension doubling, ew_impulse() ratio/dir matching. Full        |
//| recompute on every call keeps the path-dependent pivot state     |
//| deterministic (see README repaint notes).                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2)
      return(0);

//--- Align indexing (root cause fix v1.01): OnCalculate price arrays arrive
//--- non-series (0 = oldest), while indicator buffers are series in OnInit
//--- (0 = newest). Force price/time arrays to series so the i / i+j pivot
//--- lookbacks below read older bars correctly. Without this the zigzag ran
//--- time-reversed (future leak) and newest-signal scan picked wrong bars.
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int L = InpZigzagLength;
   double errMin = (100.0 - InpErrorPercent) / 100.0;
   double errMax = (100.0 + InpErrorPercent) / 100.0;
   double entryRange = InpEntryPercent / 100.0;
   int start = (InpWaitForConfirmation ? 1 : 0);

//--- Pine-style persistent state, rebuilt oldest -> newest
   int pdir = 0, pdirPrev = 0;             // pivots() dir and its previous value
   double zzP[EWI_MAX_PIVOTS];             // zigzag pivot prices, newest at [0]
   int    zzB[EWI_MAX_PIVOTS];             // zigzag pivot bar (series) indices
   int    zzD[EWI_MAX_PIVOTS];             // zigzag pivot dirs (may be doubled)
   int    zzN = 0;
   for(int z = 0; z < EWI_MAX_PIVOTS; z++)
     {
      zzP[z] = 0.0;
      zzB[z] = 0;
      zzD[z] = 0;
     }
   double lastP0 = EMPTY_VALUE, lastP1 = EMPTY_VALUE, lastP2 = EMPTY_VALUE;
   bool   haveLast = false;                // Pine waveLinesArray starts as na lines
   int    bullCount = 0, bearCount = 0;

//--- i is series index (0 = forming bar); k is bar age (0 = oldest)
   for(int i = rates_total - 1; i >= 0; i--)
     {
      int k = rates_total - 1 - i;
      double h = high[i], l = low[i];

      //--- pivots(length): highestbars/highest + lowestbars/lowest over L bars
      bool winFull = (k >= L - 1);
      bool isPhigh = false, isPlow = false;
      if(winFull)
        {
         double mx = high[i], mn = low[i];
         int offH = 0, offL = 0;
         for(int j = 1; j < L; j++)
           {
            if(i + j >= rates_total)
               break;
            if(high[i + j] > mx)
              {
               mx = high[i + j];
               offH = j;
              }
            if(low[i + j] < mn)
              {
               mn = low[i + j];
               offL = j;
              }
           }
         // Strict '>' keeps the most recent bar on ties (see README T6).
         isPhigh = (offH == 0);
         isPlow = (offL == 0);
        }
      if(isPhigh && !isPlow)
         pdir = 1;
      else if(isPlow && !isPhigh)
         pdir = -1;
      bool dirChanged = (pdir != pdirPrev);
      pdirPrev = pdir;

      //--- zigzag(): replace-or-keep the newest pivot, extension doubling
      if(isPhigh || isPlow)
        {
         double value = (pdir == 1 ? h : l);
         int bar = i;
         if(!dirChanged && zzN >= 1)
           {
            double pivot = zzP[0];
            int pivotBar = zzB[0];
            int pivotDir = zzD[0];
            for(int s = 0; s + 1 < zzN; s++)
              {
               zzP[s] = zzP[s + 1];
               zzB[s] = zzB[s + 1];
               zzD[s] = zzD[s + 1];
              }
            zzN--;
//--- Pine: value := value*pivotdir < pivot*pivotdir ? pivot : value
//--- (keep whichever extreme is further out).
            if(value * pivotDir < pivot * pivotDir)
              {
               value = pivot;
               bar = pivotBar;
              }
           }
         if(zzN >= 2)
           {
            double lastPoint = zzP[1];
            if(pdir * value > pdir * lastPoint)
               pdir = pdir * 2;
           }
         if(zzN < EWI_MAX_PIVOTS)
           {
            for(int s = zzN; s > 0; s--)
              {
               zzP[s] = zzP[s - 1];
               zzB[s] = zzB[s - 1];
               zzD[s] = zzD[s - 1];
              }
            zzP[0] = value;
            zzB[0] = bar;
            zzD[0] = pdir;
            zzN++;
           }
         else
           {
            // At capacity: unshift then pop the oldest (Pine unshifts then pops).
            for(int s = EWI_MAX_PIVOTS - 1; s > 0; s--)
              {
               zzP[s] = zzP[s - 1];
               zzB[s] = zzB[s - 1];
               zzD[s] = zzD[s - 1];
              }
            zzP[0] = value;
            zzB[0] = bar;
            zzD[0] = pdir;
           }
        }

      //--- ew_impulse(): ratio + direction match on pivots [start .. start+2]
      bool sigBull = false, sigBear = false;
      double entry = EMPTY_VALUE, stop = EMPTY_VALUE, tstop = EMPTY_VALUE;
      double t1 = EMPTY_VALUE, t2 = EMPTY_VALUE, t3 = EMPTY_VALUE, t4 = EMPTY_VALUE;
      double P0 = 0.0, P1 = 0.0, P2 = 0.0;
      int B0 = -1, B1 = -1, B2 = -1;
      bool havePattern = false;
      if(zzN >= 3 + start)
        {
         P2 = zzP[start];
         P1 = zzP[start + 1];
         P0 = zzP[start + 2];
         B2 = zzB[start];
         B1 = zzB[start + 1];
         B0 = zzB[start + 2];
         int P2Dir = zzD[start];
         int P1Dir = zzD[start + 1];
         double W1 = MathAbs(P1 - P0);
         double W2 = MathAbs(P2 - P1);
         if(W1 > 0.0)
           {
            double r2 = W2 / W1;
            bool patternMatched =
               ((r2 > 0.50 * errMin && r2 < 0.50 * errMax) ||
                (r2 > 0.618 * errMin && r2 < 0.618 * errMax) ||
                (r2 > 0.764 * errMin && r2 < 0.764 * errMax) ||
                (r2 > 0.854 * errMin && r2 < 0.854 * errMax));
            bool dirMatched = ((P1Dir == 2 && P2Dir == -1) ||
                               (P1Dir == -2 && P2Dir == 1));
            bool ignore = (haveLast && (lastP0 == P0 || lastP1 == P1 || lastP2 == P2));
            if(!ignore && patternMatched && dirMatched)
              {
               havePattern = true;
               int dir = (P0 > P1 ? -1 : 1);
               entry = P2 + dir * entryRange * W2;
               stop = P0;
               tstop = P2 - dir * entryRange * W2;
               t1 = P2 + dir * 1.618 * W2;
               t2 = P2 + dir * 2.0 * W2;
               t3 = P2 + dir * 2.618 * W2;
               t4 = P2 + dir * 3.236 * W2;
               if(dir == 1)
                  sigBull = true;
               else
                  sigBear = true;
              }
           }
        }

      //--- Closed-bar output only: the forming bar (i==0) may still repaint
      //--- (faithful to the Pine zigzag; see README T4).
      bool closedBar = (i >= 1);
      ExtBuy[i] = EMPTY_VALUE;
      ExtSell[i] = EMPTY_VALUE;
      ExtEntry[i] = EMPTY_VALUE;
      ExtStop[i] = EMPTY_VALUE;
      ExtTStop[i] = EMPTY_VALUE;
      ExtT1[i] = EMPTY_VALUE;
      ExtT2[i] = EMPTY_VALUE;
      ExtT3[i] = EMPTY_VALUE;
      ExtT4[i] = EMPTY_VALUE;
      ExtSigP0[i] = EMPTY_VALUE;
      ExtSigP1[i] = EMPTY_VALUE;
      ExtSigP2[i] = EMPTY_VALUE;
      ExtSigT0[i] = 0.0;
      ExtSigT1[i] = 0.0;
      ExtSigT2[i] = 0.0;
      if(havePattern && closedBar)
        {
         if(sigBull)
           {
            ExtBuy[i] = entry;
            bullCount++;
           }
         else
           {
            ExtSell[i] = entry;
            bearCount++;
           }
         ExtEntry[i] = entry;
         ExtStop[i] = stop;
         ExtTStop[i] = tstop;
         ExtT1[i] = t1;
         ExtT2[i] = t2;
         ExtT3[i] = t3;
         ExtT4[i] = t4;
         ExtSigP0[i] = P0;
         ExtSigP1[i] = P1;
         ExtSigP2[i] = P2;
         ExtSigT0[i] = (B0 >= 0 && B0 < rates_total ? (double)time[B0] : 0.0);
         ExtSigT1[i] = (B1 >= 0 && B1 < rates_total ? (double)time[B1] : 0.0);
         ExtSigT2[i] = (B2 >= 0 && B2 < rates_total ? (double)time[B2] : 0.0);
         lastP0 = P0;
         lastP1 = P1;
         lastP2 = P2;
         haveLast = true;
        }
     }

//--- zigzag display buffers from the final pivot set (Pine's live view)
   for(int i = 0; i < rates_total; i++)
     {
      ExtZZUp[i] = EMPTY_VALUE;
      ExtZZDn[i] = EMPTY_VALUE;
     }
   if(InpShowZigZag)
     {
      for(int s = 0; s < zzN; s++)
        {
         int bi = zzB[s];
         if(bi < 0 || bi >= rates_total)
            continue;
         if(zzD[s] > 0)
            ExtZZUp[bi] = zzP[s];
         else if(zzD[s] < 0)
            ExtZZDn[bi] = zzP[s];
        }
     }

//--- chart objects: the latest signal owns the 7 level lines (Pine deletes
//--- the previous target lines/labels on each new signal); wave legs W1/W2
//--- persist per signal with a cap, mirroring max_lines_count=500.
   static datetime lastObjSigBar = 0;
   int newestSigIdx = -1;
   for(int i = 1; i < rates_total; i++)
     {
      if(ExtBuy[i] != EMPTY_VALUE || ExtSell[i] != EMPTY_VALUE)
        {
         newestSigIdx = i;
         break;
        }
     }
   if(newestSigIdx >= 0 && time[newestSigIdx] != lastObjSigBar)
     {
      lastObjSigBar = time[newestSigIdx];
      ObjectsDeleteAll(0, EWI_OBJ_PREFIX + "L_");
      ObjectsDeleteAll(0, EWI_OBJ_PREFIX + "W_");
      bool isBull = (ExtBuy[newestSigIdx] != EMPTY_VALUE);
      color dirClr = (isBull ? C'76,175,80' : C'255,82,82');
      color stopClr = (isBull ? C'255,82,82' : C'76,175,80');
      EwiHLine(EWI_OBJ_PREFIX + "L_Entry", ExtEntry[newestSigIdx], C'41,98,255');
      EwiHLine(EWI_OBJ_PREFIX + "L_Stop", ExtStop[newestSigIdx], stopClr);
      EwiHLine(EWI_OBJ_PREFIX + "L_TStop", ExtTStop[newestSigIdx], stopClr);
      EwiHLine(EWI_OBJ_PREFIX + "L_T1", ExtT1[newestSigIdx], dirClr);
      EwiHLine(EWI_OBJ_PREFIX + "L_T2", ExtT2[newestSigIdx], dirClr);
      EwiHLine(EWI_OBJ_PREFIX + "L_T3", ExtT3[newestSigIdx], dirClr);
      EwiHLine(EWI_OBJ_PREFIX + "L_T4", ExtT4[newestSigIdx], dirClr);
      //--- wave legs for the newest signals (Pine w1/w2; capped, see README)
      int drawn = 0;
      for(int i = 1; i < rates_total && drawn < EWI_MAX_WAVELINES; i++)
        {
         if(ExtBuy[i] == EMPTY_VALUE && ExtSell[i] == EMPTY_VALUE)
            continue;
         if(ExtSigT0[i] == 0 || ExtSigT1[i] == 0 || ExtSigT2[i] == 0)
            continue;
         color legClr = (ExtSigP1[i] > ExtSigP2[i] ? C'76,175,80' : C'255,82,82');
         string leg1 = StringFormat("%sW_%d_1", EWI_OBJ_PREFIX, (long)time[i]);
         string leg2 = StringFormat("%sW_%d_2", EWI_OBJ_PREFIX, (long)time[i]);
         EwiWaveLine(leg1, ExtSigT0[i], ExtSigP0[i], ExtSigT1[i], ExtSigP1[i], legClr);
         EwiWaveLine(leg2, ExtSigT1[i], ExtSigP1[i], ExtSigT2[i], ExtSigP2[i], legClr);
         drawn++;
        }
     }

//--- dashboard (Pine draws a stats table; MQL5 uses Comment(), see README)
   if(InpShowDashboard)
      Comment(StringFormat("EW Impulse Trendoscope | Bullish: %d  Bearish: %d", bullCount, bearCount));
   else
      Comment("");

//--- alerts on the last closed bar only (Pine alertcondition equivalent)
   if(InpEnableAlerts && rates_total >= 2)
     {
      static datetime lastAlertBar = 0;
      if(time[1] != lastAlertBar)
        {
         if(ExtBuy[1] != EMPTY_VALUE || ExtSell[1] != EMPTY_VALUE)
           {
            string side = (ExtBuy[1] != EMPTY_VALUE ? "BULLISH" : "BEARISH");
            Alert(StringFormat("EW Impulse %s %s %s entry %s",
                               side, _Symbol, EnumToString(_Period),
                               DoubleToString(ExtEntry[1], _Digits)));
            lastAlertBar = time[1];
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+

