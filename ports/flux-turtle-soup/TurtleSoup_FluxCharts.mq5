//+------------------------------------------------------------------+
//|                                           TurtleSoup_FluxCharts.mq5 |
//| MQL5 INDICATOR port of "ICT Turtle Soup | Flux Charts" (Pine v5) |
//| by TradingView user fluxchart.                                   |
//| Original: https://www.tradingview.com/script/b67pK4jN-ICT-Turtle-Soup-Flux-Charts/ |
//|                                                                  |
//| This Source Code Form is subject to the terms of the Mozilla     |
//| Public License, v. 2.0. If a copy of the MPL was not distributed |
//| with this folder, you can obtain one at https://mozilla.org/MPL/2.0/ |
//|                                                                  |
//| This MQL5 file is ORIGINAL code written from the Pine algorithm  |
//| summarized in README.md. No Pine Script text is copied into it,  |
//| and no text is taken from any other (closed or invite-only)      |
//| script. Original Pine concept (c) fluxchart. MQL5 port (c) 2026  |
//| stratcorealpha contributor (muse-spark-1.3, 2026-09-29).         |
//+------------------------------------------------------------------+
#property copyright   "Original Pine (c) fluxchart; MQL5 port MPL-2.0"
#property link        "https://www.tradingview.com/script/b67pK4jN-ICT-Turtle-Soup-Flux-Charts/"
#property version     "1.02"
#property description "ICT Turtle Soup (Flux Charts) port for MT5. See README.md / CREDITS.md."
#property description "Liquidity sweep + MSS execution detector with dynamic/fixed TP/SL."
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   9

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

#property indicator_label3  "TakeProfit"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  C'41,98,255'
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "StopLoss"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  C'255,82,82'
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "SweepHigh"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  C'255,82,82'
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

#property indicator_label6  "SweepLow"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  C'76,175,80'
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

#property indicator_label7  "EntryPrice"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "StopLevel"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "TakeProfitLevel"
#property indicator_type9   DRAW_NONE

//--- inputs mirroring the Pine script
input int    InpMssSwingLen        = 10;       // MSS swing length (Pine: mssOffset)
input int    InpHigherTimeframeMin = 60;       // Higher timeframe, minutes (Pine: higherTimeframe "60")
input string InpBreakoutMethod     = "Wick";   // Breakout method: Close|Wick
input string InpEntryMethod        = "Classic";// Entry method: Classic|Adaptive
input string InpTpslLayout         = "Default";// TP/SL drawing: Default|Alternative
input bool   InpShowLiqZones       = false;    // Show liquidity zones (Pine: showHL)
input bool   InpShowLiqGrabs       = true;     // Liquidity grab markers (Pine: showLiqGrabs)
input bool   InpShowTPSL           = true;     // TP/SL drawings (Pine: showTPSL)
input string InpTpslMethod         = "Dynamic";// TP/SL method: Dynamic|Fixed
input string InpRisk               = "Low";    // Dynamic risk: Highest|High|Normal|Low|Lowest
input double InpTpPercent          = 0.3;      // Fixed take-profit % (Pine: tpPercent)
input double InpSlPercent          = 0.4;      // Fixed stop-loss % (Pine: slPercent)
input double InpRiskReward         = 0.9;      // Dynamic TP distance = SL distance x RR (Pine: RR)
input bool   InpAlertBuy           = true;     // Buy-signal alerts (Pine: buyAlertEnabled)
input bool   InpAlertSell          = true;     // Sell-signal alerts (Pine: sellAlertEnabled)
input bool   InpAlertTP            = true;     // Take-profit alerts (Pine: tpAlertEnabled)
input bool   InpAlertSL            = true;     // Stop-loss alerts (Pine: slAlertEnabled)
//--- MQL5-side extras (Pine always shows its dashboard / arms alert() post-bootstrap)
input bool   InpShowDashboard       = true;    // Comment() backtest readout (Pine: table)
input bool   InpEnableAlerts        = false;   // Master Alert() switch (default off)

