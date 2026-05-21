//+------------------------------------------------------------------+
//|                                     TradingJournalEA_v7.mq5     |
//|      Trading Journal — Full Analytics Suite (7 Modules)          |
//|                                                                  |
//|  v5 CHANGES:                                                     |
//|  - ลบ R:R ออกทุกจุด → แสดงเป็น USD/Currency ทั้งหมด            |
//|  - Period cards: Net P&L $ เป็นตัวเลขหลัก, % เป็น badge         |
//|  - Stat grid: Gross Profit, Gross Loss แทน R:R Sum               |
//|  - Chart 2: P&L per Trade ($) แทน R:R chart                     |
//|  - Monthly: แสดง Profit $ เป็น default                           |
//|  - Trade list: Net P&L $ ใหญ่ %, Lots, Duration แทน R:R          |
//|  - แก้ currency display (USC → USD สำหรับ broker บางราย)         |
//+------------------------------------------------------------------+
#property copyright "Trading Journal EA v7"
#property version   "7.00"
#property strict

//========================= INPUTS ==================================
input group "=== Risk Settings ==="
input double InpRiskPercent  = 1.0;
input double InpFixedRisk    = 0.0;    // 0 = ใช้ % ของ balance ต้นช่วง
input double InpBEThreshold  = 1.0;   // |net| <= ค่านี้ = Break-Even

input group "=== Trade Filters ==="
input string InpSymbolFilter = "ALL";
input long   InpMagicFilter  = 0;

input group "=== Refresh ==="
input int    InpRefreshSec   = 30;
input bool   InpAutoOpen     = true;

input group "=== Output ==="
input string InpHTMLFile     = "trading_dashboard.html";

//========================= BUTTONS ================================
#define BTN_TODAY   "j_today"
#define BTN_WEEKLY  "j_weekly"
#define BTN_MONTHLY "j_monthly"
#define BTN_ALL     "j_alltime"
#define BTN_REFRESH  "j_refresh"
#define BTN_LASTWEEK "j_lastweek"

struct BtnDef { string name; string label; string period; int x; };
BtnDef g_btns[] = {
    {BTN_TODAY,    "  Today   ", "today",    10 },
    {BTN_WEEKLY,   "  Weekly  ", "weekly",   112},
    {BTN_LASTWEEK, " Last Week", "lastweek", 214},
    {BTN_MONTHLY,  " Monthly  ", "monthly",  316},
    {BTN_ALL,      " All Time ", "alltime",  418},
    {BTN_REFRESH,  "  Refresh ", "",          520}
};
string g_period = "today";
bool   g_browser_opened = false;   // เปิดเบราว์เซอร์แค่ครั้งแรกเท่านั้น

//========================= STRUCTS ================================
struct Pos {
    long     id;
    string   symbol, side, strategy;
    double   volume, profit, commission, swap, net, rr;
    double   open_price;   // Module 2: deal price at entry
    double   mae_usd;      // Module 2: Maximum Adverse Excursion ($)
    double   mfe_usd;      // Module 2: Maximum Favorable Excursion ($)
    datetime open_t, close_t;
    bool     closed;
};

struct Stats {
    string label;
    double rr_sum;       // ผลรวม R:R
    double net;          // Net P&L
    double pct;          // % P&L vs period-start balance
    double gross_profit; // รวม profit ของ winning trades
    double gross_loss;   // รวม loss ของ losing trades
    double profit_factor;
    double recovery_factor;
    double win_rate;
    double max_dd;       // Max Drawdown ($)
    double max_dd_pct;   // Max Drawdown (%)
    double lots;
    double commission;
    double swap;
    double avg_dur;         // วินาที
    double period_start_bal;// balance จริง ณ ต้นช่วง
    // Module 4: Consecutive Streaks & Risk Profiling
    int    max_cw;          // Max consecutive wins
    int    max_cl;          // Max consecutive losses
    double avg_win;         // Average win ($)
    double avg_loss;        // Average loss ($)
    int    total, wins, losses, be, open_c;
};

Pos    g_pos[];
double g_init_bal  = 0;   // balance จาก balance deal แรกสุดในระบบ
double g_bal_now   = 0;   // current account balance
double g_equity    = 0;
double g_risk_base = 0;   // risk per trade (คำนวณจาก input)

#import "shell32.dll"
int ShellExecuteW(int hwnd,string op,string file,string params,string dir,int show);
#import


//========================= BEHAVIORAL GRID STRUCT ================
struct BehaviorGrid {
    // Dim 1: Risk-Adjusted Performance (weight 35%)
    double expectancy;      // (WR×AvgWin) - (LR×AvgLoss)
    double profit_factor;
    double sharpe_approx;   // mean_pnl×sqrt(N) / stddev_pnl

    // Dim 2: Consistency & Discipline (weight 25%)
    double monthly_wr;      // % profitable months in period
    double coeff_var;       // stddev / |mean| (lower = more consistent)
    int    sample_size;

    // Dim 3: Capital Preservation (weight 25%)
    double max_dd_pct;
    double calmar_ratio;    // annualized return / max dd %
    int    max_consec_loss;

    // Dim 4: Execution Quality (weight 15%)
    double trade_efficiency;// avg(net/mfe) % — how well TP is set
    double mae_net_ratio;   // avg(mae/|net|) — pain taken per $ profit

    // Scores per dimension: 100=Elite, 60=Standard, 0=Fail
    int    d1_score, d2_score, d3_score, d4_score;
    string d1_level, d2_level, d3_level, d4_level;

    double composite;       // weighted composite 0-100
    int    stars;           // 0-5
    string rank_title;
    string rank_code;       // SUPREME / MARSHAL / GENERAL / COLONEL / MAJOR / PRIVATE
    string tactical_notes;  // auto-generated assessment
};

//========================= INIT ===================================
int OnInit() {
    g_bal_now = AccountInfoDouble(ACCOUNT_BALANCE);
    g_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    CreateButtons();
    EventSetTimer(MathMax(10, InpRefreshSec));
    RunAnalysis(g_period);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    EventKillTimer();
    for(int i=0;i<ArraySize(g_btns);i++) ObjectDelete(0,g_btns[i].name);
    ChartRedraw();
    Comment("");
}

void OnTimer() { RunAnalysis(g_period); }

void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp) {
    if(id!=CHARTEVENT_OBJECT_CLICK) return;
    for(int i=0;i<ArraySize(g_btns);i++) {
        if(sp==g_btns[i].name) {
            if(g_btns[i].name!=BTN_REFRESH) g_period=g_btns[i].period;
            RefreshBtns();
            // ปุ่ม Refresh = อัพเดทข้อมูล + เปิด browser (reload ล่าสุด)
            // ปุ่มอื่น = แค่เปลี่ยน period ที่ EA จะ export ครั้งหน้า
            if(g_btns[i].name==BTN_REFRESH) {
                g_browser_opened = false;  // reset flag ให้เปิด browser ใหม่
            }
            RunAnalysis(g_period);
        }
    }
    ObjectSetInteger(0,sp,OBJPROP_STATE,false);
    ChartRedraw();
}

//========================= BUTTONS ================================
void CreateButtons() {
    for(int i=0;i<ArraySize(g_btns);i++){
        string n=g_btns[i].name;
        if(ObjectFind(0,n)>=0) ObjectDelete(0,n);
        ObjectCreate(0,n,OBJ_BUTTON,0,0,0);
        ObjectSetInteger(0,n,OBJPROP_XDISTANCE,g_btns[i].x);
        ObjectSetInteger(0,n,OBJPROP_YDISTANCE,22);
        ObjectSetInteger(0,n,OBJPROP_XSIZE,100);
        ObjectSetInteger(0,n,OBJPROP_YSIZE,28);
        ObjectSetString (0,n,OBJPROP_TEXT,g_btns[i].label);
        ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
        ObjectSetString (0,n,OBJPROP_FONT,"Arial Bold");
        ObjectSetInteger(0,n,OBJPROP_BACK,false);
        ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,n,OBJPROP_STATE,false);
    }
    RefreshBtns();
    ChartRedraw();
}

void RefreshBtns() {
    for(int i=0;i<ArraySize(g_btns);i++){
        string n=g_btns[i].name;
        bool act=(g_btns[i].period==g_period && g_btns[i].name!=BTN_REFRESH);
        if(n==BTN_REFRESH){
            ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'30,60,100');
            ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);
        } else if(act){
            ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'37,99,235');
            ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);
        } else {
            ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'22,30,44');
            ObjectSetInteger(0,n,OBJPROP_COLOR,C'140,160,184');
        }
    }
    ChartRedraw();
}

//========================= PERIOD RANGE ===========================
void PeriodRange(string period, datetime &from, datetime &to) {
    to = TimeCurrent();
    MqlDateTime d; TimeToStruct(to,d);
    if(period=="today") {
        d.hour=0;d.min=0;d.sec=0;
        from=StructToTime(d);
    } else if(period=="weekly") {
        int bk=(d.day_of_week==0?6:d.day_of_week-1);
        d.hour=0;d.min=0;d.sec=0;
        from=StructToTime(d)-bk*86400;
    } else if(period=="lastweek") {
        // หา start of this week (Monday) แล้วถอยกลับไป 7 วัน
        int dow=(d.day_of_week==0?6:d.day_of_week-1);  // 0=Mon..6=Sun
        d.hour=0;d.min=0;d.sec=0;
        datetime start_this_week=StructToTime(d)-dow*86400;
        from=start_this_week-7*86400;  // start of last week (Mon)
        to  =start_this_week-1;        // end of last week (Sun 23:59:59)
        return;  // ออกเลย ไม่ต้องใช้ to=TimeCurrent()
    } else if(period=="monthly") {
        d.day=1;d.hour=0;d.min=0;d.sec=0;
        from=StructToTime(d);
    } else {
        from=D'2000.01.01 00:00';
    }
}


//========================= MODULE 2: MAE & MFE ===================
// คำนวณ Maximum Adverse/Favorable Excursion จาก M1 bar data
// จำกัดที่ 150 trades ล่าสุดเพื่อ performance
void CalcMAE_MFE() {
    int n = ArraySize(g_pos);
    int start = MathMax(0, n - 150);

    for(int i = start; i < n; i++) {
        if(!g_pos[i].closed)                     continue;
        if(g_pos[i].open_price <= 0)             continue;
        if(g_pos[i].close_t <= g_pos[i].open_t) continue;

        string sym    = g_pos[i].symbol;
        bool   is_lng = (g_pos[i].side == "LONG");
        double op     = g_pos[i].open_price;

        MqlRates rates[];
        int copied = CopyRates(sym, PERIOD_M1,
                               g_pos[i].open_t,
                               g_pos[i].close_t, rates);

        double mae_pts = 0, mfe_pts = 0;
        if(copied > 0) {
            for(int j = 0; j < copied; j++) {
                double adv = is_lng ? (op - rates[j].low)  : (rates[j].high - op);
                double fav = is_lng ? (rates[j].high - op) : (op - rates[j].low);
                if(adv > mae_pts) mae_pts = adv;
                if(fav > mfe_pts) mfe_pts = fav;
            }
        } else {
            // fallback: ประมาณจาก net P&L
            g_pos[i].mae_usd = (g_pos[i].net < 0 ? MathAbs(g_pos[i].net) : 0);
            g_pos[i].mfe_usd = (g_pos[i].net > 0 ? g_pos[i].net : 0);
            continue;
        }

        // แปลง price points -> USD
        double tick_val  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
        double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
        double vol       = g_pos[i].volume;
        if(tick_size > 0 && tick_val > 0 && vol > 0) {
            double mult = vol * tick_val / tick_size;
            g_pos[i].mae_usd = mae_pts * mult;
            g_pos[i].mfe_usd = mfe_pts * mult;
        }
    }
}


//========================= MODULE: BEHAVIORAL GRID ===============

// คำนวณ % ของเดือนที่มีกำไรในช่วง period
double CalcMonthlyWinRate(datetime from, datetime to) {
    int profitable = 0, active = 0;
    // scan monthly data (reuse g_pos)
    // group by year-month
    int yms[]; // year*100 + month
    double ym_pnl[];
    int n = ArraySize(g_pos);
    for(int i = 0; i < n; i++) {
        if(!g_pos[i].closed) continue;
        if(g_pos[i].close_t < from || g_pos[i].close_t > to) continue;
        MqlDateTime d; TimeToStruct(g_pos[i].close_t, d);
        int ym = d.year * 100 + d.mon;
        int idx = -1;
        for(int j = 0; j < ArraySize(yms); j++) if(yms[j]==ym){idx=j;break;}
        if(idx < 0) {
            idx = ArraySize(yms);
            ArrayResize(yms, idx+1);
            ArrayResize(ym_pnl, idx+1);
            yms[idx] = ym; ym_pnl[idx] = 0;
        }
        ym_pnl[idx] += g_pos[i].net;
    }
    active = ArraySize(yms);
    if(active == 0) return 0;
    for(int j = 0; j < active; j++)
        if(ym_pnl[j] > 0) profitable++;
    return 100.0 * profitable / active;
}

// คำนวณ StdDev ของ trade PnL
double CalcStdDevPnL(datetime from, datetime to, double mean_pnl) {
    int n = ArraySize(g_pos), cnt = 0;
    double variance = 0;
    for(int i = 0; i < n; i++) {
        if(!g_pos[i].closed) continue;
        if(g_pos[i].close_t < from || g_pos[i].close_t > to) continue;
        variance += MathPow(g_pos[i].net - mean_pnl, 2);
        cnt++;
    }
    return (cnt > 1 ? MathSqrt(variance / (cnt - 1)) : 0);
}

// ให้คะแนน dimension และ level string
int ScoreMetric(double val, double elite, double standard, double fail, bool lower_is_better=false) {
    if(!lower_is_better) {
        if(val >= elite)    return 100;
        if(val >= standard) return 60;
        if(val <= fail)     return 0;
        return 30; // between standard and fail
    } else {
        if(val <= elite)    return 100;
        if(val <= standard) return 60;
        if(val >= fail)     return 0;
        return 30;
    }
}

string LevelStr(int score) {
    if(score >= 100) return "ELITE";
    if(score >= 60)  return "STANDARD";
    if(score >= 30)  return "CAUTION";
    return "FAIL";
}

// Main function
void CalcBehaviorGrid(datetime from, datetime to, const Stats &s, BehaviorGrid &bg) {
    // ── Collect filtered trade data ──────────────────────────────
    int n = ArraySize(g_pos);
    double mean_pnl = (s.total > 0 ? s.net / s.total : 0);
    double std_pnl  = CalcStdDevPnL(from, to, mean_pnl);
    double sum_eff  = 0; int eff_cnt  = 0;
    double sum_mae  = 0; int mae_cnt  = 0;

    for(int i = 0; i < n; i++) {
        if(!g_pos[i].closed) continue;
        if(g_pos[i].close_t < from || g_pos[i].close_t > to) continue;
        // Trade efficiency: net/mfe for winning trades with mfe > 0
        if(g_pos[i].net > InpBEThreshold && g_pos[i].mfe_usd > 0.01) {
            sum_eff += MathMin(g_pos[i].net / g_pos[i].mfe_usd, 1.0);
            eff_cnt++;
        }
        // MAE ratio: mae/|net| — how much pain per dollar result
        if(g_pos[i].mae_usd > 0.01 && MathAbs(g_pos[i].net) > 0.01) {
            sum_mae += g_pos[i].mae_usd / MathAbs(g_pos[i].net);
            mae_cnt++;
        }
    }

    // ── Dim 1: Risk-Adjusted Performance ─────────────────────────
    double lr = 1.0 - s.win_rate / 100.0;
    bg.expectancy   = (s.total > 0)
                    ? (s.win_rate/100.0 * s.avg_win) - (lr * s.avg_loss) : 0;
    bg.profit_factor= s.profit_factor;
    // Sharpe approx: mean_pnl / stddev * sqrt(N)
    bg.sharpe_approx= (std_pnl > 0 && s.total > 1)
                    ? (mean_pnl / std_pnl) * MathSqrt((double)s.total) : 0;

    int e_score  = ScoreMetric(bg.expectancy,    0.5, 0.0, -1.0);
    int pf_score = ScoreMetric(bg.profit_factor, 2.0, 1.3, 1.0);
    int sh_score = ScoreMetric(bg.sharpe_approx, 1.5, 0.5, 0.0);
    bg.d1_score  = (int)MathRound((e_score + pf_score + sh_score) / 3.0);
    bg.d1_level  = LevelStr(bg.d1_score);

    // ── Dim 2: Consistency & Discipline ──────────────────────────
    bg.monthly_wr  = CalcMonthlyWinRate(from, to);
    bg.coeff_var   = (MathAbs(mean_pnl) > 0.01) ? std_pnl / MathAbs(mean_pnl) : 999;
    bg.sample_size = s.total;

    int mwr_score  = ScoreMetric(bg.monthly_wr,  70.0, 50.0, 30.0);
    int cv_score   = ScoreMetric(bg.coeff_var,   1.5,  3.0,  5.0, true);
    int ss_score   = ScoreMetric((double)s.total, 50.0, 20.0, 10.0);
    bg.d2_score    = (int)MathRound((mwr_score + cv_score + ss_score) / 3.0);
    bg.d2_level    = LevelStr(bg.d2_score);

    // ── Dim 3: Capital Preservation ──────────────────────────────
    bg.max_dd_pct      = s.max_dd_pct;
    bg.max_consec_loss = s.max_cl;
    // Calmar = annualized return % / max dd %
    double period_days = MathMax((double)(to - from) / 86400.0, 1.0);
    double ann_ret_pct = (s.period_start_bal > 0)
                       ? (s.net / s.period_start_bal) * (365.0 / period_days) * 100.0 : 0;
    bg.calmar_ratio    = (s.max_dd_pct > 0.01) ? ann_ret_pct / s.max_dd_pct
                       : (ann_ret_pct > 0 ? 999.0 : 0.0);

    int dd_score  = ScoreMetric(s.max_dd_pct,    5.0, 15.0, 25.0, true);
    int cal_score = ScoreMetric(bg.calmar_ratio,  3.0,  1.0,  0.5);
    int cl_score  = ScoreMetric((double)s.max_cl, 3.0,  6.0, 10.0, true);
    bg.d3_score   = (int)MathRound((dd_score + cal_score + cl_score) / 3.0);
    bg.d3_level   = LevelStr(bg.d3_score);

    // ── Dim 4: Execution Quality ──────────────────────────────────
    bg.trade_efficiency = (eff_cnt > 0) ? sum_eff / eff_cnt * 100.0 : 0;
    bg.mae_net_ratio    = (mae_cnt > 0) ? sum_mae / mae_cnt : 0;

    // ถ้าไม่มี MAE/MFE data ให้ neutral score
    if(eff_cnt + mae_cnt == 0) {
        bg.d4_score = 60; bg.d4_level = "N/A";
    } else {
        int eff_score = ScoreMetric(bg.trade_efficiency, 60.0, 30.0, 10.0);
        int mae_score = ScoreMetric(bg.mae_net_ratio,     0.5,  1.0,  2.0, true);
        bg.d4_score   = (int)MathRound((eff_score + mae_score) / 2.0);
        bg.d4_level   = LevelStr(bg.d4_score);
    }

    // ── Composite Score ───────────────────────────────────────────
    bg.composite = bg.d1_score * 0.35
                 + bg.d2_score * 0.25
                 + bg.d3_score * 0.25
                 + bg.d4_score * 0.15;

    // ── Rank Assignment ───────────────────────────────────────────
    if(bg.composite >= 90) {
        bg.stars=5; bg.rank_title="Supreme Commander"; bg.rank_code="SUPREME";
    } else if(bg.composite >= 75) {
        bg.stars=4; bg.rank_title="Field Marshal";     bg.rank_code="MARSHAL";
    } else if(bg.composite >= 60) {
        bg.stars=3; bg.rank_title="General";           bg.rank_code="GENERAL";
    } else if(bg.composite >= 45) {
        bg.stars=2; bg.rank_title="Colonel";           bg.rank_code="COLONEL";
    } else if(bg.composite >= 30) {
        bg.stars=1; bg.rank_title="Major";             bg.rank_code="MAJOR";
    } else {
        bg.stars=0; bg.rank_title="Private (Under Review)"; bg.rank_code="PRIVATE";
    }

    // ── Tactical Notes ────────────────────────────────────────────
    string notes = "";
    if(bg.d1_level=="FAIL")     notes += "ALERT: Risk-reward system is losing money — halt trading immediately. ";
    else if(bg.d1_level=="ELITE") notes += "D1 CLEAR: Risk-adjusted performance is battle-ready. ";

    if(bg.d3_level=="FAIL")     notes += "CRITICAL: Capital under siege — drawdown exceeds safe perimeter. ";
    else if(bg.max_dd_pct < 5.0) notes += "D3 SECURE: Capital fortification is excellent. ";

    if(bg.coeff_var > 5.0)      notes += "WARNING: Highly erratic PnL pattern — discipline breakdown detected. ";
    else if(bg.coeff_var < 1.5) notes += "D2 CONSISTENT: Systematic execution confirmed. ";

    if(bg.trade_efficiency > 0 && bg.trade_efficiency < 30.0)
        notes += "D4 ADVISORY: Exits too early — significant profit left on the battlefield. ";

    if(bg.max_consec_loss >= 8)
        notes += "FATIGUE RISK: " + (string)bg.max_consec_loss + " consecutive losses detected — mandatory stand-down protocol recommended. ";

    if(bg.sample_size < 20)
        notes += "DATA CAUTION: Insufficient mission count (n=" + (string)bg.sample_size + ") — statistical confidence is low. ";

    if(notes == "") notes = "All systems nominal. Continue current tactical protocol.";
    bg.tactical_notes = notes;
}

// Serialize BehaviorGrid to JSON string
string SBG(const BehaviorGrid &bg) {
    string r = "{";
    r += "\"exp\":"      + DoubleToString(bg.expectancy,2);
    r += ",\"pf\":"      + DoubleToString(bg.profit_factor,2);
    r += ",\"sharpe\":"  + DoubleToString(bg.sharpe_approx,2);
    r += ",\"mwr\":"     + DoubleToString(bg.monthly_wr,1);
    r += ",\"cv\":"      + DoubleToString(bg.coeff_var,2);
    r += ",\"ss\":"      + (string)bg.sample_size;
    r += ",\"maxddp\":" + DoubleToString(bg.max_dd_pct,2);
    r += ",\"calmar\":" + DoubleToString(bg.calmar_ratio,2);
    r += ",\"mcl\":"     + (string)bg.max_consec_loss;
    r += ",\"teff\":"    + DoubleToString(bg.trade_efficiency,1);
    r += ",\"maer\":"    + DoubleToString(bg.mae_net_ratio,2);
    r += ",\"d1s\":"     + (string)bg.d1_score;
    r += ",\"d1l\":\"" + bg.d1_level + "\"";
    r += ",\"d2s\":"     + (string)bg.d2_score;
    r += ",\"d2l\":\"" + bg.d2_level + "\"";
    r += ",\"d3s\":"     + (string)bg.d3_score;
    r += ",\"d3l\":\"" + bg.d3_level + "\"";
    r += ",\"d4s\":"     + (string)bg.d4_score;
    r += ",\"d4l\":\"" + bg.d4_level + "\"";
    r += ",\"comp\":"    + DoubleToString(bg.composite,1);
    r += ",\"stars\":"   + (string)bg.stars;
    r += ",\"title\":\"" + JE(bg.rank_title)      + "\"";
    r += ",\"code\":\""  + bg.rank_code            + "\"";
    r += ",\"notes\":\"" + JE(bg.tactical_notes)   + "\"";
    r += "}";
    return r;
}

