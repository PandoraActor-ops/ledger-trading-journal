-- ═══════════════════════════════════════════════════════════════════
-- Ledger — Trading Journal  ·  Supabase Database Schema
-- วิธีใช้: เปิด Supabase Dashboard → SQL Editor → วางทั้งหมด → Run
-- ═══════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── Profiles (ข้อมูลผู้ใช้) ────────────────────────────────────────
CREATE TABLE public.profiles (
  id           UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  alias        TEXT UNIQUE NOT NULL,
  mt5_account  TEXT,           -- masked account number
  mt5_server   TEXT,
  country      TEXT DEFAULT 'TH',
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─── Trades (ประวัติการเทรดแต่ละ order) ───────────────────────────
CREATE TABLE public.trades (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  ticket        BIGINT,         -- MT5 ticket number (unique ต่อ account)
  symbol        TEXT NOT NULL,
  side          TEXT NOT NULL CHECK (side IN ('buy', 'sell')),
  lots          DECIMAL(10, 2),
  open_price    DECIMAL(15, 5),
  close_price   DECIMAL(15, 5),
  open_time     TIMESTAMPTZ,
  close_time    TIMESTAMPTZ NOT NULL,
  duration_min  INTEGER,
  pnl           DECIMAL(15, 2) NOT NULL,
  commission    DECIMAL(10, 2) DEFAULT 0,
  swap          DECIMAL(10, 2) DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, ticket)    -- ป้องกัน duplicate trade
);

-- ─── Account Stats (สถิติสรุปแยกตาม period — EA ส่งมาอัพเดท) ─────
CREATE TABLE public.account_stats (
  id              BIGSERIAL PRIMARY KEY,
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  period          TEXT NOT NULL DEFAULT 'alltime',
  start_balance   DECIMAL(15, 2) DEFAULT 10000,
  current_balance DECIMAL(15, 2),
  net_pnl         DECIMAL(15, 2),
  pct_return      DECIMAL(10, 4),   -- % return
  win_rate        DECIMAL(8, 4),    -- % win rate
  trades_count    INTEGER,
  profit_factor   DECIMAL(10, 4),
  recovery_factor DECIMAL(10, 4),
  max_dd_pct      DECIMAL(8, 4),    -- max drawdown %
  max_dd_usd      DECIMAL(15, 2),
  avg_win         DECIMAL(15, 2),
  avg_loss        DECIMAL(15, 2),
  max_cons_win    INTEGER,
  max_cons_loss   INTEGER,
  best_trade      DECIMAL(15, 2),
  worst_trade     DECIMAL(15, 2),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, period)
);

-- ─── Equity Snapshots (สำหรับ equity curve chart) ─────────────────
CREATE TABLE public.equity_snapshots (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  balance       DECIMAL(15, 2) NOT NULL,
  equity        DECIMAL(15, 2),
  snapshot_time TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─── API Tokens (EA ใช้ token นี้ส่งข้อมูลเข้าระบบ) ───────────────
CREATE TABLE public.api_tokens (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  token       TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  label       TEXT DEFAULT 'MT5 EA',
  last_used   TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════
-- Row Level Security (RLS)
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trades           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_stats    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equity_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_tokens       ENABLE ROW LEVEL SECURITY;

-- Profiles: ทุกคนอ่านได้ (leaderboard), เจ้าของเท่านั้นแก้ได้
CREATE POLICY "profiles_public_read" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "profiles_own_write"   ON public.profiles FOR ALL    USING (auth.uid() = id);

-- Trades: ทุกคนอ่านได้ (public profile), เจ้าของเท่านั้นเขียนได้
CREATE POLICY "trades_public_read" ON public.trades FOR SELECT USING (true);
CREATE POLICY "trades_own_write"   ON public.trades FOR ALL    USING (auth.uid() = user_id);

-- Account stats: ทุกคนอ่านได้ (leaderboard ranking)
CREATE POLICY "stats_public_read" ON public.account_stats FOR SELECT USING (true);
CREATE POLICY "stats_own_write"   ON public.account_stats FOR ALL    USING (auth.uid() = user_id);

-- Equity snapshots: เจ้าของเท่านั้น
CREATE POLICY "equity_own" ON public.equity_snapshots FOR ALL USING (auth.uid() = user_id);

-- API tokens: เจ้าของเท่านั้น
CREATE POLICY "tokens_own" ON public.api_tokens FOR ALL USING (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════════
-- Triggers
-- ═══════════════════════════════════════════════════════════════════

-- สร้าง profile อัตโนมัติเมื่อ user สมัครสมาชิก
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, alias, mt5_account, mt5_server, country)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'alias', 'Trader_' || left(NEW.id::text, 6)),
    NEW.raw_user_meta_data->>'mt5_account',
    NEW.raw_user_meta_data->>'mt5_server',
    COALESCE(NEW.raw_user_meta_data->>'country', 'TH')
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- สร้าง API token อัตโนมัติเมื่อ profile ถูกสร้าง
CREATE OR REPLACE FUNCTION public.handle_new_profile()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.api_tokens (user_id, label)
  VALUES (NEW.id, 'MT5 EA — default');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_profile_created
  AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_profile();

-- ═══════════════════════════════════════════════════════════════════
-- Helper View: Leaderboard (optional — สะดวกสำหรับ query โดยตรง)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.leaderboard_alltime AS
  SELECT
    p.alias,
    p.mt5_account,
    p.country,
    s.pct_return,
    s.net_pnl,
    s.win_rate,
    s.trades_count,
    s.profit_factor,
    s.max_dd_pct,
    s.updated_at
  FROM public.profiles p
  LEFT JOIN public.account_stats s ON s.user_id = p.id AND s.period = 'alltime'
  ORDER BY s.pct_return DESC NULLS LAST;
