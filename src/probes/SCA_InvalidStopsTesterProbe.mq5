#property strict
#property version "1.00"
// Tester-only probe. Intentionally invalid BUY stop loss for diagnostic evidence.
bool attempted=false;
int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      Print("SCA_INVALID_STOPS_PROBE blocked: Strategy Tester only");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(attempted) return;
   attempted=true;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.volume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   request.type=ORDER_TYPE_BUY;
   request.price=tick.ask;
   request.sl=tick.ask+100.0*_Point; // SL above BUY entry is invalid by construction.
   request.deviation=10;
   bool accepted=OrderSend(request,result);
   PrintFormat("SCA_INVALID_STOPS_PROBE accepted=%s retcode=%u comment=%s symbol=%s",accepted?"true":"false",result.retcode,result.comment,_Symbol);
}