//========================= MAIN RUN ===============================
void RunAnalysis(string period) {
    g_bal_now = AccountInfoDouble(ACCOUNT_BALANCE);
    g_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    ArrayResize(g_pos,0);
    g_init_bal=0;

    if(!HistorySelect(D'2000.01.01',TimeCurrent())) return;
    LoadPositions();   // โหลดทุก position ก่อน

    // คำนวณ risk base จาก initial balance
    g_risk_base = (InpFixedRisk>0) ? InpFixedRisk
                : (g_init_bal>0 ? g_init_bal : g_bal_now)*InpRiskPercent/100.0;
    if(g_risk_base<=0) g_risk_base=1;

    // กำหนด RR ให้ทุก closed position
    int n=ArraySize(g_pos);
    for(int i=0;i<n;i++)
        if(g_pos[i].closed)
            g_pos[i].rr=g_pos[i].net/g_risk_base;

    CalcMAE_MFE();  // Module 2: MAE & MFE

    // คำนวณ stats ทั้ง 4 period
    datetime from,to;
    PeriodRange(period,from,to);

    Stats sel,s_today,s_week,s_lastweek,s_month,s_all;
    datetime f2,t2;

    CalcStats(from,to,sel);
    sel.label=PeriodLabel(period);

    PeriodRange("today",f2,t2);    CalcStats(f2,t2,s_today);    s_today.label="Today";
    PeriodRange("weekly",f2,t2);   CalcStats(f2,t2,s_week);     s_week.label="This Week";
    PeriodRange("lastweek",f2,t2); CalcStats(f2,t2,s_lastweek); s_lastweek.label="Last Week";
    PeriodRange("monthly",f2,t2);  CalcStats(f2,t2,s_month);    s_month.label="This Month";
    PeriodRange("alltime",f2,t2);  CalcStats(f2,t2,s_all);      s_all.label="All Time";

    // Series: ส่ง ALL TIME เสมอ — JS จะ filter เอง ตาม period ที่เลือก
    string bal_j,rr_j;
    datetime all_from=D'2000.01.01 00:00', all_to=TimeCurrent();
    BuildSeries(all_from, all_to, g_init_bal, bal_j, rr_j);
    string monthly_j=BuildMonthlyJSON();
    // Closed trades: ส่งทั้งหมด (ไม่กรอง period) — JS filter เอง
    string closed_j =BuildTradesJSON(false,0,0);
    string open_j   =BuildTradesJSON(true,0,0);
    string side_j   =BuildSideJSON();      // Analytics: Buy vs Sell
    string session_j=BuildSessionJSON();    // Analytics: Sessions

    // Module: Behavioral Grid — คำนวณทุก period เพื่อให้ JS switch ได้
    BehaviorGrid bg, bg_today, bg_week, bg_lastweek, bg_month, bg_all;
    CalcBehaviorGrid(from, to, sel, bg);  // active period
    PeriodRange("today",f2,t2);    CalcBehaviorGrid(f2,t2,s_today,   bg_today);
    PeriodRange("weekly",f2,t2);   CalcBehaviorGrid(f2,t2,s_week,    bg_week);
    PeriodRange("lastweek",f2,t2); CalcBehaviorGrid(f2,t2,s_lastweek,bg_lastweek);
    PeriodRange("monthly",f2,t2);  CalcBehaviorGrid(f2,t2,s_month,   bg_month);
    PeriodRange("alltime",f2,t2);  CalcBehaviorGrid(f2,t2,s_all,     bg_all);

    WriteHTML(period,sel,s_today,s_week,s_lastweek,s_month,s_all,
              bg,bg_today,bg_week,bg_lastweek,bg_month,bg_all,
              bal_j,rr_j,monthly_j,open_j,closed_j,side_j,session_j);

    // Chart comment
    string ccy=AccountInfoString(ACCOUNT_CURRENCY);
    Comment("Trading Journal v5  |  Period: "+PeriodLabel(period)+"\n"
            +"Net: "+(sel.net>=0?"+":"")+DoubleToString(sel.net,2)+" "+ccy
            +"  |  WinRate: "+DoubleToString(sel.win_rate,1)+"%"
            +"  |  PF: "+DoubleToString(sel.profit_factor,2)+"\n"
            +"Updated: "+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));

    // เปิดเบราว์เซอร์แค่ครั้งแรก หรือเมื่อกดปุ่มบน chart
    // ไม่เปิดซ้ำทุก timer เพราะจะทำให้ browser โหลดหน้าใหม่และ reset period ที่เลือก
    if(InpAutoOpen && !g_browser_opened){
        string p=TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL5\\Files\\"+InpHTMLFile;
        ShellExecuteW(0,"open",p,"","",1);
        g_browser_opened = true;
    }
}

string PeriodLabel(string p) {
    if(p=="today")    return "Today";
    if(p=="weekly")   return "This Week";
    if(p=="lastweek") return "Last Week";
    if(p=="monthly")  return "This Month";
    return "All Time";
}

//========================= LOAD POSITIONS =========================
void LoadPositions() {
    int n=HistoryDealsTotal();
    bool started=false;

    for(int i=0;i<n;i++){
        ulong tk=HistoryDealGetTicket(i);
        if(!tk) continue;

        long    type  =HistoryDealGetInteger(tk,DEAL_TYPE);
        long    entry =HistoryDealGetInteger(tk,DEAL_ENTRY);
        long    magic =HistoryDealGetInteger(tk,DEAL_MAGIC);
        long    pid   =HistoryDealGetInteger(tk,DEAL_POSITION_ID);
        string  sym   =HistoryDealGetString(tk,DEAL_SYMBOL);
        double  prf   =HistoryDealGetDouble(tk,DEAL_PROFIT);
        double  com   =HistoryDealGetDouble(tk,DEAL_COMMISSION);
        double  swp   =HistoryDealGetDouble(tk,DEAL_SWAP);
        double  vol   =HistoryDealGetDouble(tk,DEAL_VOLUME);
        datetime dt   =(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
        string  cmt   =HistoryDealGetString(tk,DEAL_COMMENT);

        // Balance / Credit deal → เก็บ initial balance
        if(type==DEAL_TYPE_BALANCE||type==DEAL_TYPE_CREDIT){
            if(!started && prf>0){g_init_bal=prf;started=true;}
            continue;
        }

        if(InpMagicFilter!=0 && magic!=InpMagicFilter) continue;
        if(!SymOK(sym)) continue;

        int idx=FindPos(pid);
        if(idx<0){
            idx=ArraySize(g_pos); ArrayResize(g_pos,idx+1);
            g_pos[idx].id=pid; g_pos[idx].symbol=sym;
            g_pos[idx].side=""; g_pos[idx].strategy=cmt;
            g_pos[idx].volume=g_pos[idx].profit=g_pos[idx].commission=0;
            g_pos[idx].swap=g_pos[idx].net=g_pos[idx].rr=0;
            g_pos[idx].open_price=g_pos[idx].mae_usd=g_pos[idx].mfe_usd=0;
            g_pos[idx].open_t=g_pos[idx].close_t=dt;
            g_pos[idx].closed=false;
        }
        g_pos[idx].profit+=prf;
        g_pos[idx].commission+=com;
        g_pos[idx].swap+=swp;

        if(entry==DEAL_ENTRY_IN){
            g_pos[idx].open_t=dt;
            g_pos[idx].volume+=vol;
            if(g_pos[idx].open_price<=0)
                g_pos[idx].open_price=HistoryDealGetDouble(tk,DEAL_PRICE);
            if(g_pos[idx].side=="")
                g_pos[idx].side=(type==DEAL_TYPE_BUY?"LONG":"SHORT");
            if(g_pos[idx].strategy=="") g_pos[idx].strategy=cmt;
        } else if(entry==DEAL_ENTRY_OUT||entry==DEAL_ENTRY_INOUT){
            g_pos[idx].close_t=dt;
            g_pos[idx].closed=true;
        }
        g_pos[idx].net=g_pos[idx].profit+g_pos[idx].commission+g_pos[idx].swap;
    }

    // โหลด Open Positions (ที่เปิดอยู่ตอนนี้)
    int op=PositionsTotal();
    for(int i=0;i<op;i++){
        ulong pt=PositionGetTicket(i); if(!pt) continue;
        if(!PositionSelectByTicket(pt)) continue;
        long magic=PositionGetInteger(POSITION_MAGIC);
        string sym=PositionGetString(POSITION_SYMBOL);
        if(InpMagicFilter!=0 && magic!=InpMagicFilter) continue;
        if(!SymOK(sym)) continue;
        long pid=PositionGetInteger(POSITION_IDENTIFIER);
        if(FindPos(pid)>=0) continue; // มีอยู่แล้ว
        int idx=ArraySize(g_pos); ArrayResize(g_pos,idx+1);
        g_pos[idx].id=pid; g_pos[idx].symbol=sym;
        g_pos[idx].side=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"LONG":"SHORT");
        g_pos[idx].strategy=PositionGetString(POSITION_COMMENT);
        g_pos[idx].volume=PositionGetDouble(POSITION_VOLUME);
        g_pos[idx].profit=PositionGetDouble(POSITION_PROFIT);
        g_pos[idx].commission=0;
        g_pos[idx].swap=PositionGetDouble(POSITION_SWAP);
        g_pos[idx].net=g_pos[idx].profit+g_pos[idx].swap;
        g_pos[idx].rr=0;
        g_pos[idx].open_t=(datetime)PositionGetInteger(POSITION_TIME);
        g_pos[idx].close_t=0;
        g_pos[idx].closed=false;
    }

    if(g_init_bal<=0) g_init_bal=g_bal_now;
}

int  FindPos(long id){int n=ArraySize(g_pos);for(int i=0;i<n;i++)if(g_pos[i].id==id)return i;return -1;}
bool SymOK(string s){
    if(InpSymbolFilter==""||StringCompare(InpSymbolFilter,"ALL",false)==0) return true;
    string p[];int n=StringSplit(InpSymbolFilter,(ushort)',',p);
    for(int i=0;i<n;i++){StringTrimLeft(p[i]);StringTrimRight(p[i]);
        if(p[i]!=""&&StringFind(s,p[i])>=0)return true;}
    return false;
}

//========================= [FIX 1] BALANCE AT TIME ================
// คำนวณ balance จริง ณ เวลา t โดยรวม net ของทุก closed trade ก่อน t
double BalanceAt(datetime t) {
    double bal=g_init_bal;
    int n=ArraySize(g_pos);
    int idxs[];long ts[];
    for(int i=0;i<n;i++){
        if(!g_pos[i].closed) continue;
        if(g_pos[i].close_t>=t) continue;  // เฉพาะ close ก่อน t
        int m=ArraySize(idxs); ArrayResize(idxs,m+1); ArrayResize(ts,m+1);
        idxs[m]=i; ts[m]=(long)g_pos[i].close_t;
    }
    SortAsc(idxs,ts);
    int m=ArraySize(idxs);
    for(int k=0;k<m;k++) bal+=g_pos[idxs[k]].net;
    return bal;
}

//========================= CALC STATS =============================
void CalcStats(datetime from, datetime to, Stats &s) {
    // Reset
    s.rr_sum=s.net=s.pct=s.gross_profit=s.gross_loss=0;
    s.profit_factor=s.recovery_factor=s.win_rate=0;
    s.max_dd=s.max_dd_pct=s.lots=s.commission=s.swap=s.avg_dur=0;
    s.total=s.wins=s.losses=s.be=s.open_c=0;
    s.max_cw=s.max_cl=0; s.avg_win=s.avg_loss=0;

    // [FIX 1] balance จริง ณ ต้นช่วง period
    s.period_start_bal = BalanceAt(from);
    if(s.period_start_bal<=0) s.period_start_bal=g_init_bal;

    // เก็บ closed trades ในช่วง period แล้ว sort
    int n=ArraySize(g_pos);
    int idxs[];long ts[];
    for(int i=0;i<n;i++){
        if(!g_pos[i].closed){
            // [FIX 5] open trade: นับถ้า open_t <= to (เปิดก่อนสิ้นสุด period)
            if(g_pos[i].open_t<=to) s.open_c++;
            continue;
        }
        if(g_pos[i].close_t<from || g_pos[i].close_t>to) continue;
        int m=ArraySize(idxs); ArrayResize(idxs,m+1); ArrayResize(ts,m+1);
        idxs[m]=i; ts[m]=(long)g_pos[i].close_t;
    }
    SortAsc(idxs,ts);

    long total_dur=0; int dur_cnt=0;
    // [FIX 2] เริ่ม peak/run จาก period_start_bal
    double peak=s.period_start_bal, run=s.period_start_bal;

    int cnt=ArraySize(idxs);
    int cur_cw=0,cur_cl=0;   // Module 4: current streak counters
    for(int k=0;k<cnt;k++){
        int i=idxs[k];
        s.total++;
        s.rr_sum   +=g_pos[i].rr;
        s.net      +=g_pos[i].net;
        s.lots     +=g_pos[i].volume;
        s.commission+=g_pos[i].commission;
        s.swap     +=g_pos[i].swap;

        if(g_pos[i].net > InpBEThreshold){
            s.wins++;
            s.gross_profit+=g_pos[i].net;
            s.avg_win+=g_pos[i].net;
            // Module 4: streak
            cur_cw++; cur_cl=0;
            if(cur_cw>s.max_cw) s.max_cw=cur_cw;
        } else if(g_pos[i].net < -InpBEThreshold){
            s.losses++;
            s.gross_loss+=MathAbs(g_pos[i].net);
            s.avg_loss+=MathAbs(g_pos[i].net);
            // Module 4: streak
            cur_cl++; cur_cw=0;
            if(cur_cl>s.max_cl) s.max_cl=cur_cl;
        } else {
            s.be++;
            cur_cw=0; cur_cl=0; // BE resets streak
        }

        if(g_pos[i].close_t>=g_pos[i].open_t){
            total_dur+=(long)(g_pos[i].close_t-g_pos[i].open_t);
            dur_cnt++;
        }

        run+=g_pos[i].net;
        if(run>peak) peak=run;
        double dd=peak-run;
        // FIX: ใช้ (startBal + peak) เป็น denominator
        // เพื่อให้ DD% สะท้อนมูลค่า account จริง ณ จุด high water mark
        double hwm=s.period_start_bal+peak;  // High Water Mark (absolute $)
        double ddp=(hwm>0.01?100.0*dd/hwm:0);
        if(dd>s.max_dd)   s.max_dd=dd;
        if(ddp>s.max_dd_pct) s.max_dd_pct=ddp;
    }
    // Module 4: compute averages
    if(s.wins>0)   s.avg_win  /= s.wins;
    if(s.losses>0) s.avg_loss /= s.losses;

    // Derived metrics
    if(s.gross_loss>0)
        s.profit_factor=s.gross_profit/s.gross_loss;
    else if(s.gross_profit>0)
        s.profit_factor=999.0;
    else
        s.profit_factor=0;

    if(s.max_dd>0)
        s.recovery_factor=s.net/s.max_dd;

    int decided=s.wins+s.losses;
    s.win_rate=(decided>0?100.0*s.wins/decided:0);

    // [FIX 3] % profit vs period-start balance
    s.pct=(s.period_start_bal>0?100.0*s.net/s.period_start_bal:0);

    s.avg_dur=(dur_cnt>0?(double)total_dur/dur_cnt:0);
}

void SortAsc(int &idx[],long &ts[]){
    int m=ArraySize(idx);
    for(int i=1;i<m;i++){
        long kt=ts[i];int ki=idx[i];int j=i-1;
        while(j>=0&&ts[j]>kt){ts[j+1]=ts[j];idx[j+1]=idx[j];j--;}
        ts[j+1]=kt;idx[j+1]=ki;}}

//========================= BUILD SERIES ===========================
// [FIX 6] ใช้ period_start_bal เป็น anchor ของ balance chart
void BuildSeries(datetime from,datetime to,double start_bal,
                 string &bj,string &rj){
    int n=ArraySize(g_pos);
    int idxs[];long ts[];
    for(int i=0;i<n;i++){
        if(!g_pos[i].closed) continue;
        if(g_pos[i].close_t<from||g_pos[i].close_t>to) continue;
        int m=ArraySize(idxs); ArrayResize(idxs,m+1); ArrayResize(ts,m+1);
        idxs[m]=i; ts[m]=(long)g_pos[i].close_t;
    }
    SortAsc(idxs,ts);

    // anchor point = balance จริงต้นช่วง period
    string b="[{\"t\":"+(string)(long)from
              +",\"v\":"+DoubleToString(start_bal,2)+"}";
    string r="[";
    bool first=true;
    double run_b=start_bal, run_r=0;
    int cnt=ArraySize(idxs);
    for(int k=0;k<cnt;k++){
        int p=idxs[k];
        run_b+=g_pos[p].net;
        run_r+=g_pos[p].rr;
        b+=",{\"t\":"+(string)ts[k]+",\"v\":"+DoubleToString(run_b,2)+"}";
        if(!first) r+=","; first=false;
        r+="{\"t\":"+(string)ts[k]
          +",\"rr\":"+DoubleToString(g_pos[p].rr,2)
          +",\"cum\":"+DoubleToString(run_r,2)
          +",\"sym\":\""+JE(g_pos[p].symbol)+"\"}";
    }
    bj=b+"]"; rj=r+"]";
}

//========================= MONTHLY JSON ===========================
string BuildMonthlyJSON(){
    int n=ArraySize(g_pos);
    int years[];
    double rr_g[],pf_g[],gp_g[],gl_g[];
    int    win_g[],cnt_g[];

    for(int i=0;i<n;i++){
        if(!g_pos[i].closed) continue;
        MqlDateTime d; TimeToStruct(g_pos[i].close_t,d);
        int y=d.year, mo=d.mon-1;
        int yi=-1;
        for(int j=0;j<ArraySize(years);j++) if(years[j]==y){yi=j;break;}
        if(yi<0){
            yi=ArraySize(years); ArrayResize(years,yi+1);
            ArrayResize(rr_g,(yi+1)*12); ArrayResize(pf_g,(yi+1)*12);
            ArrayResize(gp_g,(yi+1)*12); ArrayResize(gl_g,(yi+1)*12);
            ArrayResize(win_g,(yi+1)*12); ArrayResize(cnt_g,(yi+1)*12);
            for(int k=0;k<12;k++){
                rr_g[yi*12+k]=pf_g[yi*12+k]=gp_g[yi*12+k]=gl_g[yi*12+k]=0;
                win_g[yi*12+k]=cnt_g[yi*12+k]=0;
            }
            years[yi]=y;
        }
        rr_g[yi*12+mo]+=g_pos[i].rr;
        pf_g[yi*12+mo]+=g_pos[i].net;
        cnt_g[yi*12+mo]++;
        // [FIX 4] ใช้ threshold เดียวกับ CalcStats
        if(g_pos[i].net>InpBEThreshold){
            win_g[yi*12+mo]++;
            gp_g[yi*12+mo]+=g_pos[i].net;
        } else if(g_pos[i].net<-InpBEThreshold){
            gl_g[yi*12+mo]+=MathAbs(g_pos[i].net);
        }
    }

    // Sort years desc
    int yc=ArraySize(years);
    for(int i=1;i<yc;i++){
        int ky=years[i];
        double krr[12],kpf[12],kgp[12],kgl[12]; int kw[12],kc[12];
        for(int k=0;k<12;k++){
            krr[k]=rr_g[i*12+k]; kpf[k]=pf_g[i*12+k];
            kgp[k]=gp_g[i*12+k]; kgl[k]=gl_g[i*12+k];
            kw[k]=win_g[i*12+k]; kc[k]=cnt_g[i*12+k];
        }
        int j=i-1;
        while(j>=0&&years[j]<ky){
            years[j+1]=years[j];
            for(int k=0;k<12;k++){
                rr_g[(j+1)*12+k]=rr_g[j*12+k]; pf_g[(j+1)*12+k]=pf_g[j*12+k];
                gp_g[(j+1)*12+k]=gp_g[j*12+k]; gl_g[(j+1)*12+k]=gl_g[j*12+k];
                win_g[(j+1)*12+k]=win_g[j*12+k]; cnt_g[(j+1)*12+k]=cnt_g[j*12+k];
            }
            j--;
        }
        years[j+1]=ky;
        for(int k=0;k<12;k++){
            rr_g[(j+1)*12+k]=krr[k]; pf_g[(j+1)*12+k]=kpf[k];
            gp_g[(j+1)*12+k]=kgp[k]; gl_g[(j+1)*12+k]=kgl[k];
            win_g[(j+1)*12+k]=kw[k]; cnt_g[(j+1)*12+k]=kc[k];
        }
    }

    string s="[";
    for(int i=0;i<yc;i++){
        if(i>0) s+=",";
        s+="{\"year\":"+(string)years[i]+",\"months\":[";
        double yr=0,yp=0,ygp=0,ygl=0; int yw=0,yc2=0;
        for(int mo=0;mo<12;mo++){
            if(mo>0) s+=",";
            int  c2=cnt_g[i*12+mo];
            double rr2=rr_g[i*12+mo], pf2=pf_g[i*12+mo];
            double gp2=gp_g[i*12+mo], gl2=gl_g[i*12+mo];
            int   w=win_g[i*12+mo];
            double wr=(c2>0?100.0*w/c2:0);
            double pfr=(gl2>0?gp2/gl2:(gp2>0?999.0:0));
            s+="{\"rr\":"+DoubleToString(rr2,2)+",\"pf\":"+DoubleToString(pf2,2)
              +",\"gp\":"+DoubleToString(gp2,2)+",\"gl\":"+DoubleToString(gl2,2)
              +",\"wr\":"+DoubleToString(wr,2)+",\"pfr\":"+DoubleToString(pfr,2)
              +",\"cnt\":"+(string)c2+"}";
            yr+=rr2; yp+=pf2; ygp+=gp2; ygl+=gl2; yw+=w; yc2+=c2;
        }
        double ywr=(yc2>0?100.0*yw/yc2:0);
        double ypfr=(ygl>0?ygp/ygl:(ygp>0?999.0:0));
        s+="],\"total\":{\"rr\":"+DoubleToString(yr,2)
          +",\"pf\":"+DoubleToString(yp,2)
          +",\"gp\":"+DoubleToString(ygp,2)
          +",\"gl\":"+DoubleToString(ygl,2)
          +",\"wr\":"+DoubleToString(ywr,2)
          +",\"pfr\":"+DoubleToString(ypfr,2)
          +",\"cnt\":"+(string)yc2+"}}";
    }
    return s+"]";
}

//========================= TRADES JSON ============================
string BuildTradesJSON(bool only_open,datetime from,datetime to){
    int n=ArraySize(g_pos);
    int idxs[];long ts[];
    for(int i=0;i<n;i++){
        if(only_open  &&  g_pos[i].closed) continue;
        if(!only_open && !g_pos[i].closed) continue;
        if(!only_open){
            if(from>0 && g_pos[i].close_t<from) continue;
            if(to>0   && g_pos[i].close_t>to)   continue;
        }
        int m=ArraySize(idxs); ArrayResize(idxs,m+1); ArrayResize(ts,m+1);
        idxs[m]=i;
        ts[m]=(long)(g_pos[i].closed?g_pos[i].close_t:g_pos[i].open_t);
    }
    // Sort desc
    int m=ArraySize(idxs);
    for(int i=1;i<m;i++){
        long kt=ts[i];int ki=idxs[i];int j=i-1;
        while(j>=0&&ts[j]<kt){ts[j+1]=ts[j];idxs[j+1]=idxs[j];j--;}
        ts[j+1]=kt;idxs[j+1]=ki;
    }
    int cap=MathMin(m,150);
    string s="[";
    for(int k=0;k<cap;k++){
        int i=idxs[k]; if(k>0) s+=",";
        s+="{\"id\":"+(string)g_pos[i].id
          +",\"sym\":\""+JE(g_pos[i].symbol)+"\""
          +",\"side\":\""+g_pos[i].side+"\""
          +",\"strat\":\""+JE(g_pos[i].strategy)+"\""
          +",\"vol\":"+DoubleToString(g_pos[i].volume,2)
          +",\"net\":"+DoubleToString(g_pos[i].net,2)
          +",\"rr\":"+DoubleToString(g_pos[i].rr,2)
          +",\"com\":"+DoubleToString(g_pos[i].commission,2)
          +",\"swp\":"+DoubleToString(g_pos[i].swap,2)
          +",\"ot\":"+(string)(long)g_pos[i].open_t
          +",\"ct\":"+(string)(long)g_pos[i].close_t
          +",\"cl\":"+(g_pos[i].closed?"true":"false")+"}";
    }
    return s+"]";
}

string JE(string s){
    string r="";int n=StringLen(s);
    for(int i=0;i<n;i++){
        ushort c=StringGetCharacter(s,i);
        if(c=='"')r+="\\\"";else if(c=='\\')r+="\\\\";
        else if(c=='\n')r+="\\n";else if(c=='\r')r+="\\r";
        else if(c<32)continue;else r+=ShortToString(c);}
    return r;
}

string SJ(const Stats &s){
    return "{\"label\":\""+JE(s.label)+"\""
      +",\"rr\":"+DoubleToString(s.rr_sum,2)
      +",\"net\":"+DoubleToString(s.net,2)
      +",\"pct\":"+DoubleToString(s.pct,2)
      +",\"gp\":"+DoubleToString(s.gross_profit,2)
      +",\"gl\":"+DoubleToString(s.gross_loss,2)
      +",\"pf\":"+DoubleToString(s.profit_factor,2)
      +",\"rf\":"+DoubleToString(s.recovery_factor,2)
      +",\"wr\":"+DoubleToString(s.win_rate,2)
      +",\"maxdd\":"+DoubleToString(s.max_dd,2)
      +",\"maxddp\":"+DoubleToString(s.max_dd_pct,2)
      +",\"lots\":"+DoubleToString(s.lots,2)
      +",\"comm\":"+DoubleToString(s.commission,2)
      +",\"swap\":"+DoubleToString(s.swap,2)
      +",\"avgdur\":"+DoubleToString(s.avg_dur,0)
      +",\"startBal\":"+DoubleToString(s.period_start_bal,2)
      +",\"total\":"+(string)s.total
      +",\"wins\":"+(string)s.wins
      +",\"losses\":"+(string)s.losses
      +",\"be\":"+(string)s.be
      +",\"open\":"+(string)s.open_c+"}";
}


//========================= ANALYTICS: SIDE (BUY vs SELL) ==========
// Session time ranges (UTC+7 / server time — ปรับตามโบรกเกอร์)
// Asian:  00:00–08:00
// London: 08:00–17:00
// New York: 13:00–22:00 (overlap กับ London 13:00–17:00)

