//+------------------------------------------------------------------+
//| SCA_T99_ORB_TestEA.mq5 — T99 rehearsal test EA (frozen ORB-v1.0)  |
//| Status: CODE ONLY — NOT compiled or run in a terminal here. The  |
//| parent compiles and runs the real HolaPrime MT5 check later and  |
//| owns the only valid compile log.                                 |
//|                                                                  |
//| TESTER ONLY: this EA unconditionally refuses to run outside the  |
//| strategy tester. There is no live-trading switch, no demo/live   |
//| bypass, and no code path that sends orders off-tester.           |
//+------------------------------------------------------------------+
#property copyright "StratCoreAlpha T99 rehearsal scaffold"
#property version   "1.00"
#include "SCA_T99_RuleLib.mqh"

//--- EXACT FROZEN INPUTS (rule freeze ORB-v1.0: changing any input value
//--- or the rules below = new freeze + re-log; inputs are the parameters
//--- the parent varies between frozen runs, nothing else is tunable)
input string InpSymbol        = "";        // symbol ("" = chart symbol)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // timeframe
input double InpRiskPercent   = 1.0;       // risk per trade, % of balance (0,5]
input string InpSessionStart  = "09:00";   // session start, SERVER HH:MM
input string InpSessionEnd    = "17:00";   // session end, SERVER HH:MM
input int    InpRangeMinutes  = 30;        // opening-range length, minutes
input int    InpMaxTradesDay  = 1;         // max entries per server day
input long   InpMagic         = 20260925;  // own magic (history reconstruction)
input double InpRRMultiple    = 2.0;       // target multiple of risk (2R)
input int    InpMaxDeviation  = 10;        // max price deviation, points
input bool   InpSessionFlatten = true;     // flatten own position at session end

