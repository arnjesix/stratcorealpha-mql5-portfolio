//+------------------------------------------------------------------+
//| SCA_Getestet2_LondonBreakout_v12.mq5 — Getestet #2 v1.2 (SERVER)  |
//| Status: COMPLETE implementation of the frozen v1.2 server-clock  |
//| proxy (RULES_london_breakout_v1.2.md). Compiled + run ONLY in the |
//| isolated HolaPrime MT5 Strategy Tester via the worker-owned ini.  |
//| TESTER ONLY: refuses to run outside the strategy tester          |
//| (INIT_PARAMETERS_INCORRECT off-tester). No live switch, no demo/ |
//| live bypass, no off-tester order path. No DLL. Fixed 0.01 lot.    |
//| Caveat: the 10:00/11:00/14:00/19:00 SERVER grid is a fixed proxy  |
//| and is NOT established exact London wall time (rules v1.2 §0).    |
//| Time exit: first modelled tick at-or-after 19:00 SERVER, same     |
//| server date, at market (incl. OnTick no-new-bar path).            |
//+------------------------------------------------------------------+
#property copyright "StratCoreAlpha Getestet #2 v1.2 (tester only)"
#property version   "1.20"

//--- FROZEN INPUTS v1.2 (changing any value = new rules version + re-log)
input string InpSymbol       = "";            // "" = chart symbol (EURUSD)
input ENUM_TIMEFRAMES InpTF  = PERIOD_M15;    // fixed M15
input string InpRangeStart   = "10:00";       // SERVER HH:MM range start
input string InpRangeEnd     = "11:00";       // SERVER HH:MM range end = entry start
input string InpEntryEnd     = "14:00";       // SERVER HH:MM entry end (exclusive)
input string InpTimeExit     = "19:00";       // SERVER HH:MM flat (same server date)
input double InpTargetR      = 1.0;           // target multiple of risk
input double InpMinRangePips = 3.0;           // degenerate guard, pips
input double InpFixedLot     = 0.01;          // FROZEN fixed volume
input long   InpMagic        = 20260927;      // own magic (history cap)
input int    InpMaxDeviation = 10;            // slippage, points

//--- Run state
string   g_symbol;
int      g_rangeStartMin, g_rangeEndMin, g_entryEndMin, g_flatMin;
double   g_pip, g_tickSize;
int      g_digits;
datetime g_lastBar;
datetime g_lastExportedBar;
datetime g_initServer;
int      g_dayKey;
int      g_rangeCount;
double   g_rangeHi, g_rangeLo;
bool     g_rangeDone, g_rangeLogged;
//--- Export handles + seq
int      g_fBars, g_fEquity, g_fDeals, g_fEvents, g_fRun;
long     g_seqBars, g_seqEquity, g_seqDeals, g_seqEvents;

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
bool G2_InTester()
  {
   return((bool)MQLInfoInteger(MQL_TESTER));
  }

int G2_ParseHM(string hm)
  {
   StringTrimLeft(hm);
   StringTrimRight(hm);
   if(StringLen(hm) != 5)
      return(-1);
   if(StringGetCharacter(hm, 2) != ':')
      return(-1);
   int hh = (int)StringToInteger(StringSubstr(hm, 0, 2));
   int mm = (int)StringToInteger(StringSubstr(hm, 3, 2));
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return(-1);
   return(hh * 60 + mm);
  }

int G2_MinOfDay(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return(s.hour * 60 + s.min);
  }

int G2_DayKey(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return(s.day_of_year * 10000 + s.year);
  }

string G2_Tchords(datetime t)
  {
   return(TimeToString(t, TIME_DATE | TIME_SECONDS));
  }

//--- Align price DOWN/UP to the tick grid (digits set display precision only)
double G2_AlignDown(double price, double tick)
  {
   if(tick <= 0)
      return(NormalizeDouble(price, g_digits));
   return(NormalizeDouble(MathFloor(price / tick + 1e-9) * tick, g_digits));
  }

double G2_AlignUp(double price, double tick)
  {
   if(tick <= 0)
      return(NormalizeDouble(price, g_digits));
   return(NormalizeDouble(MathCeil(price / tick - 1e-9) * tick, g_digits));
  }