string BuildSideJSON(){
    // สะสม stats แยก BUY / SELL จาก closedTrades ทั้งหมด
    int    b_total=0,b_wins=0,s_total=0,s_wins=0;
    double b_gp=0,b_gl=0,b_rr=0,s_gp=0,s_gl=0,s_rr=0;

    int n=ArraySize(g_pos);
    for(int i=0;i<n;i++){
        if(!g_pos[i].closed) continue;
        bool is_buy=(g_pos[i].side=="LONG");
        double net=g_pos[i].net;

        if(is_buy){
            b_total++;
            b_rr+=g_pos[i].rr;
            if(net>InpBEThreshold){b_wins++;b_gp+=net;}
            else if(net<-InpBEThreshold){b_gl+=MathAbs(net);}
        } else {
            s_total++;
            s_rr+=g_pos[i].rr;
            if(net>InpBEThreshold){s_wins++;s_gp+=net;}
            else if(net<-InpBEThreshold){s_gl+=MathAbs(net);}
        }
    }

    double b_wr  =(b_total>0?100.0*b_wins/b_total:0);
    double s_wr  =(s_total>0?100.0*s_wins/s_total:0);
    double b_pf  =(b_gl>0?b_gp/b_gl:(b_gp>0?999:0));
    double s_pf  =(s_gl>0?s_gp/s_gl:(s_gp>0?999:0));
    double b_net =b_gp-b_gl;
    double s_net =s_gp-s_gl;
    double b_avgrr=(b_total>0?b_rr/b_total:0);
    double s_avgrr=(s_total>0?s_rr/s_total:0);

    string sd="{";
    sd += "\"bTotal\":"   + (string)b_total;
    sd += ",\"sTotal\":"  + (string)s_total;
    sd += ",\"bWins\":"   + (string)b_wins;
    sd += ",\"sWins\":"   + (string)s_wins;
    sd += ",\"bWR\":"     + DoubleToString(b_wr,1);
    sd += ",\"sWR\":"     + DoubleToString(s_wr,1);
    sd += ",\"bPF\":"     + DoubleToString(b_pf,2);
    sd += ",\"sPF\":"     + DoubleToString(s_pf,2);
    sd += ",\"bNet\":"    + DoubleToString(b_net,2);
    sd += ",\"sNet\":"    + DoubleToString(s_net,2);
    sd += ",\"bGP\":"     + DoubleToString(b_gp,2);
    sd += ",\"sGP\":"     + DoubleToString(s_gp,2);
    sd += ",\"bGL\":"     + DoubleToString(b_gl,2);
    sd += ",\"sGL\":"     + DoubleToString(s_gl,2);
    sd += ",\"bAvgRR\":" + DoubleToString(b_avgrr,2);
    sd += ",\"sAvgRR\":" + DoubleToString(s_avgrr,2);
    sd += "}";
    return sd;
}

//========================= ANALYTICS: SESSION =====================
struct SessionStats {
    int    total, wins;
    double gp, gl, rr_sum;
};

int GetSessionIdx(datetime t){
    // คืน index: 0=Asian 1=London 2=NewYork 3=OutOfSession
    MqlDateTime d; TimeToStruct(t,d);
    int h=d.hour;
    // ปรับ offset ได้ตรงนี้ (ค่า default = UTC+7)
    // Asian 00-08, London 08-17, NY 13-22 (overlap หลาย session → นับ session แรกที่ตรง)
    if(h>=0  && h<8)  return 0; // Asian
    if(h>=8  && h<13) return 1; // London only
    if(h>=13 && h<17) return 2; // London+NY overlap → นับ NY
    if(h>=17 && h<22) return 2; // NY only
    return 3; // Out of session (22:00-24:00)
}

string BuildSessionJSON(){
    // local arrays สำหรับ 4 sessions
    int n=ArraySize(g_pos);
    int  tot[4]={0,0,0,0}, wins[4]={0,0,0,0};
    double gp[4]={0,0,0,0}, gl[4]={0,0,0,0}, rr[4]={0,0,0,0};

    for(int i=0;i<n;i++){
        if(!g_pos[i].closed) continue;
        int idx=GetSessionIdx(g_pos[i].open_t); // ใช้ open_t
        double net=g_pos[i].net;
        tot[idx]++;
        rr[idx]+=g_pos[i].rr;
        if(net>InpBEThreshold){wins[idx]++;gp[idx]+=net;}
        else if(net<-InpBEThreshold){gl[idx]+=MathAbs(net);}
    }

    string snames[4]={"Asian","London","NewYork","OutOfSession"};
    string r="[";
    for(int i=0;i<4;i++){
        double wr =(tot[i]>0?100.0*wins[i]/tot[i]:0);
        double pf =(gl[i]>0?gp[i]/gl[i]:(gp[i]>0?999:0));
        double net=gp[i]-gl[i];
        double avgrr=(tot[i]>0?rr[i]/tot[i]:0);
        if(i>0) r+=",";
        string se="{";
        se += "\"name\":\""   + snames[i] + "\"";
        se += ",\"total\":"  + (string)tot[i];
        se += ",\"wins\":"   + (string)wins[i];
        se += ",\"wr\":"     + DoubleToString(wr,1);
        se += ",\"pf\":"     + DoubleToString(pf,2);
        se += ",\"net\":"    + DoubleToString(net,2);
        se += ",\"gp\":"     + DoubleToString(gp[i],2);
        se += ",\"gl\":"     + DoubleToString(gl[i],2);
        se += ",\"avgrr\":" + DoubleToString(avgrr,2);
        se += "}";
        r += se;
    }
    return r+"]";
}











string GetRankImages1(){
    string r="";
    r+="var RANK_IMG={en:{},th:{}};\n";
    r+="RANK_IMG.en[\"SUPREME\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.th[\"SUPREME\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.en[\"MARSHAL\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.th[\"MARSHAL\"]=\"data:image/png;base64,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";
    r+="\";\n";
    return r;
}

string GetRankImages2(){
    string r="";
    r+="RANK_IMG.en[\"GENERAL\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.th[\"GENERAL\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.en[\"COLONEL\"]=\"data:image/png;base64,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";
    r+="\";\n";
    return r;
}

string GetRankImages3(){
    string r="";
    r+="RANK_IMG.th[\"COLONEL\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.en[\"MAJOR\"]=\"data:image/png;base64,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";
    r+="\";\n";
    r+="RANK_IMG.th[\"MAJOR\"]=\"data:image/png;base64,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";
    r+="\";\n";
    return r;
}

string GetRankImages4(){
    string r="";
    r+="RANK_IMG.en[\"PRIVATE\"]=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIwAAACMCAYAAACuwEE+AAAksElEQVR42u2deXhcV333zzl3nVWakTyjfbFsrbYsS5bkTZYdx9hxnMgUslEIhWwEl5LyPm1IFxpowwuGLH1paelTyksaEkIgCQQnjuMktmzLu2Vr37eZ0ez7zJ252znvH6MJquM4fYG2kXw/z+NH0j13Gd/7nd92lguAhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhobGUgMuoN0JDQ2N369lAQAAi8VqtdsLChZv08iAtFvwGxeEEEIQQtjZuX37ts4dOwAAACGEsntodwoAWrsFABBCCAAAqKqqAgDAth07dvi8Ph+EEGa3ZfbQuOEtDMMwjNlsNptMJhPHcVxl5cqVaxrWrOE5nq8or6zkeZ3OYDAYTCazmWVZVrMwN/o3BiG0c+euXbt27d5dUlZSUlBYUCArqkoIAH/zjSeekGRJ8nq83sH+vr433njtNUmSJAghzFqlGw3qRheMqqrq+PjYWCgYDicTqZTX6/FQFEWlRUmanpqaGh4cGuq9ePHiO28fOZJIJhI3+v1atoLJBqkfXlOBkBCMHU6HAwIIbfaCgpGRkZHpqakpRZbl0dGRkbNne3okSRSvd57F11nOAfKyjGEYhmUJIQQhhMgC1wt5KYqiACAk37ZiRVllZeXcrMMRj8fjBUVFRStsNpuiyHL2XNcLnBdfk2U5ThPMErEqZWXl5Xv27N2LMcYmk8m0evXq1RlRfIBbwhhDCGFlVVXV2Z6eHp9nft7v9XgmxsbGCgoKCmiGYTDG+HpxUGVlVVVOTm4uxhjv2bN3b9Wq1asznwmhDzpmKVqiZRn0Tk6Ojz/44MMPb2hta0sJgvDmm2+8oaqqeq1gNbtthc1uDwdCoZ6T3d0Ox8wsJgR73PPz7Zu2bCkuKi6enZ2Z+aDjMcaYpmj6vvsfekhv1Ovzrfn5/+srjzyStT3vc10IIbyQrtM0TSuKomgxzP+IhUEIAEKamzdsqGtYsybXYrWeOnHixOnTp059UGaT/ZZzLM+Pjo6MeH1uNwGAQAhhLB6Nzs3OziIEYTKZTF7PsgVDgYCO1+nWN2/YkBRSqWQiHnc6HQ6EICIEEAAAoCiKwhhjQghpXr+++ZN33X3X8NDAoChePz7SXNJ/kTsiBGOD3mCoqamrGxkeHu4+3t1d17BmTV5efj4hhFzroWRFFAoHg9FYOJzdJ7t/UojHvT6v9/rXJcRisVob17e09Jzq6RkZGhpataq62mQ0mTAmOOsOVVVVi4uLir/9ne9+95nv/+Cf/f5AIBqNRT8sPvpI3edlF5RBhDDBuL1t82a/z+s151osLMMwFy+dO5f9di9+0Nd6+O/btqCga+2XSY0gbGpqaQEQgEDA7y8rKSs71XPiRMb9ZKrFNE3Rn/2jz3/uvi88/HAyJYrvvnX06A/+8ZlngsFgcCnVdZZdDIMJxjTNMLMz09Men9ud+VZkUt7FD+VaD+i32UYIIQACcKn3/PnstrSQSjEMwyiqoqiqqq5rbFz36F/99V+taW5pmZ2ene272Ns7NTEyEgwGgxAhRK4TUGuC+e8oximK4vG53Yvdy9WWpbCwsDARjycEQRAABAAQAAjIRhv/0QbDjOYAIAAYDHqD0Wgyzrvd89lzLT43AAD4Al5vNl75zL333vuVRx97DLIc53K4XJfOnTvHsQxz4vixY+Aqy6XFMP+FEcv1WgnI1EMQgghBiCiEKIQgyoqHphnmjw8c+OO0rCoqxqqqYlXFWMWYYEyu+ocJVjF5bx9JBfjAFx8+gCiKIoQQCABEaOEacOF6FEWpqqo+9thjj33jWwcPYkRRkUAgcPH0mTM6lmWvXDx73uVyuZZS7LLELUwmIL3ezb5W3aSosKiovnplvc8f9NXU1tTsXL+qs8BqKMg1G3JNOtZk4BkDx9IchRCFAEQqxqooKWIiLSXiSSkejMSCoZQcWl29enXNyvLq4uLi4sGxqWH3vMsFrjJNf/P4449//uEvftEfCIVEIZk89taRIxgDYDYw3KFDhw4t1WowvbTsCoQsy3GEEJIt1b8vSAUAEgBIW0NVW2VJfqWJZ015ZkOezcjYkNmOcouqcl0D510Mb9Dfc9P6e2g5SSdFJSmIipBOS+l4PBVXVFUhgBAKURRLQ9bC0pYiu7HIUGI0EH0uQZyeu3tbw90V6zZV+B2TfjE0L3qiaU8smYqNzrpHb73n/ls/c/+DD/pD4bCYFoQ3XnvttVg0Ht/Y3tjyD3//vX+IxROxrBXKBumaYP5L7AohoiiKf/iH997785de+KkoSaLBYDAIgiC8J5yFeOTB/VsfrLZy1Q5/xJEUpKTbH3Y7vbJz57rOnRdd3RfbWNj27Ijy5rsn+y/ocm02AilKxYTQNMcByCAMCYEAAEVMpykkQQQTWIz6fDd3trV9ehO8u9cl9VbvKKmeOH5iokyXLmspt7ZgWcD3feHAfWXtu2vj8UQilYjHf/Xzl1+moIr37Nyw8/jxE8dHxqdHs8W6bVs7O6/0Xb4cjUWjGTf70XdPS0YwCCFUWFhUVFpaVtbSsmFDXX1dncvpdJ440d09ONjff7W1UaSU8uzR8WdfGRB7EYXQ9k1r147MTU9vU2Fn4aqGqpHRybHdN63fnqdLGN8eQT6zkeMURVUZhmUpmqIIAIBgQsRUKsVwLJsQJOn2Nsua9o4N7aOjk2OldetrFYDU45PC8OrV5cJb/3byX7/5Vwe+tLpj31oxnU4TOZU+887hd2vLcqqa11U3n7nQf+bgk/90sLmltXVbx9ateSvy8z0en6/75PHj16oIa0Hv71yUI4RleX59U0tLMBgIyJKi9PZevjww0NdHrpH+UhBSGHHYaCsvN+bY7aWlJSW37+nsPN596tTWtsbm4ZHJyWIrXXxLR/ktUloQVEVRCAFAlDH2B+PxgD8cFoR0GkJCVEVRlLQg7NlStMfESqbRsenp9ub6NW+/093ddUtnp8Ws1z/x9a9+9ZGvfOURq5Ez5PKqzjN62tlSndfStq6y7dzFwXOPPPrEIwQQcvnyxYuirKrmHKsVQoRuuunmmw0Go1Gr9P6eXRGEEE5PT0ycOnXyZH9ff//szMwMx9F0plj3/puNCcEQYKjIslyQz/MnT1+4sKF5zbpUWhSDoWBwRb7FcvLs4Ml1tdZ1BRaKkhQAIKIoRolEHthf1vpvB3d8pbYIoUgsnZYVACpsNF1Xbqw7furKcdsKi8Xr9XhlSVFWVdjLdm5r2/ynX7rvAUKSRIj5kod++fIhx7zPIWFWOnVx/NQjX33ikWz5f/Pmjg6KZphDhw4dmpmemQmFQqGllC0tmb4kQjLDEMpLy8uHhgcHx8dGR20rbDbXvNOZHXe7kHBDAADYt7l+33xAmB/0o0jbmrKy9Wuqqs6e7710y+7tN/WcOne6osRWxskerraIrmV5TnnzXHBklUUUv/XFVX9x561Vd6r+KXXv1sLd0VB87PRA2PHIHWUft6KY1ROUPXyOnRsYGBloWle3pryirPz2rttvl+SUHAoEgz994ec/nXL4pxSox3Mu7+zjf/fdxwVBEBCEiOM4LicnN/dE97FjEACgqopy/vzZs5IkikvlOSypzkcIIfR4PZ5YLBpNConEzOz09NWxy3uC2VS/z+lLOB1poxwKRSKf2Ld1eyotptxOp6u6pnL1xUsDl/Zuzttr0lGmhkpjw/nR+DEhHAzes4m6B9I0PHUldqqjeUVH0BsMhhPqyEN77Q+yHMPSCNJvnZk/WlFZVN7U3Ny0cUvHZllW5XA4HH7ppVdecnvCPos1z6rKafnJp555MhaPxxBCCBOCFUVRPJ75+VRKEIJBvx9jVU0kltYoviVVuMMYY0WR5cWj2xZbl6tM0numSc8zzPd+8PyzTWtr1ur0Bp1jzumoKzfUOjxJh05P6YRYTPi7B6r/DNIIjc8mxuOOmfg9t5TdMzAVHzjX5z7313fm/6WYSIhCNC6Mjc6NleSR4vUb2prXt25qF0RFDkUikZdf/uXLHm/Qb87NzaWAAp566umnItFoBCGEFteEsp9dVVXV6XQ4FvdvaRbmf6YGDAEAYG977d75YGp+KMgk1q7Ky9u1rbn1l6+9/WZ9TXm1kJIFK/JY999UsX9+2jEf9EWDBTqpwB1W54cmgkONFXwjT4m8bz7gUyRF4aU4H48JcZqm6OrKnOqcsvacxq23bJYkUUylUqk3Dh36tcft91msVmtBDpvX/bMfdl8Yc1y4WizLgeU7zYQQgDHGep5hhiaCwUAoGvr8vZ/41PTc/HQ8EoxbDIzF73T6EYVQOBANx+PxeDCBg78eYIc8Ydnz4lueF7/4984/5RjEhcKJkCpjVUoJkpOsc9Zsu6M9nRaEZDKROPzr117z+0Kh8rLiYp3BaHz933/4ej6r5kOY6Utabrd1+QmGvPeDYAAxJoTwep7v7unr+/nLr79SWVZUabZYzTOexEw8lo5HAtEIxApkjUbWGWWjIm02K7ROOTWmnOqL2O3dU1z3+nUl651OrzOS2xlZ1XlPi5hKJIREMtn99jvviKIklZeXltIUpJ/83rPPihiJK1dVrCREVeFyHD4Clq+JeS8dT6UEYV19RUXHlg2bvb6gV0gkBJOBM0GKgvFoMh4KJUMIK+jmVku73ZBO166y1O5Yw+3Io0Ohm1pW3OR0+p2W9XdZWm/97FYxFY/LYlK4fOHMWUQhZLfb7ViV5Ge+/5NnPaFksrBgRSEkeNnOGli2E9neG6hAMKYQQu9cmJnxByKRNbXlq/Q6i35oKjhkY/02q56ypkQ5NTPumdm1csWubX9Suq13NN1blEMX/eM96E+scNoqVt4m3nHXgTsdLrcLKJI8NnhlEEEI9QaDQZHS4vd+8NMXAlFJKiwqLpZkQSKEWraT3NDysysZoRCMSSZTyow5oBmeBxBChqYYo4E3FpSWFYx7qXGeZfk8izHP5Y67Lp4dv8ihNFdo1xfa8nibmAiJc9SmuS1dn+1AIA2xklamR66My6Is6fU6fckKQ8Gxw6+/6/bHYoUlpaUYIAQIAIRAolmYJWdhMMlYGQgJUVWaYtlJVySi5+fGV1iMeXq9Th+H+fEzY84z9QWGeoIxcbgFx+mT06crSnMq+hzuvtzGT+Ruvf2z26VkJA1VnvidIz5rrs5atdJeFQpEQwcPfv9g32TQVVBSWYkohoFQUQgBZDkGu8s+hiEYEwIywyezs4ASIkK9Q04nBQFl1PNG3mDmHVKRY9ijDs9H8LzFzFlUSVVHR+dHddW369bu+lRrWogKspSQE4GxxJpa+5rOras6TRwxvfDDf3uhb9zvoM1FRQhBKEuSBCFCBBBCMNEszFJDxUTNZkwQLHRe0hBSjNV66MTY5eoiztCxcV2HnkN6T4jxRIRwxKCGDHLELX/sjns/tvm2P9zCgBQNCYYex5THoOcMeg7pHdNhx7Pf+rtnq/XJaqWtUDk2DuYxBgCBjFWBhEBCsCaYpUbGLWT6sTNRDISEAEAAhEhntXrj6fSho2ffuP3mpn1BJRk06VlTIqAkbvrE52+yN32sanx6fpoiaRJ0TQWK7NailAxS0Vgo+vaPn367PCdd3rppTWuXju+yHZr74c8upC/r9DyPgKp+wMhgzSV9VMnWPrCqLoyBwhgs6s0mhBCagjCm6HRzUY6LOIciX75V/+VNq5VNHTdt6TBVtJXEk7GYLxAKneq5dHo+rHhkyMhCMiX84nvf/oXfMeMXMCu4nT43IBjcf3vl/R1Vsl1IKwpE2e4KrGY/jGZhlgiyosgk26GUtS4kIx5CAGApAIjOaHzltOPI7MTcbOP6+sa7P2W7+8pc/xVXoDARmJ+ZIYhhOI7nJEmVHv/bf3x8YtI7h4z2fHk4LeewCeVTHeIdn9tf/bnta3Tbj4+nfwJYg+E31k1zSUvGxAACgCQpEkNBhuDMUMtFaTcgAABMAOAZCOdiCG3YeHPOpw/s+fTxn/34eE2xWhMN5QxNp6qJ3WYycSzF/sU3/ul/944GAsXlDQ0cy/NiOpGQIMN865D7taK8qaLGensjg9JAxIRQkFCSrEiaS1pSigFAFBUxz8Tl0RQABCCUmTUC3psHhCAAXl8weOetra0/fOqeZ8w8Ntc01tT09bn7DO7zhvW6CyuJGE3887/+7IUrIy5XWWlpqZ7X6ymEEAIQmniathWXl790KvZSPBiKE0jTFAVAnoHNi6fEOFimPmnZxjBxQYpbDbQ1V4eQignBqixDCADAhCAEgNcXCOy7ac2a7z350HcxBbHH6fKo6Ziqsmb1woR6gZkfYBzHfug4P+hylZSWlCCaYRYvNCOrhBgYjHNz9Lk8DfgCoySZWUJyjUxuLJmOLf4smmA++gYGxNJSDGAZ5DKSBBbmJ0JACM1QlNfj99+6Y+3af3jqgYM0R9Nhjy/smxn0XegZuEBkkdRvaKx/4rj+iZcuw8OlxQUFDKvXE5zpl4IAAIQglGRV3VwYyPvyrblfri43V99Wk9itV8JhrMo4mhSjmktaYvijCT+EAEYjkUiBEQAJQ8gwLBsKR6Mf62ho+D9PfPqbLAtY/8yIf7b37dnR/slRHQN1OSvsOd//9fw/jfggUfU2G8vrdBhnhfibghxCEI7Oy6O+iOgbnQqMDnrowXBSUaAqw1BSDGlB75IxMBAiBJA7mHCbOMoUSkhSjiWVKsszGgenfL6dm+rq/vKRu/44Ek1FPFPDnumLR6Ydc36HQccaeGsh//QrjqcvTcRixcWFhQyr1xMAIQGy/B/mUAMAZBWAikKu4uJQ6OKIQxgpyDcUxJKyaGBogycseDTBLBFUnKmBzPnjcxArsMDMsFN+SSoxer27N1dXP/TgXZ8OJeSQc2LE6Tr3iistqekcsyHHYi+yfPvF8W+fHQmFSkuKihjOYMgMjwAAZJPyhb8xAcDAU9TbE4w7j4KjBXlFOScvBacqrDSnyKLijgrubM1Hc0kf1f/IwmT7prrSpsOvffOwPsesd3jDjmq7vtoXjMVspeXlD973qXsjgpp2To45h999cTiWkGIcz3H5hYX5T/5i6slT/X5vgd1qpTm9PiuW7LqYmYKcogBCCEIQpiWMKwpyckqKbbZpvyQpyGisyKUq/NGUPyYqsYUUXhPMRz07WmHRr9j9sZLd33ls93dcgZTLzsTt21oqKw88/Nk/8sTklHd2bGbu5PNzBKtEp2N0peUlpc+8MvPMsUseV2lJURHN6nSAYIyuym8IyfRDEwCAKGFcnANALptOD0wFAjIGgIGyXGmlKsdckbFM2g6XZXy4bAaBEwIIQhBNzgUmJ3v6Jr/26Nav8aY83h1k3H9w30MfDyZkKTw/PR06+5OgjiE6nUGnq6gsr3j61dmnj15wz5aVFBYyOpOJqIpCIE0TgBCFFsJcoqoYq6qCIWQZilqZT1FKWhBGXYIAIEVhAkC+TpY3F8O2X12Y/VUkLUcgzCwKoAnmIy4aioLUlanQFXM6bb73c+vu1dtK9QPjsT5K9InR3pcjPCXzeqNBX1JWXPLa+dBrZ/s9w2ZLXh5gTSYIARBSimJmJYlDihIWEGJphERJUQDBuNjC8wV6WXZ6I5FZvyhyPMchQIggyvK2ClQLxAh4o9/9BsnojGgWZkmoBgBEIerd8653SpFYur3ZsD0RcCew8zImikRonqfLygvLnjseeu7f3xg7WV6Ym1thN5t1DIRpSVUrrIryxIH6r96+NX/n+LjnRDgJVLuZogqMGItpQZj0CEIiRQhLI0QhhGQVYz1Mp/dWMzuOXp49OhsWZhGESBPMUollIISAAMJyNHvfZ/fcN355cpxPBXmTRWea9UuzpaX20pfPxl9+8ejkhbz8nJxYEsJYUlUpqChlpjT793+27pmWjTUtxQWm4vZSob2/39UdSOCoK5BKBeIAMBTLZlbmVVWGpul4SpK2VcCqHBDP+dkFx88UTBSwjFleK4ED8N6ac7e1NN526dTkJQaIjGNwzFFpDFfe3J5388un/C//39eGTxbarVaO0+loBkJA0/RsCGN/VPDbcxX7QO/EwJljF89Y2Yg1mkhHJ9yiiAFF6ViahgudmwhBmJYxtutlub2Ean+rf/6ttILTy9m6LDvBAAgBggDdsbXljs61FZ3O6bDz+Z+PPO+KQde/vDD1LwVUqOBLdxR8aUtLcXFCzKydmyn5E0JBAErzmFITJZimRmanZkdmZo0gaVxpZ1bSFIQILlZBJukW04Kwp4bZNucOzp2bDZ+DECz71+IsG5eUXTJjX1vjvn3tDfuGxyaH47FY3BWWXc/3Bp4fcKYHQFQB6yvh+jt32j4ZC8cmB514noIQsgzDJFOKsncdai3JBSU/OUl+4vBIDk4VuJSopHqm0CjP0jQhGUkgCEAkLggdlVRxfU6q/scnpn4cSsmh5ZoZLYZeHmKBCGOM97Y27t2xduWOvv7hvkRSSDi8YUdfINGXVpV0GgPxUH/skJCaFmptA7V6IVePUCkFSeZlWgxFyCqLvOpXJyK/4hTE2fOh/UgfPtJaprTqKKQoKk0jSAhNUVQoLkkNdsJtLyXbXzk998psJDWLIESYEAyWOUteMAhChDHBjRXFjRurCjcGve6gPxj2e0Nx71AoORRIiYHsBP0rnuiVshWGMrOl2Hx0ljqaFGVdDp+xTBTEWEimhEgwFWlYwTRU2kHlqCSOEhURAAnBGGOGoahIMp2uzJHkP6hj7j49NHe6eyrUDSGAN4JYlrxLygaY+UZ9/mc6mz+TiEYSk3PuyXBcCF/xxa/4BNGXcSKAQAAggYBM+pOTZXn6sj1rLHt8CWnIEcWynmMYlRByflI82blS2dJSAVpooNDeiOo9eBR/R6TMZgoBEEmm06stMvhkHfzkwMT8wEu97pcwIBjcQC/zW5KCgTCzmHL2W/2ZjqbPCLGo4PIGXJFEOnLBHbkQEqVQViyLsyiVEHXAGR2wMsC6q868SwHQNxEQQwzDMIQ1m4+Nij06IKqzQTL71HH6xwprs9EIwngymWwvxvm3rYa3XR5zX36x1/2ihLGUXeb1RhHMkh4RZsvV2e7/5Pb7HX0zjkQ8nvDFkr5eb6xXUFThgx5kdjsEAO6qte3as654z0SCnTgyoZ5LKDzPczqdmIpGiaqqrCEnR5IkyUCl07uq0IbVJmn1O/2udw6PBA6rhKg3mliWnGAysQgEZiNv/tZjn/hWTXleDR2Zo88cHznz7JG5Zyfi6Ym0qqY/7EEubm+wmxq61hd1GXPMxpMOcLLPCwMY6fUEEILUZLKpANi3lKAtqXg09cve+V/2eeJ9V5/jRmJJBb0IIaSqWL17R8Xdd99ccXfu+p25h7/5l4fjoVB8VpRm06qavtoNXYvsg4YQwEFvfHDuncm5nTX5O7etXrFtfYEu3jMX71EJxFvL4MdyUTr37Ijv7NujwbcjohLJnv9GFMvSy5IWamKUIlGXfvGLS9Kvfy1RcYE6O6+cjafkOI0g/f9TmicEEAQBiktK/NV+z6sX5yIXt1fnbd9dlrcbUQiNOIIjz48Enp+JpGbey8hukGxoGbkkAGxm3vbnuwv/3KIkLPMKP//0O76nQ0kxtGA6yG9xEyCAv1lTpsqqr4IQwImgMPHedcnyHBB145hGCtEr7caV6APe2vq7CPLDtmkswbT6fRbi93x+TSg3gHA0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NG5YILh+f9B1236XYyGAEGhdFhoay9SyLPQ0G3SUwWykzFf3PC8M84QrrPSKa7VBCKDJQJlMBsp07fbMsQuzuN93bI6JztHrkH659ngvv/clEUAIAWRjE7dxTwe/J/v34nYAAHjgDsMDLEOxV7cRAsi2Vm7b9nZu+7WO5RjEPXCH4YHF51p87J6t3J5N67hNVx+7XFhWqzdwLOKMemQ0GihjdTlTTVOQDkZxEEIIGQoxBh0y0Ayi11Yza3kO8RwDuUicRPQ80iNEIR0PdWYjZa4qZaoYGjKBMA5QFKQoRFEGHTTQDKLX1bLrWBqyNA2ouADiep7SUxSkeA7x1lzKWl7ElLMMYn0h1ccyiAUAAlUlqiaYj6AbWmGlVjx0l/mh3Fw6t3dI7J12ytMb1+s2fnyn/uMTs8pEWyPXdkun/pZAWA28fTr9drGdKr5tp+E2ex5lD0ZI8Av3mL5gNFLG8/3p8y6v6trSot+yb4d+3/iMMr6jnd+xrV23zetXve+eTb9bWUpX7r/ZuF/PA30yRZIPf8r8MMsi9nRv+nQwgoNbW/Vb92zV7xmekoaTKZzUxu58BLMiAADIMVI5XTsNXRSFKAAgvG2H4bZMzJGhvZFvb67nmgEAYM1qfk1Hi64ju+ihxUxZunbquzJ/Q9h1k77LmkNZs393tPAdDau5BgAAaG7gmtsa+bbseW15tO22HfrbAICQpii6a6exy2ykzIs/23Jg2Sy7SkBmBkA0oUYliUh7O3R7ZQxkigKUP6T4EQIIY4BdPsW1tYXfWrCCLjAboPl8v3QeAEIoBKhwTA2rKlD3dupvAQAATAgORdUQhQClYqC6/di9YQ27obyIKjcbkfnEhfQJAABACCBfUPFRFEft6dDvZmjISBKWYgk1lr2uFvR+BN0SJgBbcihLcwPTPDojjw6NS0O1K+naimKmIvPQINzSwm0BAIDz/eJ5USJiRyvbASGAKgZqYT5T2FjLNI5MyiPDk/Lw2hp2beEKplDFQIUQwI4NbEdaIunz/eJ5CMDCuSDEGOCKEqaidiVTOzghDY5NS2PrG9j1FjNlwRhgzR19hNHzSG/Q0YbfBMIUZzIwpoyoELLmMtasCwIAgLwcJi/7QA162qDjKV22TcdROqOeNmYFac1hrIslas1lrWBh1oLJwJg4luKyrQYdbdDxSLcMXf/yrcdcnfpe3fZh7b/vYzU+4mK5VsD5vikqHzBlBS7w2xx7rbb3f0aouan/HjHARS8Whu89XIQyrmHxtqt/Zve5+lzXe3jXut4HHf9B51t8Dk0s/xOROrr+bMcPE8Li7dnfKYqiFouC53k+Jycn51rXoyiK+s9YisX7XU1+fn7+9dq1tPr3AEVR1IEDBw5Eo9FoPB6Ph8PhcE1NTY2iKMqFCxcuFBQUFGzevHnzq6+++qrNZrMdPnz48Pbt27fPzc3N+f1+/9e//vWvP/roo4+uXr169Z49e/aYTCZTd3d3d1VVVVUqlUqJoii+/vrrr6dSqVRXV1fX7Ozs7JYtW7b4/X6/2+12UxRFlZWVlUWj0ejs7Oys2Ww2Hzly5EhnZ2dnIpFI7N27d+/IyMiI3+/319fX14dCodD4+Pi41Wq1Hj169OjBgwcPfu1rX/taa2trK8/zPE3T9Ouvv/46QggtlReLLqm0muM4zm63248cOXKkrq6ubvv27dtHR0dHp6enp1taWlrOnz9/PpFIJK5cuXJly5YtW3ie5zdv3rzZ7Xa729ra2uLxeHzDhg0bhoeHh3t6enqcTqfz2LFjx6qrq6uHhoaG+vv7+wVBEKqqqqo4juMCgUAAIYTOnj17trGxsbG6urra7Xa7h4aGhgYHBwc3bty4ked5vqOjo6O/v7/f6/V6e3t7ewsLCwvD4XB4aGhoaHJycrK+vr5+7dq1aysqKirq6+vrm5qamrq7u7urq6urTSaTaSm9hXZJCUZRFMVoNBp37ty589ixY8eGh4eHa2pqapqamprGx8fHk8lkMh6Px1VVVS9evHjxvvvuu29mZmYmazFGRkZG9u/fv58QQmRZlkVRFAkhRFVV1Wg0GnU6nQ4AAGw2my0ej8dlWZbz8vLyWltbW71erzcajUYNBoPBaDQaE4lE4vLly5ez15AkSRIEQYjFYjFZlmWO4zij0WhMpVIpn8/n279///6nn3766V27du1KL0AIIRaLxbKU4polJRiapumJiYmJ55577rlTp06dIoSQN998880f/ehHPyouLi5ubm5ubmhoaLDZbLZjx44d6+rq6jp+/Pjx2tra2vHx8fGBgYGBUCgUstlstmQymcx+sxVFUSiKooxGo5FlWdbpdDpzc3NzaZqmz5w5c+a55557jluAEEJomqbz8/PzT548ebKrq6vr5MmTJ41Go7Gpqampvb29fbELNZvNZrfb7W5qamrq6enpqaurq4tEIhEAANDpdLpgMBjMpOFLY0HoJbY+DIQGg8EgCIIAAAAsy7J4AZqmaYvFYuF5nvf7/f5EIpGwWq3WUCgUMhgMhmQymcyKjqIoSlEUheM4ThAEwWaz2fLz8/NVVVWnpqamZFmW77zzzjt7e3t7XS6XS5IkiWEYhqZpuqioqIiiKGpubm5u8TU4juOKioqKZFmWw+FwuLi4uJimadrhcDiSyWTSYrFYgsFg0Gq1WpPJZLKurq6uoKCg4PDhw4eXUgyz7NPvxab+w7KrqwNso9Fo/M9kW7+NO8lmYBr/TUK41u9XF9uu9SCv1X6tY6+3z3/mM3zQfloNRuN3Fr6GhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhsZvw/8DN2hR/Svxip4AAAAASUVORK5CYII=";
    r+="\";\n";
    r+="RANK_IMG.th[\"PRIVATE\"]=\"data:image/png;base64,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";
    r+="\";\n";
    return r;
}