//--- FROZEN RULES ORB-v1.0 (binding):
//--- 1. Range = high/low of COMPLETED bars (shift>=1, forming bar never
//---    used) inside [SessionStart, SessionStart+RangeMinutes) on the SAME
//---    server day. Bars from any other day are ignored (no range reuse).
//---    Overnight sessions (InpSessionEnd <= InpSessionStart) are REJECTED
//---    at init (INIT_PARAMETERS_INCORRECT) — never silently continued.
//--- 2. Entries only AFTER the window is complete (server time >= range
//---    end) AND on a later completed bar whose CLOSE confirms outside the
//---    range: close > high -> BUY, close < low -> SELL. Equality = no
//---    signal (strict, deterministic). Signal bar must be inside the
//---    session; the completed signal bar must itself be at/after the
//---    window end (no lookahead, no forming-bar use).
//--- 3. One entry per server day (InpMaxTradesDay), counted by
//---    reconstructing today's own-magic ENTRY deals from deal history, so
//---    a terminal restart cannot reset the cap. HistorySelect failure
//---    fails CLOSED (cap treated as reached, no extra trade). No second
//---    position while an own-magic position is open.
//--- 4. Stop = opposite range edge; target = entry +/- InpRRMultiple * risk
//---    distance (2R default). Entry, stop AND target are aligned to the
//---    SYMBOL_TRADE_TICK_SIZE grid (digits only set display precision).
//---    Stop distance must clear SYMBOL_TRADE_STOPS_LEVEL.
//--- 5. Size from ACTUAL entry (ask for BUY / bid for SELL) via
//---    OrderCalcProfit over (entry -> stop) for 1.0 lot; volume rounded
//---    DOWN to the volume step, NEVER forced up to the minimum: a
//---    below-minimum size skips the trade. Capped at maximum.
//--- 6. Symbol filling mode / trade mode respected; UNKNOWN filling modes
//---    are rejected (no order sent). Actual retcode checked
//---    (TRADE_RETCODE_DONE) and the position re-selected to confirm;
//---    DONE without a visible own position is logged unconfirmed.
//--- 7. Session-end flatten (non-overnight sessions only, which are the
//---    only accepted inputs): at/after InpSessionEnd the own position is
//---    closed (when InpSessionFlatten=true). No overnight flatten is
//---    advertised or attempted.
//--- 8. Every decision logs Print("T99 reason=...") with rule + values.
//--- 9. Tester export (tester Files dir, parent converts/normalizes later).
//---    TIME HONESTY: in the MQL5 Strategy Tester TimeGMT() equals the
//---    modeled SERVER time, so it is NEVER exported as UTC. All exports
//---    carry explicit SERVER timestamps plus a per-row seq and tester
//---    offset provenance. UTC conversion happens OFFLINE in
//---    tester_ea_convert.py under an explicitly frozen broker offset
//---    policy (constant only if genuinely valid over the whole window,
//---    otherwise dated transitions or the broker's real IANA zone; the
//---    parent verifies the actual HolaPrime policy before conversion).
//---    No offset is fabricated in the EA or the converter.
//---      T99_bars.csv   seq,server_time,open,high,low,close,bar_time_iso
//---                     (one row per COMPLETED bar, including the first
//---                     completed bar seen and the last completed bar at
//---                     deinit; bar_time is the completed bar's server
//---                     open time; seq keeps repeated server timestamps
//---                     distinguishable)
//---      T99_equity.csv seq,server_time,balance,equity
//---                     (initialization snapshot at init, then EVERY
//---                     tester tick via OnTick, then a final snapshot at
//---                     deinit; per-tick recording is best-effort —
//---                     coalesced ticks / weekend gaps are recording
//---                     limits documented in T99_run.json, never hidden)
//---      T99_deals.csv  seq,ticket,server_time,tester_utc_offset_sec,
//---                     symbol,magic,direction,entry,volume,price,
//---                     commission,swap,profit
//---                     (server_time = DEAL_TIME server clock; direction =
//---                     BUY|SELL from DEAL_TYPE; entry = IN|OUT|INOUT;
//---                     tester_utc_offset_sec = TimeTradeServer()-TimeGMT()
//---                     at export time, recorded as PROVENANCE ONLY —
//---                     in-tester it is ~0 and MUST NOT be used as a UTC
//---                     conversion; the frozen policy converts)
//---      T99_run.json   tester start/end server times, symbol/timeframe,
//---                     session inputs, file row counts, tick-recording
//---                     limits, and the frozen-policy filename the parent
//---                     used (or "PENDING_PARENT_POLICY" until verified).
//---    Coverage start/end are the first/last exported server times;
//---    tick_complete/event_complete MUST NOT be declared from a flag
//---    alone: the converter requires recorded run provenance (run file
//---    + row counts + coverage span covering the declared period) or it
//---    keeps sampled/absent.
string   g_symbol;
datetime g_last_bar = 0;
datetime g_last_exported_bar = 0;
datetime g_init_server_time = 0;
int      g_f_bars = INVALID_HANDLE;
int      g_f_equity = INVALID_HANDLE;
int      g_f_deals = INVALID_HANDLE;
int      g_f_run = INVALID_HANDLE;
long     g_seq_bars = 0, g_seq_equity = 0, g_seq_deals = 0;
ulong    g_exported_tickets[];
int      g_n_exported = 0;

//+------------------------------------------------------------------+
bool T99_InTester()
  {
   return((bool)MQLInfoInteger(MQL_TESTER));
  }

//+------------------------------------------------------------------+
int T99_HHMM_ToMinutes(string hm)
  {
   return((int)StringSubstr(hm, 0, 2) * 60 + (int)StringSubstr(hm, 3, 2));
  }

//+------------------------------------------------------------------+
//| Validate HH:MM server clock + reject overnight/degenerate input. |
//+------------------------------------------------------------------+
bool T99_ValidSession(string start, string end)
  {
   if(StringLen(start) != 5 || StringLen(end) != 5)
      return(false);
   if(StringGetCharacter(start, 2) != ':' || StringGetCharacter(end, 2) != ':')
      return(false);
   int sh = (int)StringSubstr(start, 0, 2), sm = (int)StringSubstr(start, 3, 2);
   int eh = (int)StringSubstr(end, 0, 2), em = (int)StringSubstr(end, 3, 2);
   if(sh < 0 || sh > 23 || eh < 0 || eh > 23 || sm < 0 || sm > 59 || em < 0 || em > 59)
      return(false);
   if(!(start < end))
      return(false);   // overnight (end <= start) and zero-length rejected
   return(true);
  }

//+------------------------------------------------------------------+
//| Align a price to the SYMBOL_TRADE_TICK_SIZE grid.                |
//+------------------------------------------------------------------+
double T99_AlignToTick(double price, double tick_sz, int digits)
  {
   if(!(tick_sz > 0.0))
      return(price);
   return(NormalizeDouble(MathFloor(price / tick_sz + 0.5) * tick_sz, digits));
  }

