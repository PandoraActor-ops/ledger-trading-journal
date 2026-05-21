/* Public Profile — read-only view of a trader */

function Profile({ trader, onBack, onOpenTrades }) {
  const t = trader;
  return (
    <div className="page page-fade">
      <button className="btn-ghost btn" onClick={onBack} style={{ marginBottom: 8 }}>← Leaderboard</button>

      <div className="profile-header">
        <div className="profile-avatar">
          {t.username.split(" ").map((s) => s[0]).join("")}
        </div>
        <div className="profile-info" style={{ flex: 1 }}>
          <h1>{t.username}</h1>
          <div className="meta">
            <span>{t.country}</span>
            <span>·</span>
            <span>{t.handle}</span>
            <span>·</span>
            <span className="mono">{t.account}</span>
            <Tier tier={t.tier} />
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div className="kicker">Global rank</div>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 64, letterSpacing: "-0.04em", lineHeight: 1, marginTop: 4 }}>
            #{t.rank}
          </div>
          <div style={{ marginTop: 4 }}>
            <TrendArrow delta={t.rankDelta} /> <span style={{ color: "var(--ink-3)", fontSize: 12 }}>vs last week</span>
          </div>
        </div>
      </div>

      <div className="stat-grid">
        <Stat label="% Return" value={`+${t.pct.toFixed(2)}%`} accent="gain" animate={t.pct} prefix="+" suffix="%" decimals={2} sub={<>Net <span className="tabular">+${fmt(t.pnl, 0)}</span></>} />
        <Stat label="Win rate" value={`${t.winRate.toFixed(1)}%`} animate={t.winRate} suffix="%" decimals={1} sub={`${t.trades} trades`} />
        <Stat label="Profit factor" value={t.profitFactor.toFixed(2)} animate={t.profitFactor} decimals={2} sub={`Recovery × ${t.recoveryFactor.toFixed(1)}`} />
        <Stat label="Max Drawdown" value={`${t.maxDD.toFixed(1)}%`} accent="loss" animate={t.maxDD} suffix="%" decimals={1} sub={`−$${fmt(t.maxDDUsd, 0)}`} />
      </div>

      <ScoreBreakdown trader={t} period="month" />

      <div className="panel" style={{ marginBottom: 14 }}>
        <div className="panel-head">
          <div>
            <h3>Equity Curve</h3>
            <div style={{ color: "var(--ink-3)", fontSize: 13 }}>Last 60 sessions</div>
          </div>
          <span className="pill gain">+{t.pct.toFixed(2)}%</span>
        </div>
        <EquityCurve data={t.equityCurve} height={260} />
      </div>

      <div className="row-2" style={{ marginTop: 14 }}>
        <div className="panel">
          <div className="panel-head"><h3>Monthly performance</h3></div>
          <MonthlyBars data={t.monthly} />
        </div>
        <div className="panel">
          <div className="panel-head"><h3>Risk profile</h3></div>
          <RiskBlock trader={t} />
        </div>
      </div>

      <div className="card flat" style={{ marginTop: 14, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="kicker">Public trade history</div>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 22 }}>
            All {t.trades} closed positions are visible to verified users.
          </div>
        </div>
        <button className="btn" onClick={onOpenTrades}>Open trade history →</button>
      </div>
    </div>
  );
}

window.Profile = Profile;
