#property strict
#property version   "1.00"
#property description "Read-only MT5 deal-history evidence exporter"
#property description "Exports reason-coded execution facts without account IDs, credentials or order placement"

input datetime InpFrom                    = D'2026.01.01 00:00:00';
input datetime InpTo                      = 0;
input string   InpSymbol                  = "";
input long     InpMagic                   = -1;
input bool     InpIncludeBalanceOperations = false;
input bool     InpUseCommonFolder         = false;
input string   InpFilePrefix              = "SCA_MT5_DealEvidence";

bool IsTradeDealType(const ENUM_DEAL_TYPE deal_type)
{
   return deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL;
}

string SafeFileToken(const string value)
{
   string safe = value;
   StringReplace(safe, "\\", "_");
   StringReplace(safe, "/", "_");
   StringReplace(safe, ":", "_");
   StringReplace(safe, "*", "_");
   StringReplace(safe, "?", "_");
   StringReplace(safe, "\"", "_");
   StringReplace(safe, "<", "_");
   StringReplace(safe, ">", "_");
   StringReplace(safe, "|", "_");
   StringTrimLeft(safe);
   StringTrimRight(safe);

   if(StringLen(safe) == 0)
      return "SCA_MT5_DealEvidence";

   return safe;
}

string BuildFileName(const datetime from_time,
                     const datetime to_time)
{
   const string from_token = TimeToString(from_time, TIME_DATE);
   const string to_token = TimeToString(to_time, TIME_DATE);
   string safe_from = from_token;
   string safe_to = to_token;
   StringReplace(safe_from, ".", "-");
   StringReplace(safe_to, ".", "-");

   return StringFormat("%s_%s_to_%s.csv",
                       SafeFileToken(InpFilePrefix),
                       safe_from,
                       safe_to);
}

bool ResolveToTime(datetime &to_time)
{
   if(InpTo > 0)
   {
      to_time = InpTo;
      return true;
   }

   const int maximum_attempts = 100;
   for(int attempt = 0; attempt < maximum_attempts; attempt++)
   {
      if((bool)TerminalInfoInteger(TERMINAL_CONNECTED))
      {
         to_time = TimeCurrent();
         return to_time > 0;
      }

      Sleep(100);
   }

   Print("SCA_DEAL_EXPORT FAILED current_end_requires_connected_terminal_or_explicit_InpTo");
   return false;
}

bool MatchesFilters(const ulong ticket)
{
   const ENUM_DEAL_TYPE deal_type =
      (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);

   if(!InpIncludeBalanceOperations && !IsTradeDealType(deal_type))
      return false;

   const string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
   if(StringLen(InpSymbol) > 0 && symbol != InpSymbol)
      return false;

   const long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
   if(InpMagic >= 0 && magic != InpMagic)
      return false;

   return true;
}

void WriteHeader(const int handle)
{
   FileWrite(handle,
             "event_index",
             "server_time",
             "time_msc",
             "symbol",
             "deal_type",
             "entry_type",
             "reason",
             "volume",
             "price",
             "sl",
             "tp",
             "commission",
             "fee",
             "swap",
             "profit",
             "magic",
             "deal_ticket",
             "order_ticket",
             "position_id");
}

void WriteDeal(const int handle,
               const int event_index,
               const ulong ticket)
{
   const long time_msc = HistoryDealGetInteger(ticket, DEAL_TIME_MSC);
   const datetime server_time =
      (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
   const string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
   const ENUM_DEAL_TYPE deal_type =
      (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
   const ENUM_DEAL_ENTRY entry_type =
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
   const ENUM_DEAL_REASON reason =
      (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
   const int digits =
      (int)MathMax(0, SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   FileWrite(handle,
             StringFormat("EVT-%06d", event_index),
             TimeToString(server_time, TIME_DATE | TIME_SECONDS),
             time_msc,
             symbol,
             EnumToString(deal_type),
             EnumToString(entry_type),
             EnumToString(reason),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 8),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), digits),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_SL), digits),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_TP), digits),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_FEE), 2),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2),
             DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2),
             HistoryDealGetInteger(ticket, DEAL_MAGIC),
             ticket,
             HistoryDealGetInteger(ticket, DEAL_ORDER),
             HistoryDealGetInteger(ticket, DEAL_POSITION_ID));
}

void OnStart()
{
   datetime to_time = 0;
   if(!ResolveToTime(to_time))
      return;

   if(InpFrom <= 0 || to_time <= 0 || InpFrom > to_time)
   {
      PrintFormat("SCA_DEAL_EXPORT FAILED invalid_range from=%s to=%s",
                  TimeToString(InpFrom, TIME_DATE | TIME_SECONDS),
                  TimeToString(to_time, TIME_DATE | TIME_SECONDS));
      return;
   }

   ResetLastError();
   if(!HistorySelect(InpFrom, to_time))
   {
      PrintFormat("SCA_DEAL_EXPORT FAILED history_select error=%d",
                  GetLastError());
      return;
   }

   const string file_name = BuildFileName(InpFrom, to_time);
   int flags = FILE_WRITE | FILE_CSV | FILE_ANSI;
   if(InpUseCommonFolder)
      flags |= FILE_COMMON;

   ResetLastError();
   const int handle = FileOpen(file_name, flags, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("SCA_DEAL_EXPORT FAILED file_open name=%s error=%d",
                  file_name,
                  GetLastError());
      return;
   }

   WriteHeader(handle);

   const int total = HistoryDealsTotal();
   int exported = 0;
   int skipped = 0;

   for(int index = 0; index < total; index++)
   {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0)
      {
         skipped++;
         continue;
      }

      if(!MatchesFilters(ticket))
      {
         skipped++;
         continue;
      }

      exported++;
      WriteDeal(handle, exported, ticket);
   }

   FileFlush(handle);
   FileClose(handle);

   const string folder_scope = InpUseCommonFolder ? "COMMON_FILES" : "TERMINAL_FILES";
   PrintFormat("SCA_DEAL_EXPORT COMPLETE file=%s scope=%s selected=%d exported=%d skipped=%d symbol_filter=%s magic_filter=%d",
               file_name,
               folder_scope,
               total,
               exported,
               skipped,
               StringLen(InpSymbol) > 0 ? InpSymbol : "ALL",
               InpMagic);
   Print("SCA_DEAL_EXPORT BOUNDARY=read_only_no_account_id_no_order_action_no_performance_claim");
}
