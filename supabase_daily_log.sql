-- 線上填寫施工日誌：資料表 site_daily_log
-- 在 Supabase SQL Editor 執行一次即可。

create table if not exists public.site_daily_log (
  id            uuid primary key default gen_random_uuid(),
  site_id       bigint,
  log_date      date not null,
  weather       text,
  proj_name     text,
  contractor    text,
  start_date    date,
  end_date      date,
  contract_days int,
  cum_days      int,
  items         jsonb default '[]'::jsonb,   -- [{name,today,unit,cum,hours}]
  workers       jsonb default '[]'::jsonb,   -- [{trade,today,cum,note}]
  notify_sub    text,
  coordinate    text,
  reviewer      text,
  supervisor    text,
  photos        jsonb default '[]'::jsonb,   -- 工進照片公開 URL
  created_by    text,
  created_at    timestamptz default now()
);

-- 同案場同日只一筆（儲存時可覆蓋）
create unique index if not exists site_daily_log_site_date_uidx
  on public.site_daily_log (site_id, log_date);

-- 與戰情室其他資料表一致：anon 可讀寫（RLS 尚未啟用）
alter table public.site_daily_log disable row level security;
grant all on table public.site_daily_log to anon, authenticated, service_role;

-- ============================================================
-- 工進照片 Storage（在 Supabase 後台 Storage 建一個 bucket）
--   1) Storage → New bucket → 名稱: daily-log-photos → 勾選 Public bucket
--   2) 下面政策允許 anon 上傳/讀取（若用 Public bucket，讀取已公開；上傳政策仍需）
-- ============================================================
-- 允許任何人對 daily-log-photos 上傳與讀取（與目前 anon 寫入模式一致）
create policy "daily log photos anon write"
  on storage.objects for insert to anon
  with check (bucket_id = 'daily-log-photos');
create policy "daily log photos anon read"
  on storage.objects for select to anon
  using (bucket_id = 'daily-log-photos');
create policy "daily log photos anon update"
  on storage.objects for update to anon
  using (bucket_id = 'daily-log-photos');
create policy "daily log photos anon delete"
  on storage.objects for delete to anon
  using (bucket_id = 'daily-log-photos');
