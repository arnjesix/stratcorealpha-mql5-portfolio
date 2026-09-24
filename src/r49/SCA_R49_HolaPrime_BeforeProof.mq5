#property strict
#property script_show_inputs
#include "SCA_R49_BeforeGate.mqh"

int g_passed = 0;
int g_failed = 0;
string g_lines = "";

void Check(const string id, const bool actual, const bool expected)
{
   const bool ok = (actual == expected);
   if(ok) g_passed++; else g_failed++;
   const string line = StringFormat("%s %s", ok ? "PASS" : "FAIL", id);
   g_lines += line + "\n";
   Print("R49_BEFORE " + line);
}

void OnStart()
{
   datetime last = 0;
   Check("BAR-01 first tick", AcceptBar(D'2026.09.24 10:00:00', last), true);
   Check("BAR-02 second tick same bar", AcceptBar(D'2026.09.24 10:00:00', last), false);
   Check("BAR-03 absent bar time", AcceptBar(0, last), false);
   const string summary = StringFormat("R49_BEFORE SUMMARY passed=%d failed=%d", g_passed, g_failed);
   Print(summary);
   Comment("R49 BEFORE | HolaPrime MT5 | synthetic gate cases\n", g_lines,
           summary, "\nRead-only. No orders or customer data.");
   ChartRedraw(0);
   Sleep(1500);
   const bool saved = ChartScreenShot(0, "SCA_R49_HolaPrime_Before_20260924.png", 1280, 720, ALIGN_LEFT);
   PrintFormat("R49_BEFORE screenshot_saved=%s", saved ? "true" : "false");
   Sleep(45000);
   Comment("");
}
