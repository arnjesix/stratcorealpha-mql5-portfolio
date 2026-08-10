//+------------------------------------------------------------------+
//|                                      SCA_MT5CashRiskProbe.mq5     |
//|                         Copyright 2026, StratCoreAlpha            |
//|                                  https://stratcorealpha.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, StratCoreAlpha"
#property link      "https://stratcorealpha.com"
#property version   "1.00"
#property description "Read-only cash-risk sizing probe for MetaTrader 5."
#property description "Calculates a broker-valid volume without sending orders."
#property script_show_inputs

enum ENUM_SCA_ORDER_SIDE
  {
   SCA_ORDER_BUY=0,
   SCA_ORDER_SELL=1
  };

input string              InpSymbol="";              // Empty = chart symbol
input ENUM_SCA_ORDER_SIDE InpSide=SCA_ORDER_BUY;      // Hypothetical order side
input double              InpEntryPrice=0.0;          // 0 = current Ask/Bid
input double              InpStopPrice=0.0;           // Required stop price
input double              InpRiskCash=100.0;          // Max loss in account currency
input double              InpCashCostReserve=0.0;     // Reserve for fees/slippage
input bool                InpRunSelfTests=true;       // Test volume flooring first

int VolumeDigits(const double step)
  {
   for(int digits=0; digits<=8; digits++)
     {
      if(MathAbs(NormalizeDouble(step,digits)-step)<1e-10)
         return digits;
     }
   return 8;
  }

double FloorVolume(const double raw_volume,
                   const double min_volume,
                   const double max_volume,
                   const double step)
  {
   if(raw_volume<=0.0 || min_volume<=0.0 || max_volume<min_volume || step<=0.0)
      return 0.0;

   double bounded=MathMin(raw_volume,max_volume);
   if(bounded<min_volume-1e-12)
      return 0.0;

   double step_count=MathFloor(((bounded-min_volume)+1e-12)/step);
   double floored=min_volume+step_count*step;
   floored=NormalizeDouble(floored,VolumeDigits(step));

   if(floored<min_volume-1e-12)
      return 0.0;
   if(floored>max_volume)
      floored=max_volume;
   return NormalizeDouble(floored,VolumeDigits(step));
  }

bool NearlyEqual(const double left,const double right)
  {
   return MathAbs(left-right)<1e-9;
  }

bool RunVolumeSelfTests()
  {
   int passed=0;
   int total=5;

   if(NearlyEqual(FloorVolume(0.137,0.01,100.0,0.01),0.13)) passed++;
   if(NearlyEqual(FloorVolume(0.009,0.01,100.0,0.01),0.0)) passed++;
   if(NearlyEqual(FloorVolume(101.0,0.01,100.0,0.01),100.0)) passed++;
   if(NearlyEqual(FloorVolume(0.39,0.10,100.0,0.10),0.30)) passed++;
   if(NearlyEqual(FloorVolume(0.20,0.10,100.0,0.03),0.19)) passed++;

   PrintFormat("SCA_SELF_TEST volume_floor passed=%d total=%d",passed,total);
   return passed==total;
  }

void PrintBlocked(const string reason)
  {
   Print("SCA_CASH_RISK_PROBE status=BLOCKED reason=",reason);
   Comment("SCA MT5 Cash Risk Probe\nBLOCKED: ",reason,
           "\nNo order was sent.");
  }

