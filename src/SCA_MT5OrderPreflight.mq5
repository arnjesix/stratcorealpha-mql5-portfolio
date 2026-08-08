//+------------------------------------------------------------------+
//| SCA_MT5OrderPreflight.mq5                                       |
//| Copyright 2026 Arnold Holm / StratCoreAlpha                      |
//| https://stratcorealpha.com                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Arnold Holm / StratCoreAlpha"
#property link      "https://stratcorealpha.com/services/mql5-bug-fix"
#property version   "1.00"
#property strict
#property script_show_inputs
#property description "Checks a proposed MT5 order against current symbol rules without sending a trade."
#property description "Reports order-mode, volume, tick-size, pending-distance and stop-distance issues."

enum SCA_ORDER_SCENARIO
{
   SCA_MARKET_BUY = 0,       // Market buy
   SCA_MARKET_SELL = 1,      // Market sell
   SCA_BUY_LIMIT = 2,        // Buy limit below Ask
   SCA_SELL_LIMIT = 3,       // Sell limit above Bid
   SCA_BUY_STOP = 4,         // Buy stop above Ask
   SCA_SELL_STOP = 5         // Sell stop below Bid
};

input SCA_ORDER_SCENARIO InpScenario = SCA_MARKET_BUY;  // Proposed order
input double             InpVolume = 0.10;              // Proposed volume
input int                InpPendingDistancePoints = 100;// Pending distance in points
input int                InpStopLossPoints = 0;         // Stop loss distance; 0 disables
input int                InpTakeProfitPoints = 0;       // Take profit distance; 0 disables
input bool               InpWriteTextFile = true;       // Save report to Common\Files
input bool               InpPrintToExperts = true;      // Print report in Experts
input string             InpFilePrefix = "SCA_OrderPreflight";

int g_passes = 0;
int g_warnings = 0;
int g_failures = 0;

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   if(!SymbolSelect(_Symbol, true))
   {
      PrintFormat("StratCoreAlpha preflight: cannot select %s. Error %d", _Symbol, GetLastError());
      return;
   }

   string report = BuildReport();

   if(InpPrintToExperts)
      Print("\n", report);

   if(InpWriteTextFile)
      SaveReport(report);
}

//+------------------------------------------------------------------+
//| Build the non-trading diagnostic report                          |
//+------------------------------------------------------------------+
string BuildReport()
{
   g_passes = 0;
   g_warnings = 0;
   g_failures = 0;

   string report = "";
   MqlTick tick;
   ResetLastError();
   bool hasTick = SymbolInfoTick(_Symbol, tick);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double volumeMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volumeMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   long orderModes = SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE);
   long fillingModes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

   AddHeading(report, "StratCoreAlpha MT5 Order Preflight");
   AddLine(report, "Generated (server time)", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   AddLine(report, "Symbol", _Symbol);
   AddLine(report, "Scenario", ScenarioText(InpScenario));
   AddLine(report, "Important", "READ-ONLY: this script never sends or modifies an order");

   AddHeading(report, "Current symbol snapshot");
   AddLine(report, "Trade mode", EnumToString(tradeMode));
   AddLine(report, "Order modes", OrderModeText(orderModes));
   AddLine(report, "Filling modes", FillingModeText(fillingModes));
   AddLine(report, "Digits", IntegerToString(digits));
   AddLine(report, "Point", DoubleToString(point, 10));
   AddLine(report, "Tick size", DoubleToString(tickSize, 10));
   AddLine(report, "Minimum volume", DoubleToString(volumeMin, 8));
   AddLine(report, "Maximum volume", DoubleToString(volumeMax, 8));
   AddLine(report, "Volume step", DoubleToString(volumeStep, 8));
   AddLine(report, "Stops level (points)", IntegerToString(stopsLevel));
   AddLine(report, "Freeze level (points)", IntegerToString(freezeLevel));

   AddHeading(report, "Checks");

   if(hasTick && tick.bid > 0.0 && tick.ask > 0.0)
   {
      AddCheck(report, "Live tick", "PASS", StringFormat("Bid %s / Ask %s", DoubleToString(tick.bid, digits), DoubleToString(tick.ask, digits)));
   }
   else
   {
      AddCheck(report, "Live tick", "FAIL", "No usable Bid/Ask tick is available; open the market or refresh the symbol.");
   }

   CheckTradeMode(report, tradeMode);
   CheckOrderMode(report, orderModes);
   CheckVolume(report, volumeMin, volumeMax, volumeStep);
   CheckPriceGeometry(report, hasTick, tick, point, tickSize, stopsLevel, digits);

   if(fillingModes == 0)
      AddCheck(report, "Filling policy", "WARN", "No explicit FOK/IOC flag is advertised; select the filling policy from the symbol at runtime.");
   else
      AddCheck(report, "Filling policy", "PASS", FillingModeText(fillingModes));

   AddHeading(report, "Summary");
   AddLine(report, "Passes", IntegerToString(g_passes));
   AddLine(report, "Warnings", IntegerToString(g_warnings));
   AddLine(report, "Failures", IntegerToString(g_failures));
   AddLine(report, "Result", g_failures == 0 ? (g_warnings == 0 ? "PASS" : "REVIEW WARNINGS") : "DO NOT SEND AS CONFIGURED");

   AddHeading(report, "Boundaries and privacy");
   report += "The preflight checks current symbol metadata and the supplied hypothetical order.\r\n";
   report += "It does not send, modify or cancel trades and does not access positions or history.\r\n";
   report += "It does not print account login, owner name, balance, equity or credentials.\r\n";
   report += "A passing report cannot guarantee server acceptance, execution price or trading results.\r\n";
   report += "Generated by SCA_MT5OrderPreflight.mq5\r\n";
   report += "https://stratcorealpha.com/services/mql5-bug-fix\r\n";

   return report;
}

