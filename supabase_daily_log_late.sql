-- 施工日誌「曾逾期」標記：daily_log_status 新增 late 欄位
-- 用途：記錄某案場某表單在哪幾天「曾經逾期未繳」。即使之後補交（marks 變 ○），
--       逐日表那格底色仍保留淡紅，作為「這天曾逾期」的紀錄。
-- 爬蟲 upload.py 只寫 marks、不碰 late（merge-duplicates upsert），故 late 會長期保留。
-- 在 Supabase SQL Editor 執行一次即可。

alter table public.daily_log_status
  add column if not exists late jsonb;   -- 曾逾期的日子，形如 [15, 30, 31]（日）