//+------------------------------------------------------------------+
//| Event + equity export                                            |
//+------------------------------------------------------------------+
void G2_Event(datetime srv, string ev, string detail)
  {
   if(g_fEvents == INVALID_HANDLE)
      return;
   FileSeek(g_fEvents, 0, SEEK_END);
   FileWrite(g_fEvents, g_seqEvents, G2_Tchords(srv), ev, detail);
   g_seqEvents++;
  }

void G2_Equity(datetime srv)
  {
   if(g_fEquity == INVALID_HANDLE)
      return;
   FileSeek(g_fEquity, 0, SEEK_END);
   FileWrite(g_fEquity, g_seqEquity, G2_Tchords(srv),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   g_seqEquity++;
  }

void G2_BarRow(datetime srv, datetime barOpen, double o, double h, double l, double c)
  {
   if(g_fBars == INVALID_HANDLE)
      return;
   FileSeek(g_fBars, 0, SEEK_END);
   FileWrite(g_fBars, g_seqBars, G2_Tchords(srv),
             DoubleToString(o, g_digits), DoubleToString(h, g_digits),
             DoubleToString(l, g_digits), DoubleToString(c, g_digits),
             G2_Tchords(barOpen));
   g_seqBars++;
   g_lastExportedBar = barOpen;
  }

//+------------------------------------------------------------------+
//| One-a-day cap: count today's own-magic ENTRY deals (fail closed) |
//+------------------------------------------------------------------+
int G2_FillsToday()
  {
   datetime now = TimeTradeServer();
   if(!HistorySelect(0, now + 86400))
     {
      G2_Event(now, "history_fail_closed", "HistorySelect failed; cap treated as reached");
      return(1);
     }
   int n = 0;
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
      datetime dt = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(G2_DayKey(dt) == g_dayKey)
         n++;
     }
   return(n);
  }