//+------------------------------------------------------------------+
//| Trade-mode checks                                                |
//+------------------------------------------------------------------+
void CheckTradeMode(string &report, const ENUM_SYMBOL_TRADE_MODE tradeMode)
{
   bool buySide = IsBuySide(InpScenario);

   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      AddCheck(report, "Trade mode", "FAIL", "Trading is disabled for this symbol.");
      return;
   }
   if(tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      AddCheck(report, "Trade mode", "FAIL", "The symbol currently allows closing only.");
      return;
   }
   if(buySide && tradeMode == SYMBOL_TRADE_MODE_SHORTONLY)
   {
      AddCheck(report, "Trade direction", "FAIL", "The symbol is short-only but the scenario is buy-side.");
      return;
   }
   if(!buySide && tradeMode == SYMBOL_TRADE_MODE_LONGONLY)
   {
      AddCheck(report, "Trade direction", "FAIL", "The symbol is long-only but the scenario is sell-side.");
      return;
   }

   AddCheck(report, "Trade mode", "PASS", EnumToString(tradeMode));
}

//+------------------------------------------------------------------+
//| Order-mode checks                                                |
//+------------------------------------------------------------------+
void CheckOrderMode(string &report, const long orderModes)
{
   long requiredFlag = IsMarket(InpScenario) ? SYMBOL_ORDER_MARKET :
                       (IsLimit(InpScenario) ? SYMBOL_ORDER_LIMIT : SYMBOL_ORDER_STOP);

   if((orderModes & requiredFlag) == 0)
      AddCheck(report, "Order type", "FAIL", ScenarioText(InpScenario) + " is not included in the symbol order-mode mask.");
   else
      AddCheck(report, "Order type", "PASS", ScenarioText(InpScenario) + " is advertised by the symbol.");

   if(InpStopLossPoints > 0 && (orderModes & SYMBOL_ORDER_SL) == 0)
      AddCheck(report, "Stop loss support", "FAIL", "The symbol does not advertise stop-loss support.");
   else if(InpStopLossPoints > 0)
      AddCheck(report, "Stop loss support", "PASS", "Stop-loss orders are advertised.");

   if(InpTakeProfitPoints > 0 && (orderModes & SYMBOL_ORDER_TP) == 0)
      AddCheck(report, "Take profit support", "FAIL", "The symbol does not advertise take-profit support.");
   else if(InpTakeProfitPoints > 0)
      AddCheck(report, "Take profit support", "PASS", "Take-profit orders are advertised.");
}

