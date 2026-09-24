//+------------------------------------------------------------------+
//| SCA_PropRuleGuardDemo.mq5                                       |
//| Copyright 2026 Arnold Holm / StratCoreAlpha                     |
//| Non-trading demonstration. No order or position operations.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Arnold Holm / StratCoreAlpha"
#property link      "https://stratcorealpha.com/?ref=symb-ws3-github&intent=mt5-repair"
#property version   "1.00"
#property strict
#property description "Non-trading demo: equity loss and server-hour checks with a persisted daily basis."
#property description "Not a prop-firm compliance guarantee or an order guard for another EA."

input double InpDailyLossPercent = 5.0;  // Demo threshold; replace with verified firm rule
input int    InpStartHour = 8;           // Inclusive broker-server hour
input int    InpEndHour = 18;            // Exclusive broker-server hour
input bool   InpRunSyntheticChecks = true;
input bool   InpSaveChartScreenshot = true;
input int    InpEvidencePauseMs = 0;    // Visual tester only; 0 for normal operation

int    g_day = 0;
double g_baseline = 0.0;
string g_basis_source = "";
string g_state = "";
string g_key = "";
bool   g_screenshot_saved = false;
int    g_fixture_passed = 0;
int    g_fixture_failed = 0;

int DayKey(const datetime at)
{
   MqlDateTime parts;
   TimeToStruct(at, parts);
   return parts.year * 10000 + parts.mon * 100 + parts.day;
}

int ServerHour(const datetime at)
{
   MqlDateTime parts;
   TimeToStruct(at, parts);
   return parts.hour;
}

string Evaluate(const double baseline, const double equity, const int hour)
{
   if(baseline <= 0.0 || equity < 0.0)
      return "BLOCK_UNKNOWN_BASIS";
   if(equity <= baseline * (1.0 - InpDailyLossPercent / 100.0))
      return "BLOCK_LOSS";
   if(hour < InpStartHour || hour >= InpEndHour)
      return "BLOCK_HOURS";
   return "ALLOW";
}

void CheckFixture(const string name, const string actual, const string expected)
{
   if(actual == expected)
      g_fixture_passed++;
   else
   {
      g_fixture_failed++;
      PrintFormat("SCA_PROP_GUARD SYNTHETIC_FIXTURE_FAIL %s actual=%s expected=%s",
                  name, actual, expected);
   }
}

void RunSyntheticChecks()
{
   const double basis = 10000.0;
   const double boundary = basis * (1.0 - InpDailyLossPercent / 100.0);
   const int inside = InpStartHour;
   CheckFixture("above_loss_inside_hours", Evaluate(basis, boundary + 1.0, inside), "ALLOW");
   CheckFixture("at_loss_boundary", Evaluate(basis, boundary, inside), "BLOCK_LOSS");
   CheckFixture("below_loss_boundary", Evaluate(basis, boundary / 2.0, inside), "BLOCK_LOSS");
   CheckFixture("before_window", Evaluate(basis, boundary + 1.0, InpStartHour - 1), "BLOCK_HOURS");
   CheckFixture("at_window_end", Evaluate(basis, boundary + 1.0, InpEndHour), "BLOCK_HOURS");
   CheckFixture("unknown_basis", Evaluate(0.0, boundary + 1.0, inside), "BLOCK_UNKNOWN_BASIS");
   PrintFormat("SCA_PROP_GUARD SYNTHETIC_SELFTEST passed=%d failed=%d",
               g_fixture_passed, g_fixture_failed);
}

bool EnsureDay(const datetime now)
{
   int day = DayKey(now);
   if(day == g_day)
      return true;

   g_day = day;
   g_key = StringFormat("SCA_PRG_%I64d_%08d", AccountInfoInteger(ACCOUNT_LOGIN), day);
   g_baseline = 0.0;
   if(GlobalVariableCheck(g_key))
   {
      g_baseline = GlobalVariableGet(g_key);
      g_basis_source = "RESTORED";
   }
   else
   {
      g_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
      g_basis_source = "FIRST_OBSERVED";
      if(g_baseline <= 0.0 || GlobalVariableSet(g_key, g_baseline) == 0)
      {
         Print("SCA_PROP_GUARD cannot persist an observed equity basis; demo blocked.");
         g_baseline = 0.0;
         return false;
      }
      GlobalVariablesFlush();
   }

   if(g_baseline <= 0.0)
   {
      Print("SCA_PROP_GUARD saved basis invalid; demo blocked.");
      return false;
   }
   PrintFormat("SCA_PROP_GUARD DAY=%08d BASIS=%s; no day-opening or compliance claim.",
               g_day, g_basis_source);
   g_state = "";
   g_screenshot_saved = false;
   return true;
}

void UpdateDisplay(const datetime now)
{
   if(!EnsureDay(now))
   {
      Comment("SCA Prop Rule Guard Demo | BLOCK_UNKNOWN_BASIS | no orders sent");
      return;
   }

   string state = Evaluate(g_baseline, AccountInfoDouble(ACCOUNT_EQUITY), ServerHour(now));
   bool changed = state != g_state;
   if(changed)
   {
      g_state = state;
      PrintFormat("SCA_PROP_GUARD DAY=%08d BASIS=%s STATE=%s; no orders sent.",
                  g_day, g_basis_source, g_state);
   }
   Comment(StringFormat("SCA Prop Rule Guard Demo | real MT5 run | %08d\n",
                        g_day),
           StringFormat("Basis: %s | State: %s\n", g_basis_source, g_state),
           StringFormat("Hours: [%02d:00,%02d:00) server time | demo loss: %.1f%%\n",
                        InpStartHour, InpEndHour, InpDailyLossPercent),
           "No orders sent. A first-observed basis is not a firm's day opening.");
   ChartRedraw(0);
   if(InpSaveChartScreenshot && !g_screenshot_saved)
   {
      string name = StringFormat("SCA_PropGuardDemo_%08d.png", g_day);
      if(ChartScreenShot(0, name, 1280, 720, ALIGN_LEFT))
      {
         Print("SCA_PROP_GUARD screenshot saved in terminal MQL5\\Files\\", name);
         g_screenshot_saved = true;
      }
   }
   if(changed && InpEvidencePauseMs > 0 && MQLInfoInteger(MQL_VISUAL_MODE))
      Sleep(InpEvidencePauseMs);
}

int OnInit()
{
   if(InpDailyLossPercent <= 0.0 || InpDailyLossPercent >= 100.0 ||
      InpStartHour < 0 || InpStartHour > 23 ||
      InpEndHour < 1 || InpEndHour > 24 || InpStartHour >= InpEndHour ||
      InpEvidencePauseMs < 0 || InpEvidencePauseMs > 30000)
   {
      Print("SCA_PROP_GUARD invalid demo percentage or server-hour window.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRunSyntheticChecks)
      RunSyntheticChecks();
   if(!EnsureDay(TimeCurrent()))
      return INIT_FAILED;
   EventSetTimer(1);
   UpdateDisplay(TimeCurrent());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
   PrintFormat("SCA_PROP_GUARD stopped reason=%d; no orders sent.", reason);
}

void OnTick()
{
   UpdateDisplay(TimeCurrent());
}

void OnTimer()
{
   UpdateDisplay(TimeCurrent());
}

double OnTester()
{
   return g_fixture_failed == 0 ? 1.0 : 0.0;
}
