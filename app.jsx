/* Main App — view router + Supabase auth/data */

function App() {
  const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
    "dashboardVariant": "A",
    "showLogin": false,
    "accent": "green",
    "myTier": "auto"
  }/*EDITMODE-END*/;

  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [view,     setView]     = useState(tweaks.showLogin ? "login" : "leaderboard");
  const [period,   setPeriod]   = useState("month");
  const [selected, setSelected] = useState(null);
  const [alias,    setAlias]    = useState(() => {
    try { return localStorage.getItem("ledger.alias") || ""; } catch (e) { return ""; }
  });
  // Bumped whenever real data replaces mock data → forces re-render
  const [dataVersion, setDataVersion] = useState(0);

  // ── Auth + data bootstrap ──────────────────────────────────────────
  useEffect(() => {
    if (!window.sbClient) return; // mock mode — nothing to do

    async function boot() {
      const { data: { session } } = await window.sbClient.auth.getSession();
      if (session) {
        await refreshData(session.user, period);
        setView("leaderboard");
      }
    }
    boot();

    const { data: { subscription } } = window.sbClient.auth.onAuthStateChange(
      async (event, session) => {
        if (session && (event === "SIGNED_IN" || event === "TOKEN_REFRESHED")) {
          await refreshData(session.user, period);
        }
      }
    );
    return () => subscription.unsubscribe();
  }, []);

  // ── Reload leaderboard when period changes ──────────────────────
  const handleSetPeriod = async (p) => {
    setPeriod(p);
    if (window.sbClient) {
      const { data: { session } } = await window.sbClient.auth.getSession();
      if (session) await refreshData(session.user, p);
    }
  };

  async function refreshData(authUser, activePeriod) {
    const traders = await window.loadLeaderboard(activePeriod);
    if (!traders || !traders.length) return;

    // Enrich with generated visuals (curves, monthly, streak)
    traders.forEach((t) => {
      t.equityCurve = genEquityCurve(t.startBal, t.pct, 60, 0.018, t.seed);
      t.sparkline   = genEquityCurve(t.startBal, t.pct, 24, 0.025, t.seed + 1);
      t.tradeList   = genTrades(20, t.winRate, t.avgWin, t.avgLoss, t.seed + 2, new Date(2026, 4, 1));
      const r = mulberry32(t.seed + 100);
      t.monthly = ["Dec","Jan","Feb","Mar","Apr","May"].map((m) => ({
        month: m,
        pnl: +((r() > 0.25 ? 1 : -1) * (Math.abs(t.pnl) / 6) * (0.4 + r() * 1.6)).toFixed(2),
      }));
      const r2 = mulberry32(t.seed + 300);
      t.streak = Array.from({ length: 12 }, () => r2() * 100 < t.winRate ? "w" : "l");
    });

    window.TRADERS = traders;

    // Identify logged-in user
    const myRow = traders.find((t) => t._userId === authUser.id);
    if (myRow) {
      const savedAlias = localStorage.getItem("ledger.alias") || "";
      window.ME = { ...myRow, username: savedAlias || myRow.username, isMe: true };
      if (savedAlias) setAlias(savedAlias);
    }

    setDataVersion((v) => v + 1);
  }

  // ── Derive "me" ──────────────────────────────────────────────────
  const baseMe = window.ME;
  const tierOverride = tweaks.myTier && tweaks.myTier !== "auto" ? tweaks.myTier : null;
  const me = {
    ...baseMe,
    username: alias && alias.trim() ? alias.trim() : baseMe.username,
    isMe: true,
  };

  // Inject alias into TRADERS for leaderboard display
  useEffect(() => {
    if (!window.TRADERS) return;
    const meIdx = window.TRADERS.findIndex((t) => t.account === baseMe.account);
    if (meIdx >= 0) {
      window.TRADERS[meIdx].username = me.username;
      window.TRADERS[meIdx].handle   = "@you";
      window.TRADERS[meIdx].isMe     = true;
    }
  }, [alias, dataVersion]);

  // ── Accent color override ─────────────────────────────────────────
  const accentMap = {
    green: { hex: "#3F8B5B", gain: "oklch(0.52 0.10 150)", tint: "oklch(0.96 0.025 150)" },
    blue:  { hex: "#3A73C4", gain: "oklch(0.52 0.12 240)", tint: "oklch(0.96 0.03 240)" },
    gold:  { hex: "#B58A3A", gain: "oklch(0.55 0.13 80)",  tint: "oklch(0.96 0.04 80)" },
  };
  useEffect(() => {
    const c = accentMap[tweaks.accent] || accentMap.green;
    document.documentElement.style.setProperty("--gain", c.gain);
    document.documentElement.style.setProperty("--gain-tint", c.tint);
  }, [tweaks.accent]);

  const goto = (v, t) => {
    if (t) setSelected(t);
    setView(v);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  if (view === "login") {
    return (
      <Login
        onLogin={(newAlias) => {
          if (newAlias) {
            setAlias(newAlias);
            try { localStorage.setItem("ledger.alias", newAlias); } catch (e) {}
          }
          goto("leaderboard");
        }}
      />
    );
  }

  return (
    <div className="app grain">
      <Nav view={view} setView={setView} me={me} setSelected={setSelected} />
      <main data-screen-label={screenLabel(view)}>
        {view === "leaderboard" && (
          <Leaderboard
            onPick={(t) => goto("profile", t)}
            period={period}
            setPeriod={handleSetPeriod}
          />
        )}
        {view === "dashboard" && (
          <Dashboard
            trader={me}
            variant={tweaks.dashboardVariant}
            onOpenTrades={() => goto("trades", me)}
            onOpenProfile={() => goto("profile", me)}
            period={period}
            setPeriod={handleSetPeriod}
            tierOverride={tierOverride}
          />
        )}
        {view === "profile" && selected && (
          <Profile
            trader={selected}
            onBack={() => goto("leaderboard")}
            onOpenTrades={() => goto("trades", selected)}
          />
        )}
        {view === "trades" && selected && (
          <TradeHistory
            trader={selected}
            onBack={() => goto(selected.isMe ? "dashboard" : "profile")}
            period={period}
            setPeriod={handleSetPeriod}
          />
        )}
      </main>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Your tier (preview)">
          <TweakSelect
            label="Tier"
            value={tweaks.myTier}
            options={[
              { value: "auto",      label: "Auto · from composite score" },
              { value: "obsidian",  label: "1 · Obsidian (highest)" },
              { value: "blackopal", label: "2 · Black Opal" },
              { value: "cobalt",    label: "3 · Cobalt" },
              { value: "redberyl",  label: "4 · Red Beryl" },
              { value: "pallasite", label: "5 · Pallasite" },
              { value: "diamond",   label: "6 · Diamond (lowest)" },
            ]}
            onChange={(v) => setTweak("myTier", v)}
          />
          <TweakButton label="Open dashboard →" onClick={() => goto("dashboard")} />
        </TweakSection>
        <TweakSection label="Dashboard">
          <TweakRadio
            label="Layout"
            value={tweaks.dashboardVariant}
            options={[{ value: "A", label: "Airy" }, { value: "B", label: "Dense" }]}
            onChange={(v) => setTweak("dashboardVariant", v)}
          />
          <TweakColor
            label="Accent"
            value={(accentMap[tweaks.accent] || accentMap.green).hex}
            options={["#3F8B5B", "#3A73C4", "#B58A3A"]}
            onChange={(v) => {
              const name = v === "#3A73C4" ? "blue" : v === "#B58A3A" ? "gold" : "green";
              setTweak("accent", name);
            }}
          />
        </TweakSection>
        <TweakSection label="Jump to screen">
          <TweakButton label="Login screen"    onClick={() => setView("login")} />
          <TweakButton label="Leaderboard"     onClick={() => goto("leaderboard")} />
          <TweakButton label="My Dashboard"    onClick={() => goto("dashboard")} />
          <TweakButton label="View #1 profile" onClick={() => goto("profile", window.TRADERS[0])} />
          <TweakButton label="Trade history"   onClick={() => goto("trades", window.ME)} />
        </TweakSection>
        {window.sbClient && (
          <TweakSection label="Account">
            <TweakButton
              label="Sign out"
              onClick={async () => {
                await window.sbClient.auth.signOut();
                setView("login");
              }}
            />
          </TweakSection>
        )}
      </TweaksPanel>
    </div>
  );
}

