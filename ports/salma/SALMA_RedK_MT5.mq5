//+------------------------------------------------------------------+
//|                                              SALMA_RedK_MT5.mq5 |
//| Original MQL5 INDICATOR port of the SALMA trend concept          |
//| (Smooth And Lazy Moving Average).                                |
//|                                                                  |
//| Original concept and Pine Script by RedKTrader:                  |
//| https://www.tradingview.com/script/JWdrXD3I-RedK-Smooth-And-Lazy-Moving-Average-SALMA/ |
//|                                                                  |
//| This MQL5 file is ORIGINAL code written from a short algorithm   |
//| description (see README.md). It does not contain text copied     |
//| from the Pine Script source or from any other script, hidden,    |
//| protected, invite-only or otherwise. No protected script was     |
//| retrieved for this port.                                         |
//|                                                                  |
//| Copyright (C) 2026, MQL5 port contributor (W7-PINE SALMA worker  |
//| session). Original indicator concept Copyright RedKTrader.       |
//|                                                                  |
//| This Source Code Form is subject to the terms of the Mozilla     |
//| Public License, v. 2.0, matching the original page source        |
//| header. A copy of the MPL-2.0 is in the LICENSE file.           |
//|                                                                  |
//| SPDX-License-Identifier: MPL-2.0                                 |
//+------------------------------------------------------------------+
#property copyright   "Original concept (c) RedKTrader; MQL5 port MPL-2.0"
#property link        "https://www.tradingview.com/script/JWdrXD3I-RedK-Smooth-And-Lazy-Moving-Average-SALMA/"
#property version     "1.00"
#property description "SALMA (RedKTrader) smoothing indicator port for MT5. See README.md / CREDITS.md."
#property description "Inputs mirror the Pine v5 script: price, length, smooth, mult, sd_len, MA1/MA2."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   5

#property indicator_label1  "SALMA REMA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'76,175,80',C'255,82,82'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "MA1"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'128,0,128'
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "MA2"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'0,0,255'
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "SwingUp"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  C'76,175,80'
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "SwingDn"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  C'255,82,82'
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

//--- MA method choices for the optional overlays (Pine: SMA/EMA/WMA)
enum SalmaMaMethod
  {
   Salma_SMA = 0,   // SMA
   Salma_EMA = 1,   // EMA
   Salma_WMA = 2    // WMA (MQL5 LWMA equivalent)
  };

//--- inputs mirroring the Pine v5 script defaults
input ENUM_APPLIED_PRICE InpPrice      = PRICE_CLOSE; // Price source (Pine: price=close)
input int                InpLength    = 10;           // REMA inner WMA length (Pine: length=10)
input int                InpSmooth    = 3;            // REMA outer WMA smoothing (Pine: smooth=3)
input double             InpMult      = 0.3;          // Band multiplier (Pine: mult=.3)
input int                InpSdLen     = 5;            // Baseline/stdev window (Pine: sd_len=5)
input bool               InpShowMA1   = false;        // Show MA1 overlay (Pine: hidden by default)
input SalmaMaMethod      InpMA1Method = Salma_SMA;    // MA1 method (Pine: SMA/EMA/WMA)
input int                InpMA1Length = 50;           // MA1 length, source close (Pine: 50)
input bool               InpShowMA2   = false;        // Show MA2 overlay (Pine: hidden by default)
input SalmaMaMethod      InpMA2Method = Salma_SMA;    // MA2 method (Pine: SMA/EMA/WMA)
input int                InpMA2Length = 100;          // MA2 length, source close (Pine: 100)
//--- MQL5-side extra (Pine alertconditions are always armed)
input bool               InpEnableAlerts = false;     // Alert() once per newly closed swing bar (opt-in)

//--- indicator buffers
double ExtRema[];       // 0: REMA line
double ExtRemaColor[];  // 1: REMA color index (0 green = rising, 1 red = otherwise)
double ExtMA1[];        // 2: MA1 overlay (close, fixed source)
double ExtMA2[];        // 3: MA2 overlay (close, fixed source)
double ExtUp[];         // 4: SwingUp marker at REMA value
double ExtDn[];         // 5: SwingDn marker at REMA value

#define SALMA_ARROW_UP   233   // Wingdings up triangle
#define SALMA_ARROW_DN   234   // Wingdings down triangle

//+------------------------------------------------------------------+
//| Price-source selector (Pine: price input, default close).        |
//+------------------------------------------------------------------+
double SalmaPriceAt(const int i,
                    const double &open[],
                    const double &high[],
                    const double &low[],
                    const double &close[])
  {
   switch(InpPrice)
     {
      case PRICE_OPEN:     return(open[i]);
      case PRICE_HIGH:     return(high[i]);
      case PRICE_LOW:      return(low[i]);
      case PRICE_MEDIAN:   return((high[i] + low[i]) / 2.0);
      case PRICE_TYPICAL:  return((high[i] + low[i] + close[i]) / 3.0);
      case PRICE_WEIGHTED: return((high[i] + low[i] + close[i] + close[i]) / 4.0);
      default:             return(close[i]);
     }
  }

