//+------------------------------------------------------------------+
//|                                                    LedgerPush.mq5 |
//|              Ledger Trading Journal — MT5 Data Pusher             |
//|  https://pandoraactor-ops.github.io/ledger-trading-journal/      |
//+------------------------------------------------------------------+
//
//  INSTALLATION
//  ────────────
//  1. Copy this file to:  MT5 → File → Open Data Folder → MQL5\Experts\
//  2. In MetaEditor: compile (F7)
//  3. In MT5 → Tools → Options → Expert Advisors:
//       ☑  Allow automated trading
//       ☑  Allow WebRequest for listed URL:
//              https://dxjwlrqpwidljudtheol.supabase.co
//  4. Attach EA to any active chart (e.g. EURUSD M1)
//  5. In EA Inputs:  paste your Token from the Ledger login page
//
//+------------------------------------------------------------------+
#property copyright "Ledger"
#property version   "1.20"
#property description "Pushes trade statistics and history to your Ledger dashboard."

//─── Inputs ─────────────────────────────────────────────────────────
input string InpToken         = "";    // ★ EA Token (from Ledger login — Step 3)
input int    InpStatMinutes   = 15;    //   Push stats every N minutes (0 = on close only)
input int    InpEquityMinutes = 60;    //   Equity snapshot interval in minutes (0 = off)
input bool   InpPushTrades    = true;  //   Push individual closed trades
input int    InpSyncDays      = 30;    //   On first run: sync trades from last N days (0 = all)
input bool   InpDebug         = false; //   Show debug messages in Experts log

//─── Endpoint (your Supabase project) ───────────────────────────────
#define ENDPOINT "https://dxjwlrqpwidljudtheol.supabase.co/functions/v1/push-trade"
#define REQ_TIMEOUT 10000

//─── State ──────────────────────────────────────────────────────────
datetime g_lastStatsPush  = 0;
datetime g_lastEquityPush = 0;
ulong    g_lastDealTicket = 0;
bool     g_firstRun       = true;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringLen(InpToken) == 0)
     {
      Alert("LedgerPush: Token is empty!\n\n"
            "Open your Ledger dashboard, go through login,\n"
            "copy the token shown in Step 3, then paste it\n"
            "into EA Inputs → EA Token.");
      return INIT_PARAMETERS_INCORRECT;
     }

   EventSetTimer(60); // Tick every minute

   // ── On first attach: sync history then push stats ────────────────
   datetime syncFrom = 0;
   if(InpSyncDays > 0)
      syncFrom = TimeCurrent() - (datetime)InpSyncDays * 86400;

   // Set g_lastDealTicket to the newest deal BEFORE syncFrom
   // (so we only upload deals within the sync window)
   if(syncFrom > 0 && HistorySelect(0, syncFrom))
     {
      int n = HistoryDealsTotal();
      for(int i = n - 1; i >= 0; i--)
        {
         ulong tk = HistoryDealGetTicket(i);
         long  ty = HistoryDealGetInteger(tk, DEAL_TYPE);
         long  en = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if((en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_INOUT) &&
            (ty == DEAL_TYPE_BUY  || ty == DEAL_TYPE_SELL))
           {
            g_lastDealTicket = tk;
            break;
           }
        }
     }

   if(InpPushTrades) SyncNewTrades();
   PushAllPeriods();
   if(InpEquityMinutes > 0) PushEquity();

   g_lastStatsPush  = TimeCurrent();
   g_lastEquityPush = TimeCurrent();
   g_firstRun       = false;

   Print("LedgerPush v1.20: started. Stats every ",
         InpStatMinutes > 0 ? (string)InpStatMinutes + " min." : "trade-close only.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   PushAllPeriods();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();

   if(InpEquityMinutes > 0 && now - g_lastEquityPush >= (datetime)InpEquityMinutes * 60)
     {
      PushEquity();
      g_lastEquityPush = now;
     }

   if(InpStatMinutes > 0 && now - g_lastStatsPush >= (datetime)InpStatMinutes * 60)
     {
      if(InpPushTrades) SyncNewTrades();
      PushAllPeriods();
      g_lastStatsPush = now;
     }
  }

void OnTick() {} // Timer handles everything; OnTick kept for chart attachment

//+------------------------------------------------------------------+
//| Push stats for all periods at once                               |
//+------------------------------------------------------------------+
void PushAllPeriods()
  {
   PushStats("alltime");
   PushStats("month");
   PushStats("week");
   PushStats("today");
  }

