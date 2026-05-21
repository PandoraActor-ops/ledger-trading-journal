/**
 * Supabase Edge Function: push-trade
 * MT5 EA calls this endpoint to push trades and stats.
 *
 * Headers required:
 *   X-EA-Token: <your API token from the dashboard>
 *   Content-Type: application/json
 *
 * Body types:
 *   { "type": "trade",  ...trade fields }
 *   { "type": "stats",  "period": "alltime"|"month"|"week"|"today", ...stat fields }
 *   { "type": "equity", "balance": 12500, "equity": 12480, "snapshot_time": "..." }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ea-token",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = Deno.env.toObject();
    const sb = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

    // ── Validate token ──────────────────────────────────────────────
    const token = req.headers.get("X-EA-Token");
    if (!token) return json({ error: "Missing X-EA-Token header" }, 401);

    const { data: tokenRow, error: tokenErr } = await sb
      .from("api_tokens").select("user_id").eq("token", token).single();
    if (tokenErr || !tokenRow) return json({ error: "Invalid token" }, 401);

    // Update last_used (fire-and-forget)
    sb.from("api_tokens").update({ last_used: new Date().toISOString() }).eq("token", token);

    // ── Dispatch by type ────────────────────────────────────────────
    const body = await req.json();
    const { type, ...payload } = body;
    const uid = tokenRow.user_id;

    if (type === "trade") {
      // Upsert on (user_id, ticket) to be idempotent
      const { error } = await sb.from("trades").upsert({
        user_id:      uid,
        ticket:       payload.ticket,
        symbol:       payload.symbol,
        side:         (payload.side || "buy").toLowerCase(),
        lots:         payload.lots,
        open_price:   payload.open_price,
        close_price:  payload.close_price,
        open_time:    payload.open_time,
        close_time:   payload.close_time,
        duration_min: payload.duration_min,
        pnl:          payload.pnl,
        commission:   payload.commission ?? 0,
        swap:         payload.swap ?? 0,
      }, { onConflict: "user_id,ticket" });
      if (error) throw error;

    } else if (type === "stats") {
      const { error } = await sb.from("account_stats").upsert({
        user_id:         uid,
        period:          payload.period || "alltime",
        start_balance:   payload.start_balance,
        current_balance: payload.current_balance,
        net_pnl:         payload.net_pnl,
        pct_return:      payload.pct_return,
        win_rate:        payload.win_rate,
        trades_count:    payload.trades_count,
        profit_factor:   payload.profit_factor,
        recovery_factor: payload.recovery_factor,
        max_dd_pct:      payload.max_dd_pct,
        max_dd_usd:      payload.max_dd_usd,
        avg_win:         payload.avg_win,
        avg_loss:        payload.avg_loss,
        max_cons_win:    payload.max_cons_win,
        max_cons_loss:   payload.max_cons_loss,
        best_trade:      payload.best_trade,
        worst_trade:     payload.worst_trade,
        updated_at:      new Date().toISOString(),
      }, { onConflict: "user_id,period" });
      if (error) throw error;

    } else if (type === "equity") {
      const { error } = await sb.from("equity_snapshots").insert({
        user_id:       uid,
        balance:       payload.balance,
        equity:        payload.equity,
        snapshot_time: payload.snapshot_time || new Date().toISOString(),
      });
      if (error) throw error;

    } else {
      return json({ error: `Unknown type: ${type}` }, 400);
    }

    return json({ ok: true });

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return json({ error: msg }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
