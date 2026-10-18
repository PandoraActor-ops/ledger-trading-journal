/* ─── Live trade data → dashboard visuals ────────────────────────────────
   Replaces the generated equity curve / sparkline / P&L bars / monthly /
   streak / trade history with values derived from the trader's real closed
   trades. If trades can't be loaded the mock visuals from app.jsx stay.
   All dates are bucketed in UTC.
   ─────────────────────────────────────────────────────────────────────── */
(function () {
  var CACHE_MS = 60 * 1000;
  var cache = {}; // userId → { at, promise }
  var MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

  function fetchTrades(userId) {
    var hit = cache[userId];
    if (hit && Date.now() - hit.at < CACHE_MS) return hit.promise;
    var promise = window.loadPerformanceTrades(userId).catch(function () { return null; });
    cache[userId] = { at: Date.now(), promise: promise };
    return promise;
  }

  // [from, to) in ms for a leaderboard period; null = no bound
  function periodRange(period) {
    var now = new Date();
    var dayStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    var DAY = 86400000;
    var weekStart = dayStart - ((now.getUTCDay() + 6) % 7) * DAY; // Monday
    if (period === "today")    return [dayStart, null];
    if (period === "week")     return [weekStart, null];
    if (period === "lastweek") return [weekStart - 7 * DAY, weekStart];
    if (period === "month")    return [Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1), null];
    return [null, null];
  }

  // Evenly pick `n` items, always keeping the last one
  function downsample(arr, n) {
    if (arr.length <= n) return arr.slice();
    var out = [];
    for (var i = 0; i < n; i++) out.push(arr[Math.round((i * (arr.length - 1)) / (n - 1))]);
    return out;
  }

  function monthLabel(d) { return MONTHS[d.getUTCMonth()]; }

  function axisLabels(times) {
    if (times.length < 2) return null;
    var first = times[0], last = times[times.length - 1];
    var spanDays = (last - first) / 86400000;
    return Array.from({ length: 6 }, function (_, i) {
      var d = new Date(first + ((last - first) * i) / 5);
      return spanDays > 60 ? monthLabel(d) : MONTHS[d.getUTCMonth()] + " " + d.getUTCDate();
    });
  }

  function normalise(tr, i) {
    var open = tr.open || tr.close;
    return {
      id: tr.id || "t" + i,
      symbol: tr.symbol, side: tr.side, lots: tr.lots, pnl: tr.pnl,
      open: open, close: tr.close,
      dur: Math.max(0, Math.round((tr.close - open) / 60000)),
      openPrice: tr.openPrice, closePrice: tr.closePrice,
    };
  }

  var DAY = 86400000, CAP = 99, MIN_EXC_TRADES = 5;

  // Summary stats from closed trades (oldest → newest), balance starting at startBal
  function computeStats(trades, startBal) {
    var wins = trades.filter(function (x) { return x.pnl > 0; });
    var losses = trades.filter(function (x) { return x.pnl < 0; });
    var grossWin = wins.reduce(function (s, x) { return s + x.pnl; }, 0);
    var grossLoss = -losses.reduce(function (s, x) { return s + x.pnl; }, 0);
    var net = grossWin - grossLoss;

    var bal = startBal, peak = startBal, ddUsd = 0, ddPct = 0;
    var curW = 0, curL = 0, maxW = 0, maxL = 0, best = 0, worst = 0;
    trades.forEach(function (x) {
      bal += x.pnl;
      if (bal > peak) peak = bal;
      var dd = peak - bal;
      if (dd > ddUsd) ddUsd = dd;
      if (peak > 0 && dd / peak * 100 > ddPct) ddPct = dd / peak * 100;
      if (x.pnl > 0) { curW++; curL = 0; } else if (x.pnl < 0) { curL++; curW = 0; } else { curW = curL = 0; }
      if (curW > maxW) maxW = curW;
      if (curL > maxL) maxL = curL;
      if (x.pnl > best) best = x.pnl;
      if (x.pnl < worst) worst = x.pnl;
    });

    // Execution quality from MFE/MAE (only trades that carry them)
    var exc = trades.filter(function (x) { return x.mfe != null && x.mae != null; });
    var sumMfe = exc.reduce(function (s, x) { return s + x.mfe; }, 0);
    var sumMae = exc.reduce(function (s, x) { return s + x.mae; }, 0);
    var sumExcPnl = exc.reduce(function (s, x) { return s + x.pnl; }, 0);
    var hasExc = exc.length >= MIN_EXC_TRADES && sumMfe > 0;

    return {
      tradeEff:       hasExc ? Math.max(0, Math.min(100, sumExcPnl / sumMfe * 100)) : null,
      maeRatio:       hasExc ? sumMae / sumMfe : null,
      pct:            startBal > 0 ? net / startBal * 100 : 0,
      pnl:            net,
      winRate:        trades.length ? wins.length / trades.length * 100 : 0,
      trades:         trades.length,
      profitFactor:   grossLoss > 0 ? Math.min(CAP, grossWin / grossLoss) : (grossWin > 0 ? CAP : 0),
      recoveryFactor: ddUsd > 0 ? Math.max(-CAP, Math.min(CAP, net / ddUsd)) : (net > 0 ? CAP : 0),
      maxDD:          ddPct,
      maxDDUsd:       ddUsd,
      avgWin:         wins.length ? grossWin / wins.length : 0,
      avgLoss:        losses.length ? grossLoss / losses.length : 0,
      maxConsWin:     maxW,
      maxConsLoss:    maxL,
      bestTrade:      best,
      worstTrade:     worst,
    };
  }

  // Length of the period window in days (alltime = span of the trades)
  function spanDays(range, trades) {
    var now = Date.now();
    if (range[0] != null) return Math.max(1, ((range[1] != null ? range[1] : now) - range[0]) / DAY);
    if (trades.length < 2) return 1;
    return Math.max(1, (trades[trades.length - 1].close - trades[0].close) / DAY);
  }

  window.enrichWithLiveTrades = async function (t, period) {
    if (!window.sbClient || !t._userId || !window.loadPerformanceTrades) return;
    var all = await fetchTrades(t._userId);
    if (!all) return; // keep mock visuals

    // ── Monthly: last 6 calendar months, independent of the period filter
    var now = new Date();
    t.monthly = Array.from({ length: 6 }, function (_, i) {
      var m = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (5 - i), 1));
      var next = Date.UTC(m.getUTCFullYear(), m.getUTCMonth() + 1, 1);
      var pnl = all.reduce(function (s, tr) {
        return tr.close >= m && tr.close < next ? s + tr.pnl : s;
      }, 0);
      return { month: monthLabel(m), pnl: +pnl.toFixed(2) };
    });

    // ── Streak: last 12 outcomes overall, oldest → newest
    t.streak = all.slice(-12).map(function (tr) { return tr.pnl > 0 ? "w" : "l"; });

    // ── Period-scoped: equity curve, sparkline, trade lists
    var range = periodRange(period);
    var inPeriod = all.filter(function (tr) {
      return (range[0] == null || tr.close >= range[0]) && (range[1] == null || tr.close < range[1]);
    });

    // ── Summary stats (drive the stat tiles, leaderboard and score)
    Object.assign(t, computeStats(inPeriod, t.startBal));
    t._live = true;
    t._spanDays = spanDays(range, inPeriod);

    var bal = t.startBal, points = [bal], times = [inPeriod.length ? inPeriod[0].close.getTime() : Date.now()];
    inPeriod.forEach(function (tr) {
      bal += tr.pnl;
      points.push(+bal.toFixed(2));
      times.push(tr.close.getTime());
    });
    if (points.length < 2) { points.push(bal); times.push(times[0]); }

    t.equityCurve  = downsample(points, 60);
    t.equityLabels = axisLabels(downsample(times, 60));
    t.sparkline    = downsample(points, 24);

    var cum = 0;
    var history = inPeriod.map(function (tr, i) {
      cum += tr.pnl;
      var n = normalise(tr, i);
      n.cum = +cum.toFixed(2);
      return n;
    }).reverse(); // newest first
    t.historyList = history;
    t.tradeList   = history.slice(0, 20);
  };
})();
