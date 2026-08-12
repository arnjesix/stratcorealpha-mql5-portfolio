//+------------------------------------------------------------------+
//| SCA_MT5AcceptanceHarness.mq5                                    |
//| Copyright 2026 Arnold Holm / StratCoreAlpha                      |
//| https://stratcorealpha.com                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Arnold Holm / StratCoreAlpha"
#property link      "https://stratcorealpha.com/services/mt5-ea-specification-audit"
#property version   "1.00"
#property strict
#property script_show_inputs
#property description "Runs deterministic synthetic acceptance cases for an MT5 entry-state contract."
#property description "It never reads market/account data and never sends, changes or closes an order."

input bool   InpWriteTextFile = true;                   // Save report to Common\Files
input bool   InpPrintToExperts = true;                  // Print report in Experts
input string InpFileName = "SCA_MT5AcceptanceHarness.txt";

enum SCA_DECISION
{
   SCA_ENTER = 0,
   SCA_BLOCK_OPEN_BAR = 1,
   SCA_BLOCK_NO_SIGNAL = 2,
   SCA_BLOCK_DUPLICATE_BAR = 3,
   SCA_BLOCK_COOLDOWN = 4,
   SCA_BLOCK_DAILY_LOCK = 5
};

struct SCA_STATE
{
   int day_key;
   int last_entry_bar;
   int last_signal_bar;
   bool daily_lock;
};

struct SCA_CANDIDATE
{
   string name;
   int day_key;
   int bar_index;
   bool closed_bar;
   bool signal;
   bool daily_lock;
   int cooldown_bars;
   SCA_DECISION expected;
};

int g_passed = 0;
int g_failed = 0;
string g_report = "";

void OnStart()
{
   g_report = "StratCoreAlpha MT5 EA Acceptance Harness\r\n";
   g_report += "Synthetic fixtures only; order_sent=false; account_data_read=false\r\n\r\n";

   SCA_STATE state;
   state.day_key = 20260812;
   state.last_entry_bar = -1000000;
   state.last_signal_bar = -1000000;
   state.daily_lock = false;

   SCA_CANDIDATE cases[8];
   SetCase(cases[0], "A1 valid closed-bar signal", 20260812, 100, true, true, false, 3, SCA_ENTER);
   SetCase(cases[1], "A2 duplicate signal bar", 20260812, 100, true, true, false, 3, SCA_BLOCK_DUPLICATE_BAR);
   SetCase(cases[2], "A3 open-bar signal", 20260812, 101, false, true, false, 3, SCA_BLOCK_OPEN_BAR);
   SetCase(cases[3], "A4 cooldown not elapsed", 20260812, 102, true, true, false, 3, SCA_BLOCK_COOLDOWN);
   SetCase(cases[4], "A5 cooldown elapsed", 20260812, 103, true, true, false, 3, SCA_ENTER);
   SetCase(cases[5], "A6 no signal", 20260812, 104, true, false, false, 3, SCA_BLOCK_NO_SIGNAL);
   SetCase(cases[6], "A7 daily lock", 20260812, 106, true, true, true, 3, SCA_BLOCK_DAILY_LOCK);
   SetCase(cases[7], "A8 new-day reset", 20260813, 107, true, true, false, 3, SCA_ENTER);

   for(int i = 0; i < ArraySize(cases); i++)
      RunCase(state, cases[i]);

   g_report += "\r\nSummary\r\n";
   g_report += StringFormat("passed=%d failed=%d result=%s\r\n", g_passed, g_failed,
                            g_failed == 0 ? "PASS" : "FAIL");
   g_report += "Boundaries: this harness proves only the synthetic state contract above.\r\n";
   g_report += "It does not prove strategy quality, broker execution, profitability or live-account behavior.\r\n";

   if(InpPrintToExperts)
      Print("\n", g_report);
   if(InpWriteTextFile)
      SaveReport();
}

void SetCase(SCA_CANDIDATE &value, const string name, const int day_key,
             const int bar_index, const bool closed_bar, const bool signal,
             const bool daily_lock, const int cooldown_bars,
             const SCA_DECISION expected)
{
   value.name = name;
   value.day_key = day_key;
   value.bar_index = bar_index;
   value.closed_bar = closed_bar;
   value.signal = signal;
   value.daily_lock = daily_lock;
   value.cooldown_bars = cooldown_bars;
   value.expected = expected;
}

SCA_DECISION EvaluateCandidate(SCA_STATE &state, const SCA_CANDIDATE &candidate)
{
   if(candidate.day_key != state.day_key)
   {
      state.day_key = candidate.day_key;
      state.daily_lock = false;
      state.last_entry_bar = -1000000;
      state.last_signal_bar = -1000000;
   }

   state.daily_lock = candidate.daily_lock;
   if(state.daily_lock)
      return SCA_BLOCK_DAILY_LOCK;
   if(!candidate.closed_bar)
      return SCA_BLOCK_OPEN_BAR;
   if(!candidate.signal)
      return SCA_BLOCK_NO_SIGNAL;
   if(candidate.bar_index == state.last_signal_bar)
      return SCA_BLOCK_DUPLICATE_BAR;
   if(candidate.bar_index - state.last_entry_bar < candidate.cooldown_bars)
      return SCA_BLOCK_COOLDOWN;

   state.last_signal_bar = candidate.bar_index;
   state.last_entry_bar = candidate.bar_index;
   return SCA_ENTER;
}

void RunCase(SCA_STATE &state, const SCA_CANDIDATE &candidate)
{
   SCA_DECISION actual = EvaluateCandidate(state, candidate);
   bool pass = actual == candidate.expected;
   if(pass)
      g_passed++;
   else
      g_failed++;

   g_report += StringFormat("[%s] %s | expected=%s actual=%s | day=%d bar=%d\r\n",
                            pass ? "PASS" : "FAIL", candidate.name,
                            DecisionText(candidate.expected), DecisionText(actual),
                            candidate.day_key, candidate.bar_index);
}

string DecisionText(const SCA_DECISION decision)
{
   switch(decision)
   {
      case SCA_ENTER:               return "ENTER";
      case SCA_BLOCK_OPEN_BAR:      return "BLOCK_OPEN_BAR";
      case SCA_BLOCK_NO_SIGNAL:     return "BLOCK_NO_SIGNAL";
      case SCA_BLOCK_DUPLICATE_BAR: return "BLOCK_DUPLICATE_BAR";
      case SCA_BLOCK_COOLDOWN:      return "BLOCK_COOLDOWN";
      case SCA_BLOCK_DAILY_LOCK:    return "BLOCK_DAILY_LOCK";
   }
   return "UNKNOWN";
}

void SaveReport()
{
   int handle = FileOpen(InpFileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("Acceptance harness could not create %s. Error %d", InpFileName, GetLastError());
      return;
   }
   FileWriteString(handle, g_report);
   FileClose(handle);
   Print("Acceptance harness report saved to ", TerminalInfoString(TERMINAL_COMMONDATA_PATH),
         "\\Files\\", InpFileName);
}
//+------------------------------------------------------------------+
