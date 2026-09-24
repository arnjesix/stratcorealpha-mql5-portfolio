//+------------------------------------------------------------------+
//| SCA_EA_ParityDemo.mq5                                            |
//| Owned sample EA: completed-bar SMA(3)/SMA(5) crossover, one bar   |
//| one event. Signal logging only by default; orders ONLY when the  |
//| user explicitly enables InpAllowTrading AND the account is NOT a |
//| live real account (Strategy Tester / demo only).                 |
//|                                                                  |
//| Order path (honest semantics, magic+symbol scoped): at most ONE  |
//| OWN position per symbol (EA magic InpMagic). A signal first      |
//| closes OWN opposite-direction positions on _Symbol, then opens   |
//| only if no OWN position remains (no pyramiding). Positions with  |
//| a different magic or symbol are never selected, closed, or       |
//| modified. On any NON-HEDGING account (RETAIL_NETTING or          |
//| EXCHANGE, both net by symbol) a FOREIGN position on _Symbol      |
//| blocks all trading (any order would merge into it). Any          |
//| unreadable position read (symbol/magic/type) fails closed and    |
//| refuses the signal. A close/open counts only on a completed      |
//| trade retcode (DONE/DONE_PARTIAL) plus a re-scan of actual       |
//| position state; queued/submitted results never claim a fill.     |
//| Volume is snapped DOWN to the broker MIN/MAX/STEP grid anchored  |
//| at MIN (requests below MIN or above MAX are refused, never       |
//| resized). Every close/open logs the trade return code.           |
//|                                                                  |
//| Owned sample. No customer case, no live track record, no profit  |
//| claim, no optimization.                                          |
//+------------------------------------------------------------------+
#property copyright "StratCoreAlpha owned sample"
#property version   "1.02"
#property description "Owned sample: SMA(3)/SMA(5) completed-bar crossover; safe-off by default, Tester/demo orders only."

#include <Trade/Trade.mqh>
#include "SCA_EA_ParityDemoSignal.mqh"

input int      InpFastPeriod   = SCA_PARITY_FAST_PERIOD;  // Fast SMA period (frozen: 3)
input int      InpSlowPeriod   = SCA_PARITY_SLOW_PERIOD;  // Slow SMA period (frozen: 5)
input bool     InpAllowTrading = false;                   // EXPLICIT opt-in: place orders in Strategy Tester/demo ONLY (default OFF/safe)
input double   InpLots         = 0.01;                    // Requested order volume (refused if below MIN/above MAX; snapped down to MIN+STEP grid at order time)
input long     InpMagic        = 20260105;                // EA magic number (only own positions with this magic are ever touched)
input int      InpSlippage     = 10;                      // Max slippage in points

// Safety bound: at most this many OWN opposite positions are closed per signal.
// If more remain, the open leg is refused rather than accumulating exposure.
#define SCA_PARITY_MAX_CLOSE_PER_SIGNAL 8

