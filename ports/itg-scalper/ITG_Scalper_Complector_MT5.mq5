//+------------------------------------------------------------------+
//|                                        ITG_Scalper_Complector_MT5.mq5 |
//| Original MQL5 INDICATOR port of the ITG Scalper trend concept.   |
//|                                                                  |
//| Original concept and Pine Script by Complector:                  |
//| https://www.tradingview.com/script/AcrZjl6Q-ITG-Scalper/         |
//|                                                                  |
//| This MQL5 file is ORIGINAL code written from a short algorithm   |
//| description (see README.md). It does not contain text copied     |
//| from the Pine Script source or from any other script, hidden,    |
//| protected, invite-only or otherwise. No protected script was     |
//| retrieved for this port.                                         |
//|                                                                  |
//| Copyright (C) 2026, MQL5 port contributor (W7-PINE ITG worker    |
//| session). Original indicator concept Copyright Complector.       |
//|                                                                  |
//| This Source Code Form is subject to the terms of the Mozilla     |
//| Public License, v. 2.0, matching the original page source        |
//| header. A copy of the MPL-2.0 is in the LICENSE file.           |
//|                                                                  |
//| SPDX-License-Identifier: MPL-2.0                                 |
//+------------------------------------------------------------------+
#property copyright   "Original concept (c) Complector; MQL5 port MPL-2.0"
#property link        "https://www.tradingview.com/script/AcrZjl6Q-ITG-Scalper/"
#property version     "1.00"
#property description "ITG Scalper (Complector) TEMA/MACD-filter indicator port for MT5. See README.md / CREDITS.md."
#property description "Inputs mirror the Pine v4 script: TEMA period, EMA filter, signal, toggles."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

#property indicator_label1  "ITG TEMA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'0,255,0',C'255,0,0',C'0,255,255'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'0,255,0'
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  C'255,0,0'
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- inputs mirroring the Pine v4 script defaults
input int            InpTemaPeriod   = 14;          // TEMA period (Pine: 14)
input bool           InpFilterOn     = true;        // Noise filter on/off (Pine: filter on)
input int            InpFastLen      = 12;          // Filter fast EMA(close) length (Pine: 12)
input int            InpSlowLen      = 26;          // Filter slow EMA(close) length (Pine: 26)
input int            InpSignalLen    = 9;           // Signal SMA(MACD) length (Pine: 9)
input bool           InpUseCurrentTF = true;        // Use current timeframe for filter (Pine: true)
input ENUM_TIMEFRAMES InpAlternateTF = PERIOD_H1;   // Alternate filter TF, minutes (Pine: 60; RESERVED, chart TF only, see README L1)
input bool           InpUseColorChange = true;      // TEMA colour shift on/off (Pine: on; off = aqua line)
input bool           InpShowArrows   = true;        // Show buy/sell arrows (Pine: toggle)
input bool           InpShowLabels   = true;        // Show Buy/Sell text labels (Pine: toggle)
//--- MQL5-side extra (Pine alert() calls are always armed)
input bool           InpEnableAlerts = false;       // Alert() once per newly closed signal bar (opt-in)

//--- indicator buffers
double ExtTema[];       // 0: TEMA line
double ExtTemaColor[];  // 1: TEMA color index (0 lime up, 1 red down, 2 aqua = shift off)
double ExtBuy[];        // 2: buy arrow at bar low
double ExtSell[];       // 3: sell arrow at bar high

#define ITG_OBJ_PREFIX "ITG_Scalper_"
#define ITG_ARROW_BUY  233   // Wingdings up triangle
#define ITG_ARROW_SELL 234   // Wingdings down triangle