string GetRankImages(){
    string r="<script>\n";
    r+=GetRankImages1();
    r+=GetRankImages2();
    r+=GetRankImages3();
    r+=GetRankImages4();
    r+="</script>\n";
    return r;
}
string GetBody(){return
"<div class='hdr'>"
"<div class='logo'>TRADING<em>.</em>JOURNAL<span style='font-size:10px;color:var(--dm);font-family:var(--fm);letter-spacing:2px;margin-left:10px'>v13</span></div>"
"<div class='hbtns'>"
"<button class='hb on' id='bToday'    data-p='today'    onclick='sw(this)'>Today</button>"
"<button class='hb' id='bWeek'     data-p='week'     onclick='sw(this)'>This Week</button>"
"<button class='hb' id='bLastWeek' data-p='lastweek' onclick='sw(this)'>Last Week</button>"
"<button class='hb' id='bMonth'    data-p='month'    onclick='sw(this)'>Monthly</button>"
"<button class='hb' id='bAll'      data-p='all'      onclick='sw(this)'>All Time</button>"
"<button class='hb hb-custom' id='bCustom' onclick='openCustom()'>Custom</button>"
"</div>"
"<div style='display:flex;align-items:center;gap:8px'>"
"<button class='lbtn on' id='lEN' onclick='setLang(\"en\")'>EN</button>"
"<button class='lbtn' id='lTH' onclick='setLang(\"th\")'>TH</button>"
"<div class='dot'></div><span class='upd' id='upd'></span>"
"</div></div>"
"<div id='cpModal' style='display:none;position:fixed;inset:0;background:rgba(0,0,0,.8);z-index:999;align-items:center;justify-content:center'>"
"  <div style='background:var(--panel);border:1px solid var(--teal);border-radius:18px;padding:28px 32px;min-width:340px'>"
"    <div id='cpTitle' style='font-family:var(--fd);font-size:22px;font-weight:700;color:var(--tx);margin-bottom:18px'>CUSTOM PERIOD</div>"
"    <div style='display:grid;gap:14px'>"
"      <div><label id='cpLblFrom' style='font-size:9px;text-transform:uppercase;letter-spacing:1.5px;color:var(--dm);display:block;margin-bottom:5px'>FROM</label>"
"      <input id='cpFrom' type='date' style='width:100%;background:var(--p2);color:var(--tx);border:1px solid var(--line2);border-radius:8px;padding:9px 12px;font-family:var(--fm);font-size:13px;outline:none'></div>"
"      <div><label id='cpLblTo' style='font-size:9px;text-transform:uppercase;letter-spacing:1.5px;color:var(--dm);display:block;margin-bottom:5px'>TO</label>"
"      <input id='cpTo' type='date' style='width:100%;background:var(--p2);color:var(--tx);border:1px solid var(--line2);border-radius:8px;padding:9px 12px;font-family:var(--fm);font-size:13px;outline:none'></div>"
"      <div style='display:flex;gap:10px;margin-top:4px'>"
"        <button id='cpBtnApply' onclick='applyCustom()' style='flex:1;background:var(--teal);color:#0d1117;border:none;border-radius:8px;padding:11px;font-weight:700;font-size:13px;cursor:pointer'>Apply</button>"
"        <button id='cpBtnCancel' onclick='closeCustom()' style='flex:1;background:var(--p2);color:var(--d2);border:1px solid var(--line2);border-radius:8px;padding:11px;font-size:13px;cursor:pointer'>Cancel</button>"
"      </div></div></div></div>"
"<div id='cpBadge' style='display:none;padding:6px 24px;background:var(--tealg);border-bottom:1px solid var(--teal);font-size:10px;color:var(--teal)'></div>"
"<div class='tabs'>"
"<button class='tab-btn on' id='tabDash' onclick='switchTab(\"dash\")'>Dashboard</button>"
"<button class='tab-btn' id='tabAna' onclick='switchTab(\"ana\")'>Analytics</button>"
"</div>"
"<div id='paneDash' class='tab-pane on'>"
"<div class='main-wrap'>"
"<div id='ibox'></div>"
"<div id='pr'></div>"
"<div class='hero'>"
"<div class='rank-card' id='grid-panel'></div>"
"<div class='chart-card'>"
"<div class='chart-header'>"
"<div><div class='chart-title' id='ctBAL'>PORTFOLIO GROWTH</div>"
"<div style='font-size:9px;color:var(--dm);margin-top:3px' id='stl'>Period Stats</div></div>"
"<div class='hero-kpi'>"
"<div class='hkpi'><div class='hkpi-val pos' id='heroNet'>\342\200\224</div><div class='hkpi-lbl'>NET P&amp;L</div></div>"
"<div class='hkpi'><div class='hkpi-val' id='heroPct'>\342\200\224</div><div class='hkpi-lbl'>RETURN</div></div>"
"</div></div>"
"<div class='cb'><canvas id='bc'></canvas></div>"
"<div class='hero-metrics' id='heroMetrics'></div>"
"</div></div>"
"<div class='stats-section'>"
"<div class='section-label'>KEY METRICS</div>"
"<div class='sg' id='sg'></div>"
"</div>"
"<div class='dim-grid' id='dimGrid'></div>"
"<div class='tactical-section' id='tacticalNotes' style='display:none'>"
"<div class='tactical-label' id='tacticalLabel'>TACTICAL ASSESSMENT</div>"
"<div class='tactical-text' id='tacticalText'></div>"
"</div>"
"<div style='display:grid;grid-template-columns:220px 1fr 240px;gap:16px'>"
"<div id='streaks-panel'></div>"
"<div style='display:flex;flex-direction:column;gap:12px'>"
"<div style='display:grid;grid-template-columns:1fr 1fr;gap:12px'>"
"<div class='chc'><div class='ctt' id='ctDOW'>P&L by Day</div><div class='cb'><canvas id='dc'></canvas></div></div>"
"<div class='chc'><div class='ctt' id='ctHOUR'>P&L by Hour</div><div class='cb'><canvas id='hc'></canvas></div></div>"
"</div>"
"<div class='chc'><div class='ctt' id='ctPNL'>P&amp;L PER TRADE</div><div class='cb'><canvas id='rc'></canvas></div></div>"
"</div>"
"<div id='maemfe-panel'></div>"
"</div>"
"<div class='monthly-card'>"
"<div class='mh'><span class='tt' id='mTitle'>Monthly Stats</span>"
"<div class='mts'>"
"<button class='mt2 on' id='mt0' data-m='pf'>Profit $</button>"
"<button class='mt2' id='mt1' data-m='wr'>Win %</button>"
"<button class='mt2' id='mt2b' data-m='pfr'>P.Factor</button>"
"<button class='mt2' id='mt3' data-m='gross'>Gross P&amp;L</button>"
"</div></div>"
"<div style='overflow-x:auto'><table class='mtb' id='mt'></table></div>"
"</div>"
"<div style='display:grid;grid-template-columns:240px 1fr;gap:16px'>"
"<div class='acct-card'><div class='ct' id='accTitle'>Account</div><div class='al' id='al'></div></div>"
"<div class='tcards'>"
"<div class='tts'>"
"<button class='tt2' id='ttOpen' data-tv='open' onclick='stv(this)'>OPEN</button>"
"<button class='tt2 on' id='ttClosed' data-tv='closed' onclick='stv(this)'>CLOSED</button>"
"</div>"
"<div class='tl' id='tl'></div>"
"</div></div>"
"</div></div>"
"<div id='paneAna' class='tab-pane'>"
"<div class='main-wrap'>"
"<div class='an-section'>"
"<div class='an-hdr'><span class='an-title'>Performance Calendar</span>"
"<div style='display:flex;gap:6px'>"
"<button class='cvb on' id='cvMonth' onclick='calSetView(\"month\")'>Month</button>"
"<button class='cvb' id='cvYear' onclick='calSetView(\"year\")'>Year</button>"
"</div></div>"
"<div style='background:var(--panel);border:1px solid var(--line2);border-radius:14px;overflow:hidden'>"
"<div class='cal-nav'>"
"<div class='cal-nav-btns'><button class='cnb' onclick='calNav(-1)'>&#8249;</button><button class='cnb' onclick='calNav(1)'>&#8250;</button></div>"
"<div class='cal-title' id='calTitle'>June 2025</div>"
"<div style='display:flex;gap:10px;font-size:9px;color:var(--dm)'>"
"<span>Profit</span><span>Loss</span>"
"</div></div>"
"<div id='calBody'></div>"
"</div></div>"
"<div class='an-section'>"
"<div class='an-hdr'><span class='an-title'>Performance by Side</span><span class='an-sub'>All Time</span></div>"
"<div class='side-grid'>"
"<div class='side-card'><div class='side-title'>Total Trades</div><div class='side-donut'><svg class='donut-svg' id='donTrades' viewBox='0 0 80 80' width='80' height='80'></svg><div class='donut-legend' id='legTrades'></div></div><div class='side-stats' id='statTrades'></div></div>"
"<div class='side-card'><div class='side-title'>Win Rate</div><div class='side-donut'><svg class='donut-svg' id='donWR' viewBox='0 0 80 80' width='80' height='80'></svg><div class='donut-legend' id='legWR'></div></div><div class='side-stats' id='statWR'></div></div>"
"<div class='side-card'><div class='side-title'>Net P&L</div><div class='side-donut'><svg class='donut-svg' id='donPNL' viewBox='0 0 80 80' width='80' height='80'></svg><div class='donut-legend' id='legPNL'></div></div><div class='side-stats' id='statPNL'></div></div>"
"<div class='side-card'><div class='side-title'>Avg RR</div><div class='side-donut'><svg class='donut-svg' id='donRR' viewBox='0 0 80 80' width='80' height='80'></svg><div class='donut-legend' id='legRR'></div></div><div class='side-stats' id='statRR'></div></div>"
"</div></div>"
"<div class='an-section'>"
"<div class='an-hdr'><span class='an-title'>Performance by Session</span><span class='an-sub' id='sessNote'>All Time</span></div>"
"<div class='sess-grid' id='sessGrid'></div>"
"</div>"
"</div></div>"
"\n";}

