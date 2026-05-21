/* Personal Dashboard — 2 variations */

function Dashboard({ trader, variant, onOpenTrades, onOpenProfile, period, setPeriod, tierOverride }) {
  const t = trader;
  // Compute the user's actual score & tier for the current period
  const score = useMemo(() => window.computeScore(t, period || "month"), [t, period]);
  // Use override (from tweaks preview) when set, else derived from score
  const tierId = tierOverride || score.tier;
  const tierDef = (window.TIERS && window.TIERS[tierId]) || {};
  const themeStyle = {
    "--tier-primary": tierDef.primary,
    "--tier-accent": tierDef.accent,
    "--tier-tint": tierDef.tint,
    "--tier-ink": tierDef.ink,
    "--tier-accent-ink": tierDef.accentInk,
    "--tier-gradient": tierDef.gradient,
  };
  // Get period-current rank from rankTraders
  const currentRank = useMemo(() => {
    const ranked = window.rankTraders(window.TRADERS, period || "month");
    const idx = ranked.findIndex((x) => x.account === t.account);
    return idx >= 0 ? idx + 1 : t.rank;
  }, [t.account, period]);
  return (
    <div
      className={`page page-fade themed-dashboard ${variant === "B" ? "variant-b" : ""}`}
      style={themeStyle}
    >
      <div className="page-head">
        <div>
          <div className="kicker">My Performance</div>
          <h1 className="page-title">Welcome back, {t.username.split(" ")[0]}.</h1>
          <p className="page-subtitle">
            Account <span className="mono">{t.account}</span> · {t.country} · Connected via MT5.
            You're currently <strong>#{currentRank}</strong> on the global leaderboard
            for <strong>{periodLabel(period)}</strong>.
          </p>
        </div>
        <div style={{ display: "flex", gap: 12 }}>
          <PeriodBar value={period} onChange={setPeriod} />
        </div>
      </div>

      <TierHero trader={{ ...t, rank: currentRank }} tierDef={tierDef} score={score} />

      {variant === "A" ? <DashboardA trader={t} onOpenTrades={onOpenTrades} onOpenProfile={onOpenProfile} period={period} /> : <DashboardB trader={t} onOpenTrades={onOpenTrades} onOpenProfile={onOpenProfile} period={period} />}
    </div>
  );
}

function periodLabel(p) {
  return ({
    today: "Today",
    week: "This Week",
    lastweek: "Last Week",
    month: "This Month",
    alltime: "All Time",
    custom: "Custom range",
  })[p] || "This Month";
}