//+------------------------------------------------------------------+
bool T99_InSession(string hm, string start, string end)
  {
   if(start <= end)
      return(hm >= start && hm < end);
   return(hm >= start || hm < end);
  }

//+------------------------------------------------------------------+
datetime T99_TodayStart(datetime server_now)
  {
   MqlDateTime s;
   TimeToStruct(server_now, s);
   return(StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                   s.year, s.mon, s.day)));
  }

//+------------------------------------------------------------------+
//| Count today's OWN entry deals from history (restart-safe cap).   |
//+------------------------------------------------------------------+
int T99_CountTodayOwnEntries(datetime day_start, datetime now)
  {
   if(!HistorySelect(day_start, now + 60))
     {
      Print("T99 reason=cap_blocked: HistorySelect failed — failing CLOSED, "
            "no extra trade permitted.");
      return(InpMaxTradesDay);   // fail closed: treat cap as reached
     }
   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_symbol)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
bool T99_OwnPositionOpen()
  {
   if(!PositionSelect(g_symbol))
      return(false);
   return(PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

//+------------------------------------------------------------------+
//| Select ORDER filling from broker execution + filling permissions.  |
//| Official MQL5 table (book/automation/experts/experts_execution_   |
//| filling): RETURN is the default and is permitted EXCEPT under      |
//| MARKET execution (there it is '-'). SYMBOL_FILLING_MODE carries   |
//| only FOK/IOC permission bits (no RETURN flag exists); RETURN      |
//| needs no permission bit off-MARKET. UNKNOWN execution modes fail  |
//| CLOSED (no order sent). Used for BOTH open and flatten.           |
//+------------------------------------------------------------------+
bool T99_SelectFilling(ENUM_ORDER_TYPE_FILLING &fill)
  {
   long exemode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_EXEMODE);
   uint fmode = (uint)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   bool allow_fok = ((fmode & SYMBOL_FILLING_FOK) != 0);
   bool allow_ioc = ((fmode & SYMBOL_FILLING_IOC) != 0);
   if(exemode == SYMBOL_TRADE_EXECUTION_MARKET)
     {
      // MARKET: RETURN forbidden; need an advertised FOK/IOC bit.
      if(allow_fok)
        { fill = ORDER_FILLING_FOK; return(true); }
      if(allow_ioc)
        { fill = ORDER_FILLING_IOC; return(true); }
      Print("T99 reason=skip_fill: MARKET execution with no FOK/IOC "
            "permission (fmode=", fmode, ") — rejected (fail closed).");
      return(false);
     }
   if(exemode == SYMBOL_TRADE_EXECUTION_INSTANT
      || exemode == SYMBOL_TRADE_EXECUTION_REQUEST
      || exemode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
     {
      // Off-MARKET: RETURN always available; prefer advertised FOK/IOC.
      if(allow_fok)
        { fill = ORDER_FILLING_FOK; return(true); }
      if(allow_ioc)
        { fill = ORDER_FILLING_IOC; return(true); }
      fill = ORDER_FILLING_RETURN;
      return(true);
     }
   Print("T99 reason=skip_fill: unknown execution mode ", exemode,
         " — rejected (fail closed).");
   return(false);
  }

//+------------------------------------------------------------------+
bool T99_HasTicket(ulong ticket)
  {
   for(int i = 0; i < g_n_exported; i++)
      if(g_exported_tickets[i] == ticket)
         return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Explicit SERVER-time equity snapshot (never TimeGMT-as-UTC).     |
//+------------------------------------------------------------------+
void T99_ExportEquity()
  {
   if(g_f_equity == INVALID_HANDLE)
      return;
   g_seq_equity++;
   datetime server_now = TimeTradeServer();
   FileWrite(g_f_equity, g_seq_equity,
             TimeToString(server_now, TIME_DATE | TIME_SECONDS),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
  }

//+------------------------------------------------------------------+
//| Completed-bar export with the bar's own SERVER open time.        |
//+------------------------------------------------------------------+
void T99_ExportBar(datetime bar_time, double o, double h, double l, double c)
  {
   if(g_f_bars == INVALID_HANDLE)
      return;
   if(bar_time <= g_last_exported_bar)
      return;   // each completed bar exported once; seq still orders repeats
   g_seq_bars++;
   g_last_exported_bar = bar_time;
   FileWrite(g_f_bars, g_seq_bars,
             TimeToString(bar_time, TIME_DATE | TIME_SECONDS),
             DoubleToString(o, _Digits), DoubleToString(h, _Digits),
             DoubleToString(l, _Digits), DoubleToString(c, _Digits),
             TimeToString(bar_time, TIME_DATE | TIME_SECONDS));
  }

//+------------------------------------------------------------------+
void T99_ExportNewDeals(datetime day_start, datetime now)
  {
   if(g_f_deals == INVALID_HANDLE)
      return;
   if(!HistorySelect(day_start, now + 60))
     {
      Print("T99 reason=deals_gap: HistorySelect failed at export — gap "
            "logged, converter must treat coverage as incomplete.");
      return;
     }
   // Provenance only: in-tester TimeGMT()==server so this is ~0. The
   // frozen broker offset policy (parent scope) converts server_time.
   long tester_off = (long)(TimeTradeServer() - TimeGMT());
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || T99_HasTicket(ticket))
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_symbol)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      g_seq_deals++;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      string direction = "UNKNOWN";
      if(dtype == DEAL_TYPE_BUY)
         direction = "BUY";
      else if(dtype == DEAL_TYPE_SELL)
         direction = "SELL";
      string entry_s = "UNKNOWN";
      if(entry == DEAL_ENTRY_IN)
         entry_s = "IN";
      else if(entry == DEAL_ENTRY_OUT)
         entry_s = "OUT";
      else if(entry == DEAL_ENTRY_INOUT)
         entry_s = "INOUT";
      FileWrite(g_f_deals, g_seq_deals, ticket,
                TimeToString((datetime)HistoryDealGetInteger(ticket, DEAL_TIME),
                             TIME_DATE | TIME_SECONDS),
                tester_off, g_symbol, InpMagic, direction, entry_s,
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), _Digits),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2));
      if(g_n_exported >= ArraySize(g_exported_tickets))
         ArrayResize(g_exported_tickets,
                     ArraySize(g_exported_tickets) + 1024);
      if(g_n_exported < ArraySize(g_exported_tickets))
         g_exported_tickets[g_n_exported++] = ticket;
      else
         Print("T99 reason=deals_gap: export ticket buffer full — gap "
               "logged, converter must treat coverage as incomplete.");
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = (InpSymbol == "" ? _Symbol : InpSymbol);
   //--- unconditional tester guard: no bypass exists
   if(!T99_InTester())
     {
      Print("T99 reason=init_refused: not in strategy tester; "
            "this EA never trades outside MQL_TESTER.");
      return(INIT_FAILED);
     }
   if(!T99_ValidSession(InpSessionStart, InpSessionEnd))
     {
      Print("T99 reason=init_refused: overnight/degenerate session rejected "
            "(start=", InpSessionStart, " end=", InpSessionEnd,
            "); use a same-day window with end > start.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
     {
      Print("T99 reason=init_refused: InpRiskPercent out of (0,5].");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRangeMinutes <= 0 || InpMaxTradesDay < 1 || InpRRMultiple <= 0.0)
     {
      Print("T99 reason=init_refused: range/trades/RR inputs invalid.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   ArrayResize(g_exported_tickets, 1024);
   g_n_exported = 0;
   g_last_bar = 0;
   g_last_exported_bar = 0;
   g_init_server_time = TimeTradeServer();
   g_f_bars = FileOpen("T99_bars.csv", FILE_WRITE | FILE_READ | FILE_CSV, ',');
   g_f_equity = FileOpen("T99_equity.csv", FILE_WRITE | FILE_READ | FILE_CSV, ',');
   g_f_deals = FileOpen("T99_deals.csv", FILE_WRITE | FILE_READ | FILE_CSV, ',');
   g_f_run = FileOpen("T99_run.json", FILE_WRITE | FILE_TXT);
   if(g_f_bars != INVALID_HANDLE)
      FileWrite(g_f_bars, "seq", "server_time", "open", "high", "low", "close",
                "bar_time_iso");
   if(g_f_equity != INVALID_HANDLE)
      FileWrite(g_f_equity, "seq", "server_time", "balance", "equity");
   if(g_f_deals != INVALID_HANDLE)
      FileWrite(g_f_deals, "seq", "ticket", "server_time",
                "tester_utc_offset_sec", "symbol", "magic", "direction",
                "entry", "volume", "price", "commission", "swap", "profit");
   if(g_f_run != INVALID_HANDLE)
     {
      FileWriteString(g_f_run,
         StringFormat("{\"ea\":\"ORB-v1.0\",\"tester_only\":true,\"symbol\":\"%s\",\"timeframe\":%d,"
                      "\"session_start\":\"%s\",\"session_end\":\"%s\",\"range_minutes\":%d,"
                      "\"init_server_time\":\"%s\",\"broker_offset_policy\":\"PENDING_PARENT_POLICY\","
                      "\"tick_recording\":\"best_effort_per_OnTick;_gaps_possible;_weekends_no_ticks\","
                      "\"time_note\":\"all_times_are_SERVER;_TimeGMT_not_used_as_UTC\"}",
                      g_symbol, InpTimeframe, InpSessionStart, InpSessionEnd,
                      InpRangeMinutes,
                      TimeToString(g_init_server_time, TIME_DATE | TIME_SECONDS)));
      FileClose(g_f_run);
      g_f_run = INVALID_HANDLE;
     }
   T99_ExportEquity();   // initialization snapshot (seq 1)
   Print("T99 reason=init_ok: ORB-v1.0 frozen rules active on ", g_symbol,
         " (tester only; compile log owned by parent terminal run).");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Final snapshot: last completed bar + final equity + open deals.  |
//+------------------------------------------------------------------+
void T99_ExportFinalBar()
  {
   if(g_f_bars == INVALID_HANDLE)
      return;
   datetime tm[];
   double hi[], lo[], cl[];
   if(CopyTime(g_symbol, InpTimeframe, 1, 1, tm) < 1)
      return;
   if(CopyHigh(g_symbol, InpTimeframe, 1, 1, hi) < 1)
      return;
   if(CopyLow(g_symbol, InpTimeframe, 1, 1, lo) < 1)
      return;
   if(CopyClose(g_symbol, InpTimeframe, 1, 1, cl) < 1)
      return;
   double op = iOpen(g_symbol, InpTimeframe, 1);
   // Run-start filter (same as OnTick): a pre-run final bar would make
   // offline conversion impossible, so it is skipped, not exported.
   if(tm[0] < g_init_server_time)
     {
      Print("T99 reason=skip_prerun_bar: final bar before run start — "
            "not exported (conversion filter).");
      return;
     }
   T99_ExportBar(tm[0], op, hi[0], lo[0], cl[0]);   // last completed bar
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(T99_InTester())
     {
      T99_ExportFinalBar();   // declared-period last completed bar
      datetime server_now = TimeTradeServer();
      // Full-run deal flush: HistorySelect from run start so tester-end
      // closures from any day are exported. An still-open remainder at
      // tester end stays open in the file — the offline converter rejects
      // it (fail closed) and downstream stays INCONCLUSIVE, never invents
      // an endpoint. OrderSend is not attempted in OnDeinit.
      T99_ExportNewDeals(g_init_server_time, server_now);
      T99_ExportEquity();     // final equity snapshot
      Print("T99 reason=deinit_export: final bar/equity/deals flushed; "
            "coverage_end_server=", TimeToString(server_now, TIME_DATE | TIME_SECONDS));
     }
   if(g_f_bars != INVALID_HANDLE)
     { FileClose(g_f_bars); g_f_bars = INVALID_HANDLE; }
   if(g_f_equity != INVALID_HANDLE)
     { FileClose(g_f_equity); g_f_equity = INVALID_HANDLE; }
   if(g_f_deals != INVALID_HANDLE)
     { FileClose(g_f_deals); g_f_deals = INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
bool T99_NewCompletedBar()
  {
   datetime t[];
   if(CopyTime(g_symbol, InpTimeframe, 0, 1, t) < 1)
      return(false);
   if(t[0] == g_last_bar)
      return(false);
   g_last_bar = t[0];
   return(true);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- unconditional tester guard (no bypass): silently ignore off-tester
   if(!T99_InTester())
      return;
   T99_ExportEquity();   // every tester tick, sequenced

   datetime server_now = TimeTradeServer();
   datetime day_start = T99_TodayStart(server_now);
   // Deal export covers the FULL run (run-start filter), not just today,
   // so final tester closures are never missed at day boundaries/deinit.
   T99_ExportNewDeals(g_init_server_time, server_now);

   //--- session-end flatten of the OWN position (runs every tick;
   //--- non-overnight sessions only — overnight inputs are rejected at
   //--- init, so no overnight flatten is advertised or attempted)
   MqlDateTime sn;
   TimeToStruct(server_now, sn);
   string now_hm = StringFormat("%02d:%02d", sn.hour, sn.min);
   if(InpSessionFlatten && T99_OwnPositionOpen()
      && !T99_InSession(now_hm, InpSessionStart, InpSessionEnd)
      && now_hm >= InpSessionEnd)
     {
      long ptype = PositionGetInteger(POSITION_TYPE);
      bool is_buy = (ptype == POSITION_TYPE_BUY);
      // MqlTradeRequest carries the CLOSING position ticket in `position`
      // (there is no `position_id` field); the ticket (not the identifier)
      // selects the position to close.
      ulong close_ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double close_vol = (double)PositionGetDouble(POSITION_VOLUME);
      ENUM_ORDER_TYPE_FILLING ffill;
      if(!T99_SelectFilling(ffill))
        {
         Print("T99 reason=flatten_failed: unknown execution/filling mode "
               "— fail closed, no close sent.");
         return;
        }
      MqlTradeRequest cf;
      MqlTradeResult  cr;
      ZeroMemory(cf);
      ZeroMemory(cr);
      double ftick = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
      int fdigits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
      double fraw = (is_buy ? SymbolInfoDouble(g_symbol, SYMBOL_BID)
                           : SymbolInfoDouble(g_symbol, SYMBOL_ASK));
      cf.action = TRADE_ACTION_DEAL;
      cf.symbol = g_symbol;
      cf.volume = close_vol;
      cf.type = is_buy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      cf.price = T99_AlignToTick(fraw, ftick, fdigits);
      cf.position = close_ticket;
      cf.deviation = InpMaxDeviation;
      cf.type_filling = ffill;
      cf.type_time = ORDER_TIME_GTC;
      cf.magic = InpMagic;
      cf.comment = "T99-flatten";
      if(OrderSend(cf, cr) && cr.retcode == TRADE_RETCODE_DONE)
        {
         // Verify the close: DONE alone does not prove the position is
         // gone — re-select the own position before claiming a flatten.
         if(T99_OwnPositionOpen())
            Print("T99 reason=flatten_unconfirmed: retcode DONE but own "
                  "position still open after close, deal=", cr.deal);
         else
           {
            Print("T99 reason=flatten: session end, own position closed, "
                  "deal=", cr.deal);
            T99_ExportNewDeals(g_init_server_time, TimeTradeServer());
           }
        }
      else
         Print("T99 reason=flatten_failed: retcode=", cr.retcode,
               " comment=", cr.comment);
      return;
     }

   if(!T99_NewCompletedBar())
      return;   // bar 0 (forming) is never evaluated

   //--- today's absolute window datetimes (same server day only)
   MqlDateTime sd;
   TimeToStruct(day_start, sd);
   string day_prefix = StringFormat("%04d.%02d.%02d ", sd.year, sd.mon, sd.day);
   datetime range_start = StringToTime(day_prefix + InpSessionStart);
   datetime range_end = range_start + InpRangeMinutes * 60;

   //--- COMPLETED-BAR EXPORT outside all decision/session/cap gates: every
   //--- new completed bar is exported once here, before any early return
   //--- below. Run-start filter: a pre-run bar (before the tester run
   //--- start) is skipped, otherwise offline conversion would face an
   //--- impossible out-of-period bar. No strategy change: export only.
   {
      datetime etm[];
      double ehi[], elo[], ecl[];
      if(CopyTime(g_symbol, InpTimeframe, 1, 1, etm) == 1
         && CopyHigh(g_symbol, InpTimeframe, 1, 1, ehi) == 1
         && CopyLow(g_symbol, InpTimeframe, 1, 1, elo) == 1
         && CopyClose(g_symbol, InpTimeframe, 1, 1, ecl) == 1)
        {
         double eop = iOpen(g_symbol, InpTimeframe, 1);
         if(etm[0] >= g_init_server_time)
            T99_ExportBar(etm[0], eop, ehi[0], elo[0], ecl[0]);
         else
            Print("T99 reason=skip_prerun_bar: completed bar ",
                  TimeToString(etm[0], TIME_DATE | TIME_SECONDS),
                  " before run start — not exported (conversion filter).");
        }
   }

   if(server_now < range_end)
     {
      Print("T99 reason=before_range: window not complete yet.");
      return;
     }

   //--- FULL same-day history (real-run fix): the old fixed
   //--- need=rangebars+10 lets the opening window fall outside the copied
   //--- history as the day advances. Fetch from midnight so the window
   //--- stays visible all session; require ALL expected window bars and
   //--- fail closed on a partial window (no silent partial range).
   //--- Strategy unchanged: same window, same strict breakout.
   long tf_sec = PeriodSeconds(InpTimeframe);
   if(tf_sec <= 0)
     {
      Print("T99 reason=no_data: invalid timeframe seconds.");
      return;
     }
   long win_sec = (long)InpRangeMinutes * 60;
   int exp_bars = (int)((win_sec + tf_sec - 1) / tf_sec);  // ceil
   if(exp_bars < 1)
      exp_bars = 1;
   long day_span = (long)(server_now - day_start);
   if(day_span < 0)
      day_span = 0;
   int need_full = (int)(day_span / tf_sec) + 10;
   if(need_full < exp_bars + 10)
      need_full = exp_bars + 10;
   if(need_full < 3)
      need_full = 3;
   datetime tm[];
   double hi[], lo[], cl[];
   int bars = CopyTime(g_symbol, InpTimeframe, 0, need_full, tm);
   if(bars < exp_bars || CopyHigh(g_symbol, InpTimeframe, 0, need_full, hi) < exp_bars ||
      CopyLow(g_symbol, InpTimeframe, 0, need_full, lo) < exp_bars ||
      CopyClose(g_symbol, InpTimeframe, 0, need_full, cl) < exp_bars)
     {
      Print("T99 reason=no_data: history too short for full-day range "
            "(need_full=", need_full, ").");
      return;
     }
   ArraySetAsSeries(tm, true);
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(cl, true);

   //--- range from completed bars (shift>=1) strictly inside today's window
   double rh = -DBL_MAX, rl = DBL_MAX;
   int found = 0;
   for(int i = 1; i < bars; i++)
     {
      if(tm[i] < range_start || tm[i] >= range_end)
         continue;   // same-day window only: older days / later bars excluded
      if(hi[i] > rh)
         rh = hi[i];
      if(lo[i] < rl)
         rl = lo[i];
      found++;
     }
   if(found != exp_bars)
     {
      Print("T99 reason=no_range: incomplete opening window (found=", found,
            " expected=", exp_bars, ") — no signal (fail closed, no partial).");
      return;
     }
   // Note: the last completed bar was already exported above (deduped by
   // T99_ExportBar); no second export here, so session/cap/signal gates
   // never suppress bar coverage.

   //--- signal bar: last completed close; must be AFTER the complete window
   if(tm[1] < range_end)
     {
      Print("T99 reason=wait_window: last completed bar still inside range window.");
      return;
     }
   MqlDateTime st;
   TimeToStruct(tm[1], st);
   string hm = StringFormat("%02d:%02d", st.hour, st.min);
   if(!T99_InSession(hm, InpSessionStart, InpSessionEnd))
     {
      Print("T99 reason=skip_session: completed bar ", hm, " outside session.");
      return;
     }
   if(T99_CountTodayOwnEntries(day_start, server_now) >= InpMaxTradesDay)
     {
      Print("T99 reason=skip_daily_cap: daily entry cap reached "
            "(reconstructed from own magic history).");
      return;
     }
   if(T99_OwnPositionOpen())
     {
      Print("T99 reason=skip_open_position: own position already open.");
      return;
     }

   //--- close-confirmed breakout, strict: equality is NO signal
   double c1 = cl[1];
   bool long_sig = (c1 > rh);
   bool short_sig = (c1 < rl);
   if(!long_sig && !short_sig)
     {
      Print("T99 reason=no_break: close=", DoubleToString(c1, _Digits),
            " inside [", DoubleToString(rl, _Digits), ", ",
            DoubleToString(rh, _Digits), "].");
      return;
     }

   //--- symbol trade mode
   long tmode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(long_sig && (tmode == SYMBOL_TRADE_MODE_SHORTONLY))
     {
      Print("T99 reason=skip_mode: symbol long-only/short-only blocks BUY.");
      return;
     }
   if(short_sig && (tmode == SYMBOL_TRADE_MODE_LONGONLY))
     {
      Print("T99 reason=skip_mode: symbol long-only/short-only blocks SELL.");
      return;
     }

   //--- actual entry (bid/ask) + stop/target on the TICK grid
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   double tick_sz = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(!(tick_sz > 0.0))
     {
      Print("T99 reason=skip_size: invalid tick size for price grid.");
      return;
     }
   double entry_raw = (long_sig ? SymbolInfoDouble(g_symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(g_symbol, SYMBOL_BID));
   double entry = T99_AlignToTick(entry_raw, tick_sz, digits);
   double stop = T99_AlignToTick(long_sig ? rl : rh, tick_sz, digits);
   double risk_dist = MathAbs(entry - stop);
   double min_stop = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL)
                     * SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(!(risk_dist > min_stop))
     {
      Print("T99 reason=skip_stops_level: risk distance inside stops level.");
      return;
     }
   double tp = T99_AlignToTick(
                  entry + (long_sig ? 1.0 : -1.0) * InpRRMultiple * risk_dist,
                  tick_sz, digits);

   //--- size from ACTUAL entry via OrderCalcProfit; round DOWN, never min-up
   double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double pl_one = 0.0;
   if(!OrderCalcProfit(long_sig ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                       g_symbol, 1.0, entry, stop, pl_one))
     {
      Print("T99 reason=skip_size: OrderCalcProfit failed.");
      return;
     }
   double loss_one = MathAbs(pl_one);
   if(!(loss_one > 0.0))
     {
      Print("T99 reason=skip_size: zero loss distance for 1.0 lot.");
      return;
     }
   double vmin = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(!(vstep > 0.0) || !(vmax >= vmin) || !(vmin > 0.0))
     {
      Print("T99 reason=skip_size: invalid volume constraints.");
      return;
     }
   double vol = MathFloor(risk_money / loss_one / vstep) * vstep;
   int vol_digits = 0;
   for(double s = vstep; s < 1.0 && vol_digits < 8; s *= 10.0)
      vol_digits++;
   vol = NormalizeDouble(vol, vol_digits);
   if(vol > vmax)
      vol = vmax;   // capping only ever reduces risk
   if(vol < vmin)
     {
      Print("T99 reason=skip_size: risk-sized volume ", DoubleToString(vol, vol_digits),
            " below minimum ", DoubleToString(vmin, vol_digits),
            " — skipped, never forced up (would exceed risk).");
      return;
     }

   //--- filling from broker execution + filling permissions (shared with
   //--- flatten; RETURN except MARKET, unknown fails closed — see helper).
   ENUM_ORDER_TYPE_FILLING fill;
   if(!T99_SelectFilling(fill))
     {
      Print("T99 reason=skip_fill: execution/filling unsupported — rejected.");
      return;
     }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = g_symbol;
   req.volume = vol;
   req.type = long_sig ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = entry;
   req.sl = stop;
   req.tp = tp;
   req.deviation = InpMaxDeviation;
   req.type_filling = fill;
   req.type_time = ORDER_TIME_GTC;
   req.magic = (ulong)InpMagic;
   req.comment = "T99-ORB";
   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
     {
      Print("T99 reason=send_failed: retcode=", res.retcode, " comment=",
            res.comment);
      return;
     }
   if(!T99_OwnPositionOpen())
     {
      Print("T99 reason=send_unconfirmed: retcode DONE but own position "
            "not found after send, deal=", res.deal);
      return;
     }
   T99_ExportNewDeals(g_init_server_time, TimeTradeServer());
   Print("T99 reason=entry: ", (long_sig ? "BUY" : "SELL"), " vol=",
         DoubleToString(vol, vol_digits),
         " entry=", DoubleToString(entry, digits),
         " sl=", DoubleToString(stop, digits),
         " tp=", DoubleToString(tp, digits),
         " range=[", DoubleToString(rl, digits), ", ",
         DoubleToString(rh, digits), "] deal=", res.deal);
  }
//+------------------------------------------------------------------+
