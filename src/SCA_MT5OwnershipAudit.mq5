//+------------------------------------------------------------------+
//| SCA_MT5OwnershipAudit.mq5                                       |
//| Copyright 2026 Arnold Holm / StratCoreAlpha                      |
//| https://stratcorealpha.com                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Arnold Holm / StratCoreAlpha"
#property link      "https://stratcorealpha.com/services/mql5-bug-fix"
#property version   "1.00"
#property strict
#property script_show_inputs
#property description "Audits open MT5 positions and pending orders against one expected magic number."
#property description "Read-only: never sends, modifies or closes a trade."

enum SCA_AUDIT_SCOPE
{
   SCA_CURRENT_SYMBOL = 0, // Audit the chart symbol only
   SCA_ALL_SYMBOLS = 1     // Audit every visible open position/order
};

input long            InpExpectedMagic = 0;            // Expected EA magic number
input SCA_AUDIT_SCOPE InpScope = SCA_CURRENT_SYMBOL;    // Symbol scope
input bool            InpIncludePendingOrders = true;  // Include active pending orders
input bool            InpWriteTextFile = true;         // Save report to Common\Files
input bool            InpPrintToExperts = true;        // Print report in Experts
input string          InpFilePrefix = "SCA_OwnershipAudit";

int g_owned_positions = 0;
int g_foreign_positions = 0;
int g_owned_orders = 0;
int g_foreign_orders = 0;

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   string report = BuildReport();

   if(InpPrintToExperts)
      Print("\n", report);

   if(InpWriteTextFile)
      SaveReport(report);
}

//+------------------------------------------------------------------+
//| Build the read-only ownership report                             |
//+------------------------------------------------------------------+
string BuildReport()
{
   g_owned_positions = 0;
   g_foreign_positions = 0;
   g_owned_orders = 0;
   g_foreign_orders = 0;

   string report = "";
   AddHeading(report, "StratCoreAlpha MT5 Ownership Audit");
   AddLine(report, "Generated (server time)", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   AddLine(report, "Scope", InpScope == SCA_CURRENT_SYMBOL ? _Symbol : "All symbols");
   AddLine(report, "Expected magic", IntegerToString(InpExpectedMagic));
   AddLine(report, "Important", "READ-ONLY: this script never sends, modifies or closes a trade");

   AddHeading(report, "Open positions");
   int positionRows = 0;
   for(int index = 0; index < PositionsTotal(); index++)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!IsInScope(symbol))
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool owned = IsOwned(magic);
      if(owned)
         g_owned_positions++;
      else
         g_foreign_positions++;

      positionRows++;
      AddAuditRow(report,
                  "Position " + IntegerToString(positionRows),
                  owned,
                  symbol,
                  type == POSITION_TYPE_BUY ? "BUY" : "SELL",
                  magic);
   }
   if(positionRows == 0)
      report += "No open positions in scope.\r\n";

   if(InpIncludePendingOrders)
   {
      AddHeading(report, "Active pending orders");
      int orderRows = 0;
      for(int index = 0; index < OrdersTotal(); index++)
      {
         ulong ticket = OrderGetTicket(index);
         if(ticket == 0)
            continue;

         string symbol = OrderGetString(ORDER_SYMBOL);
         if(!IsInScope(symbol))
            continue;

         long magic = OrderGetInteger(ORDER_MAGIC);
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         bool owned = IsOwned(magic);
         if(owned)
            g_owned_orders++;
         else
            g_foreign_orders++;

         orderRows++;
         AddAuditRow(report,
                     "Order " + IntegerToString(orderRows),
                     owned,
                     symbol,
                     EnumToString(type),
                     magic);
      }
      if(orderRows == 0)
         report += "No active pending orders in scope.\r\n";
   }

   AddHeading(report, "Summary");
   AddLine(report, "Owned positions", IntegerToString(g_owned_positions));
   AddLine(report, "Foreign positions", IntegerToString(g_foreign_positions));
   AddLine(report, "Owned pending orders", IntegerToString(g_owned_orders));
   AddLine(report, "Foreign pending orders", IntegerToString(g_foreign_orders));
   AddLine(report,
           "Result",
           (g_foreign_positions + g_foreign_orders) == 0
              ? "NO FOREIGN EXPOSURE FOUND IN SCOPE"
              : "REVIEW FOREIGN EXPOSURE BEFORE AUTOMATED MANAGEMENT");

   AddHeading(report, "Boundaries and privacy");
   report += "Ownership means exact magic-number equality; it does not prove which source code created a trade.\r\n";
   report += "Manual trades commonly use magic 0. A configured expected magic of 0 therefore needs extra review.\r\n";
   report += "The report omits account identity, login, balance, equity, ticket IDs, volume, price and profit.\r\n";
   report += "Run it locally and still review symbol and magic-number rows before sharing.\r\n";
   report += "Generated by SCA_MT5OwnershipAudit.mq5\r\n";
   report += "https://stratcorealpha.com/services/mql5-bug-fix\r\n";
   return report;
}

bool IsInScope(const string symbol)
{
   return InpScope == SCA_ALL_SYMBOLS || symbol == _Symbol;
}

bool IsOwned(const long observedMagic)
{
   return observedMagic == InpExpectedMagic;
}

void AddHeading(string &report, const string heading)
{
   report += "\r\n=== " + heading + " ===\r\n";
}

void AddLine(string &report, const string label, const string value)
{
   report += StringFormat("%-30s %s\r\n", label + ":", value);
}

void AddAuditRow(string &report,
                 const string label,
                 const bool owned,
                 const string symbol,
                 const string type,
                 const long magic)
{
   report += StringFormat("[%-7s] %-12s symbol=%s | type=%s | magic=%s\r\n",
                          owned ? "OWNED" : "FOREIGN",
                          label + ":",
                          symbol,
                          type,
                          IntegerToString(magic));
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
   string scopePart = InpScope == SCA_CURRENT_SYMBOL ? _Symbol : "ALL";
   string fileName = SafeFilePart(InpFilePrefix) + "_" + SafeFilePart(scopePart) + ".txt";
   ResetLastError();
   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("StratCoreAlpha ownership audit: cannot create %s. Error %d", fileName, GetLastError());
      return;
   }

   FileWriteString(handle, report);
   FileClose(handle);
   Print("StratCoreAlpha ownership audit saved to: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", fileName);
}
//+------------------------------------------------------------------+
