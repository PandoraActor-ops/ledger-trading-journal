/* ScoreBreakdown — visualize the 4-dimension composite score
   from the MQL5 EA's BehaviorGrid. Shown on My Dashboard and
   on the public Profile.
*/

function ScoreBreakdown({ trader, period }) {
  const s = useMemo(
    () => window.computeScore(trader, period || "month"),
    [trader, period]
  );

  return (
    <div className="score-breakdown">
      <ScoreHeader score={s} />
      <div className="dim-grid">
        {s.dims.map((dim, i) => (
          <DimCard key={dim.id} dim={dim} sub={s.sub[dim.id]} index={i} />
        ))}
      </div>
      <ScoreFormula score={s} />
    </div>
  );
}

function ScoreHeader({ score }) {
  return (
    <div className="score-header">
      <div className="score-header-left">
        <div className="kicker">Composite Score · weighted across 4 dimensions</div>
        <div className="score-big">
          <CountUp value={score.composite} decimals={1} duration={1400} />
          <span className="score-out-of">/100</span>
        </div>
        <div className="rank-badge">
          <Stars n={score.stars} />
          <span className="rank-title">{score.rankTitle}</span>
          <span className="rank-code mono">· {score.rankCode}</span>
        </div>
      </div>
      <div className="score-header-right">
        <ScoreGauge value={score.composite} />
      </div>
    </div>
  );
}

function Stars({ n, total = 5 }) {
  const arr = Array.from({ length: total }, (_, i) => i < n);
  return (
    <span className="stars" aria-label={`${n} of ${total} stars`}>
      {arr.map((on, i) => (
        <svg key={i} viewBox="0 0 16 16" width="14" height="14" style={{ opacity: on ? 1 : 0.18 }}>
          <path
            d="M8 1.5l1.95 4.13 4.55.55-3.36 3.13.86 4.49L8 11.6 3.99 13.8l.86-4.49L1.5 6.18l4.55-.55L8 1.5z"
            fill="currentColor"
          />
        </svg>
      ))}
    </span>
  );
}

function ScoreGauge({ value }) {
  const r = 56;
  const c = 2 * Math.PI * r;
  const pct = Math.max(0, Math.min(100, value)) / 100;
  const color = value >= 90 ? "var(--gain)" : value >= 60 ? "var(--ink)" : value >= 30 ? "oklch(0.6 0.12 60)" : "var(--loss)";
  return (
    <svg width="140" height="140" viewBox="0 0 140 140">
      <circle cx="70" cy="70" r={r} fill="none" stroke="var(--line)" strokeWidth="6" />
      <circle
        cx="70" cy="70" r={r}
        fill="none"
        stroke={color}
        strokeWidth="6"
        strokeLinecap="round"
        strokeDasharray={`${c * pct} ${c}`}
        transform="rotate(-90 70 70)"
        style={{ transition: "stroke-dasharray 1s cubic-bezier(.2,.7,.2,1)" }}
      />
      <text x="70" y="68" textAnchor="middle" fontFamily="var(--font-display)" fontSize="34" fill="var(--ink)">
        {value.toFixed(0)}
      </text>
      <text x="70" y="86" textAnchor="middle" fontFamily="var(--font-mono)" fontSize="9" fill="var(--ink-3)" letterSpacing="0.1em">
        COMPOSITE
      </text>
    </svg>
  );
}

function DimCard({ dim, sub, index }) {
  const levelColor = {
    ELITE: "var(--gain)",
    STANDARD: "var(--ink)",
    CAUTION: "oklch(0.6 0.12 60)",
    FAIL: "var(--loss)",
  }[dim.level] || "var(--ink-3)";

  return (
    <div className="dim-card">
      <div className="dim-head">
        <div>
          <div className="dim-label mono">D{index + 1} · WEIGHT {Math.round(dim.weight * 100)}%</div>
          <div className="dim-name">{dim.name}</div>
        </div>
        <div className="dim-score-block">
          <div className="dim-score tabular" style={{ color: levelColor }}>{dim.score}</div>
          <div className="dim-level" style={{ color: levelColor }}>{dim.level}</div>
        </div>
      </div>
      <div className="dim-bar">
        <div className="dim-bar-fill" style={{ width: `${dim.score}%`, background: levelColor }} />
        <div className="dim-bar-tick" style={{ left: "60%" }} title="Standard threshold (60)"></div>
        <div className="dim-bar-tick elite" style={{ left: "90%" }} title="Elite threshold (90)"></div>
      </div>
      <div className="sub-metrics">
        {sub.map((m, i) => (
          <SubMetric key={i} metric={m} />
        ))}
      </div>
    </div>
  );
}

function SubMetric({ metric }) {
  const lvl = window.levelOf(metric.score);
  const color = {
    ELITE: "var(--gain)",
    STANDARD: "var(--ink)",
    CAUTION: "oklch(0.6 0.12 60)",
    FAIL: "var(--loss)",
  }[lvl];
  const arrow = metric.lower ? "≤" : "≥";
  return (
    <div className="sub">
      <div className="sub-name">{metric.key}</div>
      <div className="sub-val tabular">
        <span>{metric.value}<span className="sub-unit">{metric.unit}</span></span>
      </div>
      <div className="sub-bar">
        <div className="sub-bar-fill" style={{ width: `${metric.score}%`, background: color }} />
      </div>
      <div className="sub-thresh mono">
        <span style={{ color: "var(--gain)" }}>elite {arrow} {metric.elite}</span>
        <span>·</span>
        <span>std {arrow} {metric.std}</span>
        <span style={{ marginLeft: "auto", color }}>{metric.score}</span>
      </div>
    </div>
  );
}

function ScoreFormula({ score }) {
  const parts = score.dims.map((d, i) => ({
    label: `D${i + 1}`,
    score: d.score,
    weight: d.weight,
    contribution: d.score * d.weight,
  }));
  const total = parts.reduce((s, p) => s + p.contribution, 0);
  return (
    <div className="score-formula">
      <div className="kicker">Composite formula</div>
      <div className="formula-row">
        {parts.map((p, i) => (
          <React.Fragment key={i}>
            <span className="formula-term">
              <span className="formula-d mono">{p.label}</span>
              <span className="formula-mul mono">{p.score}</span>
              <span className="formula-x mono">×</span>
              <span className="formula-w mono">{p.weight}</span>
              <span className="formula-eq mono">=</span>
              <span className="formula-c tabular">{p.contribution.toFixed(1)}</span>
            </span>
            {i < parts.length - 1 ? <span className="formula-plus mono">+</span> : null}
          </React.Fragment>
        ))}
        <span className="formula-equals mono">=</span>
        <span className="formula-total tabular">{total.toFixed(1)}</span>
      </div>
    </div>
  );
}

window.ScoreBreakdown = ScoreBreakdown;
