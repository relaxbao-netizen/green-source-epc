-- 自主檢查表（11 種檢查項目共用一張表，各項目的欄位存在 data jsonb）
-- 在 Supabase 後台 → SQL Editor 貼上執行一次即可。做法與其他資料表一致（不另開 RLS）。

create table if not exists site_selfcheck (
  id          bigint generated always as identity primary key,
  site_id     bigint not null,                  -- 對應 sites.id
  sc_type     text   not null,                  -- 檢查項目代碼，如 'bracket'（支架及固定座）
  check_date  date   not null,                  -- 檢驗日期
  data        jsonb  default '{}'::jsonb,        -- 該項目的表單內容（各項目欄位不同，存這裡）
  pdf         jsonb,                             -- 合成 PDF {id, view}
  note        text,                              -- 備註
  created_by  text,                              -- 填表人（登入者姓名）
  created_at  timestamptz default now()
);

create index if not exists idx_selfcheck_type_site_date on site_selfcheck (sc_type, site_id, check_date desc);

-- Supabase 新表預設會開 RLS，本專案其他表都關閉（anon 直接可寫），故關掉以保持一致：
alter table site_selfcheck disable row level security;
