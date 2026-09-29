//+------------------------------------------------------------------+
//|                                        HalfTrend_Everget_MT5.mq5 |
//| Original MQL5 indicator port of the HalfTrend trend concept      |
//|                                                                  |
//| Original concept and Pine Script by Alex Orekhov (everget):      |
//| https://www.tradingview.com/script/U1SJ8ubc-HalfTrend-everget/   |
//|                                                                  |
//| This MQL5 file is ORIGINAL code written from a short algorithm   |
//| summary. It does not contain text copied from the Pine Script    |
//| source or from any other script.                                 |
//|                                                                  |
//| Copyright (C) 2026, MQL5 port contributor (W7-PINE port 1).      |
//| Original indicator concept Copyright (c) 2021-present,           |
//| Alex Orekhov (everget).                                          |
//|                                                                  |
//| This program is free software: you can redistribute it and/or    |
//| modify it under the terms of the GNU General Public License     |
//| as published by the Free Software Foundation, either version 3  |
//| of the License, or (at your option) any later version.           |
//|                                                                  |
//| This program is distributed in the hope that it will be useful,  |
//| but WITHOUT ANY WARRANTY; without even the implied warranty of  |
//| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the     |
//| GNU General Public License (LICENSE file) for more details.      |
//|                                                                  |
//| SPDX-License-Identifier: GPL-3.0-or-later                        |
//+------------------------------------------------------------------+
#property copyright   "Original concept (c) 2021-present Alex Orekhov (everget); MQL5 port GPL-3.0"
#property link        "https://www.tradingview.com/script/U1SJ8ubc-HalfTrend-everget/"
#property version     "1.01"
#property description "HalfTrend (everget) ATR trend indicator port for MT5. See README.md / CREDITS.md."
#property description "Inputs mirror the Pine script: amplitude, channelDeviation, show toggles."
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   9

#property indicator_label1  "HalfTrend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'41,98,255',C'255,82,82'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "ATR High"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  C'41,98,255',C'255,82,82'
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "ATR Low"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_color3  C'41,98,255',C'255,82,82'
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

#property indicator_label4  "Buy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  C'41,98,255'
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "Sell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  C'255,82,82'
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "Ribbon Up High"
#property indicator_type6   DRAW_FILLING
#property indicator_color6  C'41,98,255'

#property indicator_label7  "Ribbon Up Low"
#property indicator_type7   DRAW_FILLING
#property indicator_color7  C'41,98,255'

#property indicator_label8  "Ribbon Dn High"
#property indicator_type8   DRAW_FILLING
#property indicator_color8  C'255,82,82'

#property indicator_label9  "Ribbon Dn Low"
#property indicator_type9   DRAW_FILLING
#property indicator_color9  C'255,82,82'

//--- inputs mirroring the Pine script
input int    InpAmplitude        = 2;     // Amplitude (Pine: amplitude)
input double InpChannelDeviation = 2.0;   // Channel deviation multiplier (Pine: channelDeviation)
input bool   InpShowArrows       = true;  // Show buy/sell triangle arrows (Pine: showArrows)
input bool   InpShowChannels     = true;  // Show ATR high/low channels (Pine: showChannels)
input bool   InpShowLabels       = true;  // Show Buy/Sell text labels (Pine: showLabels)
//--- MQL5-side extras (Pine always fills / always arms alertconditions)
input bool   InpShowFills        = true;  // Show channel fill ribbons (MQL5 fills are opaque; Pine fills are translucent)
input bool   InpEnableAlerts     = false; // Alert() on a newly closed buy/sell bar (Pine: alertcondition buy/sell)

//--- indicator buffers
double ExtHt[];        // 0: HalfTrend line
double ExtHtColor[];   // 1: HalfTrend color index (0 up/blue, 1 down/red)
double ExtHi[];        // 2: ATR high channel
double ExtHiColor[];   // 3: ATR high color index
double ExtLo[];        // 4: ATR low channel
double ExtLoColor[];   // 5: ATR low color index
double ExtBuy[];       // 6: buy triangle anchor price
double ExtSell[];      // 7: sell triangle anchor price
double ExtFillUpHt[];  // 8:  ribbon fill boundary (HT, uptrend, high side)
double ExtFillUpHi[];  // 9:  ribbon fill boundary (ATR high, uptrend)
double ExtFillUpHt2[]; // 10: ribbon fill boundary (HT, uptrend, low side)
double ExtFillUpLo[];  // 11: ribbon fill boundary (ATR low, uptrend)
double ExtFillDnHt[];  // 12: ribbon fill boundary (HT, downtrend, high side)
double ExtFillDnHi[];  // 13: ribbon fill boundary (ATR high, downtrend)
double ExtFillDnHt2[]; // 14: ribbon fill boundary (HT, downtrend, low side)
double ExtFillDnLo[];  // 15: ribbon fill boundary (ATR low, downtrend)

