/* Performance Calendar + Performance by Session
   Premium-minimal interpretation of the dark-theme reference. */

function PerformanceCalendar({ trader, period }) {
  const [view, setView] = useState("month"); // "month" | "year"
  const [cursor, setCursor] = useState(() => new Date(2026, 4, 1)); // May 2026

  const days = useMemo(() => buildTradingCalendar(trader, cursor), [trader, cursor]);

  const prev = () => {
    const d = new Date(cursor);
    if (view === "month") d.setMonth(d.getMonth() - 1);
    else d.setFullYear(d.getFullYear() - 1);
    setCursor(d);
  };
  const next = () => {
    const d = new Date(cursor);
    if (view === "month") d.setMonth(d.getMonth() + 1);
    else d.setFullYear(d.getFullYear() + 1);
    setCursor(d);
  };

  return (
    <div className="panel calendar-panel">
      <div className="panel-head">
        <h3>Performance Calendar</h3>
        <div className="cal-controls">
          <div className="seg-pill">
            <button className={view === "month" ? "active" : ""} onClick={() => setView("month")}>Month</button>
            <button className={view === "year" ? "active" : ""} onClick={() => setView("year")}>Year</button>
          </div>
        </div>
      </div>

      <div className="cal-nav">
        <button className="icon-btn" onClick={prev} aria-label="Previous">‹</button>
        <div className="cal-title serif">
          {view === "month"
            ? cursor.toLocaleString(undefined, { month: "long", year: "numeric" })
            : cursor.getFullYear()}
        </div>
        <button className="icon-btn" onClick={next} aria-label="Next">›</button>
        <div className="cal-legend">
          <span><span className="dot gain"></span>Profit</span>
          <span><span className="dot loss"></span>Loss</span>
        </div>
      </div>

      {view === "month" ? (
        <MonthGrid days={days} />
      ) : (
        <YearGrid trader={trader} year={cursor.getFullYear()} />
      )}
    </div>
  );
}

function MonthGrid({ days }) {
  const heads = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
  return (
    <div className="cal-grid">
      <div className="cal-head-row">
        {heads.map((h) => <div key={h} className="cal-head-cell">{h}</div>)}
      </div>
      <div className="cal-body">
        {days.map((d, i) => (
          <DayCell key={i} day={d} />
        ))}
      </div>
    </div>
  );
}