//+------------------------------------------------------------------+
//| Volume checks                                                    |
//+------------------------------------------------------------------+
void CheckVolume(string &report, const double minimum, const double maximum, const double step)
{
   if(InpVolume <= 0.0)
   {
      AddCheck(report, "Volume", "FAIL", "Volume must be greater than zero.");
      return;
   }
   if(InpVolume < minimum - 1e-12 || InpVolume > maximum + 1e-12)
   {
      AddCheck(report, "Volume range", "FAIL", StringFormat("%.8f is outside %.8f to %.8f.", InpVolume, minimum, maximum));
   }
   else
   {
      AddCheck(report, "Volume range", "PASS", StringFormat("%.8f is inside the advertised range.", InpVolume));
   }

   if(step <= 0.0)
   {
      AddCheck(report, "Volume step", "FAIL", "The symbol reports an invalid volume step.");
      return;
   }

   double units = (InpVolume - minimum) / step;
   double nearestUnits = MathRound(units);
   double normalized = minimum + nearestUnits * step;
   double tolerance = MathMax(1e-10, step * 1e-8);
   if(MathAbs(InpVolume - normalized) > tolerance)
      AddCheck(report, "Volume alignment", "FAIL", StringFormat("%.8f is off-step; nearest aligned value is %.8f.", InpVolume, normalized));
   else
      AddCheck(report, "Volume alignment", "PASS", StringFormat("%.8f matches step %.8f.", InpVolume, step));
}

//+------------------------------------------------------------------+
//| Pending-price and protective-distance checks                     |
//+------------------------------------------------------------------+
void CheckPriceGeometry(string &report,
                        const bool hasTick,
                        const MqlTick &tick,
                        const double point,
                        const double tickSize,
                        const int stopsLevel,
                        const int digits)
{
   if(point <= 0.0 || tickSize <= 0.0)
   {
      AddCheck(report, "Price units", "FAIL", "Point or tick size is zero or unavailable.");
      return;
   }

   if(InpPendingDistancePoints < 0 || InpStopLossPoints < 0 || InpTakeProfitPoints < 0)
   {
      AddCheck(report, "Input distances", "FAIL", "Pending, stop-loss and take-profit distances cannot be negative.");
      return;
   }

   if(!IsMarket(InpScenario))
   {
      if(!hasTick || tick.bid <= 0.0 || tick.ask <= 0.0)
      {
         AddCheck(report, "Pending price", "FAIL", "A live tick is required to calculate the hypothetical pending price.");
      }
      else
      {
         double basePrice = IsBuySide(InpScenario) ? tick.ask : tick.bid;
         double direction = PendingDirection(InpScenario);
         double rawPrice = basePrice + direction * InpPendingDistancePoints * point;
         double normalizedPrice = NormalizeToTick(rawPrice, tickSize, digits);
         string detail = StringFormat("Raw %s, tick-normalized %s.", DoubleToString(rawPrice, digits), DoubleToString(normalizedPrice, digits));

         if(InpPendingDistancePoints < stopsLevel)
            AddCheck(report, "Pending distance", "FAIL", detail + StringFormat(" Distance %d is below stops level %d points.", InpPendingDistancePoints, stopsLevel));
         else
            AddCheck(report, "Pending distance", "PASS", detail + StringFormat(" Distance %d points.", InpPendingDistancePoints));
      }
   }

   CheckProtectiveDistance(report, "Stop loss distance", InpStopLossPoints, stopsLevel);
   CheckProtectiveDistance(report, "Take profit distance", InpTakeProfitPoints, stopsLevel);
}

void CheckProtectiveDistance(string &report, const string label, const int distance, const int stopsLevel)
{
   if(distance == 0)
   {
      AddCheck(report, label, "WARN", "Disabled in this scenario.");
      return;
   }
   if(distance < stopsLevel)
      AddCheck(report, label, "FAIL", StringFormat("%d points is below the current stops level of %d.", distance, stopsLevel));
   else
      AddCheck(report, label, "PASS", StringFormat("%d points meets the current stops level of %d.", distance, stopsLevel));
}

//+------------------------------------------------------------------+
//| Formatting and scenario helpers                                  |
//+------------------------------------------------------------------+
void AddHeading(string &report, const string heading)
{
   report += "\r\n=== " + heading + " ===\r\n";
}

