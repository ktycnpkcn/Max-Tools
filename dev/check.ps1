# MaxTools statik kontrolleri. Kullanım:  powershell -ExecutionPolicy Bypass -File dev\check.ps1
$root = Split-Path -Parent $PSScriptRoot
$p = Join-Path $root "MaxTools.ms"
$t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
$lines = $t -split "`r?`n"
$fail = 0

# 1) Fonksiyon tanımları, ileri referans, tanımsız MT_ adları
$defs = @{}; $dup = @()
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*fn\s+((MT_|MaxTools_)\w+)') { if ($defs.ContainsKey($matches[1])) { $dup += $matches[1] }; $defs[$matches[1]] = $i + 1 } }
$globals = @(); foreach ($l in $lines) { if ($l -match '^global\s+(.*)$') { $globals += ($matches[1] -split ',\s*' | % { ($_ -split '[\s=]')[0].Trim() }) } }
$fwd = @(); $undef = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  $code = ($lines[$i] -replace '--.*$', '') -replace '"[^"]*"', ''
  foreach ($m in [regex]::Matches($code, '\b((MT_|MaxTools_)\w+)\b')) {
    $n = $m.Groups[1].Value
    if ($defs.ContainsKey($n) -and $defs[$n] -gt ($i + 1) -and -not ($globals -contains $n)) { $fwd += "$($i+1): $n" }
    if (-not $defs.ContainsKey($n) -and -not ($globals -contains $n) -and $n -notmatch '^(MT_Timer|MaxTools_Main)$') { $undef += "$($i+1): $n" }
  }
}
"cift tanim     : $($dup.Count) $($dup -join ', ')"; $fail += $dup.Count
"ileri referans : $($fwd.Count) $($fwd -join ', ')"; $fail += $fwd.Count
"tanimsiz MT_   : $($undef.Count) $(($undef | Select-Object -Unique) -join ', ')"; $fail += $undef.Count

# 2) Büyük/küçük harf çakışması ve anahtar kelime / sınıf adı olan değişkenler
$clean = [regex]::Replace($t, '"(?:[^"\\]|\\.)*"', '""'); $clean = [regex]::Replace($clean, '--[^\r\n]*', '')
$cl = $clean -split "`r?`n"; $case = @()
for ($i = 0; $i -lt $cl.Count; $i++) {
  if ($cl[$i] -match '^\s*fn\s+(\w+)') {
    $name = $matches[1]; $depth = 0; $started = $false; $body = @()
    for ($j = $i; $j -lt $cl.Count; $j++) { $body += $cl[$j]; $depth += ([regex]::Matches($cl[$j], '\(')).Count - ([regex]::Matches($cl[$j], '\)')).Count; if ($cl[$j] -match '\(') { $started = $true }; if ($started -and $depth -le 0) { break }; if (-not $started -and $j -gt $i -and $cl[$j] -notmatch '^\s*$') { break } }
    $ids = [regex]::Matches(($body -join "`n"), '(?<![\.#\w])([A-Za-z_]\w*)') | % { $_.Groups[1].Value } | Sort-Object -Unique -CaseSensitive
    $ids | Group-Object { $_.ToLower() } | ? { ($_.Group | Sort-Object -Unique -CaseSensitive).Count -gt 1 } | % { $case += "$name : " + ($_.Group -join '/') }
  }
}
"buyuk/kucuk    : $($case.Count) $($case -join '; ')"; $fail += $case.Count
$kw = 'about','and','animate','as','at','by','case','catch','collect','continue','coordsys','do','else','exit','fn','for','from','function','global','if','in','local','macroscript','mapped','max','not','of','off','on','or','parameters','persistent','plugin','return','rollout','set','struct','then','throw','to','tool','try','undo','utility','when','where','while','with','color','point2','point3','box','name','string','path','array','integer','float','node','mesh','plane','sphere','ray','quat','matrix3','bitarray','time','value','index','geometry','selection'
$kwh = @()
foreach ($m in [regex]::Matches($clean, '(?im)\blocal\s+([^\r\n]+)')) { foreach ($part in ($m.Groups[1].Value -split ',')) { $n = ($part.Trim() -split '[\s=]')[0]; if ($kw -contains $n.ToLower()) { $kwh += $n } } }
foreach ($m in [regex]::Matches($clean, '(?im)^\s*fn\s+\w+\s+([^=\r\n]*)=')) { foreach ($n in ($m.Groups[1].Value.Trim() -split '\s+')) { $nn = ($n -split ':')[0]; if ($nn -and ($kw -contains $nn.ToLower())) { $kwh += $nn } } }
foreach ($m in [regex]::Matches($clean, '(?i)\bfor\s+(\w+)\s+(in|=)')) { if ($kw -contains $m.Groups[1].Value.ToLower()) { $kwh += "for:" + $m.Groups[1].Value } }
"anahtar kelime : $($kwh.Count) $($kwh -join ', ')"; $fail += $kwh.Count