//+------------------------------------------------------------------+
//| Calculate and push account stats for one period                  |
//+------------------------------------------------------------------+
void PushStats(const string period)
  {
   // ── Date range ───────────────────────────────────────────────────
   datetime fromDate = 0;
   datetime toDate   = TimeCurrent() + 86400;

   MqlDateTime tNow;
   TimeToStruct(TimeCurrent(), tNow);

   if(period == "today")
     {
      MqlDateTime d = tNow; d.hour = 0; d.min = 0; d.sec = 0;
      fromDate = StructToTime(d);
     }
   else if(period == "week")
     {
      int dow = (tNow.day_of_week == 0) ? 6 : tNow.day_of_week - 1;
      MqlDateTime d;
      TimeToStruct(TimeCurrent() - (datetime)dow * 86400, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      fromDate = StructToTime(d);
     }
   else if(period == "month")
     {
      MqlDateTime d = tNow; d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
      fromDate = StructToTime(d);
     }
   // alltime: fromDate stays 0

   if(!HistorySelect(fromDate, toDate))
     { if(InpDebug) Print("LedgerPush: HistorySelect failed [", period, "]"); return; }

   // ── Find start balance ───────────────────────────────────────────
   double startBalance = 0;
   if(period == "alltime")
     {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(tk, DEAL_TYPE) == DEAL_TYPE_BALANCE)
            startBalance += HistoryDealGetDouble(tk, DEAL_PROFIT);
        }
      if(startBalance <= 0)
         startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }
   // For other periods: startBalance = currentBal - periodNet (calculated below)

   // ── Scan exit deals ──────────────────────────────────────────────
   int    n            = HistoryDealsTotal();
   double periodNet    = 0;
   double totalProfit  = 0;
   double totalLoss    = 0;
   int    wins         = 0;
   int    losses       = 0;
   int    tradeCount   = 0;
   double bestTrade    = 0;
   double worstTrade   = 0;
   int    cWin = 0,  maxCWin  = 0;
   int    cLoss = 0, maxCLoss = 0;

   // Running balance for drawdown
   double runBal[];
   int    runIdx = 0;
   ArrayResize(runBal, n + 1);

   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;

      long dType  = HistoryDealGetInteger(tk, DEAL_TYPE);
      long dEntry = HistoryDealGetInteger(tk, DEAL_ENTRY);

      if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;
      if(dType  != DEAL_TYPE_BUY  && dType  != DEAL_TYPE_SELL)  continue;

      double pnl  = HistoryDealGetDouble(tk, DEAL_PROFIT);
      double comm = HistoryDealGetDouble(tk, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(tk, DEAL_SWAP);
      double net  = pnl + comm + swap;

      tradeCount++;
      periodNet += net;
      runBal[runIdx++] = periodNet;

      if(net >= 0) { wins++;   totalProfit += net;  cWin++;  cLoss = 0; }
      else          { losses++; totalLoss  -= net;   cLoss++; cWin  = 0; }

      if(cWin  > maxCWin)  maxCWin  = cWin;
      if(cLoss > maxCLoss) maxCLoss = cLoss;
      if(net > bestTrade)  bestTrade  = net;
      if(net < worstTrade) worstTrade = net;
     }

   // Skip empty sub-periods (nothing to report)
   if(tradeCount == 0 && period != "alltime") return;

   // ── Derived stats ────────────────────────────────────────────────
   double curBal       = AccountInfoDouble(ACCOUNT_BALANCE);
   if(period != "alltime") startBalance = curBal - periodNet;

   double netPnl       = (period == "alltime") ? (curBal - startBalance) : periodNet;
   double pctReturn    = startBalance > 0 ? netPnl / startBalance * 100.0 : 0;
   double winRate      = tradeCount   > 0 ? (double)wins / tradeCount * 100.0 : 0;
   double profitFactor = totalLoss    > 0 ? totalProfit / totalLoss : (totalProfit > 0 ? 999.0 : 0);
   double avgWin       = wins   > 0 ? totalProfit / wins   : 0;
   double avgLoss      = losses > 0 ? totalLoss   / losses : 0;

   // Peak-to-trough drawdown on period's cumulative PnL
   double peak = 0, maxDDUsd = 0;
   for(int i = 0; i < runIdx; i++)
     {
      if(runBal[i] > peak) peak = runBal[i];
      double dd = peak - runBal[i];
      if(dd > maxDDUsd) maxDDUsd = dd;
     }
   double maxDDPct    = startBalance > 0 ? maxDDUsd / startBalance * 100.0 : 0;
   double recovFactor = maxDDUsd > 0 ? netPnl / maxDDUsd : 0;

   // ── JSON ─────────────────────────────────────────────────────────
   string j = "{\"type\":\"stats\"";
   j += ",\"period\":\""          + period                               + "\"";
   j += ",\"start_balance\":"     + DoubleToString(startBalance,  2);
   j += ",\"current_balance\":"   + DoubleToString(curBal,        2);
   j += ",\"net_pnl\":"           + DoubleToString(netPnl,        2);
   j += ",\"pct_return\":"        + DoubleToString(pctReturn,     4);
   j += ",\"win_rate\":"          + DoubleToString(winRate,       2);
   j += ",\"trades_count\":"      + IntegerToString(tradeCount);
   j += ",\"profit_factor\":"     + DoubleToString(profitFactor,  4);
   j += ",\"recovery_factor\":"   + DoubleToString(recovFactor,   4);
   j += ",\"max_dd_pct\":"        + DoubleToString(maxDDPct,      4);
   j += ",\"max_dd_usd\":"        + DoubleToString(maxDDUsd,      2);
   j += ",\"avg_win\":"           + DoubleToString(avgWin,        2);
   j += ",\"avg_loss\":"          + DoubleToString(avgLoss,       2);
   j += ",\"max_cons_win\":"      + IntegerToString(maxCWin);
   j += ",\"max_cons_loss\":"     + IntegerToString(maxCLoss);
   j += ",\"best_trade\":"        + DoubleToString(bestTrade,     2);
   j += ",\"worst_trade\":"       + DoubleToString(worstTrade,    2);
   j += "}";

   HttpPost(j, "stats/" + period);
  }