//+------------------------------------------------------------------+
//| Pine ta.wma equivalent on a series array. Most recent bar (i)    |
//| carries weight len; bars i..i+len-1 are used. EMPTY_VALUE when   |
//| the window is incomplete (Pine returns na there).                |
//+------------------------------------------------------------------+
double SalmaWmaAt(const double &a[], const int i, const int len, const int total)
  {
   if(len < 1 || i < 0 || i + len > total)
      return(EMPTY_VALUE);
   double num = 0.0;
   for(int m = 0; m < len; m++)
     {
      if(a[i + m] == EMPTY_VALUE)
         return(EMPTY_VALUE);
      num += a[i + m] * (len - m);
     }
   return(num / (len * (len + 1) / 2.0));
  }

//+------------------------------------------------------------------+
//| Pine ta.stdev (population, biased) equivalent on a series array. |
//+------------------------------------------------------------------+
double SalmaStdevPopAt(const double &a[], const int i, const int len, const int total)
  {
   if(len < 1 || i < 0 || i + len > total)
      return(EMPTY_VALUE);
   double sum = 0.0;
   for(int m = 0; m < len; m++)
     {
      if(a[i + m] == EMPTY_VALUE)
         return(EMPTY_VALUE);
      sum += a[i + m];
     }
   double mean = sum / len;
   double sq = 0.0;
   for(int m = 0; m < len; m++)
     {
      double d = a[i + m] - mean;
      sq += d * d;
     }
   return(MathSqrt(sq / len));
  }

//+------------------------------------------------------------------+
//| Indicator initialization.                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLength < 1 || InpSmooth < 1 || InpSdLen < 1 || InpMA1Length < 1 || InpMA2Length < 1)
     {
      Print("SALMA_RedK_MT5: length/smooth/sd_len/MA lengths must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, ExtRema,      INDICATOR_DATA);
   SetIndexBuffer(1, ExtRemaColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, ExtMA1,        INDICATOR_DATA);
   SetIndexBuffer(3, ExtMA2,        INDICATOR_DATA);
   SetIndexBuffer(4, ExtUp,         INDICATOR_DATA);
   SetIndexBuffer(5, ExtDn,         INDICATOR_DATA);

   ArraySetAsSeries(ExtRema, true);
   ArraySetAsSeries(ExtRemaColor, true);
   ArraySetAsSeries(ExtMA1, true);
   ArraySetAsSeries(ExtMA2, true);
   ArraySetAsSeries(ExtUp, true);
   ArraySetAsSeries(ExtDn, true);

   PlotIndexSetInteger(3, PLOT_ARROW, SALMA_ARROW_UP);
   PlotIndexSetInteger(4, PLOT_ARROW, SALMA_ARROW_DN);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 0);

   for(int p = 0; p < 5; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!InpShowMA1)
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
   if(!InpShowMA2)
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("SALMA RedK (%d,%d,%.2f,%d)",
                                   InpLength, InpSmooth, InpMult, InpSdLen));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Main calculation. Full oldest->newest recompute keeps the        |
//| windowed state deterministic; no prev_calculated shortcut.       |
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

//--- Align indexing: OnCalculate price/time arrays arrive non-series
//--- (index 0 = oldest) while indicator buffers are series in OnInit
//--- (index 0 = newest). Force series so the i / i+m window lookbacks
//--- below read older bars correctly (same guard as the HalfTrend fix).
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

//--- Working arrays (series, same orientation as inputs/buffers).
   double src[];
   double base[];
   double cprice[];
   double inner[];
   double rema[];
   ArrayResize(src, rates_total);
   ArrayResize(base, rates_total);
   ArrayResize(cprice, rates_total);
   ArrayResize(inner, rates_total);
   ArrayResize(rema, rates_total);
   ArraySetAsSeries(src, true);
   ArraySetAsSeries(base, true);
   ArraySetAsSeries(cprice, true);
   ArraySetAsSeries(inner, true);
   ArraySetAsSeries(rema, true);

//--- Pass 1: price source.
   for(int i = rates_total - 1; i >= 0; i--)
      src[i] = SalmaPriceAt(i, open, high, low, close);

//--- Pass 2: baseline = WMA(price, sd_len); bands = baseline +/- mult * stdev_pop(price, sd_len).
   for(int i = rates_total - 1; i >= 0; i--)
     {
      base[i] = SalmaWmaAt(src, i, InpSdLen, rates_total);
      double sd = SalmaStdevPopAt(src, i, InpSdLen, rates_total);
      if(base[i] == EMPTY_VALUE || sd == EMPTY_VALUE)
         cprice[i] = EMPTY_VALUE;
      else
        {
         double upper = base[i] + InpMult * sd;
         double lower = base[i] - InpMult * sd;
         double p = src[i];
         cprice[i] = (p > upper ? upper : (p < lower ? lower : p));
        }
     }

