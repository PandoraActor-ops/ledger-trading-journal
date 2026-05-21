/* Trade history — sortable, filterable */

function TradeHistory({ trader, onBack, period, setPeriod }) {
  const t = trader;
  const [sym, setSym] = useState("ALL");
  const [side, setSide] = useState("ALL");

  // Generate a larger pool of trades for the history view
  const allTrades = useMemo(() => {
    return genHistoryTrades(t);
  }, [t]);

  const filtered = allTrades.filter((tr) => {
    if (sym !== "ALL" && tr.symbol !== sym) return false;
    if (side !== "ALL" && tr.side !== side) return false;
    return true;
  });

  const totalPnL = filtered.reduce((s, t) => s + t.pnl, 0);
  const wins = filtered.filter((t) => t.pnl > 0).length;
  const losses = filtered.filter((t) => t.pnl < 0).length;

  const symbols = ["ALL", ...new Set(allTrades.map((t) => t.symbol))];

  return (
    <div className="page page-fade">
      <button className="btn-ghost btn" onClick={onBack} style={{ marginBottom: 8 }}>← Back</button>
      <div className="page-head">
        <div>
          <div className="kicker">Trade ledger</div>
          <h1 className="page-title">{t.username}'s trades</h1>
          <p className="page-subtitle">
            {filtered.length} closed positions · {wins} wins / {losses} losses · Net{" "}
            <strong style={{ color: totalPnL >= 0 ? "var(--gain)" : "var(--loss)" }}>
              {totalPnL >= 0 ? "+" : "−"}${fmt(Math.abs(totalPnL), 2)}
            </strong>
          </p>
        </div>
        <PeriodBar value={period} onChange={setPeriod} />
      </div>

      {/* Filters */}
      <div style={{ display: "flex", gap: 8, marginBottom: 14, alignItems: "center" }}>
        <span className="kicker" style={{ marginRight: 4 }}>Symbol</span>
        <div className="period-bar">
          {symbols.map((s) => (
            <button key={s} className={sym === s ? "active" : ""} onClick={() => setSym(s)}>{s}</button>
          ))}
        </div>
        <span className="kicker" style={{ margin: "0 4px 0 16px" }}>Side</span>
        <div className="period-bar">
          {["ALL", "buy", "sell"].map((s) => (
            <button key={s} className={side === s ? "active" : ""} onClick={() => setSide(s)}>{s.toUpperCase()}</button>
          ))}
        </div>
      </div>

      <div className="card" style={{ padding: 0 }}>
        <table className="trades" style={{ fontSize: 13 }}>
          <thead>
            <tr>
              <th style={{ paddingLeft: 22 }}>#</th>
              <th>Symbol</th>
              <th>Side</th>
              <th style={{ textAlign: "right" }}>Lots</th>
              <th style={{ textAlign: "right" }}>Open</th>
              <th style={{ textAlign: "right" }}>Close</th>
              <th style={{ textAlign: "right" }}>Duration</th>
              <th style={{ textAlign: "right" }}>P&L</th>
              <th style={{ textAlign: "right", paddingRight: 22 }}>Cumulative</th>
            </tr>
          </thead>
          <tbody>
            {filtered.slice(0, 30).map((tr, i) => (
              <tr key={tr.id}>
                <td style={{ paddingLeft: 22, color: "var(--ink-3)" }} className="mono">{String(i + 1).padStart(3, "0")}</td>
                <td><span className="mono">{tr.symbol}</span></td>
                <td><span className={`side ${tr.side}`}>{tr.side.toUpperCase()}</span></td>
                <td style={{ textAlign: "right" }} className="tabular">{tr.lots.toFixed(2)}</td>
                <td style={{ textAlign: "right", color: "var(--ink-3)" }} className="mono">{tr.open.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}</td>
                <td style={{ textAlign: "right", color: "var(--ink-3)" }} className="mono">{tr.close.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}</td>
                <td style={{ textAlign: "right" }} className="tabular">{Math.floor(tr.dur / 60)}h {tr.dur % 60}m</td>
                <td style={{ textAlign: "right", fontWeight: 500, color: tr.pnl >= 0 ? "var(--gain)" : "var(--loss)" }} className="tabular">
                  {tr.pnl >= 0 ? "+" : "−"}${Math.abs(tr.pnl).toFixed(2)}
                </td>
                <td style={{ textAlign: "right", paddingRight: 22 }} className="tabular">
                  ${tr.cum.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {filtered.length > 30 ? (
        <div style={{ marginTop: 14, textAlign: "center", color: "var(--ink-3)", fontSize: 12 }}>
          Showing 30 of {filtered.length} · <a href="#" style={{ color: "var(--ink)" }}>Load more</a>
        </div>
      ) : null}
    </div>
  );
}

function genHistoryTrades(t) {
  // re-use same generator but more, then build cumulative
  const symbols = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "BTCUSD", "USOIL", "US30", "NAS100"];
  const list = [];
  const seed = t.seed + 500;
  const total = Math.min(64, t.trades);
  // use simple LCG
  let s = seed;
  const r = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 0xFFFFFFFF; };
  let cum = 0;
  let d = new Date(2026, 4, 21, 16, 0);
  for (let i = 0; i < total; i++) {
    const win = r() < t.winRate / 100;
    const sym = symbols[Math.floor(r() * symbols.length)];
    const ssd = r() > 0.5 ? "buy" : "sell";
    const lots = +(0.05 + r() * 0.95).toFixed(2);
    const pnl = win
      ? +(t.avgWin * (0.4 + r() * 1.6)).toFixed(2)
      : -+(t.avgLoss * (0.4 + r() * 1.6)).toFixed(2);
    cum += pnl;
    d = new Date(d.getTime() - (1 + r() * 12) * 3600 * 1000);
    const dur = Math.floor(20 + r() * 600);
    list.push({
      id: 30000 + i,
      symbol: sym, side: ssd, lots,
      pnl: +pnl.toFixed(2),
      cum: +cum.toFixed(2),
      open: new Date(d.getTime() - dur * 60000),
      close: new Date(d),
      dur,
    });
  }
  return list;
}

window.TradeHistory = TradeHistory;