//+------------------------------------------------------------------+
//| Push equity snapshot                                             |
//+------------------------------------------------------------------+
void PushEquity()
  {
   string j = "{\"type\":\"equity\"";
   j += ",\"balance\":"         + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   j += ",\"equity\":"          + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),  2);
   j += ",\"snapshot_time\":\"" + TimeToISO(TimeCurrent()) + "\"";
   j += "}";
   HttpPost(j, "equity");
  }

//+------------------------------------------------------------------+
//| Scan history and upload any deals newer than g_lastDealTicket   |
//+------------------------------------------------------------------+
void SyncNewTrades()
  {
   if(!HistorySelect(0, TimeCurrent() + 86400)) return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || ticket <= g_lastDealTicket) continue;

      long dType  = HistoryDealGetInteger(ticket, DEAL_TYPE);
      long dEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

      if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;
      if(dType  != DEAL_TYPE_BUY  && dType  != DEAL_TYPE_SELL)  continue;

      // ── Get open deal for this position ─────────────────────────
      ulong    posId     = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double   closePr   = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double   openPr    = 0;
      datetime openTime  = 0;

      for(int k = 0; k < total; k++)
        {
         ulong tk = HistoryDealGetTicket(k);
         if((ulong)HistoryDealGetInteger(tk, DEAL_POSITION_ID) == posId &&
            HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            openPr   = HistoryDealGetDouble(tk, DEAL_PRICE);
            openTime = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
            break;
           }
        }

      int durMin = openTime > 0 ? (int)((closeTime - openTime) / 60) : 0;

      string j = "{\"type\":\"trade\"";
      j += ",\"ticket\":"       + IntegerToString((long)posId);
      j += ",\"symbol\":\""     + HistoryDealGetString(ticket, DEAL_SYMBOL) + "\"";
      j += ",\"side\":\""       + (dType == DEAL_TYPE_BUY ? "buy" : "sell") + "\"";
      j += ",\"lots\":"         + DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2);
      j += ",\"open_price\":"   + DoubleToString(openPr,  5);
      j += ",\"close_price\":"  + DoubleToString(closePr, 5);
      j += ",\"open_time\":\""  + TimeToISO(openTime)  + "\"";
      j += ",\"close_time\":\"" + TimeToISO(closeTime) + "\"";
      j += ",\"duration_min\":" + IntegerToString(durMin);
      j += ",\"pnl\":"          + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT),     2);
      j += ",\"commission\":"   + DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2);
      j += ",\"swap\":"         + DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP),       2);
      j += "}";

      if(HttpPost(j, "trade #" + IntegerToString((long)posId)))
         if(ticket > g_lastDealTicket) g_lastDealTicket = ticket;
     }
  }

//+------------------------------------------------------------------+
//| HTTP POST to Ledger Edge Function                                |
//+------------------------------------------------------------------+
bool HttpPost(const string body, const string label)
  {
   char   data[];
   char   result[];
   string resultHeaders;

   int len = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   ArrayResize(data, len);

   string reqHeaders = "Content-Type: application/json\r\n"
                     + "X-EA-Token: " + InpToken + "\r\n";

   ResetLastError();
   int code = WebRequest("POST", ENDPOINT, reqHeaders, REQ_TIMEOUT, data, result, resultHeaders);

   if(code == -1)
     {
      int e = GetLastError();
      if(e == 4014)
         Alert("LedgerPush: URL not whitelisted in MT5!\n\n"
               "Tools → Options → Expert Advisors\n"
               "☑ Allow WebRequest for listed URL\n"
               "Add:  https://dxjwlrqpwidljudtheol.supabase.co");
      else if(InpDebug)
         Print("LedgerPush [", label, "]: error ", e);
      return false;
     }

   if(code != 200)
     {
      if(InpDebug)
         Print("LedgerPush [", label, "]: HTTP ", code, " — ",
               CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8));
      return false;
     }

   if(InpDebug)
      Print("LedgerPush [", label, "]: ✓ ", CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8));
   return true;
  }

//+------------------------------------------------------------------+
//| Convert MT5 datetime to ISO 8601 UTC string                     |
//+------------------------------------------------------------------+
string TimeToISO(const datetime t)
  {
   if(t == 0) return "1970-01-01T00:00:00Z";
   MqlDateTime s;
   TimeToStruct(t, s);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       s.year, s.mon, s.day, s.hour, s.min, s.sec);
  }
//+------------------------------------------------------------------+
