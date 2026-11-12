-- 進料檢驗表（8 種檢驗項目共用一張表，各項目的欄位存在 data jsonb）
-- 在 Supabase 後台 → SQL Editor 貼上執行一次即可。做法與其他資料表一致（不另開 RLS）。

create table if not exists site_incoming (
  id          bigint generated always as identity primary key,
  site_id     bigint not null,                  -- 對應 sites.id
  sc_type     text   not null,                  -- 檢驗項目代碼
  check_date  date   not null,                  -- 檢驗日期
  data        jsonb  default '{}'::jsonb,        -- 該項目的表單內容（各項目欄位不同，存這裡）
  pdf         jsonb,                             -- 合成 PDF {id, view, folder}
  note        text,                              -- 備註
  created_by  text,                              -- 填表人（登入者姓名）
  created_at  timestamptz default now()
);

create index if not exists idx_incoming_type_site_date on site_incoming (sc_type, site_id, check_date desc);

-- Supabase 新表預設會開 RLS，本專案其他表都關閉（anon 直接可寫），故關掉以保持一致：
alter table site_incoming disable row level security;