#define HT_OBJ_PREFIX "HT_Everget_"
#define HT_ATR_LEN    100
#define HT_ARROW_BUY  233   // Wingdings up triangle (matches Pine built-in triangles)
#define HT_ARROW_SELL 234   // Wingdings down triangle

//+------------------------------------------------------------------+
//| Create or refresh one Buy/Sell text label chart object.          |
//+------------------------------------------------------------------+
void EnsureHtLabel(const string name, const datetime t, const double price,
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
   if(InpAmplitude < 1)
     {
      Print("HalfTrend_Everget_MT5: InpAmplitude must be >= 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0,  ExtHt,       INDICATOR_DATA);
   SetIndexBuffer(1,  ExtHtColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  ExtHi,       INDICATOR_DATA);
   SetIndexBuffer(3,  ExtHiColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4,  ExtLo,       INDICATOR_DATA);
   SetIndexBuffer(5,  ExtLoColor,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6,  ExtBuy,      INDICATOR_DATA);
   SetIndexBuffer(7,  ExtSell,     INDICATOR_DATA);
   SetIndexBuffer(8,  ExtFillUpHt, INDICATOR_DATA);
   SetIndexBuffer(9,  ExtFillUpHi, INDICATOR_DATA);
   SetIndexBuffer(10, ExtFillUpHt2, INDICATOR_DATA);
   SetIndexBuffer(11, ExtFillUpLo,  INDICATOR_DATA);
   SetIndexBuffer(12, ExtFillDnHt,  INDICATOR_DATA);
   SetIndexBuffer(13, ExtFillDnHi,  INDICATOR_DATA);
   SetIndexBuffer(14, ExtFillDnHt2, INDICATOR_DATA);
   SetIndexBuffer(15, ExtFillDnLo,  INDICATOR_DATA);

   ArraySetAsSeries(ExtHt, true);
   ArraySetAsSeries(ExtHtColor, true);
   ArraySetAsSeries(ExtHi, true);
   ArraySetAsSeries(ExtHiColor, true);
   ArraySetAsSeries(ExtLo, true);
   ArraySetAsSeries(ExtLoColor, true);
   ArraySetAsSeries(ExtBuy, true);
   ArraySetAsSeries(ExtSell, true);
   ArraySetAsSeries(ExtFillUpHt, true);
   ArraySetAsSeries(ExtFillUpHi, true);
   ArraySetAsSeries(ExtFillUpHt2, true);
   ArraySetAsSeries(ExtFillUpLo, true);
   ArraySetAsSeries(ExtFillDnHt, true);
   ArraySetAsSeries(ExtFillDnHi, true);
   ArraySetAsSeries(ExtFillDnHt2, true);
   ArraySetAsSeries(ExtFillDnLo, true);

   PlotIndexSetInteger(1, PLOT_LINE_STYLE, STYLE_DOT);
   PlotIndexSetInteger(2, PLOT_LINE_STYLE, STYLE_DOT);
   PlotIndexSetInteger(3, PLOT_ARROW, HT_ARROW_BUY);
   PlotIndexSetInteger(4, PLOT_ARROW, HT_ARROW_SELL);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 0);

   for(int p = 0; p < 9; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(!InpShowArrows)
     {
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
     }
   if(!InpShowChannels)
     {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
     }
   if(!InpShowFills)
     {
      for(int p = 5; p < 9; p++)
         PlotIndexSetInteger(p, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("HalfTrend Everget (%d, %.1f)", InpAmplitude, InpChannelDeviation));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   if(!InpShowLabels)
      ObjectsDeleteAll(0, HT_OBJ_PREFIX);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Indicator deinitialization: remove our text label objects.       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, HT_OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
//| Main calculation. State machine mirrors the Pine script:         |
//| trend/nextTrend, maxLowPrice/minHighPrice, up/down, atr channels,|
//| transition arrows at up-atr2 / down+atr2. Full recompute from    |
//| the oldest bar on every call keeps the path-dependent state      |
//| deterministic (see README warmup notes).                         |
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
//--- (0 = newest). Force used price/time arrays to series so the i / i+1 /
//--- i+j lookbacks below read older bars correctly. Without this the state
//--- machine ran time-reversed with future leak and suppressed arrows.
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int    amp     = (InpAmplitude < 1 ? 1 : InpAmplitude);
   double devMult = (InpChannelDeviation < 0.0 ? 0.0 : InpChannelDeviation);

//--- persistent Pine-style state, rebuilt oldest -> newest
   int    trend = 0, nextTrend = 0;
   double maxLowPrice = 0.0, minHighPrice = 0.0;
   bool   mmInit = false;
   double up = 0.0, down = 0.0;
   bool   upDefined = false, downDefined = false;
   double atrPrev = 0.0, trSum = 0.0;
   double sumHigh = 0.0, sumLow = 0.0;

//--- i is series index (0 = forming bar); k is bar age (0 = oldest)
   for(int i = rates_total - 1; i >= 0; i--)
     {
      int    k = rates_total - 1 - i;
      double h = high[i], l = low[i], c = close[i];
      double prevLow   = ((i + 1 < rates_total) ? low[i + 1]   : l);
      double prevHigh  = ((i + 1 < rates_total) ? high[i + 1]  : h);
      double prevClose = ((i + 1 < rates_total) ? close[i + 1] : c);

      // Pine: var maxLowPrice = nz(low[1], low), var minHighPrice = nz(high[1], high)
      if(!mmInit)
        {
         maxLowPrice = l;
         minHighPrice = h;
         mmInit = true;
        }

      //--- Wilder ATR(100)/2 (Pine ta.atr(100)/2); seeded with SMA of first 100 TRs
      double tr;
      if(k == 0)
         tr = h - l;
      else
        {
         double d1 = h - l;
         double d2 = MathAbs(h - prevClose);
         double d3 = MathAbs(l - prevClose);
         tr = MathMax(d1, MathMax(d2, d3));
        }
      bool   atrValid = (k >= HT_ATR_LEN - 1);
      double atr = 0.0;
      if(k < HT_ATR_LEN)
        {
         trSum += tr;
         if(k == HT_ATR_LEN - 1)
           {
            atr = trSum / HT_ATR_LEN;
            atrPrev = atr;
           }
        }
      else
        {
         atr = (atrPrev * (HT_ATR_LEN - 1) + tr) / HT_ATR_LEN;
         atrPrev = atr;
        }
      double atr2 = atr / 2.0;
      double dev  = devMult * atr2;

      //--- SMA(high, amp), SMA(low, amp) via sliding window
      sumHigh += h;
      sumLow  += l;
      if(k >= amp)
        {
         sumHigh -= high[i + amp];
         sumLow  -= low[i + amp];
        }
      bool winValid = (k >= amp - 1);

      //--- rolling highest-high / lowest-low over `amp` bars (ties: most recent bar)
      double highPrice = 0.0, lowPrice = 0.0;
      if(winValid)
        {
         double mx = high[i], mn = low[i];
         for(int j = 1; j < amp; j++)
           {
            if(high[i + j] > mx)
               mx = high[i + j];
            if(low[i + j] < mn)
               mn = low[i + j];
           }
         highPrice = mx;
         lowPrice = mn;
        }
      double highma = (winValid ? sumHigh / amp : 0.0);
      double lowma  = (winValid ? sumLow / amp : 0.0);

      //--- trend / nextTrend transitions
      int  trendPrev = trend;
      bool hasPrev = (k > 0);
      double upPrev = up, downPrev = down;
      bool upDefPrev = upDefined, downDefPrev = downDefined;

      if(nextTrend == 1)
        {
         if(winValid)
            maxLowPrice = MathMax(lowPrice, maxLowPrice);
         if(winValid && highma < maxLowPrice && c < prevLow)
           {
            trend = 1;
            nextTrend = 0;
            minHighPrice = highPrice;
           }
        }
      else
        {
         if(winValid)
            minHighPrice = MathMin(highPrice, minHighPrice);
         if(winValid && lowma > minHighPrice && c > prevHigh)
           {
            trend = 0;
            nextTrend = 1;
            maxLowPrice = lowPrice;
           }
        }

      //--- up/down lines; arrows fire only on a completed ATR warmup transition
      bool isTransition = (hasPrev && trend != trendPrev);
      double arrowUp = EMPTY_VALUE, arrowDown = EMPTY_VALUE;

      if(trend == 0)
        {
         if(isTransition)
           {
            // Pine: up takes the previous down value; fallback seeds the very
            // first cycle so the lines can start (documented in README).
            up = (downDefPrev ? downPrev : maxLowPrice);
            upDefined = true;
            if(atrValid)
               arrowUp = up - atr2;
           }
         else
           {
            up = (upDefPrev ? MathMax(maxLowPrice, upPrev) : maxLowPrice);
            upDefined = true;
           }
        }
      else
        {
         if(isTransition)
           {
            down = (upDefPrev ? upPrev : minHighPrice);
            downDefined = true;
            if(atrValid)
               arrowDown = down + atr2;
           }
         else
           {
            down = (downDefPrev ? MathMin(minHighPrice, downPrev) : minHighPrice);
            downDefined = true;
           }
        }

      //--- outputs
      int    htCol = (trend == 0 ? 0 : 1);
      double htVal = (trend == 0 ? (upDefined ? up : EMPTY_VALUE)
                                 : (downDefined ? down : EMPTY_VALUE));
      double hiVal = EMPTY_VALUE, loVal = EMPTY_VALUE;
      if(atrValid && htVal != EMPTY_VALUE)
        {
         double base = (trend == 0 ? up : down);
         hiVal = base + dev;
         loVal = base - dev;
        }

      ExtHt[i]      = htVal;
      ExtHtColor[i] = htCol;
      ExtHi[i]      = hiVal;
      ExtHiColor[i] = htCol;
      ExtLo[i]      = loVal;
      ExtLoColor[i] = htCol;
      ExtBuy[i]     = arrowUp;
      ExtSell[i]    = arrowDown;

      if(trend == 0 && htVal != EMPTY_VALUE && hiVal != EMPTY_VALUE)
        {
         ExtFillUpHt[i] = htVal;  ExtFillUpHi[i] = hiVal;
         ExtFillUpHt2[i] = htVal; ExtFillUpLo[i] = loVal;
         ExtFillDnHt[i] = EMPTY_VALUE;  ExtFillDnHi[i] = EMPTY_VALUE;
         ExtFillDnHt2[i] = EMPTY_VALUE; ExtFillDnLo[i] = EMPTY_VALUE;
        }
      else if(trend == 1 && htVal != EMPTY_VALUE && hiVal != EMPTY_VALUE)
        {
         ExtFillDnHt[i] = htVal;  ExtFillDnHi[i] = hiVal;
         ExtFillDnHt2[i] = htVal; ExtFillDnLo[i] = loVal;
         ExtFillUpHt[i] = EMPTY_VALUE;  ExtFillUpHi[i] = EMPTY_VALUE;
         ExtFillUpHt2[i] = EMPTY_VALUE; ExtFillUpLo[i] = EMPTY_VALUE;
        }
      else
        {
         ExtFillUpHt[i] = EMPTY_VALUE;  ExtFillUpHi[i] = EMPTY_VALUE;
         ExtFillUpHt2[i] = EMPTY_VALUE; ExtFillUpLo[i] = EMPTY_VALUE;
         ExtFillDnHt[i] = EMPTY_VALUE;  ExtFillDnHi[i] = EMPTY_VALUE;
         ExtFillDnHt2[i] = EMPTY_VALUE; ExtFillDnLo[i] = EMPTY_VALUE;
        }

      //--- Buy/Sell text labels at the arrow anchors (chart objects)
      if(InpShowLabels)
        {
         string buyName  = HT_OBJ_PREFIX + "Buy_" + IntegerToString((long)time[i]);
         string sellName = HT_OBJ_PREFIX + "Sell_" + IntegerToString((long)time[i]);
         if(arrowUp != EMPTY_VALUE)
            EnsureHtLabel(buyName, time[i], arrowUp, "Buy", C'41,98,255', ANCHOR_UPPER);
         else if(i == 0)
            ObjectDelete(0, buyName);
         if(arrowDown != EMPTY_VALUE)
            EnsureHtLabel(sellName, time[i], arrowDown, "Sell", C'255,82,82', ANCHOR_LOWER);
         else if(i == 0)
            ObjectDelete(0, sellName);
        }
     }

//--- alerts on the last closed bar only (Pine alertcondition buy/sell equivalent)
   if(InpEnableAlerts && rates_total >= 2)
     {
      static datetime lastAlertBar = 0;
      if(time[1] != lastAlertBar)
        {
         if(ExtBuy[1] != EMPTY_VALUE)
           {
            Alert(StringFormat("HalfTrend Everget BUY %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(close[1], _Digits)));
            lastAlertBar = time[1];
           }
         else if(ExtSell[1] != EMPTY_VALUE)
           {
            Alert(StringFormat("HalfTrend Everget SELL %s %s @ %s",
                               _Symbol, EnumToString(_Period),
                               DoubleToString(close[1], _Digits)));
            lastAlertBar = time[1];
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
