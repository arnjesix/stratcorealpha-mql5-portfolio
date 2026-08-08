//+------------------------------------------------------------------+
//| SCA_BrokerEnvironmentReport.mq5                                  |
//| Copyright 2026 Arnold Holm / StratCoreAlpha                      |
//| https://stratcorealpha.com                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Arnold Holm / StratCoreAlpha"
#property link      "https://stratcorealpha.com/services/mql5-bug-fix"
#property version   "1.00"
#property strict
#property script_show_inputs
#property description "Creates a privacy-conscious MT5 broker and symbol environment report."
#property description "It does not collect account numbers, names, balances, positions, history or credentials."

input bool   InpWriteTextFile = true;                    // Save report to Common\Files
input bool   InpPrintToExperts = true;                   // Print report in the Experts tab
input string InpFilePrefix = "SCA_BrokerEnvironment";   // Output filename prefix

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   if(!SymbolSelect(_Symbol, true))
   {
      PrintFormat("StratCoreAlpha report: cannot select symbol %s. Error %d", _Symbol, GetLastError());
      return;
   }

   string report = BuildReport();

   if(InpPrintToExperts)
      Print("\n", report);

   if(InpWriteTextFile)
      SaveReport(report);
}

//+------------------------------------------------------------------+
//| Build a report without personal or trading-account data          |
//+------------------------------------------------------------------+
string BuildReport()
{
   string report = "";
   AddHeading(report, "StratCoreAlpha MT5 Broker Environment Report");
   AddLine(report, "Generated (server time)", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   AddLine(report, "Terminal build", IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   AddLine(report, "MQL5 build", IntegerToString((int)__MQL5BUILD__));
   AddLine(report, "Account margin mode", EnumToString((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
   AddLine(report, "Account leverage", "1:" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LEVERAGE)));
   AddLine(report, "Deposit currency", AccountInfoString(ACCOUNT_CURRENCY));

   AddHeading(report, "Symbol identity");
   AddLine(report, "Symbol", _Symbol);
   AddLine(report, "Description", SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION));
   AddLine(report, "Path", SymbolInfoString(_Symbol, SYMBOL_PATH));
   AddLine(report, "Base currency", SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE));
   AddLine(report, "Profit currency", SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT));
   AddLine(report, "Margin currency", SymbolInfoString(_Symbol, SYMBOL_CURRENCY_MARGIN));
   AddLine(report, "Digits", IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
   AddLine(report, "Point", Number(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 10));
   AddLine(report, "Tick size", Number(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), 10));
   AddLine(report, "Contract size", Number(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), 4));

   AddHeading(report, "Trading rules");
   AddLine(report, "Trade mode", EnumToString((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE)));
   AddLine(report, "Calculation mode", EnumToString((ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE)));
   AddLine(report, "Order modes", OrderModeText(SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE)));
   AddLine(report, "Filling modes", FillingModeText(SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE)));
   AddLine(report, "Expiration modes", ExpirationModeText(SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE)));
   AddLine(report, "Stops level (points)", IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)));
   AddLine(report, "Freeze level (points)", IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)));

   AddHeading(report, "Volume and tick values");
   AddLine(report, "Minimum volume", Number(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 8));
   AddLine(report, "Maximum volume", Number(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), 8));
   AddLine(report, "Volume step", Number(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 8));
   AddLine(report, "Directional volume limit", Number(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT), 8));
   AddLine(report, "Tick value", Number(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 8));
   AddLine(report, "Tick value profit", Number(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT), 8));
   AddLine(report, "Tick value loss", Number(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS), 8));

   AddHeading(report, "Privacy note");
   report += "This report intentionally excludes account login, owner name, broker server,\r\n";
   report += "balance, equity, open positions, order/deal history, files, keys and credentials.\r\n";
   report += "Review the text before sharing it with any developer.\r\n";
   report += "Generated by SCA_BrokerEnvironmentReport.mq5\r\n";
   report += "https://stratcorealpha.com/services/mql5-bug-fix\r\n";

   return report;
}

//+------------------------------------------------------------------+
//| Save to the terminal's shared Common\Files folder                |
//+------------------------------------------------------------------+
void SaveReport(const string report)
{
   string symbolPart = SafeFilePart(_Symbol);
   string prefixPart = SafeFilePart(InpFilePrefix);
   string fileName = prefixPart + "_" + symbolPart + ".txt";

   ResetLastError();
   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("StratCoreAlpha report: cannot create %s. Error %d", fileName, GetLastError());
      return;
   }

   FileWriteString(handle, report);
   FileClose(handle);

   string fullPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + fileName;
   Print("StratCoreAlpha report saved to: ", fullPath);
}

//+------------------------------------------------------------------+
//| Formatting helpers                                               |
//+------------------------------------------------------------------+
void AddHeading(string &report, const string heading)
{
   report += "\r\n=== " + heading + " ===\r\n";
}

void AddLine(string &report, const string label, const string value)
{
   report += StringFormat("%-30s %s\r\n", label + ":", value);
}

string Number(const double value, const int digits)
{
   return DoubleToString(value, digits);
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

string AppendFlag(string text, const string flagName)
{
   if(text != "")
      text += ", ";
   return text + flagName;
}

string OrderModeText(const long mask)
{
   string text = "";
   if((mask & SYMBOL_ORDER_MARKET) != 0)     text = AppendFlag(text, "MARKET");
   if((mask & SYMBOL_ORDER_LIMIT) != 0)      text = AppendFlag(text, "LIMIT");
   if((mask & SYMBOL_ORDER_STOP) != 0)       text = AppendFlag(text, "STOP");
   if((mask & SYMBOL_ORDER_STOP_LIMIT) != 0) text = AppendFlag(text, "STOP_LIMIT");
   if((mask & SYMBOL_ORDER_SL) != 0)         text = AppendFlag(text, "SL");
   if((mask & SYMBOL_ORDER_TP) != 0)         text = AppendFlag(text, "TP");
   if((mask & SYMBOL_ORDER_CLOSEBY) != 0)    text = AppendFlag(text, "CLOSE_BY");
   return text == "" ? "none (raw " + IntegerToString((int)mask) + ")" : text + " (raw " + IntegerToString((int)mask) + ")";
}

string FillingModeText(const long mask)
{
   string text = "";
   if((mask & SYMBOL_FILLING_FOK) != 0) text = AppendFlag(text, "FOK");
   if((mask & SYMBOL_FILLING_IOC) != 0) text = AppendFlag(text, "IOC");
   if((mask & SYMBOL_FILLING_BOC) != 0) text = AppendFlag(text, "BOC");
   return text == "" ? "broker/default (raw " + IntegerToString((int)mask) + ")" : text + " (raw " + IntegerToString((int)mask) + ")";
}

string ExpirationModeText(const long mask)
{
   string text = "";
   if((mask & SYMBOL_EXPIRATION_GTC) != 0)           text = AppendFlag(text, "GTC");
   if((mask & SYMBOL_EXPIRATION_DAY) != 0)           text = AppendFlag(text, "DAY");
   if((mask & SYMBOL_EXPIRATION_SPECIFIED) != 0)     text = AppendFlag(text, "SPECIFIED");
   if((mask & SYMBOL_EXPIRATION_SPECIFIED_DAY) != 0) text = AppendFlag(text, "SPECIFIED_DAY");
   return text == "" ? "none (raw " + IntegerToString((int)mask) + ")" : text + " (raw " + IntegerToString((int)mask) + ")";
}
//+------------------------------------------------------------------+