//--- Pass 3: REMA = WMA(WMA(cprice, length), smooth).
   for(int i = rates_total - 1; i >= 0; i--)
      inner[i] = SalmaWmaAt(cprice, i, InpLength, rates_total);
   for(int i = rates_total - 1; i >= 0; i--)
      rema[i] = SalmaWmaAt(inner, i, InpSmooth, rates_total);

//--- Pass 4: optional MA overlays on close (fixed source, Pine default).
//--- EMA runs oldest -> newest with an SMA seed, exactly like Pine ta.ema.
   double ema1Sum = 0.0, ema1Val = 0.0, ema2Sum = 0.0, ema2Val = 0.0;
   int ema1Cnt = 0, ema2Cnt = 0;
   bool ema1Init = false, ema2Init = false;
   double sma1Sum = 0.0, sma2Sum = 0.0;
   double a1 = 2.0 / (InpMA1Length + 1.0);
   double a2 = 2.0 / (InpMA2Length + 1.0);

//--- Pass 5: outputs oldest -> newest (series index i, age k).
   for(int i = rates_total - 1; i >= 0; i--)
     {
      int k = rates_total - 1 - i;

      //--- MA overlays (running state, oldest -> newest order of this loop).
      double c = close[i];
      double ma1 = EMPTY_VALUE, ma2 = EMPTY_VALUE;
      if(InpShowMA1)
        {
         if(InpMA1Method == Salma_SMA)
           {
            sma1Sum += c;
            if(k >= InpMA1Length)
               sma1Sum -= close[i + InpMA1Length];
            if(k >= InpMA1Length - 1)
               ma1 = sma1Sum / InpMA1Length;
           }
         else if(InpMA1Method == Salma_WMA)
            ma1 = SalmaWmaAt(close, i, InpMA1Length, rates_total);
         else
           {
            if(!ema1Init)
              {
               ema1Sum += c;
               ema1Cnt++;
               if(ema1Cnt == InpMA1Length)
                 {
                  ema1Val = ema1Sum / InpMA1Length;
                  ema1Init = true;
                  ma1 = ema1Val;
                 }
              }
            else
              {
               ema1Val = a1 * c + (1.0 - a1) * ema1Val;
               ma1 = ema1Val;
              }
           }
        }
      if(InpShowMA2)
        {
         if(InpMA2Method == Salma_SMA)
           {
            sma2Sum += c;
            if(k >= InpMA2Length)
               sma2Sum -= close[i + InpMA2Length];
            if(k >= InpMA2Length - 1)
               ma2 = sma2Sum / InpMA2Length;
           }
         else if(InpMA2Method == Salma_WMA)
            ma2 = SalmaWmaAt(close, i, InpMA2Length, rates_total);
         else
           {
            if(!ema2Init)
              {
               ema2Sum += c;
               ema2Cnt++;
               if(ema2Cnt == InpMA2Length)
                 {
                  ema2Val = ema2Sum / InpMA2Length;
                  ema2Init = true;
                  ma2 = ema2Val;
                 }
              }
            else
              {
               ema2Val = a2 * c + (1.0 - a2) * ema2Val;
               ma2 = ema2Val;
              }
           }
        }

      //--- REMA color and swing markers. Green only on strict rise;
      //--- red otherwise (Pine: green if REMA > REMA[1], red otherwise).
      bool curOk  = (rema[i] != EMPTY_VALUE);
      bool prevOk = (i + 1 < rates_total && rema[i + 1] != EMPTY_VALUE);
      bool green = (curOk && prevOk && rema[i] > rema[i + 1]);
      bool greenPrev = false;
      if(prevOk && i + 2 < rates_total && rema[i + 2] != EMPTY_VALUE)
         greenPrev = (rema[i + 1] > rema[i + 2]);
      //--- Undefined predecessors read as not-green (Pine: na comparison
      //--- is not true), so the first defined bar can still seed a swing.
      bool swingUp = (curOk && prevOk && green && !greenPrev);
      bool swingDn = (curOk && prevOk && !green && greenPrev);

      ExtRema[i]      = (curOk ? rema[i] : EMPTY_VALUE);
      ExtRemaColor[i] = (green ? 0 : 1);
      ExtMA1[i]       = ma1;
      ExtMA2[i]       = ma2;
      ExtUp[i]        = (swingUp ? rema[i] : EMPTY_VALUE);
      ExtDn[i]        = (swingDn ? rema[i] : EMPTY_VALUE);
     }

//--- Alerts on the last closed bar only (Pine SwingUp/SwingDn alertconditions).
   if(InpEnableAlerts && rates_total >= 3)
     {
      static datetime lastAlertBar = 0;
      if(time[1] != lastAlertBar)
        {
         if(ExtUp[1] != EMPTY_VALUE)
           {
            Alert(StringFormat("SALMA RedK SwingUp %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(close[1], _Digits)));
            lastAlertBar = time[1];
           }
         else if(ExtDn[1] != EMPTY_VALUE)
           {
            Alert(StringFormat("SALMA RedK SwingDn %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(close[1], _Digits)));
            lastAlertBar = time[1];
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
