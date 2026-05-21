/* Shared building blocks */
const { useState, useEffect, useRef, useMemo } = React;

// CountUp animation — uses setInterval so it still fires when iframe is backgrounded
function CountUp({ value, decimals = 0, prefix = "", suffix = "", duration = 1200 }) {
  const [v, setV] = useState(value);
  const fromRef = useRef(value);
  useEffect(() => {
    const from = fromRef.current;
    const to = value;
    if (from === to) return;
    const start = Date.now();
    const id = setInterval(() => {
      const p = Math.min(1, (Date.now() - start) / duration);
      const e = 1 - Math.pow(1 - p, 3);
      setV(from + (to - from) * e);
      if (p >= 1) {
        clearInterval(id);
        fromRef.current = to;
      }
    }, 16);
    return () => clearInterval(id);
  }, [value, duration]);
  // animate from 0 on first mount
  const mountRef = useRef(false);
  useEffect(() => {
    if (mountRef.current) return;
    mountRef.current = true;
    const to = value;
    if (to === 0) return;
    fromRef.current = 0;
    setV(0);
    const start = Date.now();
    const id = setInterval(() => {
      const p = Math.min(1, (Date.now() - start) / duration);
      const e = 1 - Math.pow(1 - p, 3);
      setV(0 + (to - 0) * e);
      if (p >= 1) {
        clearInterval(id);
        fromRef.current = to;
      }
    }, 16);
    return () => clearInterval(id);
  }, []);
  const formatted = v.toLocaleString(undefined, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
  return <span className="countup tabular">{prefix}{formatted}{suffix}</span>;
}

function Avatar({ name, size = 40, src }) {
  const init = (name || "?")
    .split(" ")
    .map((s) => s[0])
    .slice(0, 2)
    .join("")
    .toUpperCase();
  const style = { width: size, height: size, fontSize: size * 0.42 };
  return (
    <span className="avatar" style={style}>{init}</span>
  );
}

function Tier({ tier, showRank }) {
  const def = (window.TIERS && window.TIERS[tier]) || { name: tier, rank: 0 };
  return (
    <span className={`tier ${tier}`}>
      <span className="dot"></span>
      {def.name}
      {showRank ? <span style={{ opacity: 0.5, marginLeft: 4 }}>· T{def.rank}</span> : null}
    </span>
  );
}

function TrendArrow({ delta }) {
  if (delta === 0) return <span className="trend flat">— 0</span>;
  if (delta > 0) return <span className="trend up">▲ {delta}</span>;
  return <span className="trend down">▼ {Math.abs(delta)}</span>;
}

// Sparkline SVG
function Sparkline({ data, width = 100, height = 32, kind }) {
  if (!data || !data.length) return null;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const pts = data.map((d, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - ((d - min) / range) * (height - 4) - 2;
    return [x, y];
  });
  const linePath = pts.map((p, i) => (i === 0 ? `M${p[0]},${p[1]}` : `L${p[0]},${p[1]}`)).join(" ");
  const fillPath = `${linePath} L${width},${height} L0,${height} Z`;
  const last = data[data.length - 1];
  const first = data[0];
  const k = kind || (last >= first ? "gain" : "loss");
  return (
    <svg className={`spark ${k}`} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
      <path className="fill" d={fillPath}></path>
      <path className="line" d={linePath}></path>
    </svg>
  );
}

// Equity curve large (with axis hints + drawing animation)
function EquityCurve({ data, height = 280 }) {
  const ref = useRef(null);
  const lineRef = useRef(null);
  const [w, setW] = useState(600);
  useEffect(() => {
    if (!ref.current) return;
    const ro = new ResizeObserver((entries) => {
      for (const e of entries) setW(e.contentRect.width);
    });
    ro.observe(ref.current);
    return () => ro.disconnect();
  }, []);
  // JS-driven stroke animation (setInterval works in backgrounded iframes; CSS may not)
  useEffect(() => {
    if (!lineRef.current) return;
    const path = lineRef.current;
    const len = path.getTotalLength();
    path.style.strokeDasharray = len;
    path.style.strokeDashoffset = len;
    const duration = 1800;
    const start = Date.now();
    const id = setInterval(() => {
      const p = Math.min(1, (Date.now() - start) / duration);
      const e = 1 - Math.pow(1 - p, 3);
      path.style.strokeDashoffset = len * (1 - e);
      if (p >= 1) clearInterval(id);
    }, 16);
    return () => clearInterval(id);
  }, [w, data]);
  const padL = 56, padR = 16, padT = 16, padB = 28;
  const cw = Math.max(w, 100);
  const ch = height;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const pts = data.map((d, i) => {
    const x = padL + (i / (data.length - 1)) * (cw - padL - padR);
    const y = padT + (1 - (d - min) / range) * (ch - padT - padB);
    return [x, y];
  });
  const linePath = pts.map((p, i) => (i === 0 ? `M${p[0]},${p[1]}` : `L${p[0]},${p[1]}`)).join(" ");
  const fillPath = `${linePath} L${cw - padR},${ch - padB} L${padL},${ch - padB} Z`;
  // y ticks
  const ticks = 4;
  const tickVals = [];
  for (let i = 0; i <= ticks; i++) tickVals.push(min + (range * i) / ticks);
  // x ticks (months)
  const xLabels = ["Dec", "Jan", "Feb", "Mar", "Apr", "May"];

  return (
    <div ref={ref} style={{ width: "100%" }}>
      <svg viewBox={`0 0 ${cw} ${ch}`} width={cw} height={ch}>
        <defs>
          <linearGradient id="eqfill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="var(--gain)" stopOpacity="0.18" />
            <stop offset="100%" stopColor="var(--gain)" stopOpacity="0.0" />
          </linearGradient>
        </defs>
        {/* Grid */}
        {tickVals.map((tv, i) => {
          const y = padT + (1 - (tv - min) / range) * (ch - padT - padB);
          return (
            <g key={i}>
              <line x1={padL} x2={cw - padR} y1={y} y2={y} stroke="var(--line)" strokeDasharray="2 4" />
              <text x={padL - 10} y={y + 4} fontSize="10" fill="var(--ink-3)" textAnchor="end" fontFamily="var(--font-mono)">
                ${(tv / 1000).toFixed(1)}k
              </text>
            </g>
          );
        })}
        {xLabels.map((l, i) => {
          const x = padL + (i / (xLabels.length - 1)) * (cw - padL - padR);
          return (
            <text key={i} x={x} y={ch - 8} fontSize="10" fill="var(--ink-3)" textAnchor="middle" fontFamily="var(--font-mono)">
              {l.toUpperCase()}
            </text>
          );
        })}
        <path className="equity-fill" d={fillPath} fill="url(#eqfill)" />
        <path ref={lineRef} className="equity-line" d={linePath} fill="none" stroke="var(--gain)" strokeWidth="1.8" strokeLinejoin="round" strokeLinecap="round" />
        {/* Endpoint dot */}
        <circle cx={pts[pts.length - 1][0]} cy={pts[pts.length - 1][1]} r="3.5" fill="var(--gain)" />
      </svg>
    </div>
  );
}

// P&L per trade bars
function PnLBars({ trades }) {
  const max = Math.max(...trades.map((t) => Math.abs(t.pnl))) || 1;
  return (
    <div className="bars">
      {trades.map((t, i) => {
        const h = (Math.abs(t.pnl) / max) * 100;
        return (
          <div
            key={i}
            className={`bar ${t.pnl >= 0 ? "gain" : "loss"}`}
            style={{ height: `${h}%`, animationDelay: `${i * 30}ms` }}
            data-tip={`${t.symbol} · $${t.pnl.toFixed(2)}`}
          />
        );
      })}
    </div>
  );
}

// Monthly bar chart with positive/negative dual-axis
function MonthlyBars({ data }) {
  const max = Math.max(...data.map((d) => Math.abs(d.pnl)));
  return (
    <div style={{ display: "flex", alignItems: "stretch", gap: 14, height: 220 }}>
      {data.map((d, i) => {
        const ratio = (Math.abs(d.pnl) / max) * 0.9;
        const isGain = d.pnl >= 0;
        return (
          <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column" }}>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "flex-end", alignItems: "stretch", borderBottom: "1px solid var(--line)" }}>
              {isGain ? (
                <div
                  className="bar gain"
                  style={{ height: `${ratio * 100}%`, borderRadius: "4px 4px 0 0" }}
                  data-tip={`$${d.pnl.toFixed(0)}`}
                />
              ) : null}
            </div>
            <div style={{ flex: 1, display: "flex", alignItems: "flex-start" }}>
              {!isGain ? (
                <div
                  className="bar loss"
                  style={{ height: `${ratio * 100}%`, width: "100%", borderRadius: "0 0 4px 4px" }}
                  data-tip={`-$${Math.abs(d.pnl).toFixed(0)}`}
                />
              ) : null}
            </div>
            <div style={{ textAlign: "center", marginTop: 8, fontSize: 11, color: "var(--ink-3)", letterSpacing: "0.06em" }}>
              {d.month.toUpperCase()}
            </div>
            <div style={{ textAlign: "center", fontSize: 11, fontFamily: "var(--font-mono)", marginTop: 2, color: isGain ? "var(--gain)" : "var(--loss)" }}>
              {isGain ? "+" : "-"}${Math.abs(d.pnl).toFixed(0)}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Streak({ items }) {
  return (
    <span className="streak">
      {items.map((s, i) => <span key={i} className={`dot ${s}`} />)}
    </span>
  );
}

Object.assign(window, {
  CountUp, Avatar, Tier, TrendArrow, Sparkline, EquityCurve, PnLBars, MonthlyBars, Streak,
});