function screenLabel(v) {
  return { login:"Login", leaderboard:"Leaderboard", dashboard:"My Dashboard", profile:"Public Profile", trades:"Trade History" }[v] || v;
}

function Nav({ view, setView, me, setSelected }) {
  const tabs = [
    { id: "leaderboard", label: "Leaderboard" },
    { id: "dashboard",   label: "My Dashboard" },
    { id: "trades",      label: "Trade History" },
  ];
  const goto = (id) => {
    if (id === "trades") setSelected(me);
    setView(id);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };
  return (
    <nav className="nav">
      <div className="nav-brand" onClick={() => goto("leaderboard")}>
        <div className="glyph">⟡</div>
        Ledger
      </div>
      <div className="nav-tabs">
        {tabs.map((t) => (
          <button key={t.id} className={`nav-tab ${view === t.id ? "active" : ""}`} onClick={() => goto(t.id)}>
            {t.label}
          </button>
        ))}
      </div>
      <div className="nav-right">
        <span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: "var(--ink-3)" }}>
          <span style={{ width: 6, height: 6, borderRadius: "50%", background: window.sbClient ? "var(--gain)" : "oklch(0.75 0.05 80)" }} />
          {window.sbClient ? "MT5 Connected" : "Demo Mode"}
        </span>
        <div style={{ display: "flex", alignItems: "center", gap: 10, paddingLeft: 12, borderLeft: "1px solid var(--line)" }}>
          <Avatar name={me.username} size={32} />
          <div>
            <div style={{ fontSize: 13, fontWeight: 500 }}>{me.username}</div>
            <div className="mono" style={{ fontSize: 11, color: "var(--ink-3)" }}>{me.account}</div>
          </div>
        </div>
      </div>
    </nav>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
