-- ============================================================
-- 綠源戰情室　資料庫安全 (RLS) 設定
-- 原則：匿名(未登入)只能「讀」；「寫入/修改/刪除」需登入(Supabase Auth)。
-- app_users(權限)只有管理員能改；audit_log(稽核)只可新增不可改刪。
-- 本機工具(施工日誌 upload.py / wbs_sync.py)請改用 service_role key，會自動略過 RLS。
--
-- 執行方式：Supabase 後台 → SQL Editor → 貼上整段 → Run。
-- 事前確認：所有管理員的 email 都已存在 app_users(is_admin=true)。若有缺，先看最下方補上。
-- 緊急還原：見檔案最下方「ROLLBACK」。
-- ============================================================

-- 1) 管理員判定函式（SECURITY DEFINER 以避免 app_users 政策自我遞迴）
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.app_users u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and u.is_admin is true
      and u.active is not false
  );
$$;

-- 2) 一般資料表：匿名可讀、登入者可寫
do $$
declare t text;
begin
  foreach t in array array[
    'cert_expiry','site_insurance','daily_log_status','supervisor_log',
    'weather_log','custom_places','supervisors','sites','uniforms',
    'equipment_photo','equipment','equipment_borrow','app_request','approvers'
  ] loop
    if to_regclass('public.'||t) is null then
      raise notice '跳過不存在的資料表: %', t;
      continue;
    end if;
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists p_read on public.%I;', t);
    execute format('drop policy if exists p_write on public.%I;', t);
    execute format('create policy p_read  on public.%I for select to anon, authenticated using (true);', t);
    execute format('create policy p_write on public.%I for all    to authenticated using (true) with check (true);', t);
  end loop;
end $$;

-- 3) app_users：所有人可讀(登入流程需讀自己權限)、只有管理員可寫(防自我升權)
alter table public.app_users enable row level security;
drop policy if exists p_read  on public.app_users;
drop policy if exists p_write on public.app_users;
create policy p_read  on public.app_users for select to anon, authenticated using (true);
create policy p_write on public.app_users for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- 4) audit_log：登入者可新增(記錄自己動作)；只有管理員可讀；不可修改/刪除(稽核不可竄改)
alter table public.audit_log enable row level security;
drop policy if exists p_read   on public.audit_log;
drop policy if exists p_insert on public.audit_log;
create policy p_read   on public.audit_log for select to authenticated using (public.is_admin());
create policy p_insert on public.audit_log for insert to authenticated with check (true);

-- ============================================================
-- (需要時) 補登管理員：若有管理員尚未在 app_users，先跑這段再啟用上面政策
-- insert into public.app_users (email, name, perms, is_admin, active)
-- values ('someone@example.com', '姓名', '[]'::jsonb, true, true)
-- on conflict (email) do update set is_admin = true, active = true;
-- ============================================================

-- ============================================================
-- ROLLBACK（緊急關閉 RLS，恢復成原本「匿名可讀可寫」）
-- do $$ declare t text; begin
--   foreach t in array array[
--     'cert_expiry','site_insurance','daily_log_status','supervisor_log',
--     'weather_log','custom_places','supervisors','sites','uniforms',
--     'equipment_photo','equipment','equipment_borrow','app_request','approvers',
--     'app_users','audit_log'
--   ] loop
--     if to_regclass('public.'||t) is not null then
--       execute format('alter table public.%I disable row level security;', t);
--     end if;
--   end loop;
-- end $$;
-- ============================================================