//--- indicator buffers
double ExtBuy[];      // 0: entry price on long-entry bar, else EMPTY
double ExtSell[];     // 1: entry price on short-entry bar, else EMPTY
double ExtTP[];       // 2: exit price on take-profit bar, else EMPTY
double ExtSL[];       // 3: exit price on stop-loss bar, else EMPTY
double ExtSwH[];      // 4: buyside sweep price on sweep bar, else EMPTY
double ExtSwL[];      // 5: sellside sweep price on sweep bar, else EMPTY
double ExtEntryPx[];  // 6: entry price while a setup is open
double ExtSLLvl[];    // 7: SL level while a setup is open
double ExtTPLvl[];    // 8: TP level while a setup is open

#define TSF_MAXBARS   4900   // Pine maxDistanceToLastBar (const)
#define TSF_ATR_LEN   5      // Pine atrLen (const)
#define TSF_MAXDRAWN  125    // Pine redraws the newest 125 setups
#define TSF_OBJ_PREFIX "TSF_"
#define TSF_ARROW_BUY  233
#define TSF_ARROW_SELL 234
#define TSF_ARROW_TP   158   // xcross
#define TSF_ARROW_SL   159   // circle

#define TSF_WAIT_LIQ  0
#define TSF_WAIT_EXEC 1
#define TSF_IN_TRADE  2

//+------------------------------------------------------------------+
//| Setup state (Pine `TurtleSoup` + `Sweep` types, flattened).       |
//+------------------------------------------------------------------+
struct TSF_Setup
  {
   int      state;          // TSF_WAIT_LIQ / TSF_WAIT_EXEC / TSF_IN_TRADE
   datetime startTime;
   datetime lastHour;       // Pine lastHour (snapshot bar time)
   double   hh;             // snapshot range high (EMPTY_VALUE = na)
   double   ll;             // snapshot range low
   bool     hasSweep;
   datetime sweepT0;
   datetime sweepT1;
   int      sweepSide;      // +1 buyside (high), -1 sellside (low)
   double   sweepPrice;
   double   sweepAtr;       // sweep-bar ATR (liquidity-box offsets)
   int      entryType;      // +1 long, -1 short
   bool     hasEntry;
   datetime entryTime;
   double   entryPrice;
   double   entryClose;     // entry-bar close (entry label anchor)
   double   entryAtr;       // entry-bar ATR (box offsets)
   double   sl;
   double   tp;
   bool     hasExit;
   bool     exitIsTP;
   datetime exitTime;
   double   exitPrice;
  };

