# log-weather — 每日自動記錄施工晴雨表

這支 Edge Function 會每天自動向中央氣象署抓各案場縣市的上午/下午天氣，寫入 `weather_log`，
**不需要有人開啟網頁**，補足前端「開頁面才記錄」可能漏掉的日子。

---

## 一次性設定（全部在 Supabase 後台操作，免安裝任何工具）

### 步驟 1：確認 weather_log 資料表已建立
若還沒建立，先在 **SQL Editor** 執行 `supabase-setup.sql` 裡的 `weather_log` 那段。

### 步驟 2：建立 Edge Function
1. Supabase 專案 → 左側 **Edge Functions** → **Deploy a new function**（或 Create function）。
2. 函式名稱填 `log-weather`。
3. 把本資料夾 `index.ts` 的內容整段貼進編輯器 → **Deploy**。

### 步驟 3：設定氣象署授權碼（secret）
1. Edge Functions → **Secrets**（或專案 Settings → Edge Functions → Secrets）。
2. 新增一筆：
   - Name：`CWA_KEY`
   - Value：`CWA-9F041E77-61F4-4DDF-A445-56F241146723`
3. 儲存。

> `SUPABASE_URL` 與 `SUPABASE_SERVICE_ROLE_KEY` 由 Supabase 自動提供，不必自己設。

### 步驟 4：設定每日排程
**方法 A（推薦，UI 操作）**：
Edge Functions → 進入 `log-weather` → **Schedules**（排程）→ 新增排程，
Cron 填 `0 23 * * *`（= 台灣時間每天早上 07:00；Supabase cron 用 UTC，23:00 UTC = 隔日 07:00 台灣）。

**方法 B（用 SQL，pg_cron）**：在 SQL Editor 執行（把 `<PROJECT_REF>` 換成你的專案代號、`<ANON_OR_SERVICE_KEY>` 換成你的 anon key）：

```sql
-- 啟用排程與 HTTP 擴充（只需一次）
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 每天 23:00 UTC（台灣 07:00）呼叫 log-weather 函式
select cron.schedule(
  'daily-weather-log',
  '0 23 * * *',
  $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/log-weather',
    headers := '{"Authorization": "Bearer <ANON_OR_SERVICE_KEY>", "Content-Type": "application/json"}'::jsonb
  );
  $$
);
```

---

## 測試
部署後，可在 Edge Functions → `log-weather` → **Invoke**（或用瀏覽器/Postman 打函式 URL）手動執行一次，
回傳會像：`{"ok":true,"counties":8,"inserted":24}`，代表成功寫入。
之後回儀表板點「📋 產生施工晴雨表」就能看到資料。

## 取消排程（方法 B）
```sql
select cron.unschedule('daily-weather-log');
```