datetime g_last_bar = 0;
CTrade   g_trade;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastPeriod <= 0 || InpSlowPeriod <= 0 || InpFastPeriod >= InpSlowPeriod)
   {
      Print("SCA_PARITY INIT_REJECTED: require 0 < Fast < Slow.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLots <= 0.0)
   {
      Print("SCA_PARITY INIT_REJECTED: require InpLots > 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpFastPeriod != SCA_PARITY_FAST_PERIOD || InpSlowPeriod != SCA_PARITY_SLOW_PERIOD)
      PrintFormat("SCA_PARITY INIT_WARNING: periods Fast=%d Slow=%d differ from frozen fixture (3/5); parity proof uses 3/5.",
                  InpFastPeriod, InpSlowPeriod);
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   if(InpAllowTrading)
      Print("SCA_PARITY MODE=TRADING-ARMED (Tester/demo only; live-real accounts are refused in code).");
   else
      Print("SCA_PARITY MODE=SIGNAL-ONLY (safe default; no order will be placed).");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime cur_bar = iTime(_Symbol, _Period, 0);
   if(cur_bar <= 0 || cur_bar == g_last_bar)
      return;                       // one evaluation per completed bar
   g_last_bar = cur_bar;

   int need = InpSlowPeriod + 1;    // enough completed closes for now + previous SMA pair
   double closes[];
   // Shift 1 = last COMPLETED bar; the forming bar is never read.
   int copied = CopyClose(_Symbol, _Period, 1, need, closes);
   if(copied < need)
      return;                       // warmup: not enough completed bars

   int last = copied - 1;           // index of most recent completed bar
   double fast_now  = SCA_ParitySMA(closes, last,     InpFastPeriod);
   double slow_now  = SCA_ParitySMA(closes, last,     InpSlowPeriod);
   double fast_prev = SCA_ParitySMA(closes, last - 1, InpFastPeriod);
   double slow_prev = SCA_ParitySMA(closes, last - 1, InpSlowPeriod);
   if(fast_now == EMPTY_VALUE || slow_now == EMPTY_VALUE ||
      fast_prev == EMPTY_VALUE || slow_prev == EMPTY_VALUE)
      return;                       // warmup / missing data: no signal

   int sig = SCA_ParitySignal(fast_prev, slow_prev, fast_now, slow_now);
   if(sig == 0)
      return;

   string side = (sig > 0 ? "BULL" : "BEAR");
   PrintFormat("SCA_PARITY SIGNAL %s bar=%s fast=%.5f slow=%.5f",
               side, TimeToString(cur_bar, TIME_DATE | TIME_SECONDS), fast_now, slow_now);

   if(!InpAllowTrading)
   {
      Print("SCA_PARITY ORDER_SUPPRESSED InpAllowTrading=false (safe default).");
      return;
   }
   if(!SCA_TradingVenueAllowed())
   {
      long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
      int tester = (int)MQLInfoInteger(MQL_TESTER);
      PrintFormat("SCA_PARITY ORDER_REFUSED venue: live real-money accounts are never traded by this sample (mode=%d tester=%d).",
                  mode, tester);
      return;
   }
   SCA_PlaceSignalOrder(sig);
}

//+------------------------------------------------------------------+
// Fail closed: live real accounts are refused even when armed.
// Strategy Tester and demo accounts pass; everything else is refused
// (contest, real, and unknown modes). The refusal is logged by the caller
// with the observed ACCOUNT_TRADE_MODE value.
bool SCA_TradingVenueAllowed()
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return true;
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode == ACCOUNT_TRADE_MODE_DEMO)
      return true;
   return false;
}

//+------------------------------------------------------------------+
// True completion gate: only DONE / DONE_PARTIAL prove an executed
// deal. Anything else (PLACED/QUEUED/accepted-for-processing, fails,
// requotes, rejections) must never be claimed as a fill.
bool SCA_RetcodeCompleted(const uint rc)
{
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL);
}

//+------------------------------------------------------------------+
// Snap the requested volume DOWN to the broker's MIN/MAX/STEP grid
// for _Symbol. The grid is anchored at MIN: valid volumes are
// MIN + k*STEP. Returns 0.0 (refuse) when the specs are unavailable,
// when InpLots is below MIN (never raised — that would change risk
// sizing) or above MAX (never cut down silently), or when the
// snapped volume leaves the [MIN, MAX] range. Off-grid requests
// inside range are snapped DOWN only, never up.
double SCA_NormalizeLots()
{
   double min_vol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(min_vol <= 0.0 || max_vol <= 0.0 || step_vol <= 0.0)
   {
      PrintFormat("SCA_PARITY ORDER_REFUSED volume specs unavailable for %s (min=%.8f max=%.8f step=%.8f).",
                  _Symbol, min_vol, max_vol, step_vol);
      return 0.0;
   }
   if(InpLots < min_vol - 1e-8)
   {
      PrintFormat("SCA_PARITY ORDER_REFUSED requested %.8f below minimum %.8f for %s (never raised).",
                  InpLots, min_vol, _Symbol);
      return 0.0;
   }
   if(InpLots > max_vol + 1e-8)
   {
      PrintFormat("SCA_PARITY ORDER_REFUSED requested %.8f above maximum %.8f for %s (never cut down).",
                  InpLots, max_vol, _Symbol);
      return 0.0;
   }
   double lots = MathFloor((InpLots - min_vol) / step_vol + 1e-8) * step_vol + min_vol;
   lots = NormalizeDouble(lots, 8);
   if(lots < min_vol - 1e-8 || lots > max_vol + 1e-8 || lots <= 0.0)
   {
      PrintFormat("SCA_PARITY ORDER_REFUSED requested %.8f outside broker volume grid (min=%.8f max=%.8f step=%.8f).",
                  InpLots, min_vol, max_vol, step_vol);
      return 0.0;
   }
   return lots;
}