string GetScript(){return
"<script>\n"
"var LANG='en';\n"
"var T={\n"
"  en:{\n"
"    today:'Today',week:'This Week',lastweek:'Last Week',\n"
"    month:'Monthly',all:'All Time',custom:'Custom',\n"
"    netPnl:'Net P&L',startBal:'Starting Balance',pctReturn:'% Return',\n"
"    grossProfit:'Gross Profit',grossLoss:'Gross Loss',\n"
"    profitFactor:'Profit Factor',winRateLbl:'Win Rate',\n"
"    maxDD:'Max Drawdown',totalTrades:'Total Trades',\n"
"    avgDur:'Avg Duration',commission:'Commission',swap:'Swap',\n"
"    streaksTitle:'Risk Profile & Streaks',\n"
"    maxWinStreak:'Max Win Streak',maxLossStreak:'Max Loss Streak',\n"
"    avgWin:'Avg Win',avgLoss:'Avg Loss',\n"
"    rewardRatio:'Reward Ratio',recovFactor:'Recovery Factor',\n"
"    balChart:'Account Balance',pnlChart:'P&L per Trade',\n"
"    dowChart:'P&L by Day of Week',hourChart:'P&L by Hour of Day',\n"
"    monthlyTitle:'Monthly Stats',\n"
"    profitBtn:'Profit $',winPctBtn:'Win %',pfBtn:'P.Factor',grossBtn:'Gross P&L',\n"
"    accTitle:'Account',balLbl:'Account Balance',equityLbl:'Equity',\n"
"    initBalLbl:'Initial Balance',curLbl:'Currency',accLbl:'Account',srvLbl:'Server',loginLbl:'Login',\n"
"    maemfeTitle:'MAE & MFE Analytics',avgMAELbl:'Avg MAE (risk taken)',\n"
"    avgMFELbl:'Avg MFE (peak potential)',tradeEffLbl:'Avg Trade Efficiency',\n"
"    openTab:'OPEN',closedTab:'CLOSED',noTrades:'No trades in this period',\n"
"    lotsLbl:'lots',feeLbl:'Fee',cpFrom:'FROM',cpTo:'TO',\n"
"    cpTitle:'🗓️ CUSTOM PERIOD',cpApply:'Apply',cpCancel:'Cancel',\n"
"    gridCmd:'TACTICAL COMMAND',gridAssess:'📡 TACTICAL ASSESSMENT:',compLbl:'Composite Score / 100',\n"
"    d1n:'Risk-Adjusted',d2n:'Consistency',d3n:'Preservation',d4n:'Execution',\n"
"    expLbl:'Expectancy',pfLbl2:'Profit Factor',sharpeLbl:'Sharpe (approx)',\n"
"    mwrLbl:'Monthly Win Rate',cvLbl:'Coeff. of Variation',ssLbl:'Sample Size',\n"
"    maxDDl:'Max Drawdown',calmarLbl:'Calmar Ratio',mclLbl:'Max Loss Streak',\n"
"    teffLbl:'Trade Efficiency',maerLbl:'MAE/Net Ratio',\n"
"    zP:'Private',zMaj:'Major',zCol:'Colonel',zGen:'General',zMar:'Marshal',zSup:'Supreme',\n"
"    rankSUPREME:'Supreme Commander',rankMARSHAL:'Field Marshal',\n"
"    rankGENERAL:'General',rankCOLONEL:'Colonel',\n"
"    rankMAJOR:'Major',rankPRIVATE:'Private (Under Review)',\n"
"    gridCommand:'TACTICAL COMMAND',calculating:'Calculating...',rankingLbl:'Ranking',\n"
"    breakEvenLbl:'Break Even',winsLbl:'Wins',lossesLbl:'Losses',\n"
"    updated:'Updated',periodStats:'Period Stats',keyMetrics:'Key Metrics'\n"
"  },\n"
"  th:{\n"
"    today:'วันนี้',week:'สัปดาห์นี้',lastweek:'สัปดาห์ก่อน',\n"
"    month:'เดือนนี้',all:'ตลอดกาล',custom:'กำหนดเอง',\n"
"    netPnl:'กำไร/ขาดทุนสุทธิ',startBal:'ยอดเริ่มต้น',pctReturn:'% ผลตอบแทน',\n"
"    grossProfit:'กำไรรวม',grossLoss:'ขาดทุนรวม',\n"
"    profitFactor:'ปัจจัยกำไร',winRateLbl:'อัตราชนะ',\n"
"    maxDD:'ดรอดาวน์สูงสุด',totalTrades:'จำนวนเทรดทั้งหมด',\n"
"    avgDur:'ระยะเวลาเฉลี่ย',commission:'ค่าคอมมิชชัน',swap:'ค่าสวอป',\n"
"    streaksTitle:'สถิติสายชนะ-แพ้',\n"
"    maxWinStreak:'ชนะติดต่อกันสูงสุด',maxLossStreak:'แพ้ติดต่อกันสูงสุด',\n"
"    avgWin:'กำไรเฉลี่ยต่อเทรด',avgLoss:'ขาดทุนเฉลี่ยต่อเทรด',\n"
"    rewardRatio:'อัตราส่วนกำไร:ขาดทุน',recovFactor:'ปัจจัยการฟื้นตัว',\n"
"    balChart:'ยอดคงเหลือบัญชี',pnlChart:'กำไร/ขาดทุนต่อเทรด',\n"
"    dowChart:'กำไรแยกตามวัน',hourChart:'กำไรแยกตามชั่วโมง',\n"
"    monthlyTitle:'สถิติรายเดือน',\n"
"    profitBtn:'กำไร $',winPctBtn:'ชนะ %',pfBtn:'ปัจจัยกำไร',grossBtn:'กำไร-ขาดทุนรวม',\n"
"    accTitle:'ข้อมูลบัญชี',balLbl:'ยอดคงเหลือ',equityLbl:'ทุนปัจจุบัน',\n"
"    initBalLbl:'ทุนเริ่มต้น',curLbl:'สกุลเงิน',accLbl:'ชื่อบัญชี',srvLbl:'เซิร์ฟเวอร์',loginLbl:'เลขบัญชี',\n"
"    maemfeTitle:'วิเคราะห์ MAE & MFE',avgMAELbl:'MAE เฉลี่ย (ความเสี่ยงที่รับ)',\n"
"    avgMFELbl:'MFE เฉลี่ย (จุดสูงสุดที่ทำได้)',tradeEffLbl:'ประสิทธิภาพการเทรดเฉลี่ย',\n"
"    openTab:'กำลังเปิด',closedTab:'ปิดแล้ว',noTrades:'ไม่มีเทรดในช่วงเวลานี้',\n"
"    lotsLbl:'ล็อต',feeLbl:'ค่าธรรมเนียม',cpFrom:'ตั้งแต่',cpTo:'ถึง',\n"
"    cpTitle:'🗓️ กำหนดช่วงเวลาเอง',cpApply:'ยืนยัน',cpCancel:'ยกเลิก',\n"
"    gridCmd:'กองบัญชาการยุทธวิธี',gridAssess:'📡 รายงานการประเมิน:',compLbl:'คะแนนรวม / 100',\n"
"    breakEvenLbl:'ทุน',winsLbl:'ชนะ',lossesLbl:'แพ้',\n"
"    d1n:'ผลตอบแทนปรับความเสี่ยง',d2n:'ความสม่ำเสมอ',d3n:'การรักษาทุน',d4n:'คุณภาพการซื้อขาย',\n"
"    expLbl:'ค่าความคาดหวัง',pfLbl2:'ปัจจัยกำไร',sharpeLbl:'ชาร์ป (ประมาณ)',\n"
"    mwrLbl:'อัตราชนะรายเดือน',cvLbl:'ค่าความแปรปรวนสัมพัทธ์',ssLbl:'จำนวนตัวอย่าง',\n"
"    maxDDl:'ดรอดาวน์สูงสุด',calmarLbl:'อัตราส่วนคาลมาร์',mclLbl:'แพ้ติดต่อกันสูงสุด',\n"
"    teffLbl:'ประสิทธิภาพเทรด',maerLbl:'อัตราส่วน MAE/Net',\n"
"    zP:'ระดับต่ำสุด',zMaj:'ขวัญใจโบรกเกอร์',zCol:'สามล้อถูกหวย',\n"
"    zGen:'เม่าปีกเหล็ก',zMar:'เจ้าพ่อ DUBAI',zSup:'ผู้เห็นอนาคต',\n"
"    rankSUPREME:'ผู้เห็นอนาคต',rankMARSHAL:'เจ้าพ่อ DUBAI',\n"
"    rankGENERAL:'เม่าปีกเหล็ก',rankCOLONEL:'สามล้อถูกหวย',\n"
"    rankMAJOR:'ขวัญใจโบรกเกอร์',rankPRIVATE:'เก็บตังไว้ซื้อหวยเถอะพี่',\n"
"    updated:'อัปเดต',periodStats:'สรุปช่วงเวลา',keyMetrics:'ตัวชี้วัดหลัก'\n"
"  }\n"
"};\n"
"function t(k){var d=T[LANG];return(d&&d[k]!=null?d[k]:(T.en[k]!=null?T.en[k]:k));}\n"
"function setLang(lang){\n"
"  LANG=lang;\n"
"  document.getElementById('lEN').classList.toggle('on',lang==='en');\n"
"  document.getElementById('lTH').classList.toggle('on',lang==='th');\n"
"  if(lang==='th')document.body.classList.add('th-mode');\n"
"  else document.body.classList.remove('th-mode');\n"
"  applyLangStatic();\n"
"  bpc();bsg(AP);updateHero(D[AP]||D.sel);buildStreaks(AP);buildBehaviorGrid(AP);\n"
"  var rng=getRange(AP);buildMaeMfe(rng.from,rng.to);genInsights(AP);bt(rng.from,rng.to);\n"
"}\n"
"function applyLangStatic(){\n"
"  var ids={bToday:'today',bWeek:'week',bLastWeek:'lastweek',bMonth:'month',bAll:'all',bCustom:'custom'};\n"
"  for(var id in ids){var el=document.getElementById(id);if(el)el.textContent=t(ids[id]);}\n"
"  var maps={ctBAL:'balChart',ctPNL:'pnlChart',ctDOW:'dowChart',ctHOUR:'hourChart',\n"
"    mTitle:'monthlyTitle',stl2:'periodStats',accTitle:'accTitle',cpTitle:'cpTitle',\n"
"    cpLblFrom:'cpFrom',cpLblTo:'cpTo',cpBtnApply:'cpApply',cpBtnCancel:'cpCancel'};\n"
"  for(var id in maps){var el=document.getElementById(id);if(el)el.textContent=t(maps[id]);}\n"
"  var mtMap={mt0:'profitBtn',mt1:'winPctBtn',mt2b:'pfBtn',mt3:'grossBtn'};\n"
"  for(var id in mtMap){var el=document.getElementById(id);if(el)el.textContent=t(mtMap[id]);}\n"
"  var ttO=document.getElementById('ttOpen'),ttC=document.getElementById('ttClosed');\n"
"  if(ttO)ttO.textContent=t('openTab');if(ttC)ttC.textContent=t('closedTab');\n"
"  var updEl=document.getElementById('upd');\n"
"  if(updEl){var ts=updEl.textContent.replace(/^[^\\d]*/,'');updEl.textContent=t('updated')+' '+ts;}\n"
"}\n"
"const _ccy=D.meta.ccy||'USD';\n"
"const SYM=(_ccy==='USD'||_ccy.startsWith('US'))?'$':\n"
"  ({'EUR':'€','GBP':'£','JPY':'¥','AUD':'A$','CAD':'C$','SGD':'S$','HKD':'HK$'})[_ccy]||(_ccy+' ');\n"
"const fm=(v,abs)=>{const s=Math.abs(v).toLocaleString('en',{minimumFractionDigits:2,maximumFractionDigits:2});\n"
"return abs?SYM+s:(v<0?'-':'')+SYM+s;};\n"
"const fms=v=>(v>=0?'+':'-')+SYM+Math.abs(v).toLocaleString('en',{minimumFractionDigits:2,maximumFractionDigits:2});\n"
"const fP=v=>(v>=0?'+':'')+v.toFixed(2)+'%';\n"
"const fc=v=>v>0.001?'pos':v<-0.001?'neg':'flat';\n"
"const fd=t=>{const d=new Date(t*1000);\n"
"return d.toLocaleDateString('en',{weekday:'short',day:'numeric',month:'short',year:'numeric'});};\n"
"const fs=t=>new Date(t*1000).toLocaleDateString('en',{day:'numeric',month:'short',year:'2-digit'});\n"
"const fdur=s=>{if(!s||s<=0)return'—';\n"
"const d=Math.floor(s/86400),h=Math.floor((s%86400)/3600),m=Math.floor((s%3600)/60);\n"
"if(d>0)return d+'d '+(h%24)+'h';if(h>0)return h+'h '+m+'m';return m+'m '+(s%60)+'s';};\n"
"const PM={today:D.today,week:D.week,lastweek:D.lastweek||D.week,month:D.month,all:D.all};\n"
"var AP=D.meta.active;\n"
"if(AP==='weekly')AP='week';if(AP==='lastweek')AP='lastweek';if(AP==='monthly')AP='month';if(AP==='alltime')AP='all';\n"
"var _customFrom=0,_customTo=0;\n"
"function getRange(k){\n"
"  if(k==='custom')return{from:_customFrom,to:_customTo};\n"
"  const r=D.meta.ranges&&D.meta.ranges[k];\n"
"  if(r)return{from:r.f,to:r.t};\n"
"  const now=Math.floor(Date.now()/1000);\n"
"  const d=new Date();\n"
"  if(k==='today'){d.setHours(0,0,0,0);return{from:Math.floor(d/1000),to:now};}\n"
"  if(k==='week'){d.setHours(0,0,0,0);const bk=d.getDay()===0?6:d.getDay()-1;\n"
"    return{from:Math.floor(d/1000)-bk*86400,to:now};}\n"
"  if(k==='lastweek'){\n"
"    const e=new Date();e.setHours(0,0,0,0);\n"
"    const bk=e.getDay()===0?6:e.getDay()-1;\n"
"    const startThis=Math.floor(e/1000)-bk*86400;\n"
"    return{from:startThis-7*86400,to:startThis-1};}\n"
"  if(k==='month'){d.setDate(1);d.setHours(0,0,0,0);return{from:Math.floor(d/1000),to:now};}\n"
"  return{from:0,to:now};\n"
"}\n"
"document.getElementById('upd').textContent='Updated '+new Date(D.meta.updated*1000).toLocaleTimeString();\n"

// ── Gauge SVG ──
"function gsv(pct){\n"
"const r=31,cx=34,cy=34,arc=p=>{\n"
"const a=Math.PI-(Math.PI*Math.max(0,Math.min(100,p))/100);\n"
"return`M${cx-r} ${cy} A${r} ${r} 0 0 1 ${(cx+r*Math.cos(a)).toFixed(1)} ${(cy-r*Math.sin(a)).toFixed(1)}`;};\n"
"const p=Math.max(0,Math.min(100,pct||0));\n"
"return`<svg viewBox='0 0 68 42'><path d='${arc(100)}' stroke='#1c2536' stroke-width='5' fill='none' stroke-linecap='round'/>`\n"
"+(p>0?`<path d='${arc(p)}' stroke='${p>=50?'#3b7ff5':'#dc2626'}' stroke-width='5' fill='none' stroke-linecap='round'/>`:'')+'</svg>';\n"
"}\n"

// ── MODULE 1: AI Insights ──
"function genInsights(pk){\n"
"const ps=PM[pk]||{};const wr=ps.wr||0,pf=ps.pf||0,mddp=ps.maxddp||0;\n"
"const maxCL=ps.maxCL||0,avgW=ps.avgWin||0,avgL=ps.avgLoss||0;\n"
"const ratio=avgL>0?avgW/avgL:0;const ins=[];\n"
"if(ps.total===0){document.getElementById('ibox').innerHTML='';return;}\n"
// Win Rate
"if(wr>=65)ins.push({t:'success',i:'🏆',m:`Strong win rate ${wr.toFixed(1)}% — your entries are precise and well-timed.`});\n"
"else if(wr>=50)ins.push({t:'info',i:'📊',m:`Win rate ${wr.toFixed(1)}% is above breakeven — continue refining your entries.`});\n"
"else if(wr>=40)ins.push({t:'warning',i:'⚠️',m:`Win rate ${wr.toFixed(1)}% is below 50% — review your entry criteria and market timing.`});\n"
"else ins.push({t:'danger',i:'🚨',m:`Critical: Win rate ${wr.toFixed(1)}% — significant entry quality issues detected.`});\n"
// Profit Factor
"if(pf>=2.5)ins.push({t:'success',i:'💎',m:`Exceptional profit factor ${pf.toFixed(2)} — excellent risk/reward management.`});\n"
"else if(pf>=1.5)ins.push({t:'success',i:'✅',m:`Healthy profit factor ${pf.toFixed(2)} — system is generating consistent returns.`});\n"
"else if(pf>=1.0)ins.push({t:'warning',i:'📉',m:`Profit factor ${pf.toFixed(2)} is marginally profitable — optimize your exits.`});\n"
"else if(ps.total>0)ins.push({t:'danger',i:'🔴',m:`Profit factor ${pf.toFixed(2)} below 1.0 — this is a losing configuration.`});\n"
// Drawdown
"if(mddp>=20)ins.push({t:'danger',i:'🚨',m:`CRITICAL: Max drawdown ${mddp.toFixed(1)}% exceeds safe limits — reduce position size immediately.`});\n"
"else if(mddp>=10)ins.push({t:'warning',i:'⚠️',m:`Max drawdown ${mddp.toFixed(1)}% is approaching dangerous territory — review risk management.`});\n"
"else if(mddp>0)ins.push({t:'info',i:'🛡️',m:`Drawdown ${mddp.toFixed(1)}% is within acceptable range — capital is well protected.`});\n"
// Win/Loss ratio
"if(ratio>=2)ins.push({t:'success',i:'🚀',m:`Excellent reward ratio ${ratio.toFixed(2)}x (avg win ${fm(avgW,true)} vs avg loss ${fm(avgL,true)}) — letting profits run effectively.`});\n"
"else if(ratio>=1)ins.push({t:'info',i:'📈',m:`Reward ratio ${ratio.toFixed(2)}x (avg win ${fm(avgW,true)} vs avg loss ${fm(avgL,true)}) — profits outpacing losses.`});\n"
"else if(ratio>0&&ratio<1)ins.push({t:'warning',i:'✂️',m:`Avg loss ${fm(avgL,true)} exceeds avg win ${fm(avgW,true)} (ratio ${ratio.toFixed(2)}x) — improve exit strategy or widen profit targets.`});\n"
// Consecutive losses
"if(maxCL>=8)ins.push({t:'danger',i:'⛔',m:`Max consecutive losses: ${maxCL} — implement a circuit breaker rule (stop after ${Math.min(maxCL,5)} losses).`});\n"
"else if(maxCL>=5)ins.push({t:'warning',i:'⚠️',m:`Max loss streak of ${maxCL} consecutive trades — consider a mandatory review after 4 losses.`});\n"
"const el=document.getElementById('ibox');\n"
"el.innerHTML=ins.map(x=>`<div class='insight ${x.t}'><span class='insight-icon'>${x.i}</span><span>${x.m}</span></div>`).join('');\n"
"}\n"

// ── Period cards ──
"function bpc(){\n"
"const D4=[{k:'today',l:'Today'},{k:'week',l:'This Week'},{k:'lastweek',l:'Last Week'},{k:'month',l:'This Month'},{k:'all',l:'All Time'}];\n"
"document.getElementById('pr').innerHTML=D4.map((d,i)=>{\n"
"const p=PM[d.k]||{},net=p.net||0,pct=p.pct||0,wr=p.wr||0;\n"
"const nc=fc(net),ba=net>0.01?'pos':net<-0.01?'neg':'flat';\n"
"const netStr=Math.abs(net).toLocaleString('en',{minimumFractionDigits:2,maximumFractionDigits:2});\n"
"return`<div class='pc${d.k===AP?' on':''}' style='animation-delay:${i*.05}s'>`"
"+`<div class='pch'><span class='tl'>${d.l}</span><span class='pbg ${ba}'>${fP(pct)}</span></div>`"
"+`<div class='prr ${nc}'><span style='font-size:18px;opacity:.7'>${net<0?'-':'+'}</span>`"
"+`<span style='font-size:14px;opacity:.6'>${SYM}</span>${netStr}</div>`"
"+`<div class='ps'><span class='${fc(pct)}'>${fP(pct)} return</span><span class='${nc}'>Win: ${wr.toFixed(1)}%</span></div>`"
"+`<div class='gr'><div class='gw'>${gsv(wr)}<div class='gp'>${wr.toFixed(1)}%</div></div>`"
"+`<div class='cr'>`"
"+`<div class='cr-row'>`"
"+`<span class='cr-lbl'>${t('totalTrades')}</span>`"
"+`<span class='cr-val'>${p.total||0}</span>`"
"+`</div>`"
"+`<div class='cr-row'>`"
"+`<span class='cr-lbl'>${t('breakEvenLbl')}</span>`"
"+`<span class='cr-val'>${p.be||0}</span>`"
"+`</div>`"
"+`<div class='cr-row'>`"
"+`<span class='cr-lbl'>${t('winsLbl')}</span>`"
"+`<span class='cr-val pos'>${p.wins||0}</span>`"
"+`</div>`"
"+`<div class='cr-row'>`"
"+`<span class='cr-lbl'>${t('lossesLbl')}</span>`"
"+`<span class='cr-val neg'>${p.losses||0}</span>`"
"+`</div>`"
"+`</div></div></div>`;\n"
"}).join('');\n"
"}\nbpc();\n"

// ── Stat Grid ──
"function bsg(pk){\n"
"const ps=PM[pk]||{};\n"
"document.getElementById('stl').textContent=(ps.label||'Period')+' — Key Metrics';\n"
"var cells=[\n"
"  {k:t('netPnl'),v:fms(ps.net||0),c:fc(ps.net)},\n"
"  {k:t('startBal'),v:fm(ps.startBal||0,true),c:'dim'},\n"
"  {k:t('pctReturn'),v:fP(ps.pct||0),c:fc(ps.pct)},\n"
"  {k:t('grossProfit'),v:'+'+fm(ps.gp||0,true),c:'pos'},\n"
"  {k:t('grossLoss'),v:'-'+fm(ps.gl||0,true),c:'neg'},\n"
"  {k:t('profitFactor'),v:(ps.pf>=999?'∞':(ps.pf||0).toFixed(2)),c:(ps.pf||0)>=1?'pos':'neg'},\n"
"  {k:t('winRateLbl'),v:(ps.wr||0).toFixed(1)+'%',c:(ps.wr||0)>=50?'pos':'neg'},\n"
"  {k:t('maxDD'),v:fm(ps.maxdd||0,true)+' / '+(ps.maxddp||0).toFixed(1)+'%',c:'neg'},\n"
"  {k:t('totalTrades'),v:(ps.total||0)+' ('+( ps.wins||0)+'W/'+( ps.losses||0)+'L/'+( ps.be||0)+'BE)',c:''},\n"
"  {k:t('avgDur'),v:fdur(ps.avgdur),c:''},\n"
"  {k:t('commission'),v:fm(ps.comm||0),c:'neg'},\n"
"  {k:t('swap'),v:fm(ps.swap||0),c:fc(ps.swap||0)},\n"
"];\n"
"document.getElementById('sg').innerHTML=cells.map(c=>'<div class=\"stat-card\"><div class=\"stat-val '+(c.c||'')+ '\">'+ c.v+'</div><div class=\"stat-lbl\">'+c.k+'</div></div>').join('');\n"
"updateHero(ps);\n"
"}\nbsg(AP);\n"

// ── MODULE 4: Streaks & Risk Profile ──
"function buildStreaks(pk){\n"
"const ps=PM[pk]||{};\n"
"const el=document.getElementById('streaks-panel');\n"
"if(!ps.total){el.innerHTML='';return;}\n"
"const maxCW=ps.maxCW||0,maxCL=ps.maxCL||0;\n"
"const avgW=ps.avgWin||0,avgL=ps.avgLoss||0;\n"
"const ratio=avgL>0?(avgW/avgL):0;\n"
"const rf=ps.rf||0,pf=ps.pf||0;\n"
"var items=[\n"
"  {v:maxCW,  lbl:t('maxWinStreak'),  c:'pos'},\n"
"  {v:maxCL,  lbl:t('maxLossStreak'), c:'neg'},\n"
"  {v:fm(avgW,true), lbl:t('avgWin'), c:'pos'},\n"
"  {v:fm(avgL,true), lbl:t('avgLoss'),c:'neg'},\n"
"  {v:ratio.toFixed(2)+'x', lbl:t('rewardRatio'),  c:fc(ratio-1)},\n"
"  {v:(pf>=999?'∞':pf.toFixed(2)), lbl:t('profitFactor'), c:pf>=1?'pos':'neg'}\n"
"];\n"
"el.innerHTML='<div class=\"sk-title\">'+ t('streaksTitle')+'</div>'\n"
"+ '<div class=\"sk-grid6\">'+items.map(function(x){\n"
"  return '<div class=\"sk-cell6\">'+\n"
"    '<div class=\"sk-v6 '+x.c+'\">'+x.v+'</div>'+\n"
"    '<div class=\"sk-k6\">'+x.lbl+'</div>'+\n"
"    '</div>';\n"
"}).join('')+'</div>';\n"
"}\nbuildStreaks(AP);\n"

// ── Balance + P&L Charts ──
"let BC,RC,DC,HC;\n"
"const CO={responsive:true,maintainAspectRatio:false,\n"
"plugins:{legend:{display:false},tooltip:{backgroundColor:'#0d1219',borderColor:'#1c2536',borderWidth:1}},\n"
"scales:{\n"
"x:{ticks:{color:'#4a5568',maxTicksLimit:7,font:{family:\"'JetBrains Mono',monospace\",size:9}},grid:{color:'rgba(28,37,54,.6)'}},\n"
"y:{ticks:{color:'#4a5568',font:{family:\"'JetBrains Mono',monospace\",size:9}},grid:{color:'rgba(28,37,54,.6)'}}}};\n"
"function bc2(from,to){\n"
"from=from||0;to=to||Math.floor(Date.now()/1000);\n"
"const allBal=D.balSeries||[];let anchorBal=D.meta.initBal||0;\n"
"for(let i=allBal.length-1;i>=0;i--){if(allBal[i].t<=from){anchorBal=allBal[i].v;break;}}\n"
"const bd=[{t:from,v:anchorBal},...allBal.filter(p=>p.t>from&&p.t<=to)];\n"
"const allRR=D.rrSeries||[];const rdRaw=allRR.filter(p=>p.t>=from&&p.t<=to);\n"
"if(BC)BC.destroy();if(RC)RC.destroy();\n"
"const bctx=document.getElementById('bc').getContext('2d');\n"
"const bg=bctx.createLinearGradient(0,0,0,190);\n"
"bg.addColorStop(0,'rgba(59,127,245,.28)');bg.addColorStop(1,'rgba(59,127,245,.01)');\n"
"BC=new Chart(bctx,{type:'line',data:{labels:bd.map(p=>fs(p.t)),\n"
"datasets:[{data:bd.map(p=>p.v),borderColor:'#3b7ff5',backgroundColor:bg,\n"
"borderWidth:2,fill:true,tension:.3,pointRadius:0,pointHoverRadius:4}]},\n"
"options:{...CO,plugins:{...CO.plugins,tooltip:{...CO.plugins.tooltip,\n"
"callbacks:{label:c=>SYM+c.raw.toLocaleString('en',{minimumFractionDigits:2})}}},\n"
"scales:{...CO.scales,y:{...CO.scales.y,ticks:{...CO.scales.y.ticks,\n"
"callback:v=>SYM+v.toLocaleString('en',{minimumFractionDigits:0})}}}}});\n"
"const rctx=document.getElementById('rc').getContext('2d');\n"
"const riskAmt=D.meta.riskAmt||1;\n"
"const pnlData=rdRaw.map(p=>+(p.rr*riskAmt).toFixed(2));\n"
"let cumRun=0;const cumData=pnlData.map(v=>{cumRun+=v;return+cumRun.toFixed(2);});\n"
"const rcolors=pnlData.map(v=>v>=0?'rgba(59,127,245,.85)':'rgba(220,38,38,.85)');\n"
"RC=new Chart(rctx,{data:{labels:rdRaw.map(p=>fs(p.t)),\n"
"datasets:[{type:'bar',label:'P&L/Trade',data:pnlData,backgroundColor:rcolors,borderRadius:3,maxBarThickness:12,order:2},\n"
"{type:'line',label:'Cumulative',data:cumData,borderColor:'#94a3b8',backgroundColor:'transparent',\n"
"borderWidth:1.5,pointRadius:0,tension:.2,order:1}]},\n"
"options:{...CO,plugins:{...CO.plugins,legend:{display:true,position:'bottom',\n"
"labels:{color:'#566878',font:{size:9},boxWidth:8,usePointStyle:true}},\n"
"tooltip:{...CO.plugins.tooltip,callbacks:{label:c=>SYM+c.raw.toLocaleString('en',{minimumFractionDigits:2})}}},\n"
"scales:{...CO.scales,y:{...CO.scales.y,ticks:{...CO.scales.y.ticks,\n"
"callback:v=>SYM+v.toLocaleString('en',{minimumFractionDigits:0})}}}}});\n"
"}\n"
"{const{from,to}=getRange(AP);try{bc2(from,to);}catch(e){console.error('Chart:',e);}}\n"

// ── MODULE 3: Time-Based Edge Analysis (Day + Hour charts) ──
"function calcTimeStats(from,to){\n"
"const trades=(D.closedTrades||[]).filter(t=>t.ct>=from&&t.ct<=to);\n"
"const days=Array(7).fill(null).map(()=>({net:0,wins:0,total:0,losses:0}));\n"
"const hours=Array(24).fill(null).map(()=>({net:0,wins:0,total:0,losses:0}));\n"
"for(const t of trades){\n"
"  const d=new Date(t.ct*1000);\n"
"  const dow=d.getDay(),h=d.getHours();\n"
"  days[dow].net+=t.net;days[dow].total++;\n"
"  if(t.net>0.001){days[dow].wins++;}else if(t.net<-0.001){days[dow].losses++;}\n"
"  hours[h].net+=t.net;hours[h].total++;\n"
"  if(t.net>0.001){hours[h].wins++;}else if(t.net<-0.001){hours[h].losses++;}\n"
"}\n"
"return{days,hours};\n"
"}\n"
"function buildTimeCharts(from,to){\n"
"const{days,hours}=calcTimeStats(from,to);\n"
"const DOW=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];\n"
// Day of week chart (Mon-Fri only — indices 1-5)
"const tradingDays=[1,2,3,4,5];\n"
"const dayLabels=tradingDays.map(i=>DOW[i]);\n"
"const dayNet=tradingDays.map(i=>+days[i].net.toFixed(2));\n"
"const dayColors=dayNet.map(v=>v>=0?'rgba(22,163,74,.75)':'rgba(220,38,38,.75)');\n"
"if(DC)DC.destroy();\n"
"try{\n"
"const dctx=document.getElementById('dc').getContext('2d');\n"
"DC=new Chart(dctx,{type:'bar',data:{labels:dayLabels,\n"
"datasets:[{data:dayNet,backgroundColor:dayColors,borderRadius:4,borderSkipped:false}]},\n"
"options:{...CO,plugins:{...CO.plugins,\n"
"tooltip:{...CO.plugins.tooltip,callbacks:{\n"
"label:c=>{const i=tradingDays[c.dataIndex];return`${SYM}${c.raw.toFixed(2)} (${days[i].wins}W/${days[i].losses}L)`;}}},\n"
"legend:{display:false}},\n"
"scales:{...CO.scales,y:{...CO.scales.y,ticks:{...CO.scales.y.ticks,\n"
"callback:v=>SYM+v.toLocaleString('en',{minimumFractionDigits:0})}}}}});\n"
"}catch(e){}\n"
// Hour chart
"const hourLabels=Array.from({length:24},(_,i)=>i+'h');\n"
"const hourNet=hours.map(h=>+h.net.toFixed(2));\n"
"const hourColors=hourNet.map(v=>v>=0?'rgba(59,127,245,.7)':'rgba(220,38,38,.7)');\n"
"if(HC)HC.destroy();\n"
"try{\n"
"const hctx=document.getElementById('hc').getContext('2d');\n"
"HC=new Chart(hctx,{type:'bar',data:{labels:hourLabels,\n"
"datasets:[{data:hourNet,backgroundColor:hourColors,borderRadius:3,borderSkipped:false}]},\n"
"options:{...CO,plugins:{...CO.plugins,\n"
"tooltip:{...CO.plugins.tooltip,callbacks:{\n"
"label:c=>{const i=c.dataIndex;return`${SYM}${c.raw.toFixed(2)} (${hours[i].wins}W/${hours[i].losses}L)`;}}},\n"
"legend:{display:false}},\n"
"scales:{...CO.scales,x:{...CO.scales.x,ticks:{...CO.scales.x.ticks,maxTicksLimit:12}},\n"
"y:{...CO.scales.y,ticks:{...CO.scales.y.ticks,\n"
"callback:v=>SYM+v.toLocaleString('en',{minimumFractionDigits:0})}}}}});\n"
"}catch(e){}\n"
"}\n"
"{const{from,to}=getRange(AP);buildTimeCharts(from,to);}\n"

// ── Monthly Table ──
"const MO=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];\n"
"let CM='pf';\n"
"function bm(){\n"
"const data=D.monthly||[];\n"
"if(!data.length){document.getElementById('mt').innerHTML='<tr><td colspan=14 class=empty>No data</td></tr>';return;}\n"
"function cell(c){\n"
"if(!c||c.cnt===0)return`<td><span style='color:var(--dm)'>—</span></td>`;\n"
"let v1,c1;\n"
"if(CM==='pf'){v1=fms(c.pf);c1=fc(c.pf);}\n"
"else if(CM==='wr'){v1=c.wr.toFixed(1)+'%';c1=c.wr>=50?'pos':'neg';}\n"
"else if(CM==='pfr'){v1=(c.pfr>=999?'∞':c.pfr.toFixed(2));c1=c.pfr>=1?'pos':'neg';}\n"
"else{const g=c.gp||0,l=c.gl||0;v1=fms(g-l);c1=fc(g-l);}\n"
"return`<td><div class='l1 ${c1}'>${v1}</div>`\n"
"+`<div class='l2 ${fc(c.pf)}'>${fms(c.pf)}</div>`\n"
"+`<div class='l3'>${c.wr.toFixed(0)}% · ${c.cnt}t</div></td>`;}\n"
"const h='<thead><tr><th>Year</th>'+MO.map(m=>'<th>'+m+'</th>').join('')+'<th>Total</th></tr></thead>';\n"
"const rows=data.map(r=>`<tr><td class='yt'>${r.year}</td>`+r.months.map(m=>cell(m)).join('')+cell(r.total)+'</tr>').join('');\n"
"document.getElementById('mt').innerHTML=h+'<tbody>'+rows+'</tbody>';\n"
"}\nbm();\n"
"document.querySelectorAll('.mt2').forEach(b=>b.addEventListener('click',()=>{\n"
"document.querySelectorAll('.mt2').forEach(x=>x.classList.remove('on'));\n"
"b.classList.add('on');CM=b.dataset.m;bm();}));\n"

// ── MODULE 2: MAE & MFE Analytics ──
"function buildMaeMfe(from,to){\n"
"const el=document.getElementById('maemfe-panel');\n"
"const trades=(D.closedTrades||[]).filter(t=>t.ct>=from&&t.ct<=to&&t.cl);\n"
"if(!trades.length){el.innerHTML='';return;}\n"
"const withData=trades.filter(t=>(t.mae||0)+(t.mfe||0)>0);\n"
"if(!withData.length){el.innerHTML=`<div class='mf-title'>MAE &amp; MFE Analytics</div>`\n"
"+`<div style='font-size:10px;color:var(--dm);text-align:center;padding:12px'>Calculating... (refresh to update)</div>`;\n"
"return;}\n"
// คำนวณค่าเฉลี่ย
"let sumMAE=0,sumMFE=0,sumEff=0,effCnt=0;\n"
"for(const t of withData){\n"
"  sumMAE+=t.mae||0;sumMFE+=t.mfe||0;\n"
"  if(t.net>0&&(t.mfe||0)>0){sumEff+=t.net/(t.mfe||1);effCnt++;}\n"
"}\n"
"const n=withData.length;\n"
"const avgMAE=sumMAE/n,avgMFE=sumMFE/n;\n"
"const avgEff=effCnt>0?sumEff/effCnt*100:0;\n"
// แสดง top 10 trades ล่าสุดเป็น visual bar
"const recent=withData.slice(-10);\n"
"const maxVal=Math.max(...recent.map(t=>Math.max(t.mae||0,t.mfe||0,Math.abs(t.net||0))),1);\n"
"const bars=recent.map((t,i)=>{\n"
"  const maePct=Math.round((t.mae||0)/maxVal*60);\n"
"  const mfePct=Math.round((t.mfe||0)/maxVal*60);\n"
"  const netPct=Math.round(Math.abs(t.net||0)/maxVal*60);\n"
"  const nc=t.net>=0?'#16a34a':'#dc2626';\n"
"  return`<div class='mf-bar-group'>`\n"
"    +`<div class='mf-bar-bg'>`\n"
"    +`<div title='MFE: ${fm(t.mfe||0,true)}' style='position:absolute;bottom:0;left:0;width:33%;height:${mfePct}px;background:rgba(22,163,74,.5);border-radius:3px 0 0 3px'></div>`\n"
"    +`<div title='Net: ${fms(t.net)}' style='position:absolute;bottom:0;left:33%;width:34%;height:${netPct}px;background:${nc};border-radius:0'></div>`\n"
"    +`<div title='MAE: ${fm(t.mae||0,true)}' style='position:absolute;bottom:0;left:67%;width:33%;height:${maePct}px;background:rgba(220,38,38,.5);border-radius:0 3px 3px 0'></div>`\n"
"    +`</div><div class='mf-bar-lbl'>${t.sym}</div></div>`;}).join('');\n"
"el.innerHTML=`<div class='mf-title'>${t('maemfeTitle')}</div>`\n"
"+`<div class='mf-row'><span style='color:var(--d2)'>${t('avgMAELbl')}</span><span class='neg'>${fm(avgMAE,true)}</span></div>`\n"
"+`<div class='mf-row'><span style='color:var(--d2)'>${t('avgMFELbl')}</span><span class='pos'>${fm(avgMFE,true)}</span></div>`\n"
"+`<div class='mf-row'><span style='color:var(--d2)'>${t('tradeEffLbl')}</span><span class='${fc(avgEff-40)}'>${avgEff.toFixed(1)}%</span></div>`\n"
"+`<div style='font-size:9px;color:var(--dm);margin:8px 0 4px'>Last ${recent.length} trades — 🟢MFE · ●Net · 🔴MAE</div>`\n"
"+`<div class='mf-bar-wrap'>${bars}</div>`;\n"
"}\n"
"{const{from,to}=getRange(AP);buildMaeMfe(from,to);}\n"

// ── Trade List ──
"var TV='closed';\n"
"var _trFrom=0,_trTo=Math.floor(Date.now()/1000);\n"
"function bt(from,to){\n"
"from=from!==undefined?from:_trFrom;\n"
"to=to!==undefined?to:_trTo;\n"
"_trFrom=from;_trTo=to;\n"
"const allClosed=D.closedTrades||[];const allOpen=D.openTrades||[];\n"
"let arr;\n"
"if(TV==='open'){arr=allOpen;}\n"
"else{arr=allClosed.filter(t=>t.ct>=from&&t.ct<=to);}\n"
"const el=document.getElementById('tl');\n"
"if(!arr.length){el.innerHTML='<div class=empty>'+t('noTrades')+'</div>';return;}\n"
"el.innerHTML=arr.map((t,i)=>{\n"
"const nc=fc(t.net),pctT=(t.net/(D.meta.initBal||1))*100;\n"
"const dl=t.cl?fd(t.ot)+' → '+fd(t.ct):'Opened '+fd(t.ot);\n"
"return`<div class='ti' style='animation-delay:${Math.min(i,10)*.02}s'>`"
"+`<div class='r1'><span class='ts'>${t.sym}</span>`"
"+`<span class='tb ${t.side.toLowerCase()}'>${t.side}</span>`"
"+`<span class='tR ${nc}'>${fms(t.net)}</span></div>`"
"+`<div class='r2'><span>${t.strat||'—'}</span>`"
"+`<span>${t.vol} lots · <span class='${fc(pctT)}'>${fP(pctT)}</span></span></div>`"
"+`<div class='r3'><span>${dl}</span>`"
"+`<span style='color:var(--dm)'>Fee: ${fm((t.com||0)+(t.swp||0))}</span></div></div>`;\n"
"}).join('');\n"
"}\n"
"{const{from,to}=getRange(AP);bt(from,to);}\n"
"function stv(b){document.querySelectorAll('.tt2').forEach(x=>x.classList.remove('on'));\n"
"b.classList.add('on');TV=b.dataset.tv;bt(_trFrom,_trTo);}\n"

// ── Account Info ──
"(function(){const m=D.meta;\n"
"document.getElementById('al').innerHTML=[\n"
"  {k:t('balLbl'),v:fm(m.bal,true),c:'pos'},\n"
"  {k:t('equityLbl'),v:fm(m.equity,true),c:fc(m.equity-m.bal)},\n"
"  {k:t('initBalLbl'),v:fm(m.initBal,true),c:''},\n"
"  {k:t('curLbl'),v:_ccy,c:''},\n"
"  {k:t('accLbl'),v:m.name,c:''},\n"
"  {k:t('srvLbl'),v:m.server,c:''},\n"
"  {k:t('loginLbl'),v:'#'+m.login,c:''},\n"
"].map(r=>`<div class='ar'><span class='k'>${r.k}</span><span class='v ${r.c}'>${r.v}</span></div>`).join('');\n"
"})();\n"

// ── MODULE 1: Run insights initially ──
"genInsights(AP);\n"

// ── Switch Period ── อัพเดททุก module พร้อมกัน ──
"function openCustom(){\n"
  "const m=document.getElementById('cpModal');\n"
  "m.style.display='flex';\n"
  "const today=new Date();const past=new Date(today-30*864e5);\n"
  "document.getElementById('cpFrom').value=past.toISOString().slice(0,10);\n"
  "document.getElementById('cpTo').value=today.toISOString().slice(0,10);\n"
"}\n"
"function closeCustom(){document.getElementById('cpModal').style.display='none';}\n"
"function applyCustom(){\n"
  "const fromStr=document.getElementById('cpFrom').value;\n"
  "const toStr=document.getElementById('cpTo').value;\n"
  "if(!fromStr||!toStr){alert('Please select both dates');return;}\n"
  "const fromD=new Date(fromStr+'T00:00:00');\n"
  "const toD=new Date(toStr+'T23:59:59');\n"
  "if(fromD>toD){alert('From date must be before To date');return;}\n"
  "_customFrom=Math.floor(fromD.getTime()/1000);\n"
  "_customTo=Math.floor(toD.getTime()/1000);\n"
  "closeCustom();\n"
  "AP='custom';\n"
  "document.querySelectorAll('.hb').forEach(b=>b.classList.remove('on'));\n"
  "document.querySelector('.hb-custom').classList.add('on');\n"
  "const{from,to}=getRange('custom');\n"
  "const badge=document.getElementById('cpBadge');\n"
  "badge.style.display='block';\n"
  "badge.innerHTML='<div style=\"display:inline-flex;align-items:center;gap:8px;'+\n"
  "  'background:var(--b2);border:1px solid var(--blue);border-radius:6px;'+\n"
  "  'padding:5px 14px;font-size:11px;font-family:var(--fm)\">'+\n"
  "  '<span style=\"color:var(--d2)\">Custom:</span> '+\n"
  "  '<span style=\"color:var(--text)\">'+fromStr+'</span> '+\n"
  "  '<span style=\"color:var(--dm)\">→</span> '+\n"
  "  '<span style=\"color:var(--text)\">'+toStr+'</span> '+\n"
  "  '<span onclick=\"clearCustom()\" style=\"cursor:pointer;color:var(--dm);margin-left:4px\">✕</span></div>';\n"
  "bpc();bsg('custom');\n"
  "try{bc2(from,to);}catch(e){}\n"
  "bt(from,to);buildTimeCharts(from,to);buildMaeMfe(from,to);genInsights('custom');buildStreaks('custom');\n"
  "document.getElementById('stl').textContent='Custom Period — Key Metrics';\n"
"}\n"
"function clearCustom(){\n"
  "document.getElementById('cpBadge').style.display='none';\n"
  "document.querySelector('.hb-custom').classList.remove('on');\n"
  "AP='today';\n"
  "document.querySelector('[data-p=\"today\"]').classList.add('on');\n"
  "const{from,to}=getRange('today');\n"
  "bpc();bsg('today');try{bc2(from,to);}catch(e){}\n"
  "bt(from,to);buildTimeCharts(from,to);buildMaeMfe(from,to);genInsights('today');buildStreaks('today');\n"
"}\n"
"document.getElementById('cpModal').addEventListener('click',function(e){if(e.target===this)closeCustom();});\n"
"function updateHero(ps){\n"
"  var hn=document.getElementById('heroNet');\n"
"  if(hn){hn.textContent=fms(ps.net||0);hn.className='pf-net-val '+(ps.net>=0?'pos':'neg');}\n"
"  var hm=document.getElementById('heroMetrics');\n"
"  if(hm)hm.innerHTML=\n"
"    '<div class=\"pf-metric\"><div class=\"pf-m-val '+(( ps.wr||0)>=50?'pos':'neg')+'\">'+(ps.wr||0).toFixed(1)+'%</div><div class=\"pf-m-lbl\">Win Rate</div></div>'\n"
"   +'<div class=\"pf-metric\"><div class=\"pf-m-val '+(( ps.pf||0)>=1?'pos':'neg')+ '\">'+( ps.pf>=999?'∞':(ps.pf||0).toFixed(2))+'</div><div class=\"pf-m-lbl\">Profit Factor</div></div>'\n"
"   +'<div class=\"pf-metric\"><div class=\"pf-m-val neg\">'+( ps.maxddp||0).toFixed(1)+'%</div><div class=\"pf-m-lbl\">Max Drawdown</div></div>';\n"
"}\n""function getGrid(pk){\n"
"  var gmap={today:D.gridToday,week:D.gridWeek,lastweek:D.gridLastWeek,\n"
"    month:D.gridMonth,all:D.gridAll,custom:D.gridAll};\n"
"  return gmap[pk]||D.grid;\n"
"}\n"
"function buildBehaviorGrid(pk){\n"
"  pk=pk||AP;\n"
"  const g=getGrid(pk);if(!g||!g.comp){document.getElementById('grid-panel').innerHTML='';return;}\n"
"  const el=document.getElementById('grid-panel');\n"
"  const rankColors={SUPREME:'#f59e0b',MARSHAL:'#94a3b8',GENERAL:'#3b7ff5',COLONEL:'#8b5cf6',MAJOR:'#16a34a',PRIVATE:'#dc2626'};\n"
"  const rc=rankColors[g.code]||'#3b7ff5';\n"
"  const stars='★'.repeat(g.stars)+'☆'.repeat(5-g.stars);\n"
"  const compGrad=g.comp>=90?'linear-gradient(90deg,#f59e0b,#fbbf24)':g.comp>=75?'linear-gradient(90deg,#64748b,#94a3b8)':g.comp>=60?'linear-gradient(90deg,#2563eb,#3b7ff5)':g.comp>=45?'linear-gradient(90deg,#7c3aed,#8b5cf6)':g.comp>=30?'linear-gradient(90deg,#15803d,#16a34a)':'linear-gradient(90deg,#991b1b,#dc2626)';\n"
"  function dimCard(num,name,icon,score,level,metrics){\n"
"    const lc=level.toLowerCase();\n"
"    const bc=level==='ELITE'?'#16a34a':level==='STANDARD'?'#d97706':level==='CAUTION'?'#f59e0b':level==='FAIL'?'#dc2626':'#475569';\n"
"    const rows=metrics.map(m=>'<div class=\"dim-metric\"><span class=\"dm-k\">'+m.k+'</span><span class=\"dm-v '+( m.c||'')+'\">'+m.v+'</span></div>').join('');\n"
"    return '<div class=\"dim-card '+lc+'\"><div class=\"dim-head\"><div class=\"dim-name\">'+icon+' D'+num+': '+name+'</div><span class=\"dim-badge '+lc+'\">'+level+'</span></div><div class=\"dim-metrics\">'+rows+'</div><div class=\"dim-pbar\"><div class=\"dim-pbar-fill\" style=\"width:'+score+'%;background:'+bc+'\"></div></div></div>';\n"
"  }\n"
"  var d1=dimCard(1,t('d1n'),'⚔️',g.d1s,g.d1l,[\n"
"    {k:t('expLbl'),v:fms(g.exp),c:fc(g.exp)},\n"
"    {k:t('pfLbl2'),v:g.pf>=999?'∞':(g.pf||0).toFixed(2),c:g.pf>=1.3?'pos':'neg'},\n"
"    {k:t('sharpeLbl'),v:(g.sharpe||0).toFixed(2),c:g.sharpe>=0.5?'pos':'neg'}\n"
"  ]);\n"
"  var d2=dimCard(2,t('d2n'),'🎯',g.d2s,g.d2l,[\n"
"    {k:t('mwrLbl'),v:(g.mwr||0).toFixed(1)+'%',c:g.mwr>=50?'pos':'neg'},\n"
"    {k:t('cvLbl'),v:(g.cv||0).toFixed(2),c:g.cv<3?'pos':'neg'},\n"
"    {k:t('ssLbl'),v:g.ss+' trades',c:g.ss>=20?'pos':'neg'}\n"
"  ]);\n"
"  var d3=dimCard(3,t('d3n'),'🏰',g.d3s,g.d3l,[\n"
"    {k:t('maxDDl'),v:(g.maxddp||0).toFixed(1)+'%',c:g.maxddp<=15?'pos':'neg'},\n"
"    {k:t('calmarLbl'),v:g.calmar>=999?'∞':(g.calmar||0).toFixed(2),c:g.calmar>=1?'pos':'neg'},\n"
"    {k:t('maxLossStreak'),v:g.mcl+' trades',c:g.mcl<=6?'pos':'neg'}\n"
"  ]);\n"
"  var d4lvl=g.d4l==='N/A'?'STANDARD':(g.d4l||'STANDARD');\n"
"  var d4=dimCard(4,t('d4n'),'🎖️',g.d4s,d4lvl,[\n"
"    {k:t('teffLbl'),v:g.teff>0?(g.teff||0).toFixed(1)+'%':'Calculating...',c:g.teff>=30?'pos':''},\n"
"    {k:t('maerLbl'),v:g.maer>0?(g.maer||0).toFixed(2)+'x':'Calculating...',c:g.maer>0&&g.maer<1?'pos':''}\n"
"  ]);\n"
"  var notesHtml=(g.notes||'').replace(/(ALERT|CRITICAL|WARNING|FATIGUE RISK)/g,'<strong>$1</strong>');\n"
"  el.innerHTML=\n"
"    '<div class=\"rank-badge\" style=\"border-color:'+rc+'40\">'\n"
"    +'<div class=\"rank-stars\" style=\"color:'+rc+'\">'+stars+'</div>'\n"
"    +'<div class=\"rank-img-wrap\"><img class=\"rank-img\" src=\"'+(RANK_IMG[LANG]&&RANK_IMG[LANG][g.code]?RANK_IMG[LANG][g.code]:(RANK_IMG.en[g.code]||''))+'\" alt=\"'+ g.code +'\"></div>'\n"
"    +'<div class=\"rank-info\">'\n"
"    +'<div class=\"rank-title\" style=\"color:'+rc+'\">'+t('rank'+g.code)+'</div>'\n"
"    +'<div class=\"rank-code\">'+t('gridCmd')+' · '+g.code+'</div></div>'\n"
"    +'<div class=\"rank-score\">'\n"
"    +'<div class=\"rs-v\" style=\"color:'+rc+'\">'+g.comp.toFixed(0)+'</div>'\n"
"    +'<div class=\"rs-l\">'+t('compLbl')+'</div></div></div>'\n"
"    +'<div class=\"comp-bar-wrap\">'\n"
"    +'<div class=\"comp-bar-bg\"><div class=\"comp-bar-fill\" style=\"width:'+g.comp+'%;background:'+compGrad+'\"></div></div>'\n"
"    +'<div class=\"comp-zones\"><span>'+t('zP')+'</span><span>'+t('zMaj')+'</span><span>'+t('zCol')+'</span><span>'+t('zGen')+'</span><span>'+t('zMar')+'</span><span>'+t('zSup')+'</span></div></div>'\n"
"    +'<div class=\"dim-grid\">'+d1+d2+d3+d4+'</div>'\n"
"    +'<div class=\"tactical-notes\">'+t('gridAssess')+' '+notesHtml+'</div>';\n"
"}\n"
"buildBehaviorGrid(AP);\n"
"var _curTab='dash';\n"
"function switchTab(tab){\n"
"  _curTab=tab;\n"
"  document.getElementById('paneDash').classList.toggle('on',tab==='dash');\n"
"  document.getElementById('paneAna').classList.toggle('on',tab==='ana');\n"
"  document.getElementById('tabDash').classList.toggle('on',tab==='dash');\n"
"  document.getElementById('tabAna').classList.toggle('on',tab==='ana');\n"
"  if(tab==='ana'){buildCalendar();buildSideAnalysis();buildSessions();}\n"
"}\n"
"var _calYear=new Date().getFullYear();\n"
"var _calMonth=new Date().getMonth();\n"
"var _calView='month';\n"
"var _MO_CAL=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];\n"
"var _DAYS_CAL=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];\n"
"function calSetView(v){\n"
"  _calView=v;\n"
"  document.getElementById('cvMonth').classList.toggle('on',v==='month');\n"
"  document.getElementById('cvYear').classList.toggle('on',v==='year');\n"
"  buildCalendar();\n"
"}\n"
"function calNav(dir){\n"
"  if(_calView==='month'){_calMonth+=dir;if(_calMonth<0){_calMonth=11;_calYear--;}if(_calMonth>11){_calMonth=0;_calYear++;}}else{_calYear+=dir;}\n"
"  buildCalendar();\n"
"}\n"
"function getDayData(year,month){\n"
"  var map={};var trades=D.closedTrades||[];\n"
"  for(var i=0;i<trades.length;i++){var tr=trades[i];if(!tr.cl)continue;\n"
"    var d=new Date(tr.ct*1000);if(d.getFullYear()!==year||d.getMonth()!==month)continue;\n"
"    var k=d.getDate();if(!map[k])map[k]={net:0,cnt:0};map[k].net+=tr.net;map[k].cnt++;\n"
"  }\n"
"  return map;\n"
"}\n"
"function getMonthData(year){\n"
"  var arr=[];for(var i=0;i<12;i++)arr.push({net:0,cnt:0});\n"
"  var trades=D.closedTrades||[];\n"
"  for(var i=0;i<trades.length;i++){var tr=trades[i];if(!tr.cl)continue;\n"
"    var d=new Date(tr.ct*1000);if(d.getFullYear()!==year)continue;\n"
"    var m=d.getMonth();arr[m].net+=tr.net;arr[m].cnt++;\n"
"  }\n"
"  return arr;\n"
"}\n"
"function buildCalendar(){\n"
"  document.getElementById('calTitle').textContent=_calView==='year'?String(_calYear):(_MO_CAL[_calMonth]+' '+_calYear);\n"
"  if(_calView==='year')_buildCalYear();else _buildCalMonth();\n"
"}\n"
"function _buildCalMonth(){\n"
"  var dayData=getDayData(_calYear,_calMonth);\n"
"  var td=new Date(),tY=td.getFullYear(),tM=td.getMonth(),tD=td.getDate();\n"
"  var first=new Date(_calYear,_calMonth,1);\n"
"  var dow=first.getDay(),off=(dow===0?6:dow-1);\n"
"  var dim=new Date(_calYear,_calMonth+1,0).getDate();\n"
"  var diPrev=new Date(_calYear,_calMonth,0).getDate();\n"
"  var h='<div class=\"cal-grid\">';\n"
"  _DAYS_CAL.forEach(function(d){h+='<div class=\"cal-dow\">'+d+'</div>';});\n"
"  for(var i=0;i<off;i++){h+='<div class=\"cal-cell other-month\"><div class=\"cal-day\">'+(diPrev-off+1+i)+'</div></div>';}\n"
"  for(var d=1;d<=dim;d++){\n"
"    var data=dayData[d];\n"
"    var cls='cal-cell'+(tY===_calYear&&tM===_calMonth&&tD===d?' today':'');\n"
"    if(data)cls+=data.net>=0?' has-profit':' has-loss';\n"
"    h+='<div class=\"'+cls+'\"><div class=\"cal-day\">'+d+'</div>';\n"
"    if(data){h+='<div class=\"cal-trades\">'+data.cnt+' trade'+(data.cnt>1?'s':'')+'</div><div class=\"cal-pnl '+(data.net>=0?'pos':'neg')+'\">'+fms(data.net)+'</div>';}\n"
"    h+='</div>';\n"
"  }\n"
"  var tot=off+dim,rem=(7-tot%7)%7;\n"
"  for(var i=1;i<=rem;i++)h+='<div class=\"cal-cell other-month\"><div class=\"cal-day\">'+i+'</div></div>';\n"
"  document.getElementById('calBody').innerHTML=h+'</div>';\n"
"}\n"
"function _buildCalYear(){\n"
"  var mData=getMonthData(_calYear);var h='<div class=\"cal-year-grid\">';\n"
"  for(var m=0;m<12;m++){var d=mData[m];\n"
"    h+='<div class=\"cal-month-card\" onclick=\"_calMonth='+m+';calSetView(\\x27month\\x27)\">'+\n"
"      '<div class=\"cmh\">'+_MO_CAL[m]+'</div>'+\n"
"      '<div class=\"cmp '+(d.cnt>0?( d.net>=0?'pos':'neg'):'')+'\">'+( d.cnt>0?fms(d.net):'—')+'</div>'+\n"
"      '<div class=\"cmt\">'+(d.cnt>0?d.cnt+' trades':'—')+'</div></div>';\n"
"  }\n"
"  document.getElementById('calBody').innerHTML=h+'</div>';\n"
"}\n"
"function makeSVGDonut(pctA,cA,cB){\n"
"  var r=30,circ=2*Math.PI*r,a=Math.max(0,Math.min(100,pctA||0));\n"
"  var dash=(circ*a/100).toFixed(1),gap=(circ*(100-a)/100).toFixed(1),off=(circ*0.25).toFixed(1);\n"
"  return '<circle cx=\"40\" cy=\"40\" r=\"'+r+'\" fill=\"none\" stroke=\"'+cB+'\" stroke-width=\"10\"/>'+\n"
"    '<circle cx=\"40\" cy=\"40\" r=\"'+r+'\" fill=\"none\" stroke=\"'+cA+'\" stroke-width=\"10\"'+\n"
"    ' stroke-dasharray=\"'+dash+' '+gap+'\" stroke-dashoffset=\"'+off+'\" stroke-linecap=\"round\"/>';\n"
"}\n"
"function buildSideAnalysis(){\n"
"  var s=D.side;if(!s)return;\n"
"  var tot=s.bTotal+s.sTotal,bPct=tot>0?s.bTotal/tot*100:50;\n"
"  var BC='#3b7ff5',SC='#16a34a';\n"
"  document.getElementById('donTrades').innerHTML=makeSVGDonut(bPct,BC,SC);\n"
"  document.getElementById('legTrades').innerHTML='<div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+BC+'\"></span>BUY<span class=\"dl-val\">'+s.bTotal+'</span></div><div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+SC+'\"></span>SELL<span class=\"dl-val\">'+s.sTotal+'</span></div><div class=\"dl-item\" style=\"color:var(--dm)\">Total<span class=\"dl-val\">'+tot+'</span></div>';\n"
"  document.getElementById('statTrades').innerHTML='<div class=\"ss-row\"><span class=\"ss-k\">Buy share</span><span class=\"ss-v\">'+bPct.toFixed(1)+'%</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell share</span><span class=\"ss-v\">'+(100-bPct).toFixed(1)+'%</span></div><div class=\"ss-row\"><span class=\"ss-k\">Buy PF</span><span class=\"ss-v '+(s.bPF>=1?'pos':'neg')+'\">'+( s.bPF>=999?'∞':s.bPF.toFixed(2))+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell PF</span><span class=\"ss-v '+(s.sPF>=1?'pos':'neg')+'\">'+( s.sPF>=999?'∞':s.sPF.toFixed(2))+'</span></div>';\n"
"  document.getElementById('donWR').innerHTML=makeSVGDonut(s.bWR,BC,SC);\n"
"  document.getElementById('legWR').innerHTML='<div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+BC+'\"></span>BUY<span class=\"dl-val '+(s.bWR>=50?'pos':'neg')+'\">'+s.bWR.toFixed(1)+'%</span></div><div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+SC+'\"></span>SELL<span class=\"dl-val '+(s.sWR>=50?'pos':'neg')+'\">'+s.sWR.toFixed(1)+'%</span></div>';\n"
"  document.getElementById('statWR').innerHTML='<div class=\"ss-row\"><span class=\"ss-k\">Buy wins</span><span class=\"ss-v pos\">'+s.bWins+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell wins</span><span class=\"ss-v pos\">'+s.sWins+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Buy losses</span><span class=\"ss-v neg\">'+(s.bTotal-s.bWins)+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell losses</span><span class=\"ss-v neg\">'+(s.sTotal-s.sWins)+'</span></div>';\n"
"  var bNA=Math.abs(s.bNet),sNA=Math.abs(s.sNet),pT=bNA+sNA;\n"
"  document.getElementById('donPNL').innerHTML=makeSVGDonut(pT>0?bNA/pT*100:50,BC,SC);\n"
"  document.getElementById('legPNL').innerHTML='<div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+BC+'\"></span>BUY<span class=\"dl-val '+fc(s.bNet)+'\">'+fms(s.bNet)+'</span></div><div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+SC+'\"></span>SELL<span class=\"dl-val '+fc(s.sNet)+'\">'+fms(s.sNet)+'</span></div>';\n"
"  document.getElementById('statPNL').innerHTML='<div class=\"ss-row\"><span class=\"ss-k\">Buy GP</span><span class=\"ss-v pos\">+'+fm(s.bGP,true)+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell GP</span><span class=\"ss-v pos\">+'+fm(s.sGP,true)+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Buy GL</span><span class=\"ss-v neg\">-'+fm(s.bGL,true)+'</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell GL</span><span class=\"ss-v neg\">-'+fm(s.sGL,true)+'</span></div>';\n"
"  var rT=Math.abs(s.bAvgRR)+Math.abs(s.sAvgRR);\n"
"  document.getElementById('donRR').innerHTML=makeSVGDonut(rT>0?Math.abs(s.bAvgRR)/rT*100:50,BC,SC);\n"
"  document.getElementById('legRR').innerHTML='<div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+BC+'\"></span>BUY<span class=\"dl-val '+fc(s.bAvgRR)+'\">'+s.bAvgRR.toFixed(2)+'R</span></div><div class=\"dl-item\"><span class=\"dl-dot\" style=\"background:'+SC+'\"></span>SELL<span class=\"dl-val '+fc(s.sAvgRR)+'\">'+s.sAvgRR.toFixed(2)+'R</span></div>';\n"
"  document.getElementById('statRR').innerHTML='<div class=\"ss-row\"><span class=\"ss-k\">Buy avg RR</span><span class=\"ss-v '+fc(s.bAvgRR)+'\">'+s.bAvgRR.toFixed(2)+'x</span></div><div class=\"ss-row\"><span class=\"ss-k\">Sell avg RR</span><span class=\"ss-v '+fc(s.sAvgRR)+'\">'+s.sAvgRR.toFixed(2)+'x</span></div>';\n"
"}\n"
"function buildSessions(){\n"
"  var ss=D.sessions||[];if(!ss.length)return;\n"
"  var names=['🌏 Asian','🇬🇧 London','🗽 New York','🌙 Off-Session'];\n"
"  var cls=['asian','london','ny','oos'];\n"
"  var times=['00:00–08:00','08:00–13:00','13:00–22:00','22:00–24:00'];\n"
"  var maxT=Math.max.apply(null,ss.map(function(s){return s.total;}));\n"
"  var h='';\n"
"  for(var i=0;i<ss.length;i++){\n"
"    var s=ss[i];\n"
"    var bW=maxT>0?s.total/maxT*100:0;\n"
"    var bc=i===0?'#f59e0b':i===1?'#3b7ff5':i===2?'#16a34a':'#475569';\n"
"    h+='<div class=\"sess-card '+cls[i]+'\">'+\n"
"      '<div class=\"sess-name\">'+names[i]+'</div>'+\n"
"      '<div class=\"sess-wr '+(s.wr>=50?'pos':'neg')+'\">'+s.wr.toFixed(1)+'%</div>'+\n"
"      '<div class=\"sess-wr-lbl\">WIN RATE</div>'+\n"
"      '<div class=\"sess-rows\">'+\n"
"        '<div class=\"sr\"><span class=\"sr-k\">Trades</span><span class=\"sr-v\">'+s.total+'</span></div>'+\n"
"        '<div class=\"sr\"><span class=\"sr-k\">Net P&L</span><span class=\"sr-v '+fc(s.net)+'\">'+fms(s.net)+'</span></div>'+\n"
"        '<div class=\"sr\"><span class=\"sr-k\">Avg RR</span><span class=\"sr-v '+fc(s.avgrr)+'\">'+s.avgrr.toFixed(2)+'x</span></div>'+\n"
"        '<div class=\"sr\"><span class=\"sr-k\">P.Factor</span><span class=\"sr-v '+(s.pf>=1?'pos':'neg')+'\">'+( s.pf>=999?'∞':s.pf.toFixed(2))+'</span></div>'+\n"
"        '<div class=\"sr\"><span class=\"sr-k\">Time</span><span class=\"sr-v\" style=\"color:var(--dm)\">'+times[i]+'</span></div>'+\n"
"      '</div>'+\n"
"      '<div class=\"sess-bar\"><div class=\"sess-bar-fill\" style=\"width:'+bW.toFixed(0)+'%;background:'+bc+'\"></div></div>'+\n"
"    '</div>';\n"
"  }\n"
"  document.getElementById('sessGrid').innerHTML=h;\n"
"}\n"
"function getGrid(pk){\n"
"  var gmap={today:D.gridToday,week:D.gridWeek,lastweek:D.gridLastWeek,month:D.gridMonth,all:D.gridAll,custom:D.gridAll};\n"
"  return gmap[pk]||D.grid;\n"
"}\n"
"function buildBehaviorGrid(pk){\n"
"  pk=pk||AP;\n"
"  var g=getGrid(pk);\n"
"  var el=document.getElementById('grid-panel');\n"
"  if(!g||!g.comp){el.innerHTML='';return;}\n"
"  var rc=g.stars>=5?'var(--teal)':g.stars>=4?'var(--purple)':g.stars>=3?'var(--gold)':g.stars>=2?'var(--sky)':'var(--d2)';\n"
"  var stars='';for(var i=0;i<5;i++)stars+=i<g.stars?'★':'☆';\n"
"  var imgSrc=RANK_IMG[LANG]&&RANK_IMG[LANG][g.code]?RANK_IMG[LANG][g.code]:(RANK_IMG.en[g.code]||'');\n"
"  el.innerHTML=\n"
"    '<div class=\"rank-card-label\">'+t('rankingLbl')+'</div>'+\n"
"    '<div class=\"rank-img-wrap\"><img class=\"rank-img\" src=\"'+imgSrc+'\" alt=\"'+g.code+'\"></div>'+\n"
"    '<div class=\"rank-title-hero\" style=\"color:'+rc+'\">'+t('rank'+g.code)+'</div>'+\n"
"    '<div class=\"rank-code-hero\">'+t('gridCommand')+' · '+g.code+'</div>'+\n"
"    '<div class=\"rank-score-wrap\">'+\n"
"      '<div class=\"rank-score-row\">'+\n"
"        '<span class=\"rank-score-lbl\">'+t('compLbl')+'</span>'+\n"
"        '<span class=\"rank-score-num\" style=\"color:'+rc+'\">'+g.comp.toFixed(0)+'</span>'+\n"
"      '</div>'+\n"
"      '<div class=\"rank-bar-bg\"><div class=\"rank-bar-fill\" style=\"width:'+g.comp+'%\"></div></div>'+\n"
"      '<div class=\"rank-zones\">'+\n"
"        '<span class=\"rank-zone\">'+t('zP')+'</span>'+\n"
"        '<span class=\"rank-zone\">'+t('zMaj')+'</span>'+\n"
"        '<span class=\"rank-zone\">'+t('zCol')+'</span>'+\n"
"        '<span class=\"rank-zone\">'+t('zGen')+'</span>'+\n"
"        '<span class=\"rank-zone\">'+t('zMar')+'</span>'+\n"
"        '<span class=\"rank-zone\">'+t('zSup')+'</span>'+\n"
"      '</div>'+\n"
"    '</div>';\n"
"  var dEl=document.getElementById('dimGrid');\n"
"  if(!dEl)return;\n"
"  var dims=[\n"
"    {n:t('d1n'),ic:'⚔️',cl:'1',s:g.d1s,lv:g.d1l,ms:[{k:t('expLbl'),v:fms(g.exp),c:fc(g.exp)},{k:t('pfLbl2'),v:g.pf>=999?'∞':(g.pf||0).toFixed(2),c:g.pf>=1.3?'pos':'neg'},{k:t('sharpeLbl'),v:(g.sharpe||0).toFixed(2),c:g.sharpe>=0.5?'pos':'neg'}]},\n"
"    {n:t('d2n'),ic:'🎯',cl:'2',s:g.d2s,lv:g.d2l,ms:[{k:t('mwrLbl'),v:(g.mwr||0).toFixed(1)+'%',c:g.mwr>=50?'pos':'neg'},{k:t('cvLbl'),v:(g.cv||0).toFixed(2),c:g.cv<3?'pos':'neg'},{k:t('ssLbl'),v:g.ss+' trades',c:g.ss>=20?'pos':'neg'}]},\n"
"    {n:t('d3n'),ic:'🏰',cl:'3',s:g.d3s,lv:g.d3l,ms:[{k:t('maxDDl'),v:(g.maxddp||0).toFixed(1)+'%',c:g.maxddp<=15?'pos':'neg'},{k:t('calmarLbl'),v:g.calmar>=999?'∞':(g.calmar||0).toFixed(2),c:g.calmar>=1?'pos':'neg'},{k:t('mclLbl'),v:g.mcl+' trades',c:g.mcl<=6?'pos':'neg'}]},\n"
"    {n:t('d4n'),ic:'🎖️',cl:'4',s:g.d4s,lv:g.d4l,ms:[{k:t('teffLbl'),v:g.teff>0?(g.teff||0).toFixed(1)+'%':t('calculating'),c:g.teff>=30?'pos':''},{k:t('maerLbl'),v:g.maer>0?(g.maer||0).toFixed(2)+'x':t('calculating'),c:g.maer>0&&g.maer<1?'pos':''}]}\n"
"  ];\n"
"  dEl.innerHTML=dims.map(function(d){\n"
"    var ms=d.ms.map(function(m){return '<div class=\"dm-row\"><span class=\"dm-k\">'+m.k+'</span><span class=\"dm-v '+m.c+'\">'+m.v+'</span></div>';}).join('');\n"
"    return '<div class=\"dim-card dim-card-'+d.cl+'\">'+\n"
"      '<div class=\"dim-icon\">'+d.ic+'</div>'+\n"
"      '<div class=\"dim-name dim-name-'+d.cl+'\">'+d.n+'</div>'+\n"
"      '<div class=\"dim-weight\">D'+d.cl+'</div>'+\n"
"      '<div class=\"dim-score-num dim-score-'+d.cl+'\">'+d.s+'</div>'+\n"
"      '<div class=\"dim-bar-bg\"><div class=\"dim-bar-fill-'+d.cl+'\" style=\"width:'+d.s+'%\"></div></div>'+\n"
"      '<div class=\"dim-level dim-name-'+d.cl+'\">'+d.lv+'</div>'+\n"
"      '<div class=\"dim-metrics\">'+ms+'</div>'+\n"
"    '</div>';\n"
"  }).join('');\n"
"  var tn=document.getElementById('tacticalNotes');\n"
"  var tt=document.getElementById('tacticalText');\n"
"  if(tn&&tt&&g.notes){\n"
"    tn.style.display='block';\n"
"    tt.innerHTML=g.notes.replace(/([A-Z]+\\s[A-Z]+:.*?\\.)\\s/g,'<span class=\"note-pos\">$1</span> ').replace(/(CRITICAL:.*?\\.)/g,'<span class=\"note-neg\">$1</span>');\n"
"  }\n"
"}\n"
"function updateHero(ps){\n"
"  var netEl=document.getElementById('heroNet');\n"
"  var pctEl=document.getElementById('heroPct');\n"
"  if(netEl){netEl.textContent=fms(ps.net||0);netEl.className='hkpi-val '+fc(ps.net);}\n"
"  if(pctEl){pctEl.textContent=fP(ps.pct||0);pctEl.className='hkpi-val '+fc(ps.pct);}\n"
"  var hm=document.getElementById('heroMetrics');\n"
"  if(!hm)return;\n"
"  var items=[\n"
"    {l:t('winRateLbl'),v:(ps.wr||0).toFixed(1)+'%',c:fc(ps.wr-50)},\n"
"    {l:t('profitFactor'),v:ps.pf>=999?'∞':(ps.pf||0).toFixed(2),c:fc(ps.pf-1)},\n"
"    {l:t('maxDD'),v:(ps.maxddp||0).toFixed(1)+'%',c:'neg'},\n"
"    {l:t('totalTrades'),v:(ps.total||0)+'',c:''},\n"
"  ];\n"
"  hm.innerHTML=items.map(function(x){return '<div class=\"hm-item\"><div class=\"hm-val '+x.c+'\">'+x.v+'</div><div class=\"hm-lbl\">'+x.l+'</div></div>';}).join('');\n"
"}\n"
"function sw(btn){\n"
"AP=btn.dataset.p;\n"
"document.querySelectorAll('.hb').forEach(b=>b.classList.toggle('on',b===btn));\n"
"document.getElementById('cpBadge').style.display='none';\n"
"const{from,to}=getRange(AP);\n"
"bpc();\n"
"bsg(AP);\n"
"try{bc2(from,to);}catch(e){console.error('Chart:',e);}\n"
"bt(from,to);\n"
"buildTimeCharts(from,to);\n"
"buildMaeMfe(from,to);\n"
"genInsights(AP);\n"
"buildStreaks(AP);\n"
"buildBehaviorGrid(AP);\n"
"document.getElementById('stl').textContent=(PM[AP]&&PM[AP].label||AP)+' — '+t('keyMetrics')+' —';\n"
"}\n"
"document.querySelectorAll('.hb').forEach(b=>b.classList.toggle('on',b.dataset.p===AP));\n"
"// Auto-reload disabled — use Refresh button on MT5 chart\n"
"</script></body></html>\n";}