//+------------------------------------------------------------------+
//| EMA pass over a series array, oldest -> newest, first-value      |
//| seeded like Pine ema(): the first non-EMPTY_VALUE source bar     |
//| becomes the seed, then ema = alpha * x + (1 - alpha) * ema with  |
//| alpha = 2 / (period + 1). Gaps (EMPTY_VALUE) stay EMPTY and do   |
//| not start, reset, or advance the seed.                           |
//+------------------------------------------------------------------+
void ItgEmaInto(const double &in[], double &out[], const int total, const int period)
  {
   double alpha = 2.0 / (period + 1.0);
   double ema = 0.0;
   bool init = false;
   for(int i = total - 1; i >= 0; i--)
     {
      double x = in[i];
      if(x == EMPTY_VALUE)
        {
         out[i] = EMPTY_VALUE;
         continue;
        }
      if(!init)
        {
         ema = x;
         init = true;
         out[i] = ema;
        }
      else
        {
         ema = alpha * x + (1.0 - alpha) * ema;
         out[i] = ema;
        }
     }
  }

//+------------------------------------------------------------------+
//| SMA pass over a series array (full window required, else EMPTY). |
//+------------------------------------------------------------------+
void ItgSmaInto(const double &in[], double &out[], const int total, const int period)
  {
   double sum = 0.0;
   for(int i = total - 1; i >= 0; i--)
     {
      if(i + period > total)
        {
         out[i] = EMPTY_VALUE;
         continue;
        }
      sum = 0.0;
      bool ok = true;
      for(int m = 0; m < period; m++)
        {
         if(in[i + m] == EMPTY_VALUE)
           {
            ok = false;
            break;
           }
         sum += in[i + m];
        }
      out[i] = (ok ? sum / period : EMPTY_VALUE);
     }
  }

//+------------------------------------------------------------------+
//| Create or refresh one Buy/Sell text label chart object.          |
//+------------------------------------------------------------------+
void EnsureItgLabel(const string name, const datetime t, const double price,
                    const string text, const color clr, const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, (long)t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
  }