bool G2_OwnPositionOpen(ulong &ticket_out)
  {
   ticket_out = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket((uint)i);
      if(tk == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      ticket_out = tk;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Volume: frozen 0.01 clamped to grid, never forced up             |
//+------------------------------------------------------------------+
double G2_FixedVolume(string &skip_reason)
  {
   skip_reason = "";
   double vmin = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0)
      vstep = 0.01;
   double v = MathFloor(InpFixedLot / vstep + 1e-9) * vstep;
   v = NormalizeDouble(v, 2);
   if(v < vmin - 1e-9)
     {
      skip_reason = StringFormat("lot_below_min v=%.2f vmin=%.2f", v, vmin);
      return(0);
     }
   if(v > vmax)
      v = vmax;
   return(NormalizeDouble(v, 2));
  }

//+------------------------------------------------------------------+
//| Order send with filling-mode + trade-mode checks                 |
//+------------------------------------------------------------------+
bool G2_Send(bool isBuy, double entry, double sl, double tp, double vol)
  {
   long tmode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_MODE_DISABLED || tmode == SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      G2_Event(TimeTradeServer(), "skip", "trade_mode_closed_for_symbol");
      return(false);
     }
   if(isBuy && tmode == SYMBOL_TRADE_MODE_SHORTONLY)
     {
      G2_Event(TimeTradeServer(), "skip", "trade_mode_short_only");
      return(false);
     }
   if(!isBuy && tmode == SYMBOL_TRADE_MODE_LONGONLY)
     {
      G2_Event(TimeTradeServer(), "skip", "trade_mode_long_only");
      return(false);
     }
   long fmode = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   ENUM_ORDER_TYPE_FILLING fills[3];
   int nfill = 0;
   if((fmode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
     {
      fills[nfill] = ORDER_FILLING_IOC;
      nfill++;
     }
   if((fmode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
     {
      fills[nfill] = ORDER_FILLING_FOK;
      nfill++;
     }
   // RETURN (no flag) is always attempted last.
   fills[nfill] = ORDER_FILLING_RETURN;
   nfill++;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = g_symbol;
   req.volume   = vol;
   req.type     = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price    = entry;
   req.sl       = sl;
   req.tp       = tp;
   req.deviation = InpMaxDeviation;
   req.magic    = InpMagic;
   req.comment  = "G2v12";

   for(int k = 0; k < nfill; k++)
     {
      req.type_filling = fills[k];
      ZeroMemory(res);
      if(!OrderSend(req, res))
        {
         G2_Event(TimeTradeServer(), "send_fail",
                  StringFormat("fill=%d err=%d", (int)fills[k], GetLastError()));
         continue;
        }
      if(res.retcode == TRADE_RETCODE_DONE)
        {
         ulong tk = 0;
         bool open = G2_OwnPositionOpen(tk);
         G2_Event(TimeTradeServer(), open ? "fill" : "fill_unconfirmed",
                  StringFormat("dir=%s vol=%.2f price=%.5f sl=%.5f tp=%.5f deal=%I64u",
                               isBuy ? "BUY" : "SELL", vol, res.price, sl, tp, res.deal));
         return(open);
        }
      G2_Event(TimeTradeServer(), "send_retcode",
               StringFormat("fill=%d retcode=%u comment=%s", (int)fills[k], res.retcode, res.comment));
     }
   return(false);
  }

bool G2_ClosePosition(ulong ticket, string why)
  {
   if(!PositionSelectByTicket(ticket))
     {
      G2_Event(TimeTradeServer(), "close_skip", why + " no_position");
      return(false);
     }
   string sym = PositionGetString(POSITION_SYMBOL);
   long ptype = PositionGetInteger(POSITION_TYPE);
   double pvol = PositionGetDouble(POSITION_VOLUME);
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
     {
      G2_Event(TimeTradeServer(), "close_fail", why + " no_tick");
      return(false);
     }
   long fmode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   ENUM_ORDER_TYPE_FILLING fills[3];
   int nfill = 0;
   if((fmode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
     {
      fills[nfill] = ORDER_FILLING_IOC;
      nfill++;
     }
   if((fmode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
     {
      fills[nfill] = ORDER_FILLING_FOK;
      nfill++;
     }
   fills[nfill] = ORDER_FILLING_RETURN;
   nfill++;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = sym;
   req.volume   = pvol;
   req.type     = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.position = ticket;
   req.deviation = InpMaxDeviation;
   req.magic    = InpMagic;
   req.comment  = "G2v12flat";
   for(int k = 0; k < nfill; k++)
     {
      req.type_filling = fills[k];
      req.price = (req.type == ORDER_TYPE_SELL) ? tick.bid : tick.ask;
      ZeroMemory(res);
      if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
        {
         G2_Event(TimeTradeServer(), "exit",
                  StringFormat("%s price=%.5f deal=%I64u", why, res.price, res.deal));
         return(true);
        }
     }
   G2_Event(TimeTradeServer(), "close_fail", why + " retcode_path_exhausted");
   return(false);
  }

//+------------------------------------------------------------------+
//| OnInit: tester gate, input validation, export headers            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!G2_InTester())
     {
      Print("G2v12 refuse: tester-only EA started off-tester");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(_Period != PERIOD_M15 || InpTF != PERIOD_M15)
     {
      Print("G2v12 refuse: M15 chart required");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_rangeStartMin = G2_ParseHM(InpRangeStart);
   g_rangeEndMin   = G2_ParseHM(InpRangeEnd);
   g_entryEndMin   = G2_ParseHM(InpEntryEnd);
   g_flatMin       = G2_ParseHM(InpTimeExit);
   if(g_rangeStartMin < 0 || g_rangeEndMin < 0 || g_entryEndMin < 0 || g_flatMin < 0)
     {
      Print("G2v12 refuse: HH:MM inputs malformed");
      return(INIT_PARAMETERS_INCORRECT);
     }
   // Frozen v1.2 ordering: 10:00 < 11:00 < 14:00 < 19:00 (same-day session).
   if(!(g_rangeStartMin < g_rangeEndMin && g_rangeEndMin < g_entryEndMin && g_entryEndMin < g_flatMin))
     {
      Print("G2v12 refuse: window ordering violated");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpTargetR <= 0 || InpFixedLot <= 0 || InpMinRangePips <= 0)
     {
      Print("G2v12 refuse: non-positive numeric input");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_symbol = (InpSymbol == "") ? _Symbol : InpSymbol;
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0)
      g_tickSize = pt;
   // Pip = 10 points on 3/5-digit symbols, else 1 point.
   g_pip = pt * ((g_digits == 3 || g_digits == 5) ? 10.0 : 1.0);

   g_lastBar = 0;
   g_lastExportedBar = 0;
   g_dayKey = -1;
   g_seqBars = g_seqEquity = g_seqDeals = g_seqEvents = 0;
   g_initServer = TimeTradeServer();

   g_fBars = FileOpen("g2_lb12_bars.csv", FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   g_fEquity = FileOpen("g2_lb12_equity.csv", FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   g_fDeals = FileOpen("g2_lb12_deals.csv", FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   g_fEvents = FileOpen("g2_lb12_events.csv", FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   g_fRun = FileOpen("g2_lb12_run.json", FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
   if(g_fBars == INVALID_HANDLE || g_fEquity == INVALID_HANDLE ||
      g_fDeals == INVALID_HANDLE || g_fEvents == INVALID_HANDLE || g_fRun == INVALID_HANDLE)
     {
      Print("G2v12 refuse: export file open failed");
      return(INIT_FAILED);
     }
   FileWrite(g_fBars, "seq", "server_time", "open", "high", "low", "close", "bar_time_iso");
   FileWrite(g_fEquity, "seq", "server_time", "balance", "equity");
   FileWrite(g_fDeals, "seq", "ticket", "server_time", "symbol", "magic",
             "direction", "entry", "volume", "price", "commission", "swap", "profit");
   FileWrite(g_fEvents, "seq", "server_time", "event", "detail");
   G2_Event(g_initServer, "init",
            StringFormat("rules=v1.2 symbol=%s tf=M15 range=%s-%s entry_end=%s flat=%s R=%.2f lot=%.2f magic=%I64d",
                         g_symbol, InpRangeStart, InpRangeEnd, InpEntryEnd, InpTimeExit,
                         InpTargetR, InpFixedLot, InpMagic));
   G2_Equity(g_initServer);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnTick: equity trace + completed-bar state machine               |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!G2_InTester())
      return;
   datetime srv = TimeTradeServer();
   G2_Equity(srv);

   datetime curBar = iTime(g_symbol, PERIOD_M15, 0);
   if(curBar == 0 || curBar == g_lastBar)
     {
      // No new completed bar: v1.2 first-tick flat — enforce every tick.
      ulong tk;
      if(G2_OwnPositionOpen(tk) && G2_MinOfDay(srv) >= g_flatMin)
         G2_ClosePosition(tk, "time_exit");
      return;
     }
   // A new bar opened => shift 1 is the latest COMPLETED bar.
   g_lastBar = curBar;
   datetime barOpen = iTime(g_symbol, PERIOD_M15, 1);
   if(barOpen == 0)
      return;
   double o = iOpen(g_symbol, PERIOD_M15, 1);
   double h = iHigh(g_symbol, PERIOD_M15, 1);
   double l = iLow(g_symbol, PERIOD_M15, 1);
   double c = iClose(g_symbol, PERIOD_M15, 1);
   if(o == 0 && h == 0 && l == 0 && c == 0)
      return;
   G2_BarRow(srv, barOpen, o, h, l, c);

   int bkey = G2_DayKey(barOpen);
   int bmin = G2_MinOfDay(barOpen);
   if(bkey != g_dayKey)
     {
      // New server date: export yesterday's range verdict once.
      if(g_dayKey >= 0 && !g_rangeLogged && g_rangeCount > 0 && g_rangeCount < 4 && g_rangeStartMin >= 0)
        {
         G2_Event(srv, "no_trade",
                  StringFormat("reason=range_incomplete have=%d need=4 datekey=%d", g_rangeCount, g_dayKey));
        }
      g_dayKey = bkey;
      g_rangeCount = 0;
      g_rangeHi = 0;
      g_rangeLo = 0;
      g_rangeDone = false;
      g_rangeLogged = false;
     }

   //--- 1. Range accumulation: completed bars opening in [start, end)
   if(bmin >= g_rangeStartMin && bmin < g_rangeEndMin)
     {
      if(g_rangeCount == 0)
        {
         g_rangeHi = h;
         g_rangeLo = l;
        }
      else
        {
         if(h > g_rangeHi)
            g_rangeHi = h;
         if(l < g_rangeLo)
            g_rangeLo = l;
        }
      g_rangeCount++;
      if(g_rangeCount == 4)
        {
         g_rangeDone = true;
         double widthPips = (g_rangeHi - g_rangeLo) / g_pip;
         G2_Event(srv, "range",
                  StringFormat("hi=%.5f lo=%.5f width_pips=%.2f", g_rangeHi, g_rangeLo, widthPips));
         if(g_rangeHi - g_rangeLo < InpMinRangePips * g_pip - 1e-12)
            G2_Event(srv, "no_trade", "reason=range_degenerate");
        }
      return; // range bars are never signal candidates
     }

   //--- 2. Range completeness verdict at entry-start boundary (logged once)
   if(!g_rangeLogged && bmin >= g_rangeEndMin && bmin < g_entryEndMin && !g_rangeDone)
     {
      g_rangeLogged = true;
      G2_Event(srv, "no_trade",
               StringFormat("reason=range_incomplete have=%d need=4", g_rangeCount));
     }

   //--- 3. Flat leg v1.2: first tick at/after 19:00 SERVER (tick path above governs; bar check re-affirms).
   ulong pticket;
   bool hasPos = G2_OwnPositionOpen(pticket);
   if(hasPos && bmin >= g_flatMin)
     {
      G2_ClosePosition(pticket, "time_exit");
      return;
     }
   if(hasPos)
      return; // one position max; no second signal while open

   //--- 4. Signal: first strict close outside, entry window only
   if(!g_rangeDone)
      return;
   if(g_rangeHi - g_rangeLo < InpMinRangePips * g_pip - 1e-12)
      return; // degenerate day
   if(!(bmin >= g_rangeEndMin && bmin < g_entryEndMin))
      return;
   bool isBuy = (c > g_rangeHi + 1e-12);
   bool isSell = (c < g_rangeLo - 1e-12);
   if(!isBuy && !isSell)
      return; // inside or equality: no signal
   if(G2_FillsToday() >= 1)
     {
      G2_Event(srv, "skip", "one_a_day_cap_reached");
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
     {
      G2_Event(srv, "skip", "no_tick");
      return;
     }
   double entry = isBuy ? tick.ask : tick.bid;
   double slRaw = isBuy ? g_rangeLo : g_rangeHi;
   double risk = MathAbs(entry - slRaw);
   if(risk <= 0)
     {
      G2_Event(srv, "no_trade", "reason=zero_risk");
      return;
     }
   long stopsPts = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (double)stopsPts * SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(risk < minDist)
     {
      G2_Event(srv, "no_trade",
               StringFormat("reason=stops_level risk=%.5f min=%.5f", risk, minDist));
      return;
     }
   double tpRaw = isBuy ? entry + InpTargetR * risk : entry - InpTargetR * risk;
   // Align stop/target AWAY-neutral: stop against us rounded protectively.
   double sl = isBuy ? G2_AlignDown(slRaw, g_tickSize) : G2_AlignUp(slRaw, g_tickSize);
   double tp = isBuy ? G2_AlignUp(tpRaw, g_tickSize) : G2_AlignDown(tpRaw, g_tickSize);
   string vskip;
   double vol = G2_FixedVolume(vskip);
   if(vol <= 0)
     {
      G2_Event(srv, "no_trade", "reason=" + vskip);
      return;
     }
   G2_Event(srv, "signal",
            StringFormat("dir=%s bar=%s close=%.5f hi=%.5f lo=%.5f entry=%.5f sl=%.5f tp=%.5f vol=%.2f",
                         isBuy ? "BUY" : "SELL", G2_Tchords(barOpen), c,
                         g_rangeHi, g_rangeLo, entry, sl, tp, vol));
   G2_Send(isBuy, entry, sl, tp, vol);
  }

//+------------------------------------------------------------------+
//| OnDeinit: trailing bar, final equity, deals scan, run metadata   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(!G2_InTester())
      return;
   datetime srv = TimeTradeServer();
   // Export the final completed bar if unseen.
   datetime barOpen = iTime(g_symbol, PERIOD_M15, 1);
   if(barOpen != 0 && barOpen != g_lastExportedBar)
     {
      double o = iOpen(g_symbol, PERIOD_M15, 1);
      double h = iHigh(g_symbol, PERIOD_M15, 1);
      double l = iLow(g_symbol, PERIOD_M15, 1);
      double c = iClose(g_symbol, PERIOD_M15, 1);
      if(!(o == 0 && h == 0 && l == 0 && c == 0))
         G2_BarRow(srv, barOpen, o, h, l, c);
     }
   G2_Equity(srv);

   // Deals scan: own-magic deals over the whole run.
   long nDeals = 0;
   if(HistorySelect(0, srv + 86400))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong dt = HistoryDealGetTicket(i);
         if(dt == 0)
            continue;
         if(HistoryDealGetString(dt, DEAL_SYMBOL) != g_symbol)
            continue;
         if(HistoryDealGetInteger(dt, DEAL_MAGIC) != InpMagic)
            continue;
         long dtype = HistoryDealGetInteger(dt, DEAL_TYPE);
         string dir = (dtype == DEAL_TYPE_BUY) ? "BUY" : (dtype == DEAL_TYPE_SELL) ? "SELL" : "OTHER";
         long entryKind = HistoryDealGetInteger(dt, DEAL_ENTRY);
         string ek = (entryKind == DEAL_ENTRY_IN) ? "IN" : (entryKind == DEAL_ENTRY_OUT) ? "OUT" : "INOUT";
         datetime dtime = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
         if(g_fDeals != INVALID_HANDLE)
           {
            FileSeek(g_fDeals, 0, SEEK_END);
            FileWrite(g_fDeals, g_seqDeals, (long)dt, G2_Tchords(dtime), g_symbol,
                      (long)InpMagic, dir, ek,
                      DoubleToString(HistoryDealGetDouble(dt, DEAL_VOLUME), 2),
                      DoubleToString(HistoryDealGetDouble(dt, DEAL_PRICE), g_digits),
                      DoubleToString(HistoryDealGetDouble(dt, DEAL_COMMISSION), 2),
                      DoubleToString(HistoryDealGetDouble(dt, DEAL_SWAP), 2),
                      DoubleToString(HistoryDealGetDouble(dt, DEAL_PROFIT), 2));
           }
         g_seqDeals++;
         nDeals++;
        }
     }
   else
      G2_Event(srv, "history_fail_closed", "deinit deals scan HistorySelect failed");
   G2_Event(srv, "deinit",
            StringFormat("reason=%d bars=%I64d equity_ticks=%I64d deals=%I64d events=%I64d",
                         reason, g_seqBars, g_seqEquity, nDeals, g_seqEvents));

   // Run metadata (offline manifest adds hashes/coverage; EA records facts).
   if(g_fRun != INVALID_HANDLE)
     {
      FileSeek(g_fRun, 0, SEEK_END);
      FileWriteString(g_fRun, StringFormat(
        "{\n  \"rules_version\": \"v1.2\",\n  \"ea\": \"SCA_Getestet2_LondonBreakout_v12\",\n"
        "  \"symbol\": \"%s\",\n  \"timeframe\": \"M15\",\n  \"clock_basis\": \"server_time_fixed_proxy (NOT claimed London wall time)\",\n"
        "  \"inputs\": {\"range\": \"%s-%s\", \"entry_end\": \"%s\", \"flat\": \"%s\", \"target_R\": %.2f, \"fixed_lot\": %.2f, \"magic\": %I64d},\n"
        "  \"init_server_time\": \"%s\",\n  \"end_server_time\": \"%s\",\n"
        "  \"n_bars\": %I64d,\n  \"n_equity_ticks\": %I64d,\n  \"n_own_deals\": %I64d,\n  \"n_events\": %I64d,\n"
        "  \"deinit_reason\": %d,\n  \"coverage_note\": \"span = first/last exported server times in g2_lb12_bars.csv\"\n}\n",
        g_symbol, InpRangeStart, InpRangeEnd, InpEntryEnd, InpTimeExit,
        InpTargetR, InpFixedLot, InpMagic,
        G2_Tchords(g_initServer), G2_Tchords(srv),
        g_seqBars, g_seqEquity, nDeals, g_seqEvents, reason));
     }
   FileClose(g_fBars);
   FileClose(g_fEquity);
   FileClose(g_fDeals);
   FileClose(g_fEvents);
   FileClose(g_fRun);
  }
//+------------------------------------------------------------------+