//+------------------------------------------------------------------+
// Count positions on _Symbol split into OWN (magic == InpMagic) vs
// FOREIGN (any other magic, including 0), plus UNREADABLE. Fail
// closed: any position whose ticket/symbol cannot be read (symbol
// unknown, so it could be the affected symbol) and any _Symbol
// position whose magic/type cannot be read or whose type is unknown
// increments unreadable_total. Callers must refuse the signal while
// unreadable_total > 0. Selection is strictly magic+symbol scoped:
// nothing else in the account is considered, and unreadable or
// foreign positions are never selected, closed, or modified.
void SCA_ScanSymbolPositions(int &own_buy, int &own_sell, int &foreign_total, int &unreadable_total)
{
   own_buy = 0;
   own_sell = 0;
   foreign_total = 0;
   unreadable_total = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket((uint)i);
      if(ticket == 0)
      {
         unreadable_total++;        // ticket unreadable: symbol unknown, fail closed
         continue;
      }
      string psym = "";
      if(!PositionGetString(POSITION_SYMBOL, psym))
      {
         unreadable_total++;        // symbol unreadable: could be _Symbol, refuse any trade
         continue;
      }
      if(psym != _Symbol)
         continue;                  // different symbol: never touched
      long pmagic = 0;
      if(!PositionGetInteger(POSITION_MAGIC, pmagic))
      {
         unreadable_total++;        // _Symbol position, magic unreadable: fail closed, never touched
         continue;
      }
      if(pmagic != InpMagic)
      {
         foreign_total++;
         continue;
      }
      long ptype = 0;
      if(!PositionGetInteger(POSITION_TYPE, ptype))
      {
         unreadable_total++;        // own magic but type unreadable: fail closed, never touched
         continue;
      }
      if(ptype == POSITION_TYPE_BUY)
         own_buy++;
      else if(ptype == POSITION_TYPE_SELL)
         own_sell++;
      else
         unreadable_total++;        // unknown type: never touched, fail closed (blocking)
   }
}