void OnStart()
  {
   Comment("");

   if(InpRunSelfTests && !RunVolumeSelfTests())
     {
      PrintBlocked("internal_volume_floor_self_test_failed");
      return;
     }

   string symbol=InpSymbol;
   if(StringLen(symbol)==0)
      symbol=_Symbol;

   if(!SymbolSelect(symbol,true))
     {
      PrintBlocked("symbol_selection_failed");
      return;
     }

   if(InpRiskCash<=0.0)
     {
      PrintBlocked("risk_cash_must_be_positive");
      return;
     }
   if(InpCashCostReserve<0.0 || InpCashCostReserve>=InpRiskCash)
     {
      PrintBlocked("cash_cost_reserve_must_be_nonnegative_and_below_risk_cash");
      return;
     }
   if(InpStopPrice<=0.0)
     {
      PrintBlocked("stop_price_is_required");
      return;
     }

   ENUM_ORDER_TYPE order_type=(InpSide==SCA_ORDER_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double entry=InpEntryPrice;
   if(entry<=0.0)
     {
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick))
        {
         PrintBlocked("current_tick_unavailable");
         return;
        }
      entry=(InpSide==SCA_ORDER_BUY ? tick.ask : tick.bid);
     }

   if(entry<=0.0)
     {
      PrintBlocked("entry_price_unavailable");
      return;
     }
   if(InpSide==SCA_ORDER_BUY && InpStopPrice>=entry)
     {
      PrintBlocked("buy_stop_must_be_below_entry");
      return;
     }
   if(InpSide==SCA_ORDER_SELL && InpStopPrice<=entry)
     {
      PrintBlocked("sell_stop_must_be_above_entry");
      return;
     }

   double min_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double volume_limit=SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT);
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   string account_currency=AccountInfoString(ACCOUNT_CURRENCY);

   if(min_volume<=0.0 || max_volume<min_volume || step<=0.0)
     {
      PrintBlocked("invalid_broker_volume_constraints");
      return;
     }

   double one_lot_result=0.0;
   ResetLastError();
   if(!OrderCalcProfit(order_type,symbol,1.0,entry,InpStopPrice,one_lot_result))
     {
      PrintBlocked(StringFormat("order_calc_profit_failed_%d",GetLastError()));
      return;
     }

   double one_lot_loss=MathAbs(one_lot_result);
   double tradable_budget=InpRiskCash-InpCashCostReserve;
   if(one_lot_loss<=0.0)
     {
      PrintBlocked("calculated_one_lot_loss_is_not_positive");
      return;
     }

   double raw_volume=tradable_budget/one_lot_loss;
   double final_volume=FloorVolume(raw_volume,min_volume,max_volume,step);
   if(final_volume<=0.0)
     {
      PrintBlocked("risk_budget_is_below_broker_minimum_volume");
      return;
     }

   double final_result=0.0;
   ResetLastError();
   if(!OrderCalcProfit(order_type,symbol,final_volume,entry,InpStopPrice,final_result))
     {
      PrintBlocked(StringFormat("final_order_calc_profit_failed_%d",GetLastError()));
      return;
     }

   double estimated_price_loss=MathAbs(final_result);
   double estimated_total=estimated_price_loss+InpCashCostReserve;
   string side=(InpSide==SCA_ORDER_BUY ? "BUY" : "SELL");
   string status=(estimated_total<=InpRiskCash+0.0000001 ? "PASS" : "BLOCKED");

   PrintFormat("SCA_CASH_RISK_PROBE status=%s symbol=%s side=%s account_currency=%s entry=%s stop=%s risk_cash=%.2f reserve=%.2f one_lot_loss=%.2f raw_volume=%.8f final_volume=%s estimated_price_loss=%.2f estimated_total=%.2f volume_min=%s volume_max=%s volume_step=%s volume_limit=%s tick_size=%s order_sent=false",
               status,
               symbol,
               side,
               account_currency,
               DoubleToString(entry,digits),
               DoubleToString(InpStopPrice,digits),
               InpRiskCash,
               InpCashCostReserve,
               one_lot_loss,
               raw_volume,
               DoubleToString(final_volume,VolumeDigits(step)),
               estimated_price_loss,
               estimated_total,
               DoubleToString(min_volume,VolumeDigits(step)),
               DoubleToString(max_volume,VolumeDigits(step)),
               DoubleToString(step,VolumeDigits(step)),
               DoubleToString(volume_limit,VolumeDigits(step)),
               DoubleToString(tick_size,digits));

   Comment("SCA MT5 Cash Risk Probe\n",
           "Status: ",status," (read-only)\n",
           "Symbol / side: ",symbol," / ",side,"\n",
           "Account currency: ",account_currency,"\n",
           "Entry / stop: ",DoubleToString(entry,digits)," / ",DoubleToString(InpStopPrice,digits),"\n",
           "Raw / broker-valid volume: ",DoubleToString(raw_volume,8)," / ",DoubleToString(final_volume,VolumeDigits(step)),"\n",
           "Estimated price loss: ",DoubleToString(estimated_price_loss,2)," ",account_currency,"\n",
           "Cost reserve: ",DoubleToString(InpCashCostReserve,2)," ",account_currency,"\n",
           "Estimated total: ",DoubleToString(estimated_total,2)," / cap ",DoubleToString(InpRiskCash,2)," ",account_currency,"\n",
           "No order was sent.");
  }
//+------------------------------------------------------------------+