//========================= WRITE HTML =============================
void WriteHTML(string period,
               const Stats &sel,
               const Stats &s_today,
               const Stats &s_week,
               const Stats &s_lastweek,
               const Stats &s_month,
               const Stats &s_all,
               const BehaviorGrid &bg,
               const BehaviorGrid &bg_today,
               const BehaviorGrid &bg_week,
               const BehaviorGrid &bg_lastweek,
               const BehaviorGrid &bg_month,
               const BehaviorGrid &bg_all,
               string &bal_j,string &rr_j,
               string &monthly_j,
               string &open_j,string &closed_j,
               string &side_j,string &session_j){

    string ccy=AccountInfoString(ACCOUNT_CURRENCY);
    // คำนวณ date range ของแต่ละ period เพื่อส่งให้ JS ใช้ filter
    datetime ft,tt;
    PeriodRange("today",    ft,tt); string pr_today    ="{\"f\":"+(string)(long)ft+",\"t\":"+(string)(long)tt+"}";
    PeriodRange("weekly",   ft,tt); string pr_week     ="{\"f\":"+(string)(long)ft+",\"t\":"+(string)(long)tt+"}";
    PeriodRange("lastweek", ft,tt); string pr_lastweek ="{\"f\":"+(string)(long)ft+",\"t\":"+(string)(long)tt+"}";
    PeriodRange("monthly",  ft,tt); string pr_month    ="{\"f\":"+(string)(long)ft+",\"t\":"+(string)(long)tt+"}";
    PeriodRange("alltime",  ft,tt); string pr_all      ="{\"f\":"+(string)(long)ft+",\"t\":"+(string)(long)tt+"}";

    string meta="{"
      +"\"updated\":"+(string)(long)TimeCurrent()
      +",\"login\":"+(string)AccountInfoInteger(ACCOUNT_LOGIN)
      +",\"server\":\""+JE(AccountInfoString(ACCOUNT_SERVER))+"\""
      +",\"name\":\""+JE(AccountInfoString(ACCOUNT_NAME))+"\""
      +",\"ccy\":\""+ccy+"\""
      +",\"bal\":"+DoubleToString(g_bal_now,2)
      +",\"equity\":"+DoubleToString(g_equity,2)
      +",\"initBal\":"+DoubleToString(g_init_bal,2)
      +",\"risk\":"+DoubleToString(InpRiskPercent,2)
      +",\"riskAmt\":"+DoubleToString(g_risk_base,2)
      +",\"active\":\""+period+"\""
      +",\"ranges\":{\"today\":"+pr_today+",\"week\":"+pr_week+",\"lastweek\":"+pr_lastweek+",\"month\":"+pr_month+",\"all\":"+pr_all+"}"

      +"}";

    string data="const D={"
      +"\"meta\":"+meta
      +",\"sel\":"+SJ(sel)
      +",\"today\":"+SJ(s_today)
      +",\"week\":"+SJ(s_week)
      +",\"lastweek\":"+SJ(s_lastweek)
      +",\"month\":"+SJ(s_month)
      +",\"all\":"+SJ(s_all)
      +",\"balSeries\":"+bal_j
      +",\"rrSeries\":"+rr_j
      +",\"monthly\":"+monthly_j
      +",\"openTrades\":"+open_j
      +",\"closedTrades\":"+closed_j
      +",\"grid\":"+SBG(bg)
      +",\"gridToday\":"+SBG(bg_today)
      +",\"gridWeek\":"+SBG(bg_week)
      +",\"gridLastWeek\":"+SBG(bg_lastweek)
      +",\"gridMonth\":"+SBG(bg_month)
      +",\"gridAll\":"+SBG(bg_all)
      +",\"side\":"+side_j
      +",\"sessions\":"+session_j
      +"};";

    int fh=FileOpen(InpHTMLFile,FILE_WRITE|FILE_BIN);
    if(fh==INVALID_HANDLE){Print("HTML write fail: ",GetLastError());return;}
    // UTF-8 BOM (optional but helps some browsers detect encoding)
    uchar bom[]={0xEF,0xBB,0xBF};
    FileWriteArray(fh,bom,0,3);
    WriteUTF8(fh,GetHead(data));
    WriteUTF8(fh,GetBody());
    WriteUTF8(fh,GetRankImages());
    WriteUTF8(fh,GetScript());
    FileClose(fh);
}

