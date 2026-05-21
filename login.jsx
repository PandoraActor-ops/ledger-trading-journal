/* Login screen — MT5 account + Supabase Auth */

function Login({ onLogin }) {
  const [account,  setAccount]  = useState("73801219");
  const [password, setPassword] = useState("");
  const [server,   setServer]   = useState("Exness-Real8");
  const [alias,    setAlias]    = useState("");
  const [step,     setStep]     = useState("connect"); // connect | register | token
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState(null);
  const [apiToken, setApiToken] = useState(null);

  const suggestions = ["GoldenFox", "Nightwave", "ByteRunner", "MarketAlchemist"];

  // If already have a session skip straight to app
  useEffect(() => {
    if (!window.sbClient) return;
    window.sbClient.auth.getSession().then(({ data: { session } }) => {
      if (session) onLogin("");
    });
  }, []);

  // ── Step 1: Connect (sign in or detect new user) ──────────────────
  const handleConnect = async (e) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    if (!window.sbClient) {
      await delay(900);
      setLoading(false);
      setStep("register");
      return;
    }

    try {
      const email = `mt5_${account.trim()}@ledger.app`;

      // Race the signIn against a 12-second timeout
      const signInPromise = window.sbClient.auth.signInWithPassword({ email, password });
      const timeout = new Promise((_, rej) =>
        setTimeout(() => rej(new Error("Connection timed out. Check your internet and try again.")), 12000)
      );
      const { data, error: signInErr } = await Promise.race([signInPromise, timeout]);

      if (data?.session) {
        setLoading(false);
        onLogin("");
        return;
      }

      if (signInErr?.message?.toLowerCase().includes("invalid login credentials")) {
        setStep("register");
      } else if (signInErr) {
        setError(signInErr.message);
      }
    } catch (err) {
      setError(err?.message || "Connection failed. Please try again.");
    }
    setLoading(false);
  };

  // ── Step 2: Register — choose alias and create account ───────────
  const handleRegister = async (e) => {
    e.preventDefault();
    const trimAlias = alias.trim();
    if (trimAlias.length < 3) return;
    setError(null);
    setLoading(true);

    if (!window.sbClient) {
      await delay(700);
      setLoading(false);
      onLogin(trimAlias);
      return;
    }

    try {
      const email = `mt5_${account.trim()}@ledger.app`;

      // ── Try sign-up first ────────────────────────────────────────
      let user = null;
      const { data, error: signUpErr } = await window.sbClient.auth.signUp({
        email,
        password,
        options: { data: { alias: trimAlias, mt5_account: account.trim(), mt5_server: server, country: "TH" } },
      });

      if (signUpErr) {
        // "User already registered" → try signing in instead
        const alreadyExists =
          signUpErr.message?.toLowerCase().includes("already") ||
          signUpErr.message?.toLowerCase().includes("registered") ||
          signUpErr.status === 422;

        if (alreadyExists) {
          const { data: siData, error: siErr } = await window.sbClient.auth.signInWithPassword({ email, password });
          if (siErr) {
            setError("Account exists — wrong password? Go back to Step 1 and sign in.");
            setLoading(false);
            return;
          }
          user = siData?.user;
        } else {
          setError(signUpErr.message);
          setLoading(false);
          return;
        }
      } else {
        user = data?.user;
      }

      // ── Fetch EA token (created by DB trigger) ───────────────────
      if (user) {
        await delay(600); // give trigger time to run
        const { data: tokenRow } = await window.sbClient
          .from("api_tokens")
          .select("token")
          .eq("user_id", user.id)
          .single();
        if (tokenRow?.token) {
          setApiToken(tokenRow.token);
          setStep("token");
          setLoading(false);
          return;
        }
      }

      setLoading(false);
      onLogin(trimAlias);
    } catch (err) {
      setError(err?.message || "Something went wrong. Please try again.");
      setLoading(false);
    }
  };

  // ── Step 3: Show EA token, then enter ─────────────────────────────
  const handleEnter = () => onLogin(alias.trim() || "");

  const delay = (ms) => new Promise((r) => setTimeout(r, ms));

  return (
    <div className="login-wrap">
      <div className="login-art">
        <div className="brandmark">⟡ Ledger</div>
        <div>
          <div className="kicker" style={{ color: "oklch(0.8 0.06 80)", marginBottom: 24 }}>
            Trading Journal · MT5 Edition
          </div>
          <h1>Every trade,<br /><em>measured.</em></h1>
          <p style={{ marginTop: 28, maxWidth: "36ch", color: "oklch(0.78 0 0)", fontSize: 15, lineHeight: 1.55 }}>
            Connect your MetaTrader 5 account and benchmark
            your performance against the global top 10.
          </p>
        </div>
        <div className="footer-meta">
          v1.0 · {new Date().getFullYear()} — Encrypted · Read-only · No order access
        </div>
        <div className="deco">
          <svg viewBox="0 0 400 400">
            {[180, 140, 100, 60].map((r) => (
              <circle key={r} cx="200" cy="200" r={r} stroke="white" strokeWidth="0.5" fill="none" />
            ))}
          </svg>
        </div>
      </div>

      <div className="login-form">
        <div className="inner">

          {/* Step indicator */}
          <div style={{ display: "flex", gap: 8, marginBottom: 18, alignItems: "center" }}>
            <StepDot active={step === "connect"} done={step !== "connect"} label="1 · Connect" />
            <span style={{ flex: 1, height: 1, background: "var(--line)" }} />
            <StepDot active={step === "register"} done={step === "token"} label="2 · Identity" />
            <span style={{ flex: 1, height: 1, background: "var(--line)" }} />
            <StepDot active={step === "token"} done={false} label="3 · EA Setup" />
          </div>

          {error && (
            <div style={{ marginBottom: 16, padding: "10px 14px", background: "oklch(0.97 0.02 15)", border: "1px solid oklch(0.85 0.05 15)", borderRadius: 8, fontSize: 13, color: "oklch(0.45 0.12 15)" }}>
              {error}
            </div>
          )}

          {/* ── Step 1: Connect ─────────────────────────────────────── */}
          {step === "connect" && (
            <>
              <div className="kicker" style={{ marginBottom: 10 }}>Sign in / Register</div>
              <h2 className="serif" style={{ fontSize: 38, margin: "0 0 24px", letterSpacing: "-0.02em" }}>
                Connect your MT5 account
              </h2>
              <form onSubmit={handleConnect}>
                <div className="field">
                  <label>Login number</label>
                  <input value={account} onChange={(e) => setAccount(e.target.value)}
                    placeholder="e.g. 73801219" className="mono" required />
                </div>
                <div className="field">
                  <label>Password</label>
                  <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                    placeholder="Create or enter your Ledger password" required />
                  <div style={{ fontSize: 11, color: "var(--ink-3)", marginTop: 5 }}>
                    {window.sbClient
                      ? "New user? This becomes your account password. Returning? Enter it to sign in."
                      : "Demo mode — any password works"}
                  </div>
                </div>
                <div className="field">
                  <label>Broker server</label>
                  <select value={server} onChange={(e) => setServer(e.target.value)}>
                    {["Exness-Real8","ICMarkets-Live02","Pepperstone-Live","FBS-Real-9","XM-Real-22","Other"].map((s) => (
                      <option key={s}>{s}</option>
                    ))}
                  </select>
                </div>
                <button className="btn" type="submit"
                  style={{ width: "100%", padding: "14px", fontSize: 14, marginTop: 8 }}
                  disabled={loading}>
                  {loading ? "Connecting…" : "Continue →"}
                </button>
              </form>
              <div style={{ marginTop: 20, display: "flex", alignItems: "center", gap: 10, fontSize: 12, color: "var(--ink-3)" }}>
                <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--gain)" }} />
                Read-only access · Investor password recommended
              </div>
            </>
          )}

          {/* ── Step 2: Alias ───────────────────────────────────────── */}
          {step === "register" && (
            <>
              <div className="kicker" style={{ marginBottom: 10 }}>
                Connected · {account ? window._maskAccount(account) : "MT5 Account"}
              </div>
              <h2 className="serif" style={{ fontSize: 38, margin: "0 0 8px", letterSpacing: "-0.02em" }}>
                Choose your alias
              </h2>
              <p style={{ color: "var(--ink-3)", fontSize: 14, margin: "0 0 24px", lineHeight: 1.5 }}>
                This name appears on the public leaderboard. Your MT5 account number stays masked.
              </p>
              <form onSubmit={handleRegister}>
                <div className="field">
                  <label>Display alias</label>
                  <input value={alias} onChange={(e) => setAlias(e.target.value)}
                    placeholder="Pick something memorable" autoFocus maxLength={24} />
                  <div style={{ fontSize: 11, color: "var(--ink-3)", marginTop: 6, display: "flex", justifyContent: "space-between" }}>
                    <span>3–24 characters</span>
                    <span className="mono">{alias.length}/24</span>
                  </div>
                </div>
                <div style={{ marginBottom: 16 }}>
                  <div className="kicker" style={{ marginBottom: 8 }}>Suggestions</div>
                  <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                    {suggestions.map((s) => (
                      <button key={s} type="button" onClick={() => setAlias(s)} className="pill"
                        style={{ cursor: "pointer", background: "var(--surface)", border: "1px solid var(--line)", padding: "5px 12px", fontSize: 12 }}>
                        {s}
                      </button>
                    ))}
                  </div>
                </div>
                <button className="btn" type="submit"
                  style={{ width: "100%", padding: "14px", fontSize: 14, marginTop: 8 }}
                  disabled={loading || alias.trim().length < 3}>
                  {loading ? "Creating account…" : "Create account →"}
                </button>
              </form>
            </>
          )}

          {/* ── Step 3: EA API Token ─────────────────────────────────── */}
          {step === "token" && (
            <>
              <div className="kicker" style={{ marginBottom: 10, color: "var(--gain)" }}>
                Account created ✓
              </div>
              <h2 className="serif" style={{ fontSize: 32, margin: "0 0 12px", letterSpacing: "-0.02em" }}>
                Your EA API Token
              </h2>
              <p style={{ color: "var(--ink-3)", fontSize: 14, margin: "0 0 20px", lineHeight: 1.5 }}>
                Copy this token into your <strong>TradingJournalEA</strong> settings in MT5.
                The EA will use it to send your trades to Ledger automatically.
              </p>

              <div style={{ background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: "14px 16px", marginBottom: 16 }}>
                <div className="kicker" style={{ marginBottom: 8 }}>API Token</div>
                <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
                  <code className="mono" style={{ fontSize: 11, flex: 1, wordBreak: "break-all", color: "var(--ink-2)", lineHeight: 1.6 }}>
                    {apiToken || "—"}
                  </code>
                  <button
                    type="button"
                    className="pill"
                    style={{ flexShrink: 0, cursor: "pointer", background: "var(--surface)", border: "1px solid var(--line)", padding: "6px 14px", fontSize: 12 }}
                    onClick={() => { navigator.clipboard.writeText(apiToken || ""); }}>
                    Copy
                  </button>
                </div>
              </div>

              <div style={{ background: "oklch(0.97 0.015 150)", border: "1px solid oklch(0.88 0.03 150)", borderRadius: 10, padding: "12px 14px", marginBottom: 20, fontSize: 12, color: "oklch(0.4 0.06 150)", lineHeight: 1.6 }}>
                <strong>In MT5:</strong> Attach TradingJournalEA → Inputs → paste token in <code>ApiToken</code> field → OK
              </div>

              <button className="btn" onClick={handleEnter}
                style={{ width: "100%", padding: "14px", fontSize: 14 }}>
                Enter the leaderboard →
              </button>

              <p style={{ marginTop: 12, fontSize: 12, color: "var(--ink-4)", textAlign: "center" }}>
                Token also visible in your Dashboard settings any time.
              </p>
            </>
          )}

          <div style={{ marginTop: 28, paddingTop: 20, borderTop: "1px solid var(--line)", fontSize: 13, color: "var(--ink-3)" }}>
            Just browsing?{" "}
            <a href="#" style={{ color: "var(--ink)" }}
              onClick={(e) => { e.preventDefault(); onLogin(""); }}>
              View leaderboard →
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}

function StepDot({ active, done, label }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 8, fontSize: 11, letterSpacing: "0.04em",
      color: active ? "var(--ink)" : done ? "var(--gain)" : "var(--ink-4)",
      fontWeight: active ? 500 : 400, whiteSpace: "nowrap" }}>
      <span style={{ width: 16, height: 16, borderRadius: "50%", display: "grid", placeItems: "center",
        border: `1.5px solid ${active ? "var(--ink)" : done ? "var(--gain)" : "var(--line)"}`,
        background: done ? "var(--gain)" : "transparent", color: "white", fontSize: 10 }}>
        {done ? "✓" : null}
      </span>
      {label}
    </span>
  );
}

window.Login = Login;
