/* ============================================================
   Ranking & scoring — mirrors TradingJournalEA_v13.mq5 logic.

   Four dimensions:
     D1 Risk-Adjusted Performance  (weight 35%)  expectancy, profit_factor, sharpe
     D2 Consistency & Discipline   (weight 25%)  monthly_wr, coeff_var, sample_size
     D3 Capital Preservation       (weight 25%)  max_dd_pct, calmar_ratio, max_consec_loss
     D4 Execution Quality          (weight 15%)  trade_efficiency, mae_net_ratio

   Per-metric ScoreMetric:
     val >= elite        -> 100
     val >= standard     -> 60
     val >= fail         -> 30
     else                -> 0
   (flipped when lowerIsBetter)

   Dimension score = mean of its metric scores.
   Composite       = 0.35*D1 + 0.25*D2 + 0.25*D3 + 0.15*D4   (0..100)
   ============================================================ */

function scoreMetric(val, elite, standard, fail, lowerIsBetter = false) {
  if (lowerIsBetter) {
    if (val <= elite)    return 100;
    if (val <= standard) return 60;
    if (val <= fail)     return 30;
    return 0;
  }
  if (val >= elite)    return 100;
  if (val >= standard) return 60;
  if (val >= fail)     return 30;
  return 0;
}

function levelOf(score) {
  if (score >= 90) return "ELITE";
  if (score >= 60) return "STANDARD";
  if (score >= 30) return "CAUTION";
  return "FAIL";
}

// Map composite score (0-100) onto our gemstone tier system.
// New numbering: T1 Obsidian (highest) → T6 Diamond (lowest)
function tierFromComposite(c) {
  if (c >= 90) return "obsidian";
  if (c >= 75) return "blackopal";
  if (c >= 60) return "cobalt";
  if (c >= 45) return "redberyl";
  if (c >= 30) return "pallasite";
  return "diamond";
}

// Period multiplier — scales stats per period so rankings shift when user toggles period.
// Each trader has a per-period seed in genPeriodSeed.
const PERIODS = ["today", "week", "lastweek", "month", "alltime", "custom"];

function periodFactor(period) {
  return {
    today:    { pctScale: 0.04, tradesScale: 0.03 },
    week:     { pctScale: 0.25, tradesScale: 0.22 },
    lastweek: { pctScale: 0.18, tradesScale: 0.20 },
    month:    { pctScale: 1.00, tradesScale: 1.00 },
    alltime:  { pctScale: 4.20, tradesScale: 4.80 },
    custom:   { pctScale: 0.60, tradesScale: 0.55 },
  }[period] || { pctScale: 1.0, tradesScale: 1.0 };
}

// Generate slight variance per (trader, period) so different periods produce
// different orderings — without losing the broad shape of the data.
function periodNoise(traderSeed, period, key) {
  let h = traderSeed * 31 + period.length * 17;
  for (let i = 0; i < key.length; i++) h = (h * 33 + key.charCodeAt(i)) >>> 0;
  // 0..1
  const r = ((h ^ (h >> 13)) >>> 0) / 4294967296;
  // ±0.25
  return 0.75 + r * 0.5;
}