function DayCell({ day }) {
  const cls = ["cal-cell"];
  if (!day.inMonth) cls.push("muted");
  if (day.pnl > 0) cls.push("gain");
  if (day.pnl < 0) cls.push("loss");
  if (day.isWeekend) cls.push("weekend");
  return (
    <div className={cls.join(" ")}>
      <div className="cal-date">{day.date.getDate()}</div>
      {day.trades > 0 ? (
        <div className="cal-content">
          <div className="cal-trades mono">{day.trades} trade{day.trades > 1 ? "s" : ""}</div>
          <div className={`cal-pnl tabular ${day.pnl >= 0 ? "gain" : "loss"}`}>
            {day.pnl >= 0 ? "+" : "−"}${Math.abs(day.pnl).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function YearGrid({ trader, year }) {
  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  const rng = mulberry(trader.seed * 7 + year);
  // Generate mini month tiles with per-month P&L
  const data = months.map((m, mi) => {
    const cursor = new Date(year, mi, 1);
    const cal = buildTradingCalendar(trader, cursor);
    const inMonth = cal.filter((d) => d.inMonth);
    const sum = inMonth.reduce((s, d) => s + d.pnl, 0);
    const winDays = inMonth.filter((d) => d.pnl > 0).length;
    return { m, mi, sum, winDays, days: inMonth };
  });
  return (
    <div className="year-grid">
      {data.map((d) => (
        <div key={d.mi} className={`year-month ${d.sum >= 0 ? "gain" : "loss"}`}>
          <div className="ym-head">
            <span className="ym-name serif">{d.m}</span>
            <span className={`ym-pnl tabular ${d.sum >= 0 ? "gain" : "loss"}`}>
              {d.sum >= 0 ? "+" : "−"}${Math.abs(d.sum).toLocaleString(undefined, { maximumFractionDigits: 0 })}
            </span>
          </div>
          <div className="ym-cells">
            {d.days.map((day, i) => (
              <div
                key={i}
                className={`ym-cell ${day.pnl > 0 ? "gain" : day.pnl < 0 ? "loss" : ""}`}
                style={{ opacity: day.trades > 0 ? 0.4 + Math.min(0.6, Math.abs(day.pnl) / 500) : 0.12 }}
                title={`${day.date.toDateString()} · ${day.trades} trades · ${day.pnl >= 0 ? "+" : "−"}$${Math.abs(day.pnl).toFixed(0)}`}
              />
            ))}
          </div>
          <div className="ym-stats mono">
            <span>{d.winDays} green days</span>
          </div>
        </div>
      ))}
    </div>
  );
}

// Deterministic per-trader per-day mock
function buildTradingCalendar(trader, anchor) {
  const year = anchor.getFullYear();
  const month = anchor.getMonth();
  // Find first day of grid (Monday-start; pad with prev month days)
  const first = new Date(year, month, 1);
  const jsDow = first.getDay(); // 0=Sun..6=Sat
  const offset = (jsDow + 6) % 7; // 0 if Monday, 6 if Sunday
  const gridStart = new Date(year, month, 1 - offset);

  const cells = [];
  for (let i = 0; i < 42; i++) {
    const date = new Date(gridStart);
    date.setDate(gridStart.getDate() + i);
    const inMonth = date.getMonth() === month;
    const isWeekend = date.getDay() === 0 || date.getDay() === 6;
    const r = mulberry((trader.seed * 31 + date.getTime()) >>> 0);
    const seed = r();
    let trades = 0, pnl = 0;
    if (!isWeekend && inMonth) {
      // Use trader.winRate-ish probability for trading days
      if (seed < 0.78) {
        trades = Math.round(1 + r() * 14);
        const isWin = r() < trader.winRate / 100;
        const magnitude = (50 + r() * 850) * (trader.pct / 100 + 0.3);
        pnl = +(isWin ? magnitude : -magnitude * 0.55).toFixed(2);
      }
    }
    cells.push({ date, inMonth, isWeekend, trades, pnl });
  }
  return cells;
}

function mulberry(a) {
  return function () {
    let t = (a += 0x6D2B79F5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ─────────── Performance by Session ─────────── */

function PerformanceBySession({ trader, period }) {
  const sessions = useMemo(() => buildSessionStats(trader), [trader]);
  return (
    <div className="panel sessions-panel">
      <div className="panel-head">
        <h3>Performance by Session</h3>
        <span className="kicker">All Time</span>
      </div>
      <div className="sessions-grid">
        {sessions.map((s) => (
          <SessionCard key={s.id} session={s} />
        ))}
      </div>
    </div>
  );
}

function SessionCard({ session }) {
  const wr = session.winRate;
  const gain = wr >= 50;
  return (
    <div className="session-card" style={{ "--sess-color": session.color }}>
      <div className="session-bar"></div>
      <div className="session-icon">
        <span className="session-glyph" aria-hidden>{session.icon}</span>
        <span className="session-name mono">{session.name.toUpperCase()}</span>
      </div>
      <div className={`session-wr serif ${gain ? "gain" : "loss"}`}>
        <CountUp value={wr} decimals={1} suffix="%" duration={1200} />
      </div>
      <div className="session-wr-label">WIN RATE</div>

      <div className="session-stats">
        <Row label="Trades" value={session.trades.toLocaleString()} />
        <Row label="Net P&L" value={
          <span className={session.pnl >= 0 ? "gain" : "loss"} style={{ fontWeight: 500 }}>
            {session.pnl >= 0 ? "+" : "−"}${Math.abs(session.pnl).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
          </span>
        } />
        <Row label="Avg RR" value={
          <span style={{ color: session.avgRR >= 0 ? "var(--ink)" : "var(--loss)" }}>
            {session.avgRR.toFixed(2)}x
          </span>
        } />
        <Row label="P.Factor" value={
          <span className={session.pf >= 1 ? "gain" : "loss"} style={{ fontWeight: 500 }}>
            {isFinite(session.pf) ? session.pf.toFixed(2) : "∞"}
          </span>
        } />
        <Row label="Time" value={<span className="mono session-time">{session.time}</span>} muted />
      </div>

      <div className="session-progress">
        <div className="session-progress-fill" style={{ width: `${Math.min(100, wr)}%`, background: session.color }} />
      </div>
    </div>
  );
}

function Row({ label, value, muted }) {
  return (
    <div className="session-row">
      <span className="session-row-label">{label}</span>
      <span className={`session-row-val tabular ${muted ? "muted" : ""}`}>{value}</span>
    </div>
  );
}

function buildSessionStats(trader) {
  const r = mulberry(trader.seed + 1000);
  const total = Math.max(10, trader.trades * 12);
  // Base distribution
  const dist = [
    { share: 0.13, name: "Asian",       id: "asian",   icon: "🌐", color: "oklch(0.66 0.14 50)",  time: "00:00–08:00", wrAdj: -8 },
    { share: 0.46, name: "London",      id: "london",  icon: "🇬🇧", color: "oklch(0.55 0.12 240)", time: "08:00–13:00", wrAdj: -5 },
    { share: 0.30, name: "New York",    id: "ny",      icon: "🌎", color: "oklch(0.55 0.12 155)", time: "13:00–22:00", wrAdj: +12 },
    { share: 0.05, name: "Off-Session", id: "off",     icon: "🌙", color: "oklch(0.62 0.10 90)",  time: "22:00–24:00", wrAdj: -2 },
  ];
  return dist.map((d, i) => {
    const trades = Math.max(2, Math.round(total * d.share * (0.85 + r() * 0.3)));
    const winRate = clamp(trader.winRate + d.wrAdj + (r() - 0.5) * 4, 35, 100);
    const wins = Math.round((winRate / 100) * trades);
    const losses = trades - wins;
    const avgWin = trader.avgWin * (0.6 + r() * 0.8);
    const avgLoss = trader.avgLoss * (0.6 + r() * 0.8);
    const pnl = wins * avgWin - losses * avgLoss;
    const avgRR = (avgWin / Math.max(1, avgLoss)) - 1 + (r() - 0.5) * 0.3;
    const pf = losses === 0 ? Infinity : (wins * avgWin) / (losses * avgLoss);
    return {
      ...d,
      trades,
      winRate,
      pnl: +pnl.toFixed(2),
      avgRR: +avgRR.toFixed(2),
      pf,
    };
  });
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

Object.assign(window, { PerformanceCalendar, PerformanceBySession });
