//+------------------------------------------------------------------+
//| SCA_MT5JournalDoctor.mq5                                        |
//| Copyright 2026 Arnold Holm / StratCoreAlpha                     |
//| https://stratcorealpha.com                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Arnold Holm / StratCoreAlpha"
#property link      "https://stratcorealpha.com/?ref=symb-ws4-github&intent=mt5-repair"
#property version   "1.00"
#property strict
#property script_show_inputs
#property description "Read-only triage of copied current-day MT5 Experts and Journal logs."
#property description "Copy both original log files into Terminal Common/Files/JournalDoctor first."
#property description "No orders, DLLs, network calls, raw log excerpts or account data in the report."

#define SCA_CATEGORY_COUNT 8
#define SCA_SOURCE_COUNT 2
#define SCA_HARD_LINE_LIMIT 20000

input string InpDateYYYYMMDD = "";     // Blank = local current day
input int    InpMaxLinesPerFile = 20000;// Maximum lines from each copied source
input bool   InpRunSyntheticChecks = true; // Labelled classifier fixtures
input bool   InpSaveRunScreenshot = true;  // Capture the actual chart after the run

string g_category_names[SCA_CATEGORY_COUNT];
string g_next_checks[SCA_CATEGORY_COUNT];
int    g_counts[SCA_SOURCE_COUNT][SCA_CATEGORY_COUNT];
int    g_lines[SCA_SOURCE_COUNT];
bool   g_read[SCA_SOURCE_COUNT];
bool   g_truncated[SCA_SOURCE_COUNT];
string g_status[SCA_SOURCE_COUNT];

void InitializeCategories()
{
   g_category_names[0] = "Invalid stops";
   g_next_checks[0] = "Compare SL/TP with bid/ask, tick size, stops level and freeze level; repeat OrderCheck.";
   g_category_names[1] = "Not enough money";
   g_next_checks[1] = "Check free margin, contract size, proposed volume and OrderCalcMargin before any retry.";
   g_category_names[2] = "Trade context busy";
   g_next_checks[2] = "Inspect outstanding trade requests and retry policy; do not submit a blind duplicate order.";
   g_category_names[3] = "Market closed";
   g_next_checks[3] = "Check the symbol trading session, server time and holiday schedule before resubmission.";
   g_category_names[4] = "AutoTrading disabled";
   g_next_checks[4] = "Check terminal Algo Trading, EA permissions and any server-side automated-trading restriction.";
   g_category_names[5] = "Invalid volume";
   g_next_checks[5] = "Check symbol minimum, maximum and step; normalize volume downward to the broker grid.";
   g_category_names[6] = "Off quotes / no price";
   g_next_checks[6] = "Check live bid/ask availability, connection state and the price/expiration used in the request.";
   g_category_names[7] = "Trade disabled";
   g_next_checks[7] = "Check symbol trade mode and account permissions; do not infer a temporary outage.";
}

string SelectedDate()
{
   string selected = InpDateYYYYMMDD;
   if(selected == "")
   {
      selected = TimeToString(TimeLocal(), TIME_DATE);
      StringReplace(selected, ".", "");
   }
   if(StringLen(selected) != 8)
      return "";
   for(int i = 0; i < 8; i++)
   {
      ushort character = StringGetCharacter(selected, i);
      if(character < '0' || character > '9')
         return "";
   }
   return selected;
}

bool Has(const string line, const string needle)
{
   return StringFind(line, needle) >= 0;
}

int Classify(const string original)
{
   string line = original;
   StringToLower(line);
   if(Has(line, "sca_journal_doctor"))
      return -1;
   if(Has(line, "invalid stops") || Has(line, "invalid stop"))
      return 0;
   if(Has(line, "not enough money") || Has(line, "insufficient funds") || Has(line, "no money"))
      return 1;
   if(Has(line, "trade context busy") || Has(line, "trade request locked"))
      return 2;
   if(Has(line, "market closed"))
      return 3;
   if(Has(line, "autotrading disabled") || Has(line, "auto trading disabled") ||
      Has(line, "algo trading disabled") || Has(line, "algorithmic trading disabled") ||
      Has(line, "automated trading is disabled"))
      return 4;
   if(Has(line, "invalid volume") || Has(line, "invalid lot size"))
      return 5;
   if(Has(line, "off quotes") || Has(line, "no prices") || Has(line, "no price"))
      return 6;
   if(Has(line, "trade disabled") || Has(line, "trading disabled"))
      return 7;
   return -1;
}

void ReadSource(const int source, const string date)
{
   string label = source == 0 ? "Experts" : "Journal";
   string name = "JournalDoctor\\" + label + "-" + date + ".log";
   g_read[source] = false;
   g_truncated[source] = false;
   g_lines[source] = 0;
   for(int category = 0; category < SCA_CATEGORY_COUNT; category++)
      g_counts[source][category] = 0;

   if(!FileIsExist(name, FILE_COMMON))
   {
      g_status[source] = "MISSING";
      Print("SCA_JOURNAL_DOCTOR ", label, " MISSING: copy today's original log to Common\\Files\\", name);
      return;
   }

   ResetLastError();
   int handle = FileOpen(name, FILE_READ | FILE_TXT | FILE_UNICODE | FILE_SHARE_READ | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      g_status[source] = "UNREADABLE";
      PrintFormat("SCA_JOURNAL_DOCTOR %s UNREADABLE: FileOpen error %d", label, GetLastError());
      return;
   }

   int limit = InpMaxLinesPerFile;
   if(limit < 1 || limit > SCA_HARD_LINE_LIMIT)
      limit = SCA_HARD_LINE_LIMIT;
   while(!FileIsEnding(handle) && g_lines[source] < limit)
   {
      string line = FileReadString(handle);
      g_lines[source]++;
      int category = Classify(line);
      if(category >= 0)
         g_counts[source][category]++;
   }
   g_truncated[source] = !FileIsEnding(handle);
   FileClose(handle);
   g_read[source] = true;
   g_status[source] = g_truncated[source] ? "TRUNCATED" : "READ";
}

