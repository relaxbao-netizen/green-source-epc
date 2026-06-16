// Supabase Edge Function：每日自動記錄各案場縣市的上午/下午天氣到 weather_log
//
// 部署與排程方式見 supabase/functions/log-weather/README.md
//
// 需要的環境變數（Supabase 會自動注入前兩個，CWA_KEY 需自行設定）：
//   SUPABASE_URL               （自動）
//   SUPABASE_SERVICE_ROLE_KEY  （自動）
//   CWA_KEY                    （中央氣象署授權碼，需手動設定 secret）

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CWA_KEY = Deno.env.get("CWA_KEY")!;
const RAIN_THRESHOLD = 70; // 與前端一致（此函式僅記錄，不在此判定）

// 案場縣市 → CWA 縣市名稱
const CWA_COUNTY: Record<string, string> = {
  "台北": "臺北市", "臺北": "臺北市", "新北": "新北市", "基隆": "基隆市", "桃園": "桃園市",
  "新竹": "新竹市", "竹北": "新竹縣", "苗栗": "苗栗縣", "台中": "臺中市", "臺中": "臺中市",
  "彰化": "彰化縣", "南投": "南投縣", "雲林": "雲林縣", "嘉義": "嘉義市", "台南": "臺南市", "臺南": "臺南市",
  "高雄": "高雄市", "屏東": "屏東縣", "宜蘭": "宜蘭縣", "花蓮": "花蓮縣", "台東": "臺東縣", "臺東": "臺東縣",
  "澎湖": "澎湖縣", "金門": "金門縣", "連江": "連江縣",
};

function cwaCountyName(city: string | null): string | null {
  if (!city) return null;
  if (CWA_COUNTY[city]) return CWA_COUNTY[city];
  if (city.endsWith("市") || city.endsWith("縣")) return city.replace("台", "臺");
  return null;
}

// 各縣市「未來2天逐3小時」鄉鎮市區預報資料集代號
const CWA_TOWN_DATASET: Record<string, string> = {
  "基隆市": "F-D0047-049", "臺北市": "F-D0047-061", "新北市": "F-D0047-069", "桃園市": "F-D0047-005",
  "新竹縣": "F-D0047-009", "新竹市": "F-D0047-053", "苗栗縣": "F-D0047-013", "臺中市": "F-D0047-073",
  "彰化縣": "F-D0047-017", "南投縣": "F-D0047-021", "雲林縣": "F-D0047-025", "嘉義縣": "F-D0047-029",
  "嘉義市": "F-D0047-057", "臺南市": "F-D0047-077", "高雄市": "F-D0047-065", "屏東縣": "F-D0047-033",
  "宜蘭縣": "F-D0047-001", "花蓮縣": "F-D0047-041", "臺東縣": "F-D0047-037", "澎湖縣": "F-D0047-045",
  "金門縣": "F-D0047-085", "連江縣": "F-D0047-081",
};

function siteArea(addr: string): string | null {
  const m = (addr || "").match(/(?:縣|市)(.{1,3}?[區鎮鄉市])/);
  return m ? m[1] : null;
}
function addrCounty(addr: string): string | null {
  const a = (addr || "").replace(/^台/, "臺");
  const m = a.match(/^(.{2}[縣市])/);
  return m ? m[0] : null;
}
// { county, area, dsId, label }；label = 區/鎮（有的話）否則縣市
function siteLoc(city: string, addr: string) {
  const county = addrCounty(addr) || cwaCountyName(city);
  const area = siteArea(addr);
  const dsId = county ? CWA_TOWN_DATASET[county] : null;
  const useArea = !!(area && dsId);
  return { county, area: useArea ? area : null, dsId: useArea ? dsId : null, label: useArea ? area : county };
}

// 取台灣時區的日期字串（YYYY-MM-DD），i=0 為今天、1 為明天…
function taiwanDate(i: number): string {
  return new Date(Date.now() + 8 * 3600e3 + i * 864e5).toISOString().slice(0, 10);
}

interface Slot { dateStr: string; hour: number; weather: string; pop: number; }