# 3) Parantez dengesi
$po = ([regex]::Matches($clean, '\(')).Count; $pc = ([regex]::Matches($clean, '\)')).Count
$bo = ([regex]::Matches($clean, '\[')).Count; $bc = ([regex]::Matches($clean, '\]')).Count
"parantez       : ( $po / ) $pc    [ $bo / ] $bc"; if ($po -ne $pc -or $bo -ne $bc) { $fail++ }

# 4) C# buton kimlikleri <-> MT_Action
$cs = [System.IO.File]::ReadAllText((Join-Path $root "MaxToolsUI.cs"), [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($cs, 'Btn\(c, "[^"]*", \d+, \d+, \d+, \d+, "([^"]+)"') | % { $_.Groups[1].Value } | Sort-Object -Unique
$ai = $t.IndexOf("fn MT_Action id ="); $ab = $t.Substring($ai, [Math]::Min(8000, $t.Length - $ai))
$noAct = $ids | ? { -not $ab.Contains('"' + $_ + '":') }
"buton/eylem    : $($ids.Count) buton, karsiligi olmayan: $($noAct -join ', ')"; $fail += @($noAct).Count

# 5) C# derlemeleri (Max'in kullandığı CodeDom ile)
foreach ($pair in @(@("MaxToolsUI.cs", @("System.dll", "System.Drawing.dll", "System.Windows.Forms.dll")), @("MaxToolsPacker.cs", @("System.dll")))) {
  $code = [System.IO.File]::ReadAllText((Join-Path $root $pair[0]))
  $prov = New-Object Microsoft.CSharp.CSharpCodeProvider; $cp = New-Object System.CodeDom.Compiler.CompilerParameters
  foreach ($a in $pair[1]) { [void]$cp.ReferencedAssemblies.Add($a) }
  $cp.GenerateInMemory = $true
  $cr = $prov.CompileAssemblyFromSource($cp, [string[]]@($code))
  if ($cr.Errors.HasErrors) { "$($pair[0]) : HATA " + (($cr.Errors | % { $_.ToString() }) -join '; '); $fail++ } else { "$($pair[0]) : derlendi" }
}

# 6) BOM
foreach ($f in "MaxTools.ms", "MaxTools_SideBar.ms", "MaxTools_Install.ms") {   # .cs dosyalarini .NET zaten UTF-8 okur
  $b = [System.IO.File]::ReadAllBytes((Join-Path $root $f))
  $hasBom = ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
  $nonAscii = @($b | ? { $_ -gt 127 }).Count -gt 0   # saf ASCII dosyada BOM gerekmez
  if ($nonAscii -and -not $hasBom) { "BOM YOK (ASCII disi karakter var): $f"; $fail++ }
}
"-----"
if ($fail -eq 0) { "SONUC: TEMIZ" } else { "SONUC: $fail SORUN" }