string BuildReport(const string date)
{
   string report = "SCA EA Journal Doctor v1.00 | " + date + "\r\n";
   report += "Read-only classification of copied logs; no raw lines retained.\r\n";
   report += "A zero count means no matching phrase in the copied part, not a clean EA or account.\r\n\r\n";
   for(int source = 0; source < SCA_SOURCE_COUNT; source++)
   {
      string label = source == 0 ? "Experts" : "Journal";
      report += StringFormat("%s: %s | lines read: %d\r\n", label, g_status[source], g_lines[source]);
      if(!g_read[source])
      {
         report += "Next: copy the original current-day file into Common\\Files\\JournalDoctor and run again.\r\n\r\n";
         continue;
      }
      if(g_truncated[source])
         report += "Only the first configured lines were read; increase the limit or narrow the original copy.\r\n";
      int matched = 0;
      for(int category = 0; category < SCA_CATEGORY_COUNT; category++)
      {
         int count = g_counts[source][category];
         if(count <= 0)
            continue;
         matched += count;
         report += StringFormat("%s: %d\r\nNext check: %s\r\n",
                                g_category_names[category], count, g_next_checks[category]);
      }
      if(matched == 0)
         report += "No matching error phrases in the copied data.\r\n";
      report += "\r\n";
   }
   report += "Excluded: no repair or compliance verdict; inspect the original private log around each event.\r\n";
   return report;
}

bool SaveReport(const string date, const string report)
{
   string name = "SCA_JournalDoctor_" + date + ".txt";
   ResetLastError();
   int handle = FileOpen(name, FILE_WRITE | FILE_TXT | FILE_UNICODE | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("SCA_JOURNAL_DOCTOR REPORT NOT SAVED: FileOpen error %d", GetLastError());
      return false;
   }
   FileWriteString(handle, report);
   FileClose(handle);
   Print("SCA_JOURNAL_DOCTOR report saved in Terminal Common\\Files\\", name);
   return true;
}

void SaveRunScreenshot(const string date)
{
   if(!InpSaveRunScreenshot)
      return;
   string summary = "SCA EA Journal Doctor | actual MT5 run | " + date + "\n";
   for(int source = 0; source < SCA_SOURCE_COUNT; source++)
   {
      string label = source == 0 ? "Experts" : "Journal";
      int matches = 0;
      for(int category = 0; category < SCA_CATEGORY_COUNT; category++)
         matches += g_counts[source][category];
      summary += StringFormat("%s: %s | %d lines | %d phrase matches\n",
                              label, g_status[source], g_lines[source], matches);
   }
   summary += "Synthetic classifier checks are reported separately in Experts.\n";
   summary += "No trading request is sent by this script.";
   Comment(summary);
   ChartRedraw(0);
   Sleep(800);
   string name = "SCA_JournalDoctor_" + date + ".png";
   ResetLastError();
   if(ChartScreenShot(0, name, 1280, 720, ALIGN_LEFT))
      Print("SCA_JOURNAL_DOCTOR screenshot saved in terminal MQL5\\Files\\", name);
   else
      PrintFormat("SCA_JOURNAL_DOCTOR screenshot failed: ChartScreenShot error %d", GetLastError());
}

void RunSyntheticChecks()
{
   string fixture[SCA_CATEGORY_COUNT] =
   {
      "invalid stops", "not enough money", "trade context busy", "market closed",
      "AutoTrading disabled", "invalid volume", "off quotes", "trade disabled"
   };
   int passed = 0;
   int failed = 0;
   for(int i = 0; i < SCA_CATEGORY_COUNT; i++)
   {
      if(Classify(fixture[i]) == i)
         passed++;
      else
         failed++;
   }
   if(Classify("invalid stops and market closed") == 0)
      passed++;
   else
      failed++;
   if(Classify("SCA_JOURNAL_DOCTOR invalid stops") == -1)
      passed++;
   else
      failed++;
   PrintFormat("SCA_JOURNAL_DOCTOR SYNTHETIC_SELFTEST passed=%d failed=%d", passed, failed);
}

void OnStart()
{
   InitializeCategories();
   string date = SelectedDate();
   if(date == "")
   {
      Print("SCA_JOURNAL_DOCTOR invalid date input: use YYYYMMDD or leave blank for today.");
      return;
   }
   if(InpRunSyntheticChecks)
      RunSyntheticChecks();
   ReadSource(0, date);
   ReadSource(1, date);
   string report = BuildReport(date);
   for(int source = 0; source < SCA_SOURCE_COUNT; source++)
   {
      string label = source == 0 ? "Experts" : "Journal";
      PrintFormat("SCA_JOURNAL_DOCTOR %s status=%s lines=%d",
                  label, g_status[source], g_lines[source]);
      if(!g_read[source])
         continue;
      for(int category = 0; category < SCA_CATEGORY_COUNT; category++)
      {
         if(g_counts[source][category] > 0)
            PrintFormat("SCA_JOURNAL_DOCTOR %s %s count=%d | Next: %s",
                        label, g_category_names[category], g_counts[source][category],
                        g_next_checks[category]);
      }
   }
   SaveReport(date, report);
   SaveRunScreenshot(date);
}
