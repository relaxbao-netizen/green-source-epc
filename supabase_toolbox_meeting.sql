-- 施工前工具箱會議記錄資料表
-- 在 Supabase 後台 → SQL Editor 貼上執行一次即可。
-- 做法與戰情室其他資料表一致（不另開 RLS，anon key 直接可讀寫）。

create table if not exists site_toolbox_meeting (
  id          bigint generated always as identity primary key,
  site_id     bigint not null,                         -- 對應 sites.id
  meet_date   date   not null,                         -- 會議日期
  items       jsonb  default '[]'::jsonb,              -- 施工項目名稱陣列，如 ["模組安裝","機電平台施作"]
  record_file jsonb,                                   -- 紙本「施工前工具箱會議記錄」掃描檔 {id, view, url}
  photos      jsonb  default '[]'::jsonb,              -- 工地人員照片 [{id, url, view}, ...]
  note        text,                                    -- 備註
  created_by  text,                                    -- 填寫人（登入者姓名）
  created_at  timestamptz default now()
);

create index if not exists idx_toolbox_site_date on site_toolbox_meeting (site_id, meet_date desc);