void AddLine(string &report, const string label, const string value)
{
   report += StringFormat("%-30s %s\r\n", label + ":", value);
}

void AddCheck(string &report, const string label, const string status, const string detail)
{
   report += StringFormat("[%-4s] %-24s %s\r\n", status, label + ":", detail);
   if(status == "PASS")
      g_passes++;
   else if(status == "WARN")
      g_warnings++;
   else
      g_failures++;
}

string ScenarioText(const SCA_ORDER_SCENARIO scenario)
{
   switch(scenario)
   {
      case SCA_MARKET_BUY:  return "Market buy";
      case SCA_MARKET_SELL: return "Market sell";
      case SCA_BUY_LIMIT:   return "Buy limit";
      case SCA_SELL_LIMIT:  return "Sell limit";
      case SCA_BUY_STOP:    return "Buy stop";
      case SCA_SELL_STOP:   return "Sell stop";
   }
   return "Unknown";
}

bool IsMarket(const SCA_ORDER_SCENARIO scenario)
{
   return scenario == SCA_MARKET_BUY || scenario == SCA_MARKET_SELL;
}

bool IsLimit(const SCA_ORDER_SCENARIO scenario)
{
   return scenario == SCA_BUY_LIMIT || scenario == SCA_SELL_LIMIT;
}

bool IsBuySide(const SCA_ORDER_SCENARIO scenario)
{
   return scenario == SCA_MARKET_BUY || scenario == SCA_BUY_LIMIT || scenario == SCA_BUY_STOP;
}

double PendingDirection(const SCA_ORDER_SCENARIO scenario)
{
   if(scenario == SCA_BUY_LIMIT || scenario == SCA_SELL_STOP)
      return -1.0;
   return 1.0;
}

double NormalizeToTick(const double price, const double tickSize, const int digits)
{
   if(tickSize <= 0.0)
      return NormalizeDouble(price, digits);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
}

string AppendFlag(string text, const string flagName)
{
   if(text != "")
      text += ", ";
   return text + flagName;
}

string OrderModeText(const long mask)
{
   string text = "";
   if((mask & SYMBOL_ORDER_MARKET) != 0) text = AppendFlag(text, "MARKET");
   if((mask & SYMBOL_ORDER_LIMIT) != 0)  text = AppendFlag(text, "LIMIT");
   if((mask & SYMBOL_ORDER_STOP) != 0)   text = AppendFlag(text, "STOP");
   if((mask & SYMBOL_ORDER_SL) != 0)     text = AppendFlag(text, "SL");
   if((mask & SYMBOL_ORDER_TP) != 0)     text = AppendFlag(text, "TP");
   return text == "" ? "none (raw " + IntegerToString((int)mask) + ")" : text;
}

string FillingModeText(const long mask)
{
   string text = "";
   if((mask & SYMBOL_FILLING_FOK) != 0) text = AppendFlag(text, "FOK");
   if((mask & SYMBOL_FILLING_IOC) != 0) text = AppendFlag(text, "IOC");
   if((mask & SYMBOL_FILLING_BOC) != 0) text = AppendFlag(text, "BOC");
   return text == "" ? "broker/default (raw " + IntegerToString((int)mask) + ")" : text;
}

string SafeFilePart(string value)
{
   StringReplace(value, "\\", "_");
   StringReplace(value, "/", "_");
   StringReplace(value, ":", "_");
   StringReplace(value, "*", "_");
   StringReplace(value, "?", "_");
   StringReplace(value, "\"", "_");
   StringReplace(value, "<", "_");
   StringReplace(value, ">", "_");
   StringReplace(value, "|", "_");
   return value;
}

//+------------------------------------------------------------------+
//| Save to terminal Common\Files                                    |
//+------------------------------------------------------------------+
void SaveReport(const string report)
{
   string fileName = SafeFilePart(InpFilePrefix) + "_" + SafeFilePart(_Symbol) + ".txt";
   ResetLastError();
   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("StratCoreAlpha preflight: cannot create %s. Error %d", fileName, GetLastError());
      return;
   }

   FileWriteString(handle, report);
   FileClose(handle);
   Print("StratCoreAlpha preflight saved to: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", fileName);
}
//+------------------------------------------------------------------+