//+------------------------------------------------------------------+
// Close OWN opposite-direction positions on _Symbol (magic-scoped).
// Returns true only when a re-scan proves no OWN opposite position
// remains AND no read failed during the final scan. Returns false
// when a close was not completed (bool false or retcode not
// DONE/DONE_PARTIAL — queued/submitted is NOT a close), when any
// position read failed (a failed read must never lead to opening),
// or when the safety bound was hit (caller must NOT open).
bool SCA_CloseOwnOpposite(const int sig)
{
   long want_type = (sig > 0 ? POSITION_TYPE_SELL : POSITION_TYPE_BUY); // type to remove
   int closed = 0;
   for(int pass = 0; pass < SCA_PARITY_MAX_CLOSE_PER_SIGNAL; pass++)
   {
      ulong victim = 0;
      bool read_failed = false;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket((uint)i);
         if(ticket == 0)
         {
            read_failed = true;     // ticket unreadable: fail closed
            continue;
         }
         string psym = "";
         if(!PositionGetString(POSITION_SYMBOL, psym))
         {
            read_failed = true;     // symbol unreadable: could be _Symbol, fail closed
            continue;
         }
         if(psym != _Symbol)
            continue;
         long pmagic = 0;
         if(!PositionGetInteger(POSITION_MAGIC, pmagic))
         {
            read_failed = true;     // _Symbol position, magic unreadable: fail closed
            continue;
         }
         if(pmagic != InpMagic)
            continue;               // foreign: never selected, never touched
         long ptype = 0;
         if(!PositionGetInteger(POSITION_TYPE, ptype))
         {
            read_failed = true;     // own magic but type unreadable: fail closed
            continue;
         }
         if(ptype != want_type)
            continue;               // same direction or unknown: not this pass's victim
         victim = ticket;
         break;
      }
      if(victim == 0)
      {
         if(read_failed)
         {
            Print("SCA_PARITY ORDER_REFUSED position read failed during close pass; open leg refused (failed read never leads to opening).");
            return false;
         }
         return true;               // re-scan proves no OWN opposite position remains
      }
      if(read_failed)
      {
         // A victim was found but another position could not be
         // inspected: refuse rather than risk changing the unknown one
         // on a netting account or miscounting the close sequence.
         Print("SCA_PARITY ORDER_REFUSED position read failed during close pass; open leg refused (failed read never leads to opening).");
         return false;
      }
      ResetLastError();
      bool ok = g_trade.PositionClose(victim, InpSlippage);
      uint rc = g_trade.ResultRetcode();
      if(!ok || !SCA_RetcodeCompleted(rc))
      {
         PrintFormat("SCA_PARITY ORDER_CLOSE_FAILED ticket=%I64u retcode=%u (%s) completed=%d; open leg refused (not completed, never counted as closed).",
                     victim, rc, g_trade.ResultRetcodeDescription(), (int)SCA_RetcodeCompleted(rc));
         return false;
      }
      closed++;
      PrintFormat("SCA_PARITY ORDER_CLOSE_PLACED ticket=%I64u retcode=%u (%s) closed=%d (completed deal confirmed).",
                  victim, rc, g_trade.ResultRetcodeDescription(), closed);
   }
   PrintFormat("SCA_PARITY ORDER_REFUSED too many own opposite positions (bound=%d); open leg refused.",
               SCA_PARITY_MAX_CLOSE_PER_SIGNAL);
   return false;
}

