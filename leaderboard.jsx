/* Leaderboard — Top 10 with rank animations */

function Leaderboard({ onPick, period, setPeriod }) {
  // Re-rank traders whenever period changes — same dimensions as MQL5 EA
  const traders = useMemo(() => window.rankTraders(window.TRADERS, period), [period]);

  const [tick, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 6500);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="page page-fade">
      {/* Hero Section */}
      <div className="hero-section">
        <div className="hero-content">
          <div className="hero-header">
            <h1 className="hero-title">Codex Trading Competition</h1>
            <p className="hero-subtitle">Compete globally. Win prizes. Prove your trading edge.</p>
          </div>

          <div className="hero-stats">
            <div className="stat-card">
              <div className="stat-value">$50,000</div>
              <div className="stat-label">Prize Pool</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">4,217</div>
              <div className="stat-label">Participants</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">23d 06h</div>
              <div className="stat-label">Time Left</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">Realtime</div>
              <div className="stat-label">Rankings Update</div>
            </div>
          </div>

          <div className="hero-ctas">
            <button className="cta-primary" onClick={() => window.location.href = '/join'}>Join Competition</button>
            <button className="cta-secondary" onClick={() => window.scrollTo({ top: document.querySelector('.page-head').offsetTop, behavior: 'smooth' })}>View Leaderboard</button>
          </div>
        </div>
      </div>

      <div className="page-head">
        <div>
          <div className="kicker">Global Standings · Live</div>
          <h1 className="page-title">The Top Ten.</h1>
          <p className="page-subtitle">
            Highest-performing accounts across all connected brokers — ranked by
            our 4-dimensional composite score (Risk-Adjusted Performance, Consistency,
            Capital Preservation, Execution Quality). Updates every 60 seconds.
          </p>
        </div>
        <PeriodBar value={period} onChange={setPeriod} />
      </div>

      {/* Podium row */}
      <div className="row-3" style={{ marginBottom: 28 }}>
        {traders.slice(0, 3).map((t, i) => (
          <PodiumCard key={t.username} trader={t} medal={i + 1} onClick={() => onPick(t)} />
        ))}
      </div>

      {/* Full table */}
      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        <table className="lb-table">
          <thead>
            <tr style={{ borderBottom: "1px solid var(--line)" }}>
              <th style={th}>#</th>
              <th style={th}>Trader</th>
              <th style={th}>Tier</th>
              <th style={th}>7-day curve</th>
              <th style={{ ...th, textAlign: "right" }}>Score</th>
              <th style={{ ...th, textAlign: "right" }}>Return</th>
              <th style={{ ...th, textAlign: "right" }}>Win rate</th>
              <th style={{ ...th, textAlign: "right" }}>Trades</th>
            </tr>
          </thead>
          <tbody>
            {traders.map((t, i) => {
              const s = t._score;
              return (
                <tr
                  key={t.username}
                  className={`lb-row ${i < 3 ? `podium-${i + 1}` : ""}`}
                  onClick={() => onPick(t)}
                >
                  <td className="rank-cell" style={{ paddingLeft: 28 }}>
                    <span className={`rank-num ${i > 2 ? "muted" : ""}`}>
                      {String(i + 1).padStart(2, "0")}
                    </span>
                    <TrendArrow delta={t.rankDelta} />
                  </td>
                  <td className="user-cell">
                    <div className="user-block">
                      <Avatar name={t.username} />
                      <div>
                        <div className="user-name">{t.username}</div>
                        <div className="user-meta">
                          <span>{t.country}</span>
                          <span className="mono">{t.account}</span>
                          <span>·</span>
                          <span>{t.handle}</span>
                        </div>
                      </div>
                    </div>
                  </td>
                  <td><Tier tier={t.tier} /></td>
                  <td style={{ width: 140 }}>
                    <Sparkline data={t.sparkline} width={120} height={32} />
                  </td>
                  <td style={{ textAlign: "right" }} className="num">
                    <ScoreCell score={s.composite} label={s.rankCode} key={tick + period} />
                  </td>
                  <td style={{ textAlign: "right" }} className="tabular num">
                    <div className="metric-big" style={{ fontSize: 18, color: s.raw.pct >= 0 ? "var(--gain)" : "var(--loss)" }}>
                      {s.raw.pct >= 0 ? "+" : "−"}{Math.abs(s.raw.pct).toFixed(2)}%
                    </div>
                  </td>
                  <td style={{ textAlign: "right" }} className="tabular num">{s.raw.winRate.toFixed(1)}%</td>
                  <td style={{ textAlign: "right", paddingRight: 28 }} className="tabular">{s.raw.trades}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div style={{ marginTop: 16, display: "flex", justifyContent: "space-between", alignItems: "center", color: "var(--ink-3)", fontSize: 12 }}>
        <span>Showing 10 of 4,217 connected accounts</span>
        <span className="mono">Last sync · {new Date().toLocaleTimeString()}</span>
      </div>
    </div>
  );
}

const th = {
  textAlign: "left",
  fontWeight: 500,
  fontSize: 11,
  letterSpacing: "0.12em",
  textTransform: "uppercase",
  color: "var(--ink-3)",
  padding: "16px 12px",
};

function ScoreCell({ score, label }) {
  // Composite is 0..100; color it by band
  const color = score >= 90 ? "var(--gain)" : score >= 60 ? "var(--ink)" : score >= 30 ? oklchAccent(70) : "var(--loss)";
  return (
    <div style={{ display: "inline-flex", flexDirection: "column", alignItems: "flex-end", gap: 4 }}>
      <div className="metric-big tabular" style={{ fontSize: 26, color }}>
        <CountUp value={score} decimals={1} duration={900} />
      </div>
      <div className="kicker" style={{ fontSize: 9, opacity: 0.65 }}>{label}</div>
    </div>
  );
}
function oklchAccent(l) { return `oklch(${l/100} 0.08 60)`; }

function PodiumCard({ trader, medal, onClick }) {
  const medalLabel = ["First", "Second", "Third"][medal - 1];
  const tierDef = (window.TIERS && window.TIERS[trader.tier]) || {};
  const ring = tierDef.accent || "var(--ink)";
  const primary = tierDef.primary || "var(--ink)";
  const s = trader._score;
  return (
    <div
      className={`card podium-card podium-${medal}`}
      onClick={onClick}
      style={{
        position: "relative",
        cursor: "pointer",
        padding: "24px 24px 22px",
        borderColor: `color-mix(in oklab, ${ring} 35%, var(--line))`,
        background: `linear-gradient(160deg, color-mix(in oklab, ${ring} 12%, var(--surface)), var(--surface) 60%)`,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: "auto -30% -50% auto",
          width: 260,
          height: 260,
          background: `radial-gradient(circle, color-mix(in oklab, ${ring} 18%, transparent), transparent 70%)`,
          pointerEvents: "none",
        }}
      />
      <div style={{ position: "relative", display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 22 }}>
        <div>
          <div className="kicker" style={{ color: ring, opacity: 0.9 }}>{medalLabel} place</div>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 64, lineHeight: 1, marginTop: 4, letterSpacing: "-0.04em" }}>
            #{medal}
          </div>
        </div>
        <div
          style={{
            width: 56,
            height: 56,
            borderRadius: "50%",
            border: `1.5px solid ${ring}`,
            background: `linear-gradient(135deg, color-mix(in oklab, ${ring} 14%, white), white)`,
            display: "grid",
            placeItems: "center",
            fontFamily: "var(--font-display)",
            fontSize: 22,
            color: primary,
            boxShadow: `0 4px 16px color-mix(in oklab, ${ring} 30%, transparent)`,
          }}
        >
          {trader.username.split(" ").map((s) => s[0]).join("")}
        </div>
      </div>
      <div style={{ position: "relative", fontSize: 17, fontWeight: 500 }}>{trader.username}</div>
      <div className="user-meta" style={{ position: "relative" }}>
        <span>{trader.country}</span>
        <span>·</span>
        <span>{trader.handle}</span>
        <Tier tier={trader.tier} />
      </div>

      <div style={{ position: "relative", marginTop: 18, display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: 16 }}>
        <div style={{ minWidth: 0 }}>
          <div className="metric-sub">Composite</div>
          <div className="metric-big" style={{ fontSize: 38, marginTop: 6, whiteSpace: "nowrap", color: ring }}>
            <CountUp value={s.composite} decimals={1} duration={1500} />
          </div>
          <div className="kicker" style={{ marginTop: 4, fontSize: 10, color: ring }}>{s.rankTitle.toUpperCase()}</div>
        </div>
        <div style={{ textAlign: "right", flexShrink: 0 }}>
          <div className="metric-sub">Return</div>
          <div className="tabular" style={{ fontFamily: "var(--font-display)", fontSize: 20, marginTop: 6, whiteSpace: "nowrap", color: s.raw.pct >= 0 ? "var(--gain)" : "var(--loss)" }}>
            {s.raw.pct >= 0 ? "+" : "−"}{Math.abs(s.raw.pct).toFixed(2)}%
          </div>
        </div>
      </div>

      <div style={{ position: "relative", marginTop: 16 }}>
        <Sparkline data={trader.equityCurve} width={300} height={48} kind="custom" />
      </div>

      <style>{`
        .podium-${medal} .spark path.line { stroke: ${ring}; }
        .podium-${medal} .spark path.fill { fill: ${ring}; opacity: 0.12; }
      `}</style>
    </div>
  );
}

function PeriodBar({ value, onChange }) {
  const periods = [
    { id: "today", label: "Today" },
    { id: "week", label: "This Week" },
    { id: "lastweek", label: "Last Week" },
    { id: "month", label: "This Month" },
    { id: "alltime", label: "All Time" },
    { id: "custom", label: "Custom" },
  ];
  return (
    <div className="period-bar">
      {periods.map((p) => (
        <button
          key={p.id}
          className={value === p.id ? "active" : ""}
          onClick={() => onChange(p.id)}
        >
          {p.label}
        </button>
      ))}
    </div>
  );
}

Object.assign(window, { Leaderboard, PeriodBar });
