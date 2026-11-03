# 資料安全 (RLS) 上線步驟

目標：讓「讀取」維持匿名可看，「新增 / 修改 / 刪除」必須登入才行。
光有網頁裡那把 anon key 的人，之後**只能看、不能改 / 刪**。

> ⚠️ 請**照順序**做。順序錯會讓網站暫時無法儲存資料。

---

## 階段 0：Supabase 後台啟用 Google 登入（你做；對正式站無影響）

1. 進 Google Cloud Console → **APIs & Services → Credentials** → 打開那個 OAuth 2.0 用戶端
   （ID：`673692132426-i5jcda1ojh535j72njtgm2pnaaed9ggo.apps.googleusercontent.com`）
   - 複製 **Client secret**（待會要用）。
   - 在 **Authorized redirect URIs** 新增：
     `https://tqczsusfovgasmdlifdk.supabase.co/auth/v1/callback`
   - 儲存。
2. 進 Supabase 後台 → **Authentication → Providers → Google**：
   - 打開 **Enable**。
   - **Client ID**：貼上上面那個 `673692132426-...apps.googleusercontent.com`
   - **Client Secret**：貼上剛剛複製的 secret。
   - **Authorized Client IDs**（重要）：也貼上同一個 `673692132426-...apps.googleusercontent.com`
     （這個欄位才會讓網站的 Google 按鈕登入被 Supabase 接受）
   - 儲存。
3. 做完跟我說 → 我再部署網站的登入程式（階段 1）。

---

## 階段 1：部署網站登入程式（我做）

- 我已改好：按原本的 Google 按鈕登入時，會順便建立一個 Supabase 登入工作階段。
- 部署後請你用公司帳號登入一次，F12 → Console 不該出現「Supabase 登入失敗」。
- 此時 **RLS 還沒開**，所以就算沒登入也還能寫（不會壞），我們先確認登入有成功建立工作階段。

### 怎麼確認登入成功（你或我做）
登入後在 Console 貼：`await sb.auth.getSession()` → 應看到 `session` 有值（不是 null）。

---

## 階段 2：本機兩支工具改用 service_role key（我做，你貼 key）

施工日誌 `upload.py`、`wbs_sync.py` 目前用 anon key；RLS 開了之後 anon 不能寫，所以改用 **service_role key**（它會略過 RLS，只放在你本機、不會進 GitHub）。

- 到 Supabase → **Settings → API** → 複製 **service_role** key（這把很敏感，別外流）。
- 給我，我把兩支工具的 key 換掉。

---

## 階段 3：開啟 RLS（你做）

1. 先確認所有管理員 email 都在 `app_users`（是 `is_admin=true`）。
   - 不確定的話，先只跑 `supabase_rls.sql` 裡「補登管理員」那段（把 email 換成你們的）。
2. Supabase → **SQL Editor** → 貼上 `supabase_rls.sql` 全部 → **Run**。
3. 完成後測試：
   - **沒登入**：能看資料、但改任何東西會失敗 ✅（這就是目的）
   - **已登入**：新增 / 修改 / 刪除都正常 ✅
   - 本機兩支工具：照常能寫 ✅

---

## 出事了怎麼辦（緊急還原）

Supabase → SQL Editor → 跑 `supabase_rls.sql` 最下方 **ROLLBACK** 那段（已註解，取消註解再跑），
會把 RLS 關掉、恢復原狀，網站立刻恢復可寫。

---

## 之後想更嚴格（選配）
- 目前「登入者皆可寫」已擋掉匿名攻擊。若要再細分（例如只有管理員能改案場、申請人只能改自己單），
  可在前端規則之外，於 RLS 再加條件（用 `auth.jwt() ->> 'email'` 比對 `app_users`）。需要再跟我說。