//+------------------------------------------------------------------+
//| Indicator initialization.                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpTemaPeriod < 1 || InpFastLen < 1 || InpSlowLen < 1 || InpSignalLen < 1)
     {
      Print("ITG_Scalper_Complector_MT5: period lengths must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, ExtTema,      INDICATOR_DATA);
   SetIndexBuffer(1, ExtTemaColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, ExtBuy,       INDICATOR_DATA);
   SetIndexBuffer(3, ExtSell,      INDICATOR_DATA);

   ArraySetAsSeries(ExtTema, true);
   ArraySetAsSeries(ExtTemaColor, true);
   ArraySetAsSeries(ExtBuy, true);
   ArraySetAsSeries(ExtSell, true);

   PlotIndexSetInteger(1, PLOT_ARROW, ITG_ARROW_BUY);
   PlotIndexSetInteger(2, PLOT_ARROW, ITG_ARROW_SELL);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 0);

   for(int p = 0; p < 3; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!InpShowArrows)
     {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("ITG Scalper Complector (%d)", InpTemaPeriod));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   if(!InpShowLabels)
      ObjectsDeleteAll(0, ITG_OBJ_PREFIX);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Indicator deinitialization: remove our text label objects.       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, ITG_OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
//| Main calculation. Full oldest->newest recompute keeps the        |
//| path-dependent last_tran state deterministic. TEMA and the MACD  |
//| filter run on the chart timeframe only (see README L1).          |
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
//--- and the i+1 "previous bar" reads below are correct (same guard
//--- as the HalfTrend time-reversal fix).
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

//--- Working arrays (series).
   double fast[], slow[], macd[], sig[];
   double e1[], e2[], e3[], tema[];
   ArrayResize(fast, rates_total);
   ArrayResize(slow, rates_total);
   ArrayResize(macd, rates_total);
   ArrayResize(sig, rates_total);
   ArrayResize(e1, rates_total);
   ArrayResize(e2, rates_total);
   ArrayResize(e3, rates_total);
   ArrayResize(tema, rates_total);
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(sig, true);
   ArraySetAsSeries(e1, true);
   ArraySetAsSeries(e2, true);
   ArraySetAsSeries(e3, true);
   ArraySetAsSeries(tema, true);

//--- MACD noise filter on chart close (Pine: fast EMA 12, slow EMA 26,
//--- MACD = fast - slow, signal = SMA(MACD, 9)).
   ItgEmaInto(close, fast, rates_total, InpFastLen);
   ItgEmaInto(close, slow, rates_total, InpSlowLen);
   for(int i = rates_total - 1; i >= 0; i--)
      macd[i] = ((fast[i] != EMPTY_VALUE && slow[i] != EMPTY_VALUE)
                 ? fast[i] - slow[i] : EMPTY_VALUE);
   ItgSmaInto(macd, sig, rates_total, InpSignalLen);

//--- TEMA = 3 * (EMA1 - EMA2) + EMA3 (triple smoothing of close).
   ItgEmaInto(close, e1, rates_total, InpTemaPeriod);
   ItgEmaInto(e1, e2, rates_total, InpTemaPeriod);
   ItgEmaInto(e2, e3, rates_total, InpTemaPeriod);
   for(int i = rates_total - 1; i >= 0; i--)
      tema[i] = ((e1[i] != EMPTY_VALUE && e2[i] != EMPTY_VALUE && e3[i] != EMPTY_VALUE)
                 ? 3.0 * (e1[i] - e2[i]) + e3[i] : EMPTY_VALUE);

//--- Pine persistent state, rebuilt oldest -> newest: last_tran starts
//--- false; long first, then short (branches are mutually exclusive).
   bool last_tran = false;

   for(int i = rates_total - 1; i >= 0; i--)
     {
      bool temaOk = (tema[i] != EMPTY_VALUE && i + 1 < rates_total &&
                     tema[i + 1] != EMPTY_VALUE);
      bool up = (temaOk && tema[i] >= tema[i + 1]);

      bool macdOk = (macd[i] != EMPTY_VALUE && sig[i] != EMPTY_VALUE);
      bool longGate  = (!InpFilterOn) || (macdOk && macd[i] >= sig[i]);
      bool shortGate = (!InpFilterOn) || (macdOk && macd[i] < sig[i]);

      double buyAt = EMPTY_VALUE, sellAt = EMPTY_VALUE;
      if(temaOk)
        {
         if(up && !last_tran && longGate)
           {
            buyAt = low[i];
            last_tran = true;   // Pine: last_tran := true, buyprice := close
           }
         else if(!up && last_tran && shortGate)
           {
            sellAt = high[i];
            last_tran = false;  // Pine: last_tran := false, sellprice := close
           }
        }

      double col = 2;  // aqua default (colour shift off)
      if(InpUseColorChange)
         col = (temaOk ? (up ? 0 : 1) : 1);

      ExtTema[i]      = (tema[i] != EMPTY_VALUE ? tema[i] : EMPTY_VALUE);
      ExtTemaColor[i] = col;
      ExtBuy[i]       = buyAt;
      ExtSell[i]      = sellAt;

      if(InpShowLabels)
        {
         string buyName  = ITG_OBJ_PREFIX + "Buy_" + IntegerToString((long)time[i]);
         string sellName = ITG_OBJ_PREFIX + "Sell_" + IntegerToString((long)time[i]);
         if(buyAt != EMPTY_VALUE)
            EnsureItgLabel(buyName, time[i], buyAt, "Buy", C'0,255,0', ANCHOR_UPPER);
         else if(i == 0)
            ObjectDelete(0, buyName);
         if(sellAt != EMPTY_VALUE)
            EnsureItgLabel(sellName, time[i], sellAt, "Sell", C'255,0,0', ANCHOR_LOWER);
         else if(i == 0)
            ObjectDelete(0, sellName);
        }
     }

//--- Alerts on the last closed bar only (Pine alert() buy/sell equivalent).
   if(InpEnableAlerts && rates_total >= 2)
     {
      static datetime lastAlertBar = 0;
      if(time[1] != lastAlertBar)
        {
         if(ExtBuy[1] != EMPTY_VALUE)
           {
            Alert(StringFormat("ITG Scalper BUY %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(close[1], _Digits)));
            lastAlertBar = time[1];
           }
         else if(ExtSell[1] != EMPTY_VALUE)
           {
            Alert(StringFormat("ITG Scalper SELL %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(close[1], _Digits)));
            lastAlertBar = time[1];
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