// Write string to file as UTF-8 bytes (supports emoji, Thai, etc.)
void WriteUTF8(int fh, string text) {
    uchar bytes[];
    int len = StringToCharArray(text, bytes, 0, -1, CP_UTF8);
    if(len > 1) FileWriteArray(fh, bytes, 0, len-1); // -1 to skip null terminator
}

//========================= HTML =================================
string GetHead(string inlineData){return

"<!DOCTYPE html><html lang='en'>\n"
"<head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>\n"
"<title>TRADING.JOURNAL</title>\n"
"<script src='https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js'></script>\n"

"<style>\n"
"@import url('https://fonts.googleapis.com/css2?family=Sarabun:wght@400;600;700&family=Space+Grotesk:wght@400;500;600;700&family=DM+Mono:wght@400;500&display=swap');\n"
":root{\n"
"  --bg:#0d1117;--panel:#161b27;--p2:#1e2535;--p3:#252d3d;\n"
"  --line:#2a3348;--line2:#35405a;\n"
"  /* Accent palette */\n"
"  --teal:#2dd4bf;--teal2:#0f766e;--tealg:rgba(45,212,191,.12);\n"
"  --coral:#f87171;--coral2:#be3434;--coralg:rgba(248,113,113,.12);\n"
"  --gold:#f59e0b;--gold2:#92530a;--goldg:rgba(245,158,11,.12);\n"
"  --purple:#a78bfa;--purple2:#5b2fc6;--purpleg:rgba(167,139,250,.12);\n"
"  --sky:#60a5fa;--sky2:#1e4fa0;\n"
"  --green:#4ade80;--red:#f87171;\n"
"  --tx:#f0f4ff;--d1:#c8d3f0;--d2:#8892b0;--dm:#4a5580;\n"
"  --pos:#4ade80;--neg:#f87171;\n"
"  /* Typography */\n"
"  --fd:'Space Grotesk',sans-serif;\n"
"  --fb:'Space Grotesk',sans-serif;\n"
"  --fm:'DM Mono',monospace;\n"
"}\n"
"*{margin:0;padding:0;box-sizing:border-box}\n"
"html,body{background:var(--bg);color:var(--tx);font-family:var(--fb);font-size:13px;min-height:100vh;line-height:1.5}\n"
"body.th-mode{font-family:'Sarabun',var(--fb)!important}\n"

/* ── HEADER ── */
"/* Header */\n"
".hdr{display:flex;align-items:center;padding:14px 24px;background:var(--panel);border-bottom:1px solid var(--line);gap:12px;position:sticky;top:0;z-index:100;backdrop-filter:blur(10px)}\n"
".logo{font-family:var(--fd);font-size:22px;font-weight:700;letter-spacing:2px;color:var(--tx);white-space:nowrap}\n"
".logo em{color:var(--teal);font-style:normal}\n"
".hbtns{display:flex;gap:6px;flex:1;justify-content:center;flex-wrap:wrap}\n"
".hb{padding:7px 14px;border-radius:8px;font-size:11px;font-weight:600;letter-spacing:.5px;border:1px solid var(--line2);background:transparent;color:var(--d2);cursor:pointer;transition:.2s all;font-family:var(--fb)}\n"
".hb.on{background:var(--teal);color:#0d1117;border-color:var(--teal);font-weight:700;box-shadow:0 0 16px rgba(45,212,191,.3)}\n"
".hb:not(.on):hover{border-color:var(--teal);color:var(--teal)}\n"
".hb-custom.on{background:var(--tealg);border-color:var(--teal);color:var(--teal)}\n"
".dot{width:6px;height:6px;border-radius:50%;background:var(--teal);box-shadow:0 0 8px var(--teal);animation:pulse 2s infinite}\n"
"@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.6;transform:scale(.8)}}\n"
".upd{font-size:9px;color:var(--dm);font-family:var(--fm);white-space:nowrap}\n"
".lbtn{padding:5px 11px;border-radius:6px;font-size:11px;font-weight:700;cursor:pointer;border:1px solid var(--line2);background:transparent;color:var(--d2);transition:.2s all}\n"
".lbtn.on{background:var(--tealg);border-color:var(--teal);color:var(--teal)}\n"

/* ── TABS ── */
"/* Tabs */\n"
".tabs{display:flex;gap:0;padding:0 24px;background:var(--panel);border-bottom:2px solid var(--line)}\n"
".tab-btn{padding:12px 22px;font-family:var(--fb);font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--d2);cursor:pointer;border:none;background:none;border-bottom:2px solid transparent;margin-bottom:-2px;transition:.2s all}\n"
".tab-btn.on{color:var(--teal);border-bottom-color:var(--teal)}\n"
".tab-btn:hover:not(.on){color:var(--d1)}\n"
".tab-pane{display:none}.tab-pane.on{display:block}\n"

/* ── MAIN LAYOUT ── */
"/* Main */\n"
".main-wrap{padding:20px 24px;max-width:1600px;margin:0 auto;display:flex;flex-direction:column;gap:16px}\n"

/* ── HERO SECTION (Rank + Chart) ── */
"/* Hero */\n"
".hero{display:grid;grid-template-columns:380px 1fr;gap:16px;min-height:320px}\n"
".rank-card{background:linear-gradient(135deg,var(--panel) 0%,var(--p2) 100%);border:1px solid var(--line2);border-radius:18px;padding:24px;display:flex;flex-direction:column;align-items:center;justify-content:center;position:relative;overflow:hidden}\n"
".rank-card::before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse at 50% 0%,var(--tealg) 0%,transparent 70%);pointer-events:none}\n"
".rank-card-label{font-family:var(--fd);font-size:31px;font-weight:700;letter-spacing:3px;text-transform:uppercase;color:var(--gold);text-shadow:0 0 20px rgba(245,158,11,.5);margin-bottom:10px;text-align:center}\n"

".rank-img-wrap{display:flex;justify-content:center;margin-bottom:12px}\n"
".rank-img{width:192px;height:192px;object-fit:contain;image-rendering:crisp-edges;filter:drop-shadow(0 0 32px rgba(45,212,191,.8)) drop-shadow(0 0 8px rgba(255,255,255,.15));transition:transform .3s,filter .3s}\n"
".rank-img:hover{transform:scale(1.06)}\n"
".rank-title-hero{font-family:var(--fd);font-size:24px;font-weight:700;text-align:center;color:var(--teal);letter-spacing:1px;margin-bottom:4px}\n"
".rank-code-hero{font-size:9px;color:var(--dm);letter-spacing:2px;text-align:center;margin-bottom:14px}\n"
".rank-score-wrap{width:100%;background:var(--p3);border-radius:10px;padding:12px 16px;border:1px solid var(--line)}\n"
".rank-score-row{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}\n"
".rank-score-lbl{font-size:9px;color:var(--dm);letter-spacing:1px}\n"
".rank-score-num{font-family:var(--fd);font-size:28px;font-weight:700;color:var(--teal)}\n"
".rank-bar-bg{height:6px;background:var(--line);border-radius:3px;overflow:hidden}\n"
".rank-bar-fill{height:100%;border-radius:3px;background:linear-gradient(90deg,var(--teal),var(--purple));transition:width 1s cubic-bezier(.4,0,.2,1)}\n"
".rank-zones{display:flex;justify-content:space-between;margin-top:5px}\n"
".rank-zone{font-size:7px;color:var(--dm)}\n"

/* ── CHART CARD ── */
"/* Chart card */\n"
".chart-card{background:var(--panel);border:1px solid var(--line2);border-radius:18px;padding:20px;display:flex;flex-direction:column;gap:12px}\n"
".chart-header{display:flex;justify-content:space-between;align-items:flex-start}\n"
".chart-title{font-family:var(--fd);font-size:13px;font-weight:700;letter-spacing:1px;color:var(--d2);text-transform:uppercase}\n"
".hero-kpi{display:flex;gap:20px}\n"
".hkpi{text-align:right}\n"
".hkpi-val{font-family:var(--fd);font-size:26px;font-weight:700;line-height:1}\n"
".hkpi-lbl{font-size:9px;color:var(--dm);letter-spacing:1px}\n"
".cb{flex:1;min-height:150px;position:relative}\n"
".hero-metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}\n"
".hm-item{background:var(--p2);border-radius:10px;padding:10px 12px;border:1px solid var(--line)}\n"
".hm-val{font-family:var(--fd);font-size:18px;font-weight:700;line-height:1;margin-bottom:2px}\n"
".hm-lbl{font-size:8px;color:var(--dm);letter-spacing:1px;text-transform:uppercase}\n"

/* ── STATS SECTION ── */
"/* Stats */\n"
".stats-section{background:var(--panel);border:1px solid var(--line2);border-radius:18px;padding:16px 20px}\n"
".section-label{font-size:9px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:var(--dm);margin-bottom:14px;display:flex;align-items:center;gap:8px}\n"
".section-label::after{content:'';flex:1;height:1px;background:var(--line)}\n"
".sg{display:grid;grid-template-columns:repeat(6,1fr);gap:10px}\n"
".sc{background:var(--p2);border-radius:12px;padding:12px;border:1px solid var(--line);transition:.2s}\n"
".sc:hover{border-color:var(--line2);background:var(--p3)}\n"
".sk{font-size:8px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--dm);margin-bottom:6px}\n"
".sv{font-family:var(--fd);font-size:18px;font-weight:700;line-height:1}\n"
".sv.pos{color:var(--pos)}.sv.neg{color:var(--neg)}.sv.dim{color:var(--d2)}\n"
".stat-card{background:var(--p2);border-radius:12px;padding:12px;border:1px solid var(--line);transition:.2s}\n"
".stat-card:hover{border-color:var(--line2);background:var(--p3)}\n"
".stat-val{font-family:var(--fd);font-size:18px;font-weight:700;line-height:1;margin-bottom:4px}\n"
".stat-val.pos{color:var(--pos)}.stat-val.neg{color:var(--neg)}.stat-val.dim{color:var(--d2)}\n"
".stat-lbl{font-size:8px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--dm)}\n"

/* ── DIMENSION CARDS (D1-D4) ── */
"/* Dim cards */\n"
".dim-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}\n"
".dim-card{border-radius:14px;padding:16px;border:1px solid var(--line);position:relative;overflow:hidden}\n"
".dim-card-1{background:linear-gradient(135deg,rgba(45,212,191,.08),transparent);border-color:rgba(45,212,191,.3)}\n"
".dim-card-2{background:linear-gradient(135deg,rgba(167,139,250,.08),transparent);border-color:rgba(167,139,250,.3)}\n"
".dim-card-3{background:linear-gradient(135deg,rgba(245,158,11,.08),transparent);border-color:rgba(245,158,11,.3)}\n"
".dim-card-4{background:linear-gradient(135deg,rgba(96,165,250,.08),transparent);border-color:rgba(96,165,250,.3)}\n"
".dim-icon{font-size:18px;margin-bottom:8px}\n"
".dim-name{font-size:10px;font-weight:700;letter-spacing:.5px;margin-bottom:2px}\n"
".dim-name-1{color:var(--teal)}.dim-name-2{color:var(--purple)}.dim-name-3{color:var(--gold)}.dim-name-4{color:var(--sky)}\n"
".dim-weight{font-size:8px;color:var(--dm);margin-bottom:12px}\n"
".dim-score-num{font-family:var(--fd);font-size:32px;font-weight:700;line-height:1}\n"
".dim-score-1{color:var(--teal)}.dim-score-2{color:var(--purple)}.dim-score-3{color:var(--gold)}.dim-score-4{color:var(--sky)}\n"
".dim-bar-bg{height:4px;background:var(--line);border-radius:2px;margin:8px 0;overflow:hidden}\n"
".dim-bar-fill-1{height:100%;border-radius:2px;background:linear-gradient(90deg,var(--teal2),var(--teal))}\n"
".dim-bar-fill-2{height:100%;border-radius:2px;background:linear-gradient(90deg,var(--purple2),var(--purple))}\n"
".dim-bar-fill-3{height:100%;border-radius:2px;background:linear-gradient(90deg,var(--gold2),var(--gold))}\n"
".dim-bar-fill-4{height:100%;border-radius:2px;background:linear-gradient(90deg,var(--sky2),var(--sky))}\n"
".dim-level{font-size:8px;font-weight:700;letter-spacing:1px}\n"
".dim-metrics{margin-top:10px;display:flex;flex-direction:column;gap:5px}\n"
".dm-row{display:flex;justify-content:space-between;font-size:10px;padding:4px 0;border-bottom:1px solid var(--line)}\n"
".dm-row:last-child{border:none}\n"
".dm-k{color:var(--dm)}.dm-v{font-family:var(--fm);font-size:10px}\n"
".dm-v.pos{color:var(--pos)}.dm-v.neg{color:var(--neg)}\n"

/* ── NOTES/TACTICAL ── */
"/* Tactical */\n"
".tactical-section{background:var(--p2);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin-top:12px}\n"
".tactical-label{font-size:9px;font-weight:700;letter-spacing:1.5px;color:var(--teal);text-transform:uppercase;margin-bottom:8px}\n"
".tactical-text{font-size:11px;color:var(--d1);line-height:1.6}\n"
".note-pos{color:var(--pos);font-weight:600}.note-neg{color:var(--neg);font-weight:600}\n"

/* ── STREAKS ── */
"/* Streaks */\n"
"#streaks-panel{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".sk-title{font-size:9px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:var(--dm);margin-bottom:12px}\n"
".sk-grid6{display:grid;grid-template-columns:1fr 1fr;gap:8px}\n"
".sk-cell6{background:var(--p2);border-radius:10px;padding:10px 8px;border:1px solid var(--line);text-align:center}\n"
".sk-v6{font-family:var(--fd);font-size:18px;font-weight:700;line-height:1;margin-bottom:4px}\n"
".sk-k6{font-size:7px;color:var(--dm);letter-spacing:.5px;line-height:1.3}\n"
".sk-v6.pos{color:var(--pos)}.sk-v6.neg{color:var(--neg)}\n"

/* ── BOTTOM ROW ── */
"/* Bottom */\n"
".bottom-row{display:grid;grid-template-columns:1fr 1fr;gap:16px}\n"
".left-col{display:flex;flex-direction:column;gap:16px}\n"
".right-col{display:flex;flex-direction:column;gap:16px}\n"

/* ── CHARTS ── */
"/* Charts */\n"
".chart-pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}\n"
".chc{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".ctt{font-size:10px;font-weight:700;letter-spacing:1px;color:var(--d2);text-transform:uppercase;margin-bottom:12px}\n"

/* ── MONTHLY TABLE ── */
"/* Monthly */\n"
".monthly-card{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".mh{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}\n"
".tt{font-family:var(--fd);font-size:14px;font-weight:700;color:var(--tx)}\n"
".mts{display:flex;gap:6px}\n"
".mt2{padding:5px 12px;border-radius:7px;font-size:10px;font-weight:600;cursor:pointer;border:1px solid var(--line2);background:transparent;color:var(--d2);transition:.2s}\n"
".mt2.on{background:var(--tealg);color:var(--teal);border-color:var(--teal)}\n"
"table.mtb{width:100%;border-collapse:collapse;font-size:10px}\n"
"table.mtb th{padding:7px 8px;text-align:center;color:var(--dm);font-size:8px;font-weight:700;letter-spacing:1px;border-bottom:1px solid var(--line)}\n"
"table.mtb td{padding:7px 8px;text-align:center;border-bottom:1px solid var(--line);font-family:var(--fm)}\n"
"table.mtb td.yt{font-family:var(--fd);font-size:16px;color:var(--teal);text-align:left;padding-left:8px;font-weight:700}\n"
"table.mtb td.pos{color:var(--pos)}.mtb td.neg{color:var(--neg)}\n"
".mtb tr:last-child td{border:none;font-weight:700;color:var(--d1)}\n"

/* ── ACCOUNT + TRADE ── */
"/* Account */\n"
".acct-card{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".ct{font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--d2);margin-bottom:12px}\n"
".al{display:flex;flex-direction:column;gap:6px}\n"
".ar{display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid var(--line);font-size:11px}\n"
".ar:last-child{border:none}\n"
".ak{color:var(--dm)}.av{font-family:var(--fm);color:var(--d1)}\n"
".tcards{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".tts{display:flex;gap:0;margin-bottom:12px;border-bottom:1px solid var(--line)}\n"
".tt2{padding:7px 16px;font-size:10px;font-weight:700;letter-spacing:.5px;cursor:pointer;border:none;background:none;color:var(--dm);border-bottom:2px solid transparent;margin-bottom:-1px;transition:.2s}\n"
".tt2.on{color:var(--teal);border-bottom-color:var(--teal)}\n"
".tl{max-height:350px;overflow-y:auto}\n"
".ti{padding:10px 0;border-bottom:1px solid var(--line);display:flex;flex-direction:column;gap:4px}\n"
".ti:last-child{border:none}\n"
".ti-top{display:flex;justify-content:space-between;align-items:center}\n"
".ti-sym{font-family:var(--fd);font-size:13px;font-weight:700}\n"
".ti-net{font-family:var(--fd);font-size:15px;font-weight:700}\n"
".ti-meta{font-size:9px;color:var(--dm)}\n"
".badge-long{background:rgba(74,222,128,.15);color:var(--pos);padding:2px 7px;border-radius:4px;font-size:8px;font-weight:700}\n"
".badge-short{background:rgba(248,113,113,.15);color:var(--neg);padding:2px 7px;border-radius:4px;font-size:8px;font-weight:700}\n"
".empty{padding:30px;text-align:center;color:var(--dm);font-size:11px}\n"

