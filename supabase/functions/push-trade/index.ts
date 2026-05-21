/**
 * Supabase Edge Function: push-trade  (v3 — native fetch, no ESM imports)
 * MT5 EA sends trade data here; validated via X-EA-Token header.
 */

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-ea-token",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return ok("ok");

  const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPA_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const rest = (path: string) => `${SUPA_URL}/rest/v1/${path}`;
  const headers = (extra?: Record<string, string>) => ({
    "apikey": SUPA_KEY,
    "Authorization": `Bearer ${SUPA_KEY}`,
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
    ...extra,
  });

  try {
    // ── Validate EA token ───────────────────────────────────────────
    const token =
      req.headers.get("x-ea-token") ?? req.headers.get("X-EA-Token");
    if (!token) return err("Missing X-EA-Token header", 401);

    const tokRes = await fetch(
      rest(`api_tokens?token=eq.${encodeURIComponent(token)}&select=user_id`),
      { headers: headers() }
    );
    const tokRows = await tokRes.json();
    if (!Array.isArray(tokRows) || tokRows.length === 0)
      return err("Invalid token", 401);
    const uid: string = tokRows[0].user_id;

    // Update last_used (fire-and-forget)
    fetch(rest(`api_tokens?token=eq.${encodeURIComponent(token)}`), {
      method: "PATCH",
      headers: headers(),
      body: JSON.stringify({ last_used: new Date().toISOString() }),
    });

    // ── Parse body ──────────────────────────────────────────────────
    const body = await req.json();
    const { type, ...p } = body;

    if (type === "trade") {
      const r = await fetch(rest("trades"), {
        method: "POST",
        headers: headers({ "Prefer": "resolution=merge-duplicates,return=minimal" }),
        body: JSON.stringify({
          user_id: uid, ticket: p.ticket, symbol: p.symbol,
          side: (p.side || "buy").toLowerCase(), lots: p.lots,
          open_price: p.open_price, close_price: p.close_price,
          open_time: p.open_time, close_time: p.close_time,
          duration_min: p.duration_min, pnl: p.pnl,
          commission: p.commission ?? 0, swap: p.swap ?? 0,
        }),
      });
      if (!r.ok) throw new Error(await r.text());

    } else if (type === "stats") {
      const r = await fetch(rest("account_stats"), {
        method: "POST",
        headers: headers({ "Prefer": "resolution=merge-duplicates,return=minimal" }),
        body: JSON.stringify({
          user_id: uid, period: p.period || "alltime",
          start_balance: p.start_balance, current_balance: p.current_balance,
          net_pnl: p.net_pnl, pct_return: p.pct_return, win_rate: p.win_rate,
          trades_count: p.trades_count, profit_factor: p.profit_factor,
          recovery_factor: p.recovery_factor, max_dd_pct: p.max_dd_pct,
          max_dd_usd: p.max_dd_usd, avg_win: p.avg_win, avg_loss: p.avg_loss,
          max_cons_win: p.max_cons_win, max_cons_loss: p.max_cons_loss,
          best_trade: p.best_trade, worst_trade: p.worst_trade,
          updated_at: new Date().toISOString(),
        }),
      });
      if (!r.ok) throw new Error(await r.text());

    } else if (type === "equity") {
      const r = await fetch(rest("equity_snapshots"), {
        method: "POST",
        headers: headers(),
        body: JSON.stringify({
          user_id: uid, balance: p.balance, equity: p.equity,
          snapshot_time: p.snapshot_time || new Date().toISOString(),
        }),
      });
      if (!r.ok) throw new Error(await r.text());

    } else {
      return err(`Unknown type: ${type}`, 400);
    }

    return ok(JSON.stringify({ ok: true }), "application/json");

  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return err(msg, 500);
  }
});

function ok(body: string, ct = "text/plain") {
  return new Response(body, { headers: { ...CORS, "Content-Type": ct } });
}
function err(msg: string, status: number) {
  return new Response(JSON.stringify({ error: msg }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
