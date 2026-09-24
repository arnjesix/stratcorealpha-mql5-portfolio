#property strict
#property version "1.00"
#property description "Owned EA reproduction: duplicate bar processing defect; no orders"
#include "SCA_R49_BeforeGate.mqh"

datetime g_last_bar = 0;
int g_passed = 0;
int g_failed = 0;

void Check(const string id, const bool actual, const bool expected)
{
   if(actual == expected)
   {
      g_passed++;
      PrintFormat("R49_BEFORE PASS %s", id);
   }
   else
   {
      g_failed++;
      PrintFormat("R49_BEFORE FAIL %s expected=%s actual=%s", id,
                  expected ? "true" : "false", actual ? "true" : "false");
   }
}

int OnInit()
{
   datetime last = 0;
   Check("BAR-01 first tick", AcceptBar(D'2026.09.24 10:00:00', last), true);
   Check("BAR-02 second tick same bar", AcceptBar(D'2026.09.24 10:00:00', last), false);
   Check("BAR-03 absent bar time", AcceptBar(0, last), false);
   PrintFormat("R49_BEFORE SUMMARY passed=%d failed=%d", g_passed, g_failed);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // Reproduces the execution gate only. No signal or order is submitted.
   if(AcceptBar(iTime(_Symbol, _Period, 0), g_last_bar))
      Print("R49_BEFORE bar accepted");
}