//+------------------------------------------------------------------+
// Honest single-own-position execution, magic+symbol scoped:
//   BULL: close OWN SELLs, then buy only if no OWN position remains.
//   BEAR: close OWN BUYs, then sell only if no OWN position remains.
// FOREIGN positions are never closed or modified. Hedging is
// determined explicitly: ONLY ACCOUNT_MARGIN_MODE_RETAIL_HEDGING
// allows parallel same-symbol positions. On any other mode —
// ACCOUNT_MARGIN_MODE_RETAIL_NETTING and ACCOUNT_MARGIN_MODE_EXCHANGE
// both net by symbol, plus any unknown future mode (fail closed) —
// any FOREIGN position on _Symbol blocks trading entirely, because a
// new order would merge into (change) that unrelated position. Any
// unreadable position read blocks trading as well. A Buy/Sell/Close
// counts only on a completed trade retcode (TRADE_RETCODE_DONE /
// TRADE_RETCODE_DONE_PARTIAL) plus a re-scan proving the actual
// position state; queued/submitted results never claim a fill and
// never release the next leg.
void SCA_PlaceSignalOrder(const int sig)
{
   double lots = SCA_NormalizeLots();
   if(lots <= 0.0)
      return;                       // refusal already logged

   int own_buy = 0, own_sell = 0, foreign_total = 0, unreadable_total = 0;
   SCA_ScanSymbolPositions(own_buy, own_sell, foreign_total, unreadable_total);
   if(unreadable_total > 0)
   {
      PrintFormat("SCA_PARITY ORDER_REFUSED unreadable position state (count=%d); fail closed, no trade on %s.",
                  unreadable_total, _Symbol);
      return;
   }

   long margin_mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   bool is_hedging = (margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(foreign_total > 0 && !is_hedging)
   {
      PrintFormat("SCA_PARITY ORDER_REFUSED foreign position on %s (count=%d) on a non-hedging account (margin_mode=%d; RETAIL_NETTING/EXCHANGE net by symbol); any order would change it.",
                  _Symbol, foreign_total, margin_mode);
      return;
   }

   int own_same = (sig > 0 ? own_buy : own_sell);
   int own_opp  = (sig > 0 ? own_sell : own_buy);

   if(own_opp > 0)
   {
      if(!SCA_CloseOwnOpposite(sig))
         return;                    // close not completed / read failed / bound already logged; do NOT open
      SCA_ScanSymbolPositions(own_buy, own_sell, foreign_total, unreadable_total);
      if(unreadable_total > 0)
      {
         PrintFormat("SCA_PARITY ORDER_REFUSED unreadable position state after close pass (count=%d); open leg refused.",
                     unreadable_total);
         return;
      }
      if(foreign_total > 0 && !is_hedging)
      {
         PrintFormat("SCA_PARITY ORDER_REFUSED foreign position on %s after close pass (count=%d); open leg refused.",
                     _Symbol, foreign_total);
         return;
      }
      own_same = (sig > 0 ? own_buy : own_sell);
      own_opp  = (sig > 0 ? own_sell : own_buy);
      if(own_opp > 0)
      {
         Print("SCA_PARITY ORDER_REFUSED own opposite position remains after close pass; open leg refused (close merely submitted is never enough).");
         return;
      }
   }

   if(own_same > 0)
   {
      PrintFormat("SCA_PARITY ORDER_SKIPPED already holding %d own %s position(s) on %s; no pyramiding.",
                  own_same, (sig > 0 ? "BUY" : "SELL"), _Symbol);
      return;
   }

   ResetLastError();
   bool ok = false;
   if(sig > 0)
      ok = g_trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, "SCA parity demo BULL");
   else
      ok = g_trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, "SCA parity demo BEAR");
   uint rc = g_trade.ResultRetcode();
   if(!ok || !SCA_RetcodeCompleted(rc))
   {
      PrintFormat("SCA_PARITY ORDER_FAILED %s lots=%.8f retcode=%u (%s) completed=%d (not completed; no position claimed).",
                  (sig > 0 ? "BUY" : "SELL"), lots, rc,
                  g_trade.ResultRetcodeDescription(), (int)SCA_RetcodeCompleted(rc));
      return;
   }
   // Completed retcode is necessary but not sufficient: re-scan actual
   // position state before claiming the fill.
   int vb = 0, vs = 0, vf = 0, vu = 0;
   SCA_ScanSymbolPositions(vb, vs, vf, vu);
   if(vu > 0)
   {
      PrintFormat("SCA_PARITY ORDER_FAILED %s lots=%.8f retcode=%u (%s): position state unreadable after submit (count=%d); fill NOT claimed.",
                  (sig > 0 ? "BUY" : "SELL"), lots, rc, g_trade.ResultRetcodeDescription(), vu);
      return;
   }
   int have_same = (sig > 0 ? vb : vs);
   if(have_same <= 0)
   {
      PrintFormat("SCA_PARITY ORDER_FAILED %s lots=%.8f retcode=%u (%s): completed retcode but no own %s position found on re-scan; fill NOT claimed.",
                  (sig > 0 ? "BUY" : "SELL"), lots, rc, g_trade.ResultRetcodeDescription(),
                  (sig > 0 ? "BUY" : "SELL"));
      return;
   }
   PrintFormat("SCA_PARITY ORDER_PLACED %s lots=%.8f order=%I64u deal=%I64u retcode=%u (%s) (completed + position verified).",
               (sig > 0 ? "BUY" : "SELL"), lots,
               g_trade.ResultOrder(), g_trade.ResultDeal(), rc, g_trade.ResultRetcodeDescription());
}
//+------------------------------------------------------------------+
