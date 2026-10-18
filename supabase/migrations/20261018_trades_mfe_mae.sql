-- Add per-trade excursion columns (sent by LedgerPush v1.30+)
-- Run in Supabase Dashboard → SQL Editor BEFORE deploying the updated push-trade function.
ALTER TABLE public.trades
  ADD COLUMN IF NOT EXISTS mfe DECIMAL(15, 2),
  ADD COLUMN IF NOT EXISTS mae DECIMAL(15, 2);
