// Read-only HolaPrime MT5 export of the owned SMA(3)/SMA(5) parity rule.
// Exports real broker bars/signals and marks the same signals on the MT5 chart.
// No order, account, position, or performance API is called.
#property script_show_inputs
#property copyright "StratCoreAlpha owned sample"
#property version "1.00"

#include "SCA_EA_ParityDemoSignal.mqh"

void OnStart()
{
   if(_Symbol != "EURUSD" || _Period != PERIOD_H1)
   {
      PrintFormat("SCA_M179_ABORT wrong chart: %s %s", _Symbol, EnumToString(_Period));
      return;
   }
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int count = CopyRates(_Symbol, _Period, D'2026.09.07 00:00:00',
                         D'2026.09.10 06:00:00', rates);
   if(count < 60)
   {
      PrintFormat("SCA_M179_ABORT insufficient broker bars: %d error=%d", count, GetLastError());
      return;
   }
   double closes[];
   ArrayResize(closes, count);
   for(int i = 0; i < count; i++)
      closes[i] = rates[i].close;

   int bars_file = FileOpen("SCA_M179_HolaPrime_EURUSD_H1_bars.csv",
                            FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   int signals_file = FileOpen("SCA_M179_HolaPrime_EURUSD_H1_signals.csv",
                               FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(bars_file == INVALID_HANDLE || signals_file == INVALID_HANDLE)
   {
      PrintFormat("SCA_M179_ABORT output open error=%d", GetLastError());
      if(bars_file != INVALID_HANDLE) FileClose(bars_file);
      if(signals_file != INVALID_HANDLE) FileClose(signals_file);
      return;
   }
   FileWrite(bars_file, "time_mt5", "open", "high", "low", "close", "direction");
   FileWrite(signals_file, "time_mt5", "direction", "open", "high", "low", "close");

   int exported = 0;
   int signals = 0;
   for(int i = 0; i < count; i++)
   {
      int signal = 0;
      if(i >= SCA_PARITY_FIRST_SIGNAL_INDEX)
      {
         double fast_prev = SCA_ParitySMA(closes, i - 1, SCA_PARITY_FAST_PERIOD);
         double slow_prev = SCA_ParitySMA(closes, i - 1, SCA_PARITY_SLOW_PERIOD);
         double fast_now = SCA_ParitySMA(closes, i, SCA_PARITY_FAST_PERIOD);
         double slow_now = SCA_ParitySMA(closes, i, SCA_PARITY_SLOW_PERIOD);
         signal = SCA_ParitySignal(fast_prev, slow_prev, fast_now, slow_now);
      }
      // HolaPrime H1 server timestamps are UTC+3 in this run. These bounds
      // align with 08 Sep 00:00 through 09 Sep 23:00 UTC in TradingView.
      if(rates[i].time < D'2026.09.08 03:00:00' ||
         rates[i].time >= D'2026.09.10 03:00:00')
         continue;
      string direction = signal > 0 ? "BULL" : (signal < 0 ? "BEAR" : "");
      string stamp = TimeToString(rates[i].time, TIME_DATE | TIME_SECONDS);
      string op = DoubleToString(rates[i].open, _Digits);
      string hi = DoubleToString(rates[i].high, _Digits);
      string lo = DoubleToString(rates[i].low, _Digits);
      string cl = DoubleToString(rates[i].close, _Digits);
      FileWrite(bars_file, stamp, op, hi, lo, cl, direction);
      exported++;
      if(signal == 0) continue;
      FileWrite(signals_file, stamp, direction, op, hi, lo, cl);
      signals++;
      string name = "SCA_M179_" + IntegerToString(i);
      double marker_price = signal > 0 ? rates[i].low - 0.00025 : rates[i].high + 0.00025;
      if(ObjectCreate(0, name, OBJ_ARROW, 0, rates[i].time, marker_price))
      {
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, signal > 0 ? 233 : 234);
         ObjectSetInteger(0, name, OBJPROP_COLOR, signal > 0 ? clrLime : clrRed);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
      }
      PrintFormat("SCA_M179_SIGNAL %s %s O=%s H=%s L=%s C=%s",
                  stamp, direction, op, hi, lo, cl);
   }
   FileClose(bars_file);
   FileClose(signals_file);
   ChartSetInteger(0, CHART_AUTOSCROLL, false);
   ChartSetInteger(0, CHART_SHIFT, false);
   ChartSetInteger(0, CHART_SCALE, 5);
   int shift = iBarShift(_Symbol, _Period, D'2026.09.10 00:00:00', false);
   ChartNavigate(0, CHART_END, -shift);
   Comment("M179 | HolaPrime-Server1 EURUSD H1 | 08-09 Sep 2026 | SMA 3/5 | BULL green, BEAR red | signal only");
   ChartRedraw(0);
   Sleep(3000);
   bool shot = ChartScreenShot(0, "SCA_M179_HolaPrime_EURUSD_H1_chart.png",
                               1600, 900, ALIGN_LEFT);
   PrintFormat("SCA_M179_EXPORT bars=%d signals=%d screenshot=%s server=%s terminal=%s",
               exported, signals, shot ? "true" : "false",
               AccountInfoString(ACCOUNT_SERVER), TerminalInfoString(TERMINAL_PATH));
}
