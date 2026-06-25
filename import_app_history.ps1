$ErrorActionPreference = 'Stop'
$base = 'https://tqczsusfovgasmdlifdk.supabase.co'
$key  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRxY3pzdXNmb3ZnYXNtZGxpZmRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMzE5MDYsImV4cCI6MjA5NjcwNzkwNn0.prkvN2iguEolMFe4fLew12nvSVNdJUKEmR_C3TIxcmg'
$hdr  = @{ apikey = $key; Authorization = "Bearer $key" }
$sheet = 'https://docs.google.com/spreadsheets/d/1frommKsQMygWJboZjgubSbode0C7P_f3XYT_P040uhA/gviz/tq?tqx=out:csv&gid=2046930903'

# --- 1. 取得試算表 CSV ---
$csv = (Invoke-WebRequest -Uri $sheet -UseBasicParsing).Content
$cols = 0..26 | ForEach-Object { "c$_" }
$rows = @($csv | ConvertFrom-Csv -Header $cols | Where-Object { $_.c1 -ne '流水編號' -and $_.c0 -notlike '*是否結束*' })

# --- 2. 工地主任名單（申請人正規化） ---
$svs = Invoke-RestMethod -Uri "$base/rest/v1/supervisors?select=name" -Headers $hdr
$svNames = @($svs | ForEach-Object { $_.name })
function Normalize-Person($n) {
  if (-not $n) { return $n }
  foreach ($s in $svNames) { if ($s -like "$n*") { return $s } }
  return $n
}
function Parse-Num($s) {
  if (-not $s) { return 0 }
  $t = ("$s" -replace '[,\s]', ''); $d = 0.0
  if ([double]::TryParse($t, [ref]$d)) { return $d } else { return 0 }
}
function Parse-Date($s) {
  if (-not $s) { return $null }
  $m = [regex]::Match("$s", '(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})')
  if (-not $m.Success) { return $null }
  return ('{0}-{1:d2}-{2:d2}' -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
}
function Parse-Qty($s) {
  $s = "$s".Trim()
  $m = [regex]::Match($s, '^([\d,.]+)\s*(.*)$')
  if ($m.Success -and $m.Groups[1].Value) { return @{ qty = (Parse-Num $m.Groups[1].Value); unit = $m.Groups[2].Value.Trim() } }
  return @{ qty = $null; unit = $s }
}
function Tier($a) { if ($a -ge 1000000) { '100萬以上' } elseif ($a -ge 100000) { '10萬~100萬' } else { '10萬以下' } }

# --- 3. 分組（多列明細） ---
$recs = New-Object System.Collections.ArrayList
$cur = $null
foreach ($r in $rows) {
  $serial = "$($r.c1)".Trim()
  if ($serial) {
    if ($cur) { [void]$recs.Add($cur) }
    $total = Parse-Num $r.c9
    $items = New-Object System.Collections.ArrayList
    if ("$($r.c6)".Trim()) { $q = Parse-Qty $r.c8; [void]$items.Add(@{ name = "$($r.c6)".Trim(); qty = $q.qty; unit = $q.unit; price = 0; amount = 0 }) }
    $cost = if ("$($r.c10)".Trim() -eq 'O') { '可向客戶請款' } else { '公司吸收' }
    $stat = if ("$($r.c0)".Trim() -eq 'X') { 'rejected' } else { 'archived' }
    $cur = [ordered]@{
      serial_no      = $serial
      apply_date     = (Parse-Date $r.c2)
      site_name      = "$($r.c3)".Trim()
      applicant      = (Normalize-Person "$($r.c4)".Trim())
      responsibility = "$($r.c5)".Trim()
      reason_text    = "$($r.c7)".Trim()
      total_amount   = $total
      amount_tier    = (Tier $total)
      cost_owner     = $cost
      client_amount  = (Parse-Num $r.c11)
      status         = $stat
      apply_dept     = ''
      items          = $items
    }
  } elseif ($cur) {
    $name = "$($r.c6)".Trim()
    if ($name) { $q = Parse-Qty $r.c8; [void]$cur.items.Add(@{ name = $name; qty = $q.qty; unit = $q.unit; price = 0; amount = 0 }) }
  }
}
if ($cur) { [void]$recs.Add($cur) }
$recs = @($recs | Where-Object { $_.site_name -or $_.total_amount -gt 0 -or $_.items.Count -gt 0 })
Write-Host ("解析筆數: {0}" -f $recs.Count)

# --- 4. 去重 ---
$existing = @(Invoke-RestMethod -Uri "$base/rest/v1/app_request?select=serial_no" -Headers $hdr)
$exSet = @{}
foreach ($e in $existing) { if ($e.serial_no) { $exSet["$($e.serial_no)"] = $true } }
$fresh = @($recs | Where-Object { -not $exSet.ContainsKey("$($_.serial_no)") })
Write-Host ("已存在: {0}　新匯入: {1}" -f ($recs.Count - $fresh.Count), $fresh.Count)
if ($fresh.Count -eq 0) { Write-Host '沒有新資料可匯入。'; exit 0 }

# --- 5. 寫入 Supabase（轉成 items 為陣列的物件） ---
$payload = @($fresh | ForEach-Object {
  $o = [ordered]@{}; foreach ($k in $_.Keys) { $o[$k] = $_[$k] }
  $o.items = @($_.items)
  $o
})
$body = ConvertTo-Json -InputObject $payload -Depth 8
if ($payload.Count -eq 1) { $body = "[$body]" }
$postHdr = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json; charset=utf-8'; Prefer = 'return=minimal' }
Invoke-RestMethod -Uri "$base/rest/v1/app_request" -Method Post -Headers $postHdr -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
Write-Host ("OK 已匯入 {0} 筆。" -f $payload.Count)

Write-Host '--- 申請人對應 ---'
$recs | Group-Object applicant | Sort-Object Count -Descending | ForEach-Object { Write-Host ("{0}  x{1}" -f $_.Name, $_.Count) }