// Compute the full BehaviorGrid + composite for one trader in one period.
function computeScore(trader, period) {
  const pf = periodFactor(period);
  const n = (key) => periodNoise(trader.seed, period, key);

  // Period-scaled raw stats (mock — real impl would slice trade history per period)
  const pct        = trader.pct        * pf.pctScale * n("pct");
  const trades     = Math.max(1, Math.round(trader.trades * pf.tradesScale * n("trades")));
  const winRate    = clamp(trader.winRate * n("winrate"), 10, 90);
  const profitFactor = Math.max(0.1, trader.profitFactor * n("pf"));
  const maxDDpct   = Math.max(0.1, trader.maxDD * n("dd"));
  const avgWin     = trader.avgWin * n("aw");
  const avgLoss    = trader.avgLoss * n("al");
  const maxConsLoss = Math.max(1, Math.round(trader.maxConsLoss * n("mcl")));

  // ── D1: Risk-Adjusted Performance ──
  const expectancy   = (winRate / 100) * avgWin - (1 - winRate / 100) * avgLoss;
  // Sharpe approx: scaled from win rate × profit factor heuristic
  const sharpeApprox = (winRate / 50 - 1) * Math.sqrt(trades) * (profitFactor / 2);
  const d1_e  = scoreMetric(expectancy, 50, 10, -10);
  const d1_pf = scoreMetric(profitFactor, 2.0, 1.3, 1.0);
  const d1_sh = scoreMetric(sharpeApprox, 1.5, 0.5, 0.0);
  const d1Score = Math.round((d1_e + d1_pf + d1_sh) / 3);

  // ── D2: Consistency & Discipline ──
  const monthlyWR  = clamp(winRate + (n("mwr") - 1) * 20, 20, 95);
  const coeffVar   = Math.max(0.2, 3 - (winRate / 100) * 2 + (n("cv") - 1) * 2);
  const sampleSize = trades;
  const d2_mwr = scoreMetric(monthlyWR, 70, 50, 30);
  const d2_cv  = scoreMetric(coeffVar, 1.5, 3.0, 5.0, true);
  const d2_ss  = scoreMetric(sampleSize, 50, 20, 10);
  const d2Score = Math.round((d2_mwr + d2_cv + d2_ss) / 3);

  // ── D3: Capital Preservation ──
  const annRetPct  = pct * (pf.pctScale === 1 ? 12 : 1 / Math.max(0.05, pf.pctScale));
  const calmar     = annRetPct / Math.max(1, maxDDpct);
  const d3_dd  = scoreMetric(maxDDpct, 5, 15, 25, true);
  const d3_cal = scoreMetric(calmar, 3, 1, 0.5);
  const d3_cl  = scoreMetric(maxConsLoss, 3, 6, 10, true);
  const d3Score = Math.round((d3_dd + d3_cal + d3_cl) / 3);

  // ── D4: Execution Quality ──
  // Trade efficiency = net captured / max favorable excursion %
  const tradeEff = clamp(40 + (profitFactor - 1) * 25 + (n("eff") - 1) * 20, 5, 90);
  const maeNet   = Math.max(0.1, 1.5 - (winRate / 100) + (n("mae") - 1) * 0.6);
  const d4_eff = scoreMetric(tradeEff, 60, 30, 10);
  const d4_mae = scoreMetric(maeNet, 0.5, 1.0, 2.0, true);
  const d4Score = Math.round((d4_eff + d4_mae) / 2);

  const composite = d1Score * 0.35 + d2Score * 0.25 + d3Score * 0.25 + d4Score * 0.15;

  // Rank assignment (military titles from MQL5)
  let stars, rankTitle, rankCode;
  if (composite >= 90)      { stars = 5; rankTitle = "Supreme Commander"; rankCode = "SUPREME"; }
  else if (composite >= 75) { stars = 4; rankTitle = "Field Marshal";     rankCode = "MARSHAL"; }
  else if (composite >= 60) { stars = 3; rankTitle = "General";           rankCode = "GENERAL"; }
  else if (composite >= 45) { stars = 2; rankTitle = "Colonel";           rankCode = "COLONEL"; }
  else if (composite >= 30) { stars = 1; rankTitle = "Major";             rankCode = "MAJOR"; }
  else                      { stars = 0; rankTitle = "Private";           rankCode = "PRIVATE"; }

  return {
    period,
    // raw stats used
    raw: { pct, trades, winRate, profitFactor, maxDDpct, expectancy, sharpeApprox,
           monthlyWR, coeffVar, sampleSize, calmar, maxConsLoss, tradeEff, maeNet },
    // sub-metric scores (per dimension)
    sub: {
      d1: [
        { key: "Expectancy",       value: expectancy.toFixed(2),     unit: "$",  score: d1_e,  elite: 50, std: 10 },
        { key: "Profit Factor",    value: profitFactor.toFixed(2),   unit: "×",  score: d1_pf, elite: 2.0, std: 1.3 },
        { key: "Sharpe (approx)",  value: sharpeApprox.toFixed(2),   unit: "",   score: d1_sh, elite: 1.5, std: 0.5 },
      ],
      d2: [
        { key: "Monthly Win Rate", value: monthlyWR.toFixed(1),      unit: "%",  score: d2_mwr, elite: 70, std: 50 },
        { key: "Coefficient of Var", value: coeffVar.toFixed(2),     unit: "",   score: d2_cv,  elite: 1.5, std: 3.0, lower: true },
        { key: "Sample Size",      value: sampleSize,                unit: " tr", score: d2_ss, elite: 50, std: 20 },
      ],
      d3: [
        { key: "Max Drawdown",     value: maxDDpct.toFixed(1),       unit: "%",  score: d3_dd,  elite: 5, std: 15, lower: true },
        { key: "Calmar Ratio",     value: calmar.toFixed(2),         unit: "",   score: d3_cal, elite: 3, std: 1 },
        { key: "Max Consec. Loss", value: maxConsLoss,               unit: "",   score: d3_cl,  elite: 3, std: 6, lower: true },
      ],
      d4: [
        { key: "Trade Efficiency", value: tradeEff.toFixed(1),       unit: "%",  score: d4_eff, elite: 60, std: 30 },
        { key: "MAE/Net Ratio",    value: maeNet.toFixed(2),         unit: "",   score: d4_mae, elite: 0.5, std: 1.0, lower: true },
      ],
    },
    // dimension scores
    dims: [
      { id: "d1", name: "Risk-Adjusted Performance", weight: 0.35, score: d1Score, level: levelOf(d1Score) },
      { id: "d2", name: "Consistency & Discipline",  weight: 0.25, score: d2Score, level: levelOf(d2Score) },
      { id: "d3", name: "Capital Preservation",      weight: 0.25, score: d3Score, level: levelOf(d3Score) },
      { id: "d4", name: "Execution Quality",         weight: 0.15, score: d4Score, level: levelOf(d4Score) },
    ],
    composite: +composite.toFixed(1),
    stars,
    rankTitle,
    rankCode,
    tier: tierFromComposite(composite),
  };
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

// Rank all traders for a period, returning sorted array with composite + tier injected.
function rankTraders(traders, period) {
  const scored = traders.map((t) => ({ ...t, _score: computeScore(t, period) }));
  scored.sort((a, b) => b._score.composite - a._score.composite);
  scored.forEach((t, i) => {
    t.rank = i + 1;
    t.rankDelta = t.rankPrev - t.rank;
    t.tier = t._score.tier;
  });
  return scored;
}

window.computeScore = computeScore;
window.rankTraders = rankTraders;
window.scoreMetric = scoreMetric;
window.levelOf = levelOf;
window.tierFromComposite = tierFromComposite;
