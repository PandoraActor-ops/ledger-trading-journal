/* ============================================================
   Mock data — Top traders & their stats
   ============================================================ */

// Seeded random for reproducibility
function mulberry32(a) {
  return function() {
    let t = (a += 0x6D2B79F5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rng = mulberry32(13);
const rand = (min, max) => min + rng() * (max - min);
const randi = (min, max) => Math.floor(rand(min, max + 1));

function genEquityCurve(startBal, growthPct, points, volatility, seed) {
  const r = mulberry32(seed);
  const target = startBal * (1 + growthPct / 100);
  const arr = [startBal];
  for (let i = 1; i < points; i++) {
    const drift = (target - arr[i - 1]) / (points - i);
    const noise = (r() - 0.5) * startBal * volatility;
    arr.push(Math.max(arr[i - 1] + drift + noise, startBal * 0.6));
  }
  arr[arr.length - 1] = target;
  return arr;
}

function genTrades(count, winRate, avgWin, avgLoss, seed, startDate) {
  const r = mulberry32(seed);
  const symbols = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "BTCUSD", "USOIL", "US30", "NAS100"];
  const trades = [];
  let cum = 0;
  let d = new Date(startDate);
  for (let i = 0; i < count; i++) {
    const win = r() < winRate / 100;
    const sym = symbols[Math.floor(r() * symbols.length)];
    const side = r() > 0.5 ? "buy" : "sell";
    const lots = +(0.05 + r() * 0.95).toFixed(2);
    const pnl = win
      ? +(avgWin * (0.4 + r() * 1.6)).toFixed(2)
      : -+(avgLoss * (0.4 + r() * 1.6)).toFixed(2);
    cum += pnl;
    d = new Date(d.getTime() + (1 + r() * 18) * 3600 * 1000);
    const dur = Math.floor(20 + r() * 600); // minutes
    trades.push({
      id: 10000 + i,
      symbol: sym,
      side,
      lots,
      pnl: +pnl.toFixed(2),
      cum: +cum.toFixed(2),
      open: new Date(d.getTime() - dur * 60000),
      close: new Date(d),
      dur,
      openPrice: +(1 + r() * 2000).toFixed(2),
      closePrice: +(1 + r() * 2000).toFixed(2),
    });
  }
  return trades.reverse();
}

const TRADERS = [
  {
    username: "Krittapas.W",
    handle: "@yodphet",
    account: "82910***74",
    country: "TH",
    flag: "🇹🇭",
    tier: "diamond",
    pct: 187.42,
    pnl: 18742.55,
    startBal: 10000,
    winRate: 71.2,
    trades: 184,
    profitFactor: 3.42,
    recoveryFactor: 4.8,
    maxDD: 6.2,
    maxDDUsd: 720.40,
    avgWin: 286.40,
    avgLoss: 124.10,
    maxConsWin: 11,
    maxConsLoss: 3,
    bestTrade: 1820.50,
    worstTrade: -540.20,
    rankPrev: 2,
    seed: 11,
  },
  {
    username: "Atharva K.",
    handle: "@atharva_fx",
    account: "55142***02",
    country: "IN",
    flag: "🇮🇳",
    tier: "diamond",
    pct: 142.08,
    pnl: 14208.10,
    startBal: 10000,
    winRate: 64.8,
    trades: 221,
    profitFactor: 2.81,
    recoveryFactor: 3.6,
    maxDD: 8.4,
    maxDDUsd: 1180.00,
    avgWin: 198.50,
    avgLoss: 102.30,
    maxConsWin: 9,
    maxConsLoss: 4,
    bestTrade: 1240.00,
    worstTrade: -420.00,
    rankPrev: 1,
    seed: 22,
  },
  {
    username: "Sirikarn P.",
    handle: "@kiki_trades",
    account: "73801***19",
    country: "TH",
    flag: "🇹🇭",
    tier: "platinum",
    pct: 118.65,
    pnl: 11865.20,
    startBal: 10000,
    winRate: 68.3,
    trades: 142,
    profitFactor: 2.94,
    recoveryFactor: 3.9,
    maxDD: 5.8,
    maxDDUsd: 680.00,
    avgWin: 220.10,
    avgLoss: 96.40,
    maxConsWin: 8,
    maxConsLoss: 2,
    bestTrade: 1410.40,
    worstTrade: -380.20,
    rankPrev: 4,
    seed: 33,
  },
  {
    username: "Daniel Chen",
    handle: "@dchen.eth",
    account: "21456***88",
    country: "SG",
    flag: "🇸🇬",
    tier: "platinum",
    pct: 96.30,
    pnl: 9630.45,
    startBal: 10000,
    winRate: 59.1,
    trades: 312,
    profitFactor: 2.21,
    recoveryFactor: 2.7,
    maxDD: 11.2,
    maxDDUsd: 1620.00,
    avgWin: 156.20,
    avgLoss: 84.80,
    maxConsWin: 7,
    maxConsLoss: 5,
    bestTrade: 980.00,
    worstTrade: -460.10,
    rankPrev: 3,
    seed: 44,
  },
  {
    username: "Phongsak J.",
    handle: "@phong.scalp",
    account: "68920***41",
    country: "TH",
    flag: "🇹🇭",
    tier: "gold",
    pct: 82.40,
    pnl: 8240.10,
    startBal: 10000,
    winRate: 73.5,
    trades: 408,
    profitFactor: 2.42,
    recoveryFactor: 3.1,
    maxDD: 7.4,
    maxDDUsd: 920.00,
    avgWin: 96.80,
    avgLoss: 62.10,
    maxConsWin: 14,
    maxConsLoss: 3,
    bestTrade: 480.00,
    worstTrade: -210.00,
    rankPrev: 5,
    seed: 55,
  },
  {
    username: "Hayato Mori",
    handle: "@hayato.jp",
    account: "44781***07",
    country: "JP",
    flag: "🇯🇵",
    tier: "gold",
    pct: 71.20,
    pnl: 7120.80,
    startBal: 10000,
    winRate: 62.0,
    trades: 168,
    profitFactor: 2.18,
    recoveryFactor: 2.8,
    maxDD: 9.1,
    maxDDUsd: 1080.00,
    avgWin: 168.20,
    avgLoss: 88.40,
    maxConsWin: 6,
    maxConsLoss: 4,
    bestTrade: 920.00,
    worstTrade: -380.00,
    rankPrev: 8,
    seed: 66,
  },
  {
    username: "Natthapong R.",
    handle: "@nat_swing",
    account: "92011***33",
    country: "TH",
    flag: "🇹🇭",
    tier: "gold",
    pct: 64.85,
    pnl: 6485.30,
    startBal: 10000,
    winRate: 55.8,
    trades: 96,
    profitFactor: 1.92,
    recoveryFactor: 2.4,
    maxDD: 10.3,
    maxDDUsd: 1240.00,
    avgWin: 248.60,
    avgLoss: 142.20,
    maxConsWin: 5,
    maxConsLoss: 4,
    bestTrade: 1180.40,
    worstTrade: -520.00,
    rankPrev: 6,
    seed: 77,
  },
  {
    username: "Emma Sterling",
    handle: "@emma.fx",
    account: "30471***96",
    country: "GB",
    flag: "🇬🇧",
    tier: "silver",
    pct: 52.10,
    pnl: 5210.60,
    startBal: 10000,
    winRate: 57.2,
    trades: 142,
    profitFactor: 1.74,
    recoveryFactor: 2.1,
    maxDD: 12.8,
    maxDDUsd: 1480.00,
    avgWin: 132.40,
    avgLoss: 78.20,
    maxConsWin: 6,
    maxConsLoss: 5,
    bestTrade: 740.00,
    worstTrade: -310.00,
    rankPrev: 7,
    seed: 88,
  },
  {
    username: "Wattana T.",
    handle: "@watt.options",
    account: "11829***54",
    country: "TH",
    flag: "🇹🇭",
    tier: "silver",
    pct: 41.30,
    pnl: 4130.00,
    startBal: 10000,
    winRate: 60.4,
    trades: 178,
    profitFactor: 1.68,
    recoveryFactor: 1.9,
    maxDD: 13.4,
    maxDDUsd: 1620.00,
    avgWin: 108.20,
    avgLoss: 72.10,
    maxConsWin: 5,
    maxConsLoss: 6,
    bestTrade: 540.00,
    worstTrade: -340.00,
    rankPrev: 9,
    seed: 99,
  },
  {
    username: "Marco Rinaldi",
    handle: "@marco.rin",
    account: "75630***82",
    country: "IT",
    flag: "🇮🇹",
    tier: "silver",
    pct: 34.65,
    pnl: 3465.20,
    startBal: 10000,
    winRate: 52.4,
    trades: 124,
    profitFactor: 1.52,
    recoveryFactor: 1.7,
    maxDD: 14.6,
    maxDDUsd: 1820.00,
    avgWin: 142.20,
    avgLoss: 96.40,
    maxConsWin: 4,
    maxConsLoss: 5,
    bestTrade: 680.00,
    worstTrade: -420.00,
    rankPrev: 10,
    seed: 111,
  },
];

// Enrich each with equity curve, sparkline, monthly, trades
TRADERS.forEach((t, idx) => {
  t.rank = idx + 1;
  t.rankDelta = t.rankPrev - t.rank;
  // Reassign tier based on new gemstone ranking system
  t.tier = (window.TIER_BY_RANK && window.TIER_BY_RANK[t.rank]) || t.tier;
  t.equityCurve = genEquityCurve(t.startBal, t.pct, 60, 0.018, t.seed);
  t.sparkline = genEquityCurve(t.startBal, t.pct, 24, 0.025, t.seed + 1);
  t.tradeList = genTrades(20, t.winRate, t.avgWin, t.avgLoss, t.seed + 2, new Date(2026, 4, 1));
  // last 6 months
  const monthLabels = ["Dec", "Jan", "Feb", "Mar", "Apr", "May"];
  t.monthly = monthLabels.map((m, i) => {
    const r = mulberry32(t.seed + 100 + i);
    const sign = r() > 0.25 ? 1 : -1;
    const amt = sign * (t.pnl / 6) * (0.4 + r() * 1.6);
    return { month: m, pnl: +amt.toFixed(2) };
  });
  // recent streak (last 12 trades win/loss)
  t.streak = [];
  const r = mulberry32(t.seed + 300);
  for (let i = 0; i < 12; i++) t.streak.push(r() * 100 < t.winRate ? "w" : "l");
});

// Make a logged-in user (after login flow). Use trader #3 by default.
const ME = {
  ...TRADERS[2], // Sirikarn
  username: "Sirikarn P.",
  isMe: true,
};

window.TRADERS = TRADERS;
window.ME = ME;