async function fetch3h(datasetId: string, locationName: string): Promise<Slot[] | null> {
  const u = `https://opendata.cwa.gov.tw/api/v1/rest/datastore/${datasetId}?Authorization=${CWA_KEY}&LocationName=${encodeURIComponent(locationName)}`;
  const res = await fetch(u);
  if (!res.ok) return null;
  const j = await res.json();
  const loc = j?.records?.Locations?.[0]?.Location?.[0];
  if (!loc) return null;
  const wx = loc.WeatherElement.find((e: any) => e.ElementName === "天氣現象");
  const pop = loc.WeatherElement.find((e: any) => e.ElementName === "3小時降雨機率");
  // CWA 時間字串已是台灣時間（+08:00），直接從字串取日期與小時，避免時區誤差
  return wx.Time.map((t: any, i: number) => ({
    dateStr: t.StartTime.slice(0, 10),
    hour: +t.StartTime.slice(11, 13),
    weather: t.ElementValue[0].Weather,
    pop: +pop.Time[i].ElementValue[0].ProbabilityOfPrecipitation,
  }));
}

// 有區/鎮則查鄉鎮資料集，失敗或無區則退回縣市級（F-D0047-089）
async function fetchLocForecast(loc: { county: string | null; area: string | null; dsId: string | null }): Promise<Slot[] | null> {
  if (loc.dsId && loc.area) {
    const s = await fetch3h(loc.dsId, loc.area);
    if (s) return s;
  }
  return loc.county ? await fetch3h("F-D0047-089", loc.county) : null;
}

// 擷取某日上午(06-12)、下午(12-18)：取該時段最大降雨機率
function extractAMPM(slots: Slot[], dateStr: string) {
  const seg: Record<string, [number, number]> = { am: [6, 12], pm: [12, 18] };
  const out: Record<string, { weather: string | null; pop: number | null }> = {};
  for (const k in seg) {
    const [a, b] = seg[k];
    let mp: number | null = null, w: string | null = null;
    for (const s of slots) {
      if (s.dateStr === dateStr && s.hour >= a && s.hour < b) {
        if (mp === null || s.pop > mp) { mp = s.pop; w = s.weather; }
      }
    }
    out[k] = { weather: w, pop: mp };
  }
  return out;
}

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 取所有案場，以「行政區或縣市」(label) 為單位，各挑一個代表
  const { data: siteRows, error: siteErr } = await supabase.from("sites").select("city, addr");
  if (siteErr) return new Response(JSON.stringify({ error: siteErr.message }), { status: 500 });
  const locMap: Record<string, ReturnType<typeof siteLoc>> = {};
  for (const r of (siteRows || [])) {
    const L = siteLoc(r.city, r.addr);
    if (L.label && !locMap[L.label]) locMap[L.label] = L;
  }
  const labels = Object.keys(locMap);
  if (!labels.length) return new Response(JSON.stringify({ ok: true, inserted: 0, note: "no locations" }));

  const dates = [0, 1, 2, 3].map(taiwanDate);

  // 已存在的 (date, label)，避免覆蓋（county 欄存放行政區或縣市字串）
  const { data: existing } = await supabase.from("weather_log")
    .select("log_date,county").in("county", labels).in("log_date", dates);
  const have = new Set((existing || []).map((r: any) => r.log_date + "|" + r.county));

  const rows: any[] = [];
  for (const label of labels) {
    const slots = await fetchLocForecast(locMap[label]);
    if (!slots) continue;
    for (const ds of dates) {
      if (have.has(ds + "|" + label)) continue;
      const ap = extractAMPM(slots, ds);
      if (ap.am.pop === null && ap.pm.pop === null) continue;
      rows.push({
        log_date: ds, county: label,
        am_weather: ap.am.weather, am_pop: ap.am.pop,
        pm_weather: ap.pm.weather, pm_pop: ap.pm.pop,
      });
    }
  }

  if (rows.length) {
    const { error } = await supabase.from("weather_log")
      .upsert(rows, { onConflict: "log_date,county", ignoreDuplicates: true });
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true, locations: labels.length, inserted: rows.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