//+------------------------------------------------------------------+
//| Indicator initialization.                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpMssSwingLen < 1)
     {
      Print("TurtleSoup_FluxCharts: InpMssSwingLen must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpHigherTimeframeMin < 1)
     {
      Print("TurtleSoup_FluxCharts: InpHigherTimeframeMin must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpBreakoutMethod != "Close" && InpBreakoutMethod != "Wick")
     {
      Print("TurtleSoup_FluxCharts: InpBreakoutMethod must be Close|Wick.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpEntryMethod != "Classic" && InpEntryMethod != "Adaptive")
     {
      Print("TurtleSoup_FluxCharts: InpEntryMethod must be Classic|Adaptive.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpTpslMethod != "Dynamic" && InpTpslMethod != "Fixed")
     {
      Print("TurtleSoup_FluxCharts: InpTpslMethod must be Dynamic|Fixed.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpTpslLayout != "Default" && InpTpslLayout != "Alternative")
     {
      Print("TurtleSoup_FluxCharts: InpTpslLayout must be Default|Alternative.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRisk != "Highest" && InpRisk != "High" && InpRisk != "Normal" &&
      InpRisk != "Low" && InpRisk != "Lowest")
     {
      Print("TurtleSoup_FluxCharts: InpRisk must be Highest|High|Normal|Low|Lowest.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, ExtBuy,     INDICATOR_DATA);
   SetIndexBuffer(1, ExtSell,    INDICATOR_DATA);
   SetIndexBuffer(2, ExtTP,      INDICATOR_DATA);
   SetIndexBuffer(3, ExtSL,      INDICATOR_DATA);
   SetIndexBuffer(4, ExtSwH,     INDICATOR_DATA);
   SetIndexBuffer(5, ExtSwL,     INDICATOR_DATA);
   SetIndexBuffer(6, ExtEntryPx, INDICATOR_DATA);
   SetIndexBuffer(7, ExtSLLvl,   INDICATOR_DATA);
   SetIndexBuffer(8, ExtTPLvl,   INDICATOR_DATA);

   ArraySetAsSeries(ExtBuy, true);
   ArraySetAsSeries(ExtSell, true);
   ArraySetAsSeries(ExtTP, true);
   ArraySetAsSeries(ExtSL, true);
   ArraySetAsSeries(ExtSwH, true);
   ArraySetAsSeries(ExtSwL, true);
   ArraySetAsSeries(ExtEntryPx, true);
   ArraySetAsSeries(ExtSLLvl, true);
   ArraySetAsSeries(ExtTPLvl, true);

   PlotIndexSetInteger(0, PLOT_ARROW, TSF_ARROW_BUY);
   PlotIndexSetInteger(1, PLOT_ARROW, TSF_ARROW_SELL);
   PlotIndexSetInteger(2, PLOT_ARROW, TSF_ARROW_TP);
   PlotIndexSetInteger(3, PLOT_ARROW, TSF_ARROW_SL);
   PlotIndexSetInteger(4, PLOT_ARROW, TSF_ARROW_SL);
   PlotIndexSetInteger(5, PLOT_ARROW, TSF_ARROW_SL);
   for(int p = 0; p < 6; p++)
      PlotIndexSetInteger(p, PLOT_ARROW_SHIFT, 0);
   for(int p = 0; p < 9; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!InpShowLiqGrabs)
     {
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Turtle Soup Flux (%d, HTF %dmin, %s/%s)",
                                   InpMssSwingLen, InpHigherTimeframeMin,
                                   InpBreakoutMethod, InpEntryMethod));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Indicator deinitialization.                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, TSF_OBJ_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Dynamic SL multiplier from the Risk input (Pine slATRMult chain). |
//+------------------------------------------------------------------+
double TsfRiskMult()
  {
   if(InpRisk == "Highest")
      return(10.0);
   if(InpRisk == "High")
      return(6.5);
   if(InpRisk == "Normal")
      return(5.5);
   if(InpRisk == "Low")
      return(3.5);
   return(1.15); // Lowest
  }

//+------------------------------------------------------------------+
//| Rolling highest/lowest over `len` bars ending at series index    |
//| `from` (toward older bars). Caller guarantees range validity.    |
//+------------------------------------------------------------------+
double TsfHighest(const double &a[], const int from, const int len)
  {
   double mx = a[from];
   for(int j = 1; j < len; j++)
      if(a[from + j] > mx)
         mx = a[from + j];
   return(mx);
  }

double TsfLowest(const double &a[], const int from, const int len)
  {
   double mn = a[from];
   for(int j = 1; j < len; j++)
      if(a[from + j] < mn)
         mn = a[from + j];
   return(mn);
  }

double TsfDiffPercent(const double v1, const double v2)
  {
   return(MathAbs(v1 - v2) / v2 * 100.0); // Pine diffPercent, verbatim
  }

//+------------------------------------------------------------------+
//| Chart-object helpers (Pine box/line/label drawings).             |
//+------------------------------------------------------------------+
void TsfTrend(const string name, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr,
              const ENUM_LINE_STYLE style, const int width)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
  }

void TsfText(const string name, const datetime t, const double price,
             const string txt, const color clr, const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
  }

void TsfBox(const string name, const datetime t1, const double p1,
            const datetime t2, const double p2, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
  }

//+------------------------------------------------------------------+
//| Main calculation. Mirrors the Pine v5 state machine bar by bar,  |
//| oldest -> newest: one active setup at a time (new setup per bar  |
//| once the previous exited), liquidity sweep, MSS execution,       |
//| fixed/dynamic TP/SL exits with Pine's exact evaluation order.    |
//| Full recompute on every call keeps the path-dependent state      |
//| deterministic (see README notes).                                |
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
//--- (0 = newest). Force price/time arrays to series so the i / i+1 /
//--- i+j lookbacks below read older bars correctly. Without this the state
//--- machine ran time-reversed (future leak) and produced zero entries.
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int chartSec = PeriodSeconds();
   if(chartSec <= 0)
      return(0);
   int htfSec = InpHigherTimeframeMin * 60;
   if(htfSec <= chartSec)
     {
      // Pine raises runtime.error("Higher timeframe must be higher...").
      Print("TurtleSoup_FluxCharts: higher timeframe must exceed chart timeframe.");
      return(0);
     }
   int barLength = htfSec / chartSec; // Pine int(htfMins/tfInMin), truncated
   if(barLength < 1)
      barLength = 1;
   int mss = InpMssSwingLen;
   bool useClose = (InpBreakoutMethod == "Close");
   bool classic = (InpEntryMethod == "Classic");
   bool fixedTPSL = (InpTpslMethod == "Fixed");
   double slMult = TsfRiskMult();

//--- Pine-style persistent state, rebuilt oldest -> newest
   TSF_Setup setups[];
   int nSetups = 0, lastIdx = -1;
   bool hasLast = false;
   int highBreaks = 0, lowBreaks = 0;
   double trSum = 0.0, atrPrev = 0.0;

//--- i is series index (0 = forming bar); k is bar age (0 = oldest)
   for(int i = rates_total - 1; i >= 0; i--)
     {
      int k = rates_total - 1 - i;
      double h = high[i], l = low[i], c = close[i];

      ExtBuy[i] = EMPTY_VALUE;
      ExtSell[i] = EMPTY_VALUE;
      ExtTP[i] = EMPTY_VALUE;
      ExtSL[i] = EMPTY_VALUE;
      ExtSwH[i] = EMPTY_VALUE;
      ExtSwL[i] = EMPTY_VALUE;
      ExtEntryPx[i] = EMPTY_VALUE;
      ExtSLLvl[i] = EMPTY_VALUE;
      ExtTPLvl[i] = EMPTY_VALUE;

      //--- Wilder ATR(atrLen), seeded with SMA of the first atrLen TRs
      double tr;
      if(k == 0)
         tr = h - l;
      else
        {
         double pc = close[i + 1];
         tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
        }
      bool atrValid = (k >= TSF_ATR_LEN - 1);
      double atr = 0.0;
      if(k < TSF_ATR_LEN)
        {
         trSum += tr;
         if(k == TSF_ATR_LEN - 1)
           {
            atr = trSum / TSF_ATR_LEN;
            atrPrev = atr;
           }
        }
      else
        {
         atr = (atrPrev * (TSF_ATR_LEN - 1) + tr) / TSF_ATR_LEN;
         atrPrev = atr;
        }

      //--- rolling windows. Pine ta.highest/lowest use available history on
      //--- early bars (never na); only time[barLength] can be na (here 0).
      int rangeLen = MathMin(barLength, k + 1);
      double high12 = TsfHighest(high, i, rangeLen);
      double low12 = TsfLowest(low, i, rangeLen);
      int mssLen = MathMin(mss, k + 1);
      double highMSS = TsfHighest(high, i, mssLen);
      double lowMSS = TsfLowest(low, i, mssLen);
      int lagLen = MathMin(mss, k); // bars strictly older than the current one
      bool mssLagOK = (lagLen >= 1);
      double highMSS1 = (mssLagOK ? TsfHighest(high, i + 1, lagLen) : EMPTY_VALUE);
      double lowMSS1 = (mssLagOK ? TsfLowest(low, i + 1, lagLen) : EMPTY_VALUE);
      datetime lastHourT = (k >= barLength ? time[i + barLength] : 0);

      //--- Pine: only the NEWEST maxDistanceToLastBar bars run the machine
      //--- (Pine: bar_index > last_bar_index - maxDistance). i is the series
      //--- index (0 = newest), so gate on i. Gating on k (age from oldest)
      //--- kept the oldest bars and blanked the live chart once history
      //--- exceeded 4900 bars (v1.02 fix).
      bool inWindow = (i < TSF_MAXBARS);
      if(!inWindow)
         continue;

      //--- Find Session Start: a fresh setup per bar once the last exited
      if(!hasLast || setups[lastIdx].hasExit)
        {
         if(nSetups >= TSF_MAXBARS + 10)
           {
            Print("TurtleSoup_FluxCharts: setup cap reached, oldest kept.");
            break;
           }
         ArrayResize(setups, nSetups + 1);
         setups[nSetups].state = TSF_WAIT_LIQ;
         setups[nSetups].startTime = time[i];
         setups[nSetups].lastHour = lastHourT;
         setups[nSetups].hh = high12;
         setups[nSetups].ll = low12;
         setups[nSetups].hasSweep = false;
         setups[nSetups].sweepT0 = 0;
         setups[nSetups].sweepT1 = 0;
         setups[nSetups].sweepSide = 0;
         setups[nSetups].sweepPrice = EMPTY_VALUE;
         setups[nSetups].sweepAtr = 0.0;
         setups[nSetups].entryType = 0;
         setups[nSetups].hasEntry = false;
         setups[nSetups].entryTime = 0;
         setups[nSetups].entryPrice = EMPTY_VALUE;
         setups[nSetups].entryClose = 0.0;
         setups[nSetups].entryAtr = 0.0;
         setups[nSetups].sl = EMPTY_VALUE;
         setups[nSetups].tp = EMPTY_VALUE;
         setups[nSetups].hasExit = false;
         setups[nSetups].exitIsTP = false;
         setups[nSetups].exitTime = 0;
         setups[nSetups].exitPrice = EMPTY_VALUE;
         lastIdx = nSetups;
         nSetups++;
         hasLast = true;
        }

      //--- Liquidity break (sellside first, exactly like Pine)
      if(setups[lastIdx].state == TSF_WAIT_LIQ &&
         setups[lastIdx].hh != EMPTY_VALUE && setups[lastIdx].ll != EMPTY_VALUE &&
         time[i] > setups[lastIdx].startTime)
        {
         double sellTrig = (useClose ? c : l);
         double buyTrig = (useClose ? c : h);
         if(sellTrig < setups[lastIdx].ll)
           {
            setups[lastIdx].hasSweep = true;
            setups[lastIdx].sweepT0 = setups[lastIdx].lastHour;
            setups[lastIdx].sweepT1 = time[i];
            setups[lastIdx].sweepSide = -1;
            setups[lastIdx].sweepPrice = setups[lastIdx].ll;
            setups[lastIdx].sweepAtr = atr;
            if(classic || highBreaks > lowBreaks)
               setups[lastIdx].entryType = +1; // Long
            else
               setups[lastIdx].entryType = -1; // Short (Adaptive flip)
            setups[lastIdx].state = TSF_WAIT_EXEC;
            if(InpShowLiqGrabs)
               ExtSwL[i] = setups[lastIdx].ll;
           }
         else if(buyTrig > setups[lastIdx].hh)
           {
            setups[lastIdx].hasSweep = true;
            setups[lastIdx].sweepT0 = setups[lastIdx].lastHour;
            setups[lastIdx].sweepT1 = time[i];
            setups[lastIdx].sweepSide = +1;
            setups[lastIdx].sweepPrice = setups[lastIdx].hh;
            setups[lastIdx].sweepAtr = atr;
            if(classic || highBreaks <= lowBreaks)
               setups[lastIdx].entryType = -1; // Short
            else
               setups[lastIdx].entryType = +1; // Long (Adaptive flip)
            setups[lastIdx].state = TSF_WAIT_EXEC;
            if(InpShowLiqGrabs)
               ExtSwH[i] = setups[lastIdx].hh;
           }
        }

      //--- MSS execution
      if(setups[lastIdx].state == TSF_WAIT_EXEC &&
         time[i] > setups[lastIdx].sweepT1)
        {
         if(setups[lastIdx].entryType == -1)
           {
            double trig = (useClose ? c : l);
            if(lowMSS1 != EMPTY_VALUE && trig < lowMSS1)
              {
               double entryPrice = (useClose ? c : lowMSS1);
               double slT, tpT;
               if(fixedTPSL)
                 {
                  slT = entryPrice * (1.0 + InpSlPercent / 100.0);
                  tpT = entryPrice * (1.0 - InpTpPercent / 100.0);
                 }
               else
                 {
                  if(highMSS == EMPTY_VALUE || !atrValid)
                     slT = EMPTY_VALUE;
                  else
                     slT = highMSS + atr * slMult;
                  tpT = (slT == EMPTY_VALUE ? EMPTY_VALUE :
                         entryPrice - MathAbs(entryPrice - slT) * InpRiskReward);
                 }
               if(slT != EMPTY_VALUE && tpT != EMPTY_VALUE)
                 {
                  setups[lastIdx].hasEntry = true;
                  setups[lastIdx].entryTime = time[i];
                  setups[lastIdx].entryPrice = entryPrice;
                  setups[lastIdx].entryClose = c;
                  setups[lastIdx].entryAtr = atr;
                  setups[lastIdx].sl = slT;
                  setups[lastIdx].tp = tpT;
                  setups[lastIdx].state = TSF_IN_TRADE;
                  ExtSell[i] = entryPrice;
                 }
              }
           }
         else // Long
           {
            double trig = (useClose ? c : h);
            if(highMSS1 != EMPTY_VALUE && trig > highMSS1)
              {
               double entryPrice = (useClose ? c : highMSS1);
               double slT, tpT;
               if(fixedTPSL)
                 {
                  slT = entryPrice * (1.0 - InpSlPercent / 100.0);
                  tpT = entryPrice * (1.0 + InpTpPercent / 100.0);
                 }
               else
                 {
                  if(lowMSS == EMPTY_VALUE || !atrValid)
                     slT = EMPTY_VALUE;
                  else
                     slT = lowMSS - atr * slMult;
                  tpT = (slT == EMPTY_VALUE ? EMPTY_VALUE :
                         entryPrice + MathAbs(entryPrice - slT) * InpRiskReward);
                 }
               if(slT != EMPTY_VALUE && tpT != EMPTY_VALUE)
                 {
                  setups[lastIdx].hasEntry = true;
                  setups[lastIdx].entryTime = time[i];
                  setups[lastIdx].entryPrice = entryPrice;
                  setups[lastIdx].entryClose = c;
                  setups[lastIdx].entryAtr = atr;
                  setups[lastIdx].sl = slT;
                  setups[lastIdx].tp = tpT;
                  setups[lastIdx].state = TSF_IN_TRADE;
                  ExtBuy[i] = entryPrice;
                 }
              }
           }
        }

      //--- Exits: Pine's exact per-branch order (SL can overwrite TP same bar)
      if(setups[lastIdx].state == TSF_IN_TRADE)
        {
         double e = setups[lastIdx].entryPrice;
         bool exitThisBar = false;
         if(fixedTPSL)
           {
            if(setups[lastIdx].entryType == +1 &&
               (h / e - 1.0) * 100.0 >= InpTpPercent)
              {
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = true;
               setups[lastIdx].exitPrice = e * (1.0 + InpTpPercent / 100.0);
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               highBreaks += 1;
              }
            if(setups[lastIdx].entryType == -1 &&
               (l / e - 1.0) * 100.0 <= -InpTpPercent)
              {
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = true;
               setups[lastIdx].exitPrice = e * (1.0 - InpTpPercent / 100.0);
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               lowBreaks += 1;
              }
            if(setups[lastIdx].entryType == +1 &&
               (l / e - 1.0) * 100.0 <= -InpSlPercent)
              {
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = false;
               setups[lastIdx].exitPrice = e * (1.0 - InpSlPercent / 100.0);
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               highBreaks -= 1;
              }
            if(setups[lastIdx].entryType == -1 &&
               (h / e - 1.0) * 100.0 >= InpSlPercent)
              {
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = false;
               setups[lastIdx].exitPrice = e * (1.0 + InpSlPercent / 100.0);
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               lowBreaks -= 1;
              }
           }
         else
           {
            // Dynamic: maxTPLastHour is const false, so TP legs use tpTarget.
            if(setups[lastIdx].entryType == +1 && h >= setups[lastIdx].tp)
              {
               double mx = MathMax(setups[lastIdx].hh, setups[lastIdx].tp);
               double mn = MathMin(setups[lastIdx].hh, setups[lastIdx].tp);
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = true;
               setups[lastIdx].exitPrice = (h >= mx ? mx : mn);
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               highBreaks += 1;
              }
            if(setups[lastIdx].entryType == -1 && l <= setups[lastIdx].tp)
              {
               double mn = MathMin(setups[lastIdx].ll, setups[lastIdx].tp);
               double mx = MathMax(setups[lastIdx].ll, setups[lastIdx].tp);
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = true;
               setups[lastIdx].exitPrice = (l <= mn ? mn : mx);
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               lowBreaks += 1;
              }
            if(setups[lastIdx].entryType == +1 && l <= setups[lastIdx].sl)
              {
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = false;
               setups[lastIdx].exitPrice = setups[lastIdx].sl;
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               highBreaks -= 1;
              }
            if(setups[lastIdx].entryType == -1 && h >= setups[lastIdx].sl)
              {
               setups[lastIdx].hasExit = true;
               setups[lastIdx].exitIsTP = false;
               setups[lastIdx].exitPrice = setups[lastIdx].sl;
               setups[lastIdx].exitTime = time[i];
               exitThisBar = true;
               lowBreaks -= 1;
              }
           }
         // Pine renders one marker from the FINAL state: a same-bar TP+SL
         // pair ends as "Stop Loss", so only the SL marker is drawn.
         if(exitThisBar)
           {
            if(setups[lastIdx].exitIsTP)
               ExtTP[i] = setups[lastIdx].exitPrice;
            else
               ExtSL[i] = setups[lastIdx].exitPrice;
           }
        }

      //--- open-position level buffers (Pine draws TP/SL lines to exitTime)
      if(hasLast && setups[lastIdx].hasEntry)
        {
         ExtEntryPx[i] = setups[lastIdx].entryPrice;
         ExtSLLvl[i] = setups[lastIdx].sl;
         ExtTPLvl[i] = setups[lastIdx].tp;
        }
     }

//--- backtesting dashboard (Pine table; here Comment(), same formulas)
   double totalProfit = 0.0;
   int wins = 0, losses = 0;
   for(int s = 0; s < nSetups; s++)
     {
      if(!setups[s].hasEntry)
         continue;
      bool isSuccess = false;
      if(setups[s].hasExit)
        {
         if((setups[s].entryType == +1 && setups[s].exitPrice > setups[s].entryPrice) ||
            (setups[s].entryType == -1 && setups[s].exitPrice < setups[s].entryPrice))
           {
            totalProfit += MathAbs(TsfDiffPercent(setups[s].entryPrice, setups[s].exitPrice));
            isSuccess = true;
           }
         else
            totalProfit -= MathAbs(TsfDiffPercent(setups[s].entryPrice, setups[s].exitPrice));
        }
      // NOTE: like Pine, an open (unexited) trade counts as a loss here.
      if(isSuccess)
         wins++;
      else
         losses++;
     }
   if(InpShowDashboard)
     {
      int total = wins + losses;
      string winRate = (total > 0 ? DoubleToString(100.0 * wins / total, 2) + "%" : "n/a");
      string avgProfit = (total > 0 ? DoubleToString(totalProfit / total, 2) + "%" : "n/a");
      Comment(StringFormat("TS Backtesting\nTotal Entries: %d\nWins: %d\nLosses: %d\n" +
                           "Winrate: %s\nAverage Profit: %s\nTotal Profit: %s%%",
                           total, wins, losses, winRate, avgProfit,
                           DoubleToString(totalProfit, 2)));
     }
   else
      Comment("");

//--- drawings for the newest TSF_MAXDRAWN setups (Pine redraws on confirmed
//--- bars; here rebuilt when a new bar forms or history changes).
   static datetime lastBuiltBar = 0;
   static int lastBuiltTotal = 0;
   if(prev_calculated == 0 || time[0] != lastBuiltBar || rates_total != lastBuiltTotal)
     {
      lastBuiltBar = time[0];
      lastBuiltTotal = rates_total;
      ObjectsDeleteAll(0, TSF_OBJ_PREFIX);
      int drawn = 0;
      for(int s = nSetups - 1; s >= 0 && drawn < TSF_MAXDRAWN; s--)
        {
         drawn++;
         string tag = StringFormat("%sS%d_", TSF_OBJ_PREFIX, (long)setups[s].startTime);
         //--- target-liquidity zone (Pine box; MQL5 rectangle, see README F5)
         if(InpShowLiqZones && setups[s].hasSweep && setups[s].sweepT0 != 0)
           {
            double off = setups[s].sweepAtr / 3.0;
            if(setups[s].sweepSide == +1)
               TsfBox(tag + "liq", setups[s].sweepT0, setups[s].hh + off,
                      setups[s].sweepT1, setups[s].hh - off, C'76,175,80');
            else
               TsfBox(tag + "liq", setups[s].sweepT0, setups[s].ll + off,
                      setups[s].sweepT1, setups[s].ll - off, C'255,82,82');
           }
         if(!setups[s].hasEntry)
            continue;
         //--- entry label (Pine: Buy/Sell label at entry bar)
         if(setups[s].entryType == +1)
            TsfText(tag + "entry", setups[s].entryTime, setups[s].entryClose,
                    "Buy", C'76,175,80', ANCHOR_UPPER);
         else
            TsfText(tag + "entry", setups[s].entryTime, setups[s].entryClose,
                    "Sell", C'255,82,82', ANCHOR_LOWER);
         //--- TP/SL drawings
         if(!InpShowTPSL)
            continue;
         datetime endT = (setups[s].hasExit ? setups[s].exitTime : time[0]);
         double off = setups[s].entryAtr / 3.0;
         if(InpTpslLayout == "Alternative")
           {
            TsfBox(tag + "tp", setups[s].entryTime, setups[s].tp + off,
                   endT, setups[s].tp - off, C'76,175,80');
            TsfBox(tag + "sl", setups[s].entryTime, setups[s].sl + off,
                   endT, setups[s].sl - off, C'255,82,82');
           }
         else
           {
            TsfTrend(tag + "ev", setups[s].entryTime, setups[s].entryPrice,
                     setups[s].entryTime, setups[s].tp, C'76,175,80',
                     STYLE_DASH, 1);
            TsfTrend(tag + "tp", setups[s].entryTime, setups[s].tp,
                     endT, setups[s].tp, C'76,175,80', STYLE_DASH, 1);
            TsfText(tag + "tpl", endT, setups[s].tp,
                    "TP", C'76,175,80', ANCHOR_LEFT);
            TsfTrend(tag + "es", setups[s].entryTime, setups[s].entryPrice,
                     setups[s].entryTime, setups[s].sl, C'255,82,82',
                     STYLE_DASH, 1);
            TsfTrend(tag + "sl", setups[s].entryTime, setups[s].sl,
                     endT, setups[s].sl, C'255,82,82', STYLE_DASH, 1);
            TsfText(tag + "sll", endT, setups[s].sl,
                    "SL", C'255,82,82', ANCHOR_LEFT);
           }
        }
     }

//--- alerts on the last closed bar only. The bootstrap bar is skipped
//--- (Pine initRun / islastconfirmedhistory equivalent), then each enabled
//--- type fires once via Alert() behind the master switch.
   if(rates_total >= 2)
     {
      static bool primed = false;
      static datetime initClosedBar = 0;
      static datetime lastAlertBar = 0;
      if(!primed)
        {
         initClosedBar = time[1];
         primed = true;
        }
      if(InpEnableAlerts && time[1] != initClosedBar && time[1] != lastAlertBar)
        {
         bool fired = false;
         if(ExtBuy[1] != EMPTY_VALUE && InpAlertBuy)
           {
            Alert(StringFormat("Turtle Soup Flux BUY %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(ExtBuy[1], _Digits)));
            fired = true;
           }
         if(ExtSell[1] != EMPTY_VALUE && InpAlertSell)
           {
            Alert(StringFormat("Turtle Soup Flux SELL %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(ExtSell[1], _Digits)));
            fired = true;
           }
         if(ExtTP[1] != EMPTY_VALUE && InpAlertTP)
           {
            Alert(StringFormat("Turtle Soup Flux TAKE-PROFIT %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(ExtTP[1], _Digits)));
            fired = true;
           }
         if(ExtSL[1] != EMPTY_VALUE && InpAlertSL)
           {
            Alert(StringFormat("Turtle Soup Flux STOP-LOSS %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(ExtSL[1], _Digits)));
            fired = true;
           }
         if(fired)
            lastAlertBar = time[1];
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