function TierHero({ trader, tierDef }) {
  const tiers = window.TIERS || {};
  // Order from lowest (rank 6 Obsidian) to highest (rank 1 Diamond) for the ladder
  const ordered = Object.values(tiers).sort((a, b) => b.rank - a.rank);
  const cur = tierDef.rank || 6;
  // Next tier = one notch better (smaller rank number with new numbering)
  const next = ordered.find((x) => x.rank === cur - 1);
  const progress = Math.min(0.96, Math.max(0.18,
    (trader.pct / 250) * 0.6 + (trader.winRate / 100) * 0.4
  ));
  return (
    <div className={`tier-hero is-${tierDef.id || "default"}`}>
      <div className="tier-hero-grid">
        <div className="tier-hero-left">
          <div className="kicker">Current Tier · T{tierDef.rank || "?"} of 6</div>
          <h2 className="tier-name">
            <em>{tierDef.name}</em>
          </h2>
          <div className="tier-desc">{tierDef.description}</div>
          <div className="tier-meta">
            <div>
              <span className="lbl">Members</span>
              <span className="val">{tierMemberCount(tierDef.id)}</span>
            </div>
            <div>
              <span className="lbl">Your % Return</span>
              <span className="val">+{trader.pct.toFixed(2)}%</span>
            </div>
            <div>
              <span className="lbl">Global Rank</span>
              <span className="val">#{trader.rank}</span>
            </div>
          </div>
        </div>
        <div className="tier-progress">
          <div className="row">
            <div>
              <div className="kicker" style={{ color: "rgba(255,255,255,0.55)" }}>Next tier</div>
              <div className="next">{next ? next.name : "Apex"}</div>
            </div>
            <div className="mono" style={{ fontSize: 13, color: "rgba(255,255,255,0.7)" }}>
              {Math.round(progress * 100)}%
            </div>
          </div>
          <div className="bar"><div style={{ width: `${progress * 100}%` }}></div></div>
          <div className="ladder">
            {ordered.map((tx) => (
              <div
                key={tx.id}
                className={`step ${tx.rank === cur ? "active" : tx.rank > cur ? "done" : ""}`}
                title={tx.name}
              >
                {tx.name.split(" ").map((s) => s[0]).join("")}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function tierMemberCount(id) {
  // mock counts inversely proportional to tier (higher tier = fewer members)
  const m = {
    diamond: 14,
    pallasite: 86,
    redberyl: 312,
    cobalt: 941,
    blackopal: 1284,
    obsidian: 1580,
  };
  return (m[id] || 0).toLocaleString();
}

// ----- Variation A: airy, hero equity curve, large stats
function DashboardA({ trader, onOpenTrades, onOpenProfile, period }) {
  const t = trader;
  return (
    <>
      {/* Hero stat row */}
      <div className="stat-grid">
        <Stat label="Net P&L" value={`+$${fmt(t.pnl, 2)}`} sub={<span className="pill gain">+{t.pct.toFixed(2)}%</span>} accent="gain" big animate={t.pnl} prefix="+$" decimals={2} />
        <Stat label="Win rate" value={`${t.winRate.toFixed(1)}%`} sub={`${Math.round(t.trades * t.winRate / 100)} wins / ${t.trades - Math.round(t.trades * t.winRate / 100)} losses`} animate={t.winRate} suffix="%" decimals={1} />
        <Stat label="Profit Factor" value={t.profitFactor.toFixed(2)} sub={`Recovery × ${t.recoveryFactor.toFixed(1)}`} animate={t.profitFactor} decimals={2} />
        <Stat label="Max Drawdown" value={`${t.maxDD.toFixed(1)}%`} sub={`−$${fmt(t.maxDDUsd, 0)}`} accent="loss" animate={t.maxDD} suffix="%" decimals={1} />
      </div>

      {/* Hero equity curve */}
      <div className="panel" style={{ marginBottom: 14 }}>
        <div className="panel-head">
          <div>
            <h3>Equity Curve</h3>
            <div style={{ color: "var(--ink-3)", fontSize: 13, marginTop: 2 }}>
              Balance growth over the last 60 trading sessions
            </div>
          </div>
          <div style={{ display: "flex", gap: 14, alignItems: "baseline" }}>
            <span className="kicker">Current balance</span>
            <span className="tabular serif" style={{ fontSize: 24 }}>
              ${fmt(t.startBal + t.pnl, 2)}
            </span>
          </div>
        </div>
        <EquityCurve data={t.equityCurve} height={260} />
      </div>

      {/* Two-column: P&L per trade + Streaks */}
      <div className="row-2" style={{ marginTop: 14 }}>
        <div className="panel">
          <div className="panel-head">
            <h3>P&L per trade</h3>
          </div>
          <PnLBars trades={t.tradeList} />
        </div>
        <div className="panel">
          <div className="panel-head">
            <h3>Risk profile</h3>
          </div>
          <RiskBlock trader={t} />
        </div>
      </div>

      {/* Monthly + Best/Worst */}
      <div className="row-2" style={{ marginTop: 14 }}>
        <div className="panel">
          <div className="panel-head">
            <h3>Monthly</h3>
          </div>
          <MonthlyBars data={t.monthly} />
        </div>
        <div className="panel">
          <div className="panel-head">
            <h3>Best &amp; Worst</h3>
          </div>
          <BestWorst trader={t} />
        </div>
      </div>

      {/* Performance by Session */}
      <div style={{ marginTop: 14 }}>
        <PerformanceBySession trader={t} period={period} />
      </div>

      {/* Performance Calendar */}
      <div style={{ marginTop: 14 }}>
        <PerformanceCalendar trader={t} period={period} />
      </div>

      {/* Composite score breakdown (moved below Monthly + Best/Worst) */}
      <div style={{ marginTop: 14 }}>
        <ScoreBreakdown trader={t} period={period} />
      </div>

      {/* CTA strip */}
      <div className="card flat" style={{ marginTop: 14, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="kicker">Trade history</div>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 24, letterSpacing: "-0.01em" }}>
            All {t.trades} closed positions
          </div>
        </div>
        <div style={{ display: "flex", gap: 10 }}>
          <button className="btn-ghost btn" onClick={onOpenProfile}>View public profile</button>
          <button className="btn" onClick={onOpenTrades}>Open trades →</button>
        </div>
      </div>
    </>
  );
}

// ----- Variation B: dense terminal-style, more data on screen
function DashboardB({ trader, onOpenTrades, onOpenProfile, period }) {
  const t = trader;
  return (
    <>
      <div className="stat-grid">
        <Stat label="Return" value={`+${t.pct.toFixed(2)}%`} accent="gain" animate={t.pct} prefix="+" suffix="%" decimals={2} />
        <Stat label="Net P&L" value={`+$${fmt(t.pnl, 0)}`} accent="gain" animate={t.pnl} prefix="+$" decimals={0} />
        <Stat label="Win rate" value={`${t.winRate.toFixed(1)}%`} animate={t.winRate} suffix="%" decimals={1} />
        <Stat label="PF" value={t.profitFactor.toFixed(2)} animate={t.profitFactor} decimals={2} />
        <Stat label="Max DD" value={`${t.maxDD.toFixed(1)}%`} accent="loss" animate={t.maxDD} suffix="%" decimals={1} />
        <Stat label="Trades" value={t.trades} animate={t.trades} decimals={0} />
      </div>

      <div className="row-2" style={{ marginTop: 14 }}>
        <div className="panel" style={{ gridColumn: "1 / 2" }}>
          <div className="panel-head">
            <h3>Equity Curve</h3>
            <div style={{ display: "flex", gap: 12 }}>
              <span className="kicker">Start ${fmt(t.startBal, 0)}</span>
              <span className="kicker" style={{ color: "var(--gain)" }}>Now ${fmt(t.startBal + t.pnl, 0)}</span>
            </div>
          </div>
          <EquityCurve data={t.equityCurve} height={220} />
        </div>
        <div className="panel">
          <div className="panel-head">
            <h3>Risk profile</h3>
          </div>
          <RiskBlock trader={t} compact />
        </div>
      </div>

      <div className="row-3" style={{ marginTop: 14 }}>
        <div className="panel">
          <div className="panel-head"><h3 style={{ fontSize: 18 }}>P&L per trade</h3></div>
          <PnLBars trades={t.tradeList.slice(0, 14)} />
        </div>
        <div className="panel">
          <div className="panel-head"><h3 style={{ fontSize: 18 }}>Monthly</h3></div>
          <MonthlyBars data={t.monthly} />
        </div>
        <div className="panel">
          <div className="panel-head"><h3 style={{ fontSize: 18 }}>Best & worst</h3></div>
          <BestWorst trader={t} />
        </div>
      </div>

      <div style={{ marginTop: 14 }}>
        <PerformanceBySession trader={t} period={period} />
      </div>
      <div style={{ marginTop: 14 }}>
        <PerformanceCalendar trader={t} period={period} />
      </div>

      {/* Composite score breakdown */}
      <div style={{ marginTop: 14 }}>
        <ScoreBreakdown trader={t} period={period} />
      </div>

      <div className="panel" style={{ marginTop: 14 }}>
        <div className="panel-head">
          <h3>Recent trades</h3>
          <button className="btn-ghost btn" onClick={onOpenTrades}>View all {t.trades} →</button>
        </div>
        <TradesMini trades={t.tradeList.slice(0, 6)} />
      </div>
    </>
  );
}

// ----- shared building pieces

function Stat({ label, value, sub, accent, big, animate, prefix = "", suffix = "", decimals = 0 }) {
  return (
    <div className="stat">
      <div className="label">{label}</div>
      <div className={`value ${accent || ""}`}>
        {animate !== undefined ? (
          <span>
            {prefix.startsWith("+") ? "+" : ""}
            {prefix.replace(/^\+/, "")}
            <CountUp value={Math.abs(animate)} decimals={decimals} suffix={suffix} duration={1400} />
          </span>
        ) : value}
      </div>
      {sub ? <div className="sub">{sub}</div> : null}
    </div>
  );
}

function RiskBlock({ trader, compact }) {
  const t = trader;
  const rows = [
    { label: "Avg Win", value: `+$${fmt(t.avgWin, 2)}`, c: "gain" },
    { label: "Avg Loss", value: `−$${fmt(t.avgLoss, 2)}`, c: "loss" },
    { label: "Max consecutive wins", value: t.maxConsWin },
    { label: "Max consecutive losses", value: t.maxConsLoss },
    { label: "Recovery factor", value: t.recoveryFactor.toFixed(2) + "×" },
  ];
  return (
    <div>
      <div style={{ marginBottom: 18 }}>
        <div className="kicker">Last 12 trades</div>
        <div style={{ marginTop: 6 }}>
          <Streak items={t.streak} />
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {rows.map((r, i) => (
          <div key={i} style={{ display: "flex", justifyContent: "space-between", paddingBottom: 8, borderBottom: i < rows.length - 1 ? "1px solid var(--line-2)" : "none" }}>
            <span style={{ color: "var(--ink-3)", fontSize: 13 }}>{r.label}</span>
            <span className={`tabular ${r.c === "gain" ? "" : ""}`} style={{ color: r.c === "gain" ? "var(--gain)" : r.c === "loss" ? "var(--loss)" : "var(--ink)", fontWeight: 500 }}>
              {r.value}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function BestWorst({ trader }) {
  const t = trader;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      <div style={{ padding: "14px 16px", background: "var(--gain-tint)", borderRadius: "var(--r)" }}>
        <div className="kicker" style={{ color: "var(--gain)" }}>Best trade</div>
        <div className="tabular" style={{ fontFamily: "var(--font-display)", fontSize: 30, color: "var(--gain)", marginTop: 4, lineHeight: 1 }}>
          +${fmt(t.bestTrade, 2)}
        </div>
        <div style={{ fontSize: 12, color: "var(--ink-3)", marginTop: 6 }}>
          XAUUSD · Buy · 2.4h · 0.48 lots
        </div>
      </div>
      <div style={{ padding: "14px 16px", background: "var(--loss-tint)", borderRadius: "var(--r)" }}>
        <div className="kicker" style={{ color: "var(--loss)" }}>Worst trade</div>
        <div className="tabular" style={{ fontFamily: "var(--font-display)", fontSize: 30, color: "var(--loss)", marginTop: 4, lineHeight: 1 }}>
          −${fmt(Math.abs(t.worstTrade), 2)}
        </div>
        <div style={{ fontSize: 12, color: "var(--ink-3)", marginTop: 6 }}>
          BTCUSD · Sell · 54m · 0.12 lots
        </div>
      </div>
    </div>
  );
}

function TradesMini({ trades }) {
  return (
    <table className="trades">
      <thead>
        <tr>
          <th>Symbol</th>
          <th>Side</th>
          <th style={{ textAlign: "right" }}>Lots</th>
          <th style={{ textAlign: "right" }}>P&L</th>
          <th style={{ textAlign: "right" }}>Closed</th>
        </tr>
      </thead>
      <tbody>
        {trades.map((tr) => (
          <tr key={tr.id}>
            <td><span className="mono">{tr.symbol}</span></td>
            <td><span className={`side ${tr.side}`}>{tr.side.toUpperCase()}</span></td>
            <td style={{ textAlign: "right" }}>{tr.lots.toFixed(2)}</td>
            <td style={{ textAlign: "right", color: tr.pnl >= 0 ? "var(--gain)" : "var(--loss)", fontWeight: 500 }}>
              {tr.pnl >= 0 ? "+" : "−"}${Math.abs(tr.pnl).toFixed(2)}
            </td>
            <td style={{ textAlign: "right", color: "var(--ink-3)" }}>
              {tr.close.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function fmt(n, d = 2) {
  return Math.abs(n).toLocaleString(undefined, { minimumFractionDigits: d, maximumFractionDigits: d });
}

Object.assign(window, { Dashboard, Stat, fmt });