/* ── MAE/MFE ── */
"/* MFE */\n"
"#maemfe-panel{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".mf-title{font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--d2);margin-bottom:12px}\n"
".mf-row{display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-bottom:1px solid var(--line);font-size:11px}\n"
".mf-row:last-child{border:none}\n"
".mf-bars{display:flex;flex-direction:column;gap:5px;margin-top:12px}\n"
".mf-bar-row{display:flex;align-items:center;gap:8px;font-size:9px}\n"
".mf-bar-wrap{flex:1;height:8px;background:var(--line);border-radius:4px;overflow:hidden}\n"
".mf-mae-fill{height:100%;background:var(--coral);border-radius:4px}\n"
".mf-mfe-fill{height:100%;background:var(--teal);border-radius:4px}\n"
".mf-net-fill{height:100%;background:var(--gold);border-radius:4px}\n"
".mf-bar-lbl{color:var(--dm);width:60px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\n"

/* ── PERIOD CARD ── */
"/* Period card */\n"
"#pr{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-bottom:0}\n"
".pc{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 12px;cursor:pointer;transition:.2s;text-align:center}\n"
".pc.on{border-color:var(--teal);background:var(--tealg);box-shadow:0 0 20px rgba(45,212,191,.15)}\n"
".pc:hover:not(.on){border-color:var(--line2)}\n"
".pl{font-size:9px;font-weight:700;letter-spacing:.5px;color:var(--dm);margin-bottom:6px;text-transform:uppercase}\n"
".pv{font-family:var(--fd);font-size:20px;font-weight:700;line-height:1;margin-bottom:2px}\n"
".pp{font-size:9px;color:var(--dm)}.pw{font-size:9px}\n"

/* ── CUSTOM MODAL ── */
"input[type=date]{color-scheme:dark}\n"
"input[type=date]:focus{border-color:var(--teal)!important;outline:none}\n"

/* ── ANALYTICS STYLES ── */
"/* Analytics */\n"
".an-section{margin-bottom:24px}\n"
".an-hdr{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}\n"
".an-title{font-family:var(--fd);font-size:18px;font-weight:700;color:var(--tx)}\n"
".an-sub{font-size:10px;color:var(--dm)}\n"
".cal-wrap{background:var(--p2);border-radius:10px;overflow:hidden}\n"
".cal-nav{display:flex;align-items:center;justify-content:space-between;padding:14px 18px;border-bottom:1px solid var(--line)}\n"
".cal-title{font-family:var(--fd);font-size:20px;color:var(--tx)}\n"
".cal-nav-btns{display:flex;gap:6px}\n"
".cnb{width:30px;height:30px;border-radius:6px;border:1px solid var(--line);background:var(--panel);color:var(--d2);cursor:pointer;font-size:14px;display:flex;align-items:center;justify-content:center}\n"
".cnb:hover{border-color:var(--teal);color:var(--teal)}\n"
".cal-view-btns{display:flex;gap:4px}\n"
".cvb{padding:5px 14px;border-radius:6px;font-size:10px;font-weight:700;cursor:pointer;border:1px solid var(--line);background:var(--panel);color:var(--dm);transition:.15s}\n"
".cvb.on{background:var(--teal);border-color:var(--teal);color:#0d1117}\n"
".cal-grid{display:grid;grid-template-columns:repeat(7,1fr)}\n"
".cal-dow{padding:8px;font-size:9px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--dm);text-align:right;border-bottom:1px solid var(--line)}\n"
".cal-cell{min-height:80px;padding:7px 9px;border-right:1px solid var(--line);border-bottom:1px solid var(--line);transition:.15s}\n"
".cal-cell.has-profit{border-top:2px solid var(--pos)}.cal-cell.has-loss{border-top:2px solid var(--neg)}\n"
".cal-cell.other-month{opacity:.3}.cal-cell.today{background:var(--tealg)}\n"
".cal-day{font-size:10px;color:var(--dm);text-align:right;margin-bottom:4px}\n"
".cal-trades{font-size:8px;color:var(--dm)}\n"
".cal-pnl{font-family:var(--fd);font-size:14px;font-weight:700}\n"
".cal-pnl.pos{color:var(--pos)}.cal-pnl.neg{color:var(--neg)}\n"
".cal-year-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;padding:14px}\n"
".cal-month-card{background:var(--panel);border-radius:8px;padding:12px;cursor:pointer;border:1px solid var(--line);transition:.15s}\n"
".cal-month-card:hover{border-color:var(--teal)}\n"
".cmh{font-size:10px;font-weight:700;color:var(--d2);margin-bottom:6px}\n"
".cmp{font-family:var(--fd);font-size:18px;font-weight:700}\n"
".cmt{font-size:9px;color:var(--dm);margin-top:2px}\n"
".side-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}\n"
".side-card{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px}\n"
".side-title{font-size:9px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--dm);margin-bottom:12px}\n"
".side-donut{display:flex;align-items:center;gap:14px}\n"
".donut-svg{flex-shrink:0}\n"
".donut-legend{display:flex;flex-direction:column;gap:6px}\n"
".dl-item{display:flex;align-items:center;gap:7px;font-size:11px}\n"
".dl-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}\n"
".dl-val{font-family:var(--fm);margin-left:auto;font-size:10px}\n"
".side-stats{margin-top:10px;display:flex;flex-direction:column;gap:4px}\n"
".ss-row{display:flex;justify-content:space-between;font-size:10px;padding:4px 0;border-bottom:1px solid var(--line)}\n"
".ss-row:last-child{border:none}\n"
".ss-k{color:var(--dm)}.ss-v{font-family:var(--fm)}\n"
".ss-v.pos{color:var(--pos)}.ss-v.neg{color:var(--neg)}\n"
".sess-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}\n"
".sess-card{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:16px;position:relative;overflow:hidden}\n"
".sess-card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px;border-radius:2px 2px 0 0}\n"
".sess-card.asian::before{background:linear-gradient(90deg,var(--gold),var(--gold2))}\n"
".sess-card.london::before{background:linear-gradient(90deg,var(--sky),var(--sky2))}\n"
".sess-card.ny::before{background:linear-gradient(90deg,var(--teal),var(--teal2))}\n"
".sess-card.oos::before{background:linear-gradient(90deg,var(--dm),var(--line))}\n"
".sess-name{font-size:9px;font-weight:700;letter-spacing:1px;color:var(--dm);margin-bottom:8px;text-transform:uppercase}\n"
".sess-wr{font-family:var(--fd);font-size:30px;font-weight:700;line-height:1;margin-bottom:2px}\n"
".sess-wr-lbl{font-size:8px;color:var(--dm);letter-spacing:.8px;margin-bottom:10px}\n"
".sess-rows{display:flex;flex-direction:column;gap:4px}\n"
".sr{display:flex;justify-content:space-between;font-size:10px}\n"
".sr-k{color:var(--dm)}.sr-v{font-family:var(--fm)}\n"
".sess-bar{height:3px;background:var(--line);border-radius:2px;margin-top:10px;overflow:hidden}\n"
".sess-bar-fill{height:100%;border-radius:2px;transition:.5s width}\n"
".cr{display:flex;flex-direction:column;gap:3px;margin-top:8px;padding-top:8px;border-top:1px solid var(--line)}\n"
".cr-row{display:flex;justify-content:space-between;align-items:center;font-size:10px;padding:1px 0}\n"
".cr-lbl{color:var(--dm);font-size:9px;letter-spacing:.3px}\n"
".cr-val{font-family:var(--fm);font-weight:600;color:var(--d1);font-size:11px}\n"
".cr-val.pos{color:var(--pos)}.cr-val.neg{color:var(--neg)}\n"
"/* Misc */\n"
".pos{color:var(--pos)}.neg{color:var(--neg)}\n"
"@keyframes fu{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}\n"
".th-mode .rank-title-hero,.th-mode .dim-name{font-family:'Sarabun',var(--fd)!important;font-size:18px!important}\n"
"</style></head><body>\n"
"<script>\n"
+inlineData+
"</script>\n"
;}


//+------------------------------------------------------------------+
