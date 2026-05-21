/* ─── Supabase integration layer ─────────────────────────────────────────
   Initialises the client and provides async data loaders.
   Falls back gracefully to mock data if Supabase is not yet configured.
   ─────────────────────────────────────────────────────────────────────── */
(function initSupabase() {
  var configured = window.SUPABASE_URL && !window.SUPABASE_URL.includes("YOUR_PROJECT");
  if (!configured || typeof window.supabase === "undefined") {
    console.info("[Ledger] Supabase not configured — using mock data");
    window.sbClient = null;
    return;
  }
  window.sbClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON, {
    auth: { persistSession: true, autoRefreshToken: true }
  });
  console.info("[Ledger] Supabase client ready ✓");
})();

/* ─── Helpers ─────────────────────────────────────────────────────────── */
function _countryFlag(code) {
  var map = { TH:"🇹🇭", IN:"🇮🇳", SG:"🇸🇬", JP:"🇯🇵", GB:"🇬🇧", IT:"🇮🇹", US:"🇺🇸", DE:"🇩🇪", CN:"🇨🇳", AU:"🇦🇺", MY:"🇲🇾", ID:"🇮🇩", PH:"🇵🇭" };
  return map[(code||"").toUpperCase()] || "🌐";
}

function _hashSeed(str) {
  var h = 5381;
  for (var i = 0; i < str.length; i++) h = ((h << 5) + h) + str.charCodeAt(i);
  return Math.abs(h >>> 0) % 99991 + 1;
}

function _maskAccount(acc) {
  if (!acc) return "N/A";
  var s = acc.toString().replace(/\D/g, "");
  if (s.length < 6) return s;
  return s.slice(0, 5) + "***" + s.slice(-2);
}

/* ─── Load leaderboard (all profiles + period stats) ─────────────────── */
async function loadLeaderboard(period) {
  if (!window.sbClient) return null;
  var periodKey = { today:"today", week:"week", lastweek:"lastweek", month:"month", alltime:"alltime" }[period] || "alltime";

  var [profRes, statRes] = await Promise.all([
    window.sbClient.from("profiles").select("id, alias, mt5_account, country"),
    window.sbClient.from("account_stats").select("*").eq("period", periodKey)
  ]);

  var profiles = profRes.data;
  if (!profiles || !profiles.length) return null;
  var stats = statRes.data || [];

  return profiles.map(function(p) {
    var s = stats.find(function(st) { return st.user_id === p.id; }) || {};
    return {
      username:       p.alias,
      handle:         "@" + p.alias.toLowerCase().replace(/[^a-z0-9]/g, "_"),
      account:        _maskAccount(p.mt5_account),
      country:        p.country || "TH",
      flag:           _countryFlag(p.country),
      pct:            +(s.pct_return      || 0),
      pnl:            +(s.net_pnl         || 0),
      startBal:       +(s.start_balance   || 10000),
      winRate:        +(s.win_rate        || 50),
      trades:         +(s.trades_count    || 0),
      profitFactor:   +(s.profit_factor   || 1.0),
      recoveryFactor: +(s.recovery_factor || 1.0),
      maxDD:          +(s.max_dd_pct      || 5),
      maxDDUsd:       +(s.max_dd_usd      || 0),
      avgWin:         +(s.avg_win         || 100),
      avgLoss:        +(s.avg_loss        || 80),
      maxConsWin:     +(s.max_cons_win    || 3),
      maxConsLoss:    +(s.max_cons_loss   || 3),
      bestTrade:      +(s.best_trade      || 0),
      worstTrade:     +(s.worst_trade     || 0),
      rankPrev:       99,
      seed:           _hashSeed(p.id),
      _userId:        p.id,
      tier:           "diamond",   // overridden by rankTraders()
    };
  });
}

/* ─── Load trade history for one user ────────────────────────────────── */
async function loadTradeHistory(userId) {
  if (!window.sbClient) return null;
  var res = await window.sbClient
    .from("trades")
    .select("*")
    .eq("user_id", userId)
    .order("close_time", { ascending: false })
    .limit(200);
  if (res.error || !res.data) return null;
  var cum = 0;
  return res.data.map(function(t) {
    cum += (t.pnl || 0);
    return {
      id:         t.ticket || t.id,
      symbol:     t.symbol,
      side:       t.side,
      lots:       t.lots,
      pnl:        +(t.pnl || 0),
      cum:        +cum.toFixed(2),
      open:       t.open_time  ? new Date(t.open_time)  : null,
      close:      t.close_time ? new Date(t.close_time) : null,
      dur:        t.duration_min,
      openPrice:  t.open_price,
      closePrice: t.close_price,
    };
  });
}

/* ─── Load equity snapshots for chart ────────────────────────────────── */
async function loadEquityCurve(userId) {
  if (!window.sbClient) return null;
  var res = await window.sbClient
    .from("equity_snapshots")
    .select("balance, snapshot_time")
    .eq("user_id", userId)
    .order("snapshot_time", { ascending: true })
    .limit(60);
  if (res.error || !res.data || !res.data.length) return null;
  return res.data.map(function(e) { return +e.balance; });
}

/* ─── Get own API token (shown in dashboard for EA setup) ────────────── */
async function getMyApiToken() {
  if (!window.sbClient) return null;
  var { data: { session } } = await window.sbClient.auth.getSession();
  if (!session) return null;
  var res = await window.sbClient
    .from("api_tokens")
    .select("token, label, created_at")
    .eq("user_id", session.user.id)
    .order("created_at", { ascending: true })
    .limit(1)
    .single();
  return res.data ? res.data.token : null;
}

window.loadLeaderboard  = loadLeaderboard;
window.loadTradeHistory = loadTradeHistory;
window.loadEquityCurve  = loadEquityCurve;
window.getMyApiToken    = getMyApiToken;
window._maskAccount     = _maskAccount;
