# MaxTools — proje rehberi (Claude için)

3ds Max 2024+ için modelleme / UV / isimlendirme / LOD-collision araç paketi.
Kullanıcı: 3D artist, **Türkçe konuşur** (yanıtlar Türkçe). **Uygulama içi metinler İngilizce**, kod yorumları Türkçe kalır.
Bu klasör (`D:\3Ds Max Element Detach\Max Tools`) hem çalışma klasörü hem git deposu hem de kullanıcının Max'inin
yüklediği kurulumdur. Üst klasördeki (`D:\3Ds Max Element Detach\*.ms|*.cs`) dosyalar ESKİ, kullanılmıyor.

## Dosyalar
| Dosya | Görev |
|---|---|
| `MaxTools.ms` | Tüm araçlar (MAXScript) + C# arayüz köprüsü. Sürüm: `MT_Version` (metin) ve `MT_BuildNum` (sayı). |
| `MaxToolsUI.cs` | Panel arayüzü (C#, sınıf `MTForm`). Max içinde CodeDom ile derlenir. Online güncelleyici de burada. |
| `MaxToolsPacker.cs` | Şekil tabanlı (raster) UV paketleyici (sınıf `MTPacker`). Max içinde derlenir. |
| `MaxTools_SideBar.ms` | Viewport soluna yapışan çubuk (cui dialog bar). İkonu `icons\MaxTools_bar_24i/m.bmp` (maske: siyah=görünür). |
| `MaxTools_Install.ms` | Kurulum: ikonları usericons'a kopyalar, `<userStartupScripts>\MaxTools_Startup.ms` yazar (macroScript `MaxTools_Open`, menü, sol çubuk). Bu klasörü fileIn eder. |
| `version.json` | Online güncelleme manifesti: version, build, notes, files (indirilecek dosyalar). |
| `README.txt` | Kullanıcı için İngilizce kurulum/güncelleme/kaldırma. |
| `dev\check.ps1` | Statik kontroller (aşağıda). Güncellemeyle dağıtılmaz. |

## Mimari
- **Arayüz tamamen C#'ta.** MAXScript'te HİÇ `dotNet.addEventHandler` olmamalı (yüzlerce MAXScript↔.NET olay bağı,
  sahne içe aktarırken bile "MAXScript Garbage Collection Error" verip işlemi geri aldırdı — bu yüzden taşındı).
- C# → MAXScript: `ManagedServices.MaxscriptSDK.ExecuteMaxscriptCommand` (reflection; MAXScript önce
  `dotNet.loadAssembly <maxroot>\ManagedServices.dll` yapar). Bulunamazsa yedek: tek `UIEvent` olayı + `MT_OnUIEvent`.
  Gönderilen komutlar: `MT_UIAction "<id>"`, `MT_UIClosed()`, `MT_ReloadAfterUpdate()`, `enableAccelerators = true/false`.
- MAXScript → C#: `Build`, `SetStartSize`, `ShowWith`, `GetInt` (sayı/segment 1..n/toggle 1-0), `GetText`,
  `SetStatus msg tip(0 bilgi,1 ok,2 uyarı,3 hata,4 çalışıyor)`, `SetProgress`, `ConfigureUpdates`, `CheckForUpdates`.
- `MAXFORM` tanımıyla `MaxCustomControls.MaxForm`'dan türer (yoksa `Form`). Kenarlıksız, kenardan boyutlandırılır
  (WM_NCHITTEST), duyarlı yerleşim: kartlar 305px, sığdığı kadar sütun; dar pencerede menü ikonlara küçülür.
- **Yeni araç eklemek:** C# `Build*Page` içine `Card(...)` + kontroller (`Btn` id'si benzersiz), `MaxTools.ms`'de
  `MT_Action` içine `"<id>": ...` ve araç fonksiyonu (`MaxTools_Status ... type:#ok` ile durum yazar, `undo "..." on (...)`).
- Ayarlar: `<plugcfg>\MaxTools.ini` ([Window] X,Y,W,H,Page; [Update] AutoCheck; [SideBar] Show).
- Teşhis: `MT_DiagWrite` → bu klasördeki `MaxTools_diag.txt` (gitignore'da). Kullanıcı Listener'ı nadiren gönderir;
  teşhisi dosyaya yazdırıp oradan okumak en verimli yol.

## Önemli teknik notlar
- **Unwrap UVW kenar numaraları Editable Poly'den tamamen farklı.** Poly kenarı → Unwrap: `MT_UV_PolyToUnwrapEdges`
  (UV kenarlarını `selectEdges #{k}`+`edgeToVertSelect`+`getSelectedVertices` ile tarar, `getVertexGeomIndexFromFace`
  ile geometri vertex'ine çevirir, sonra `peltEdgeSelToSeam` Unwrap'ın kendi dönüşümünü yapar). Doğrulandı.
- Yeni Unwrap'ta seam dizisi boş olabilir → önce `MT_UV_PrimeSeams`. Max 2024'te `quickPeel` YOK → `Unfold3DSolve`/`LSCMSolve`.
- Auto Unwrap = `FlattenBySmoothingGroup`; çok ada olursa (sculpt) çok yavaş → `MT_CountUVIslands` ile >500 ise sorulur.
- Gruplar (Drop to Ground): en dıştaki KAPALI grup başı taşınır; açık (Open) grupta üye tek başına (`isOpenGroupHead`).
- **Cables sayfası (5. sayfa, `MT_Cable*`):** rota noktaları yalnızca `CablePoint_R<rota>_<no>` adlı Dummy'ler; ad değişmez,
  sıra `MT_CableOrder` user prop'unda. Noktaya özel ayar `MT_C_<anahtar>` user prop; rota ayarları File Properties > Custom
  `MTCable_R<rota>`. Bir noktadaki ayar sonraki aralığı belirler. Çıktı `Cable_R<rota>_<no>` (+`MT_CableRoute` prop),
  Generate eskisini silip yeniden üretir. Yuvarlak = renderable spline, Flat = elle kurulan mesh (bant yönü kontrol için).
  C#↔MAXScript: `CableSetRoutes/CableSetList/CableShow`, değer değişince `cblSet` (`CableArg 0/1`). Panel öne gelince liste yenilenir.
- C#'ta `HashSet` YOK (Max'in CodeDom'u System.Core eklemiyor) → `List`/`Dictionary` kullan.
- **3ds Max 2026+ .NET 8 kullanır: CodeDom yok** ("Operation is not supported on this platform"). Derleme `MT_CompileCS`
  üzerinden: 2026+ `CSharpUtilities.CSharpCompilationHelper.Compile code #()` (yüklü tüm assembly'leri referanslar;
  MAXFORM kaynağın başına `#define` ile eklenir), eskiler CodeDom. C# kodu iki ortamda da derlenmeli:
  .NET 8'de `MethodInvoker` belirsiz → `System.Windows.Forms.MethodInvoker` yaz; WebClient yalnızca uyarı verir.
- **Yazı tipleri piksel cinsinden (`PxFont`, `new Font` kullanma):** yerleşim sabit piksel; punto yazılar Windows
  ölçeklemesinde (125/150%) büyüyüp kutulardan taşıyordu.
- 2025+ `menuMan` yok → başlatıcı menüyü `#cuiRegisterMenus` callback'iyle kurar (`CreateSubMenu`/`CreateAction ... 647394
  "MaxTools_Open`MaxTools"`), menü Max yeniden açılınca görünür.
- Bu bilgisayarda 3ds Max 2026 da kurulu: `C:\Program Files\Autodesk\3ds Max 2026\3dsmaxbatch.exe <test.ms>` ile
  arayüzsüz MAXScript çalıştırıp .NET 8 derlemesi test edilebilir (sonucu dosyaya yazdır).

## MAXScript tuzakları (hepsi yaşandı)
- Büyük/küçük harf duyarsız: `fE`=`fe`, `fN`=`fn`. Anahtar kelime/sınıf adı değişken olmaz (`mapped`, `box`, `path`, `index`, `color`...).
- Sonradan tanımlanan fonksiyona ileri referans `undefined` olur → en üstte `global` bildir.
- Döngü gövdesindeki local iç içe `for ... collect` tarafından okunuyor VE aynı isim başka yerde de varsa
  "Bad free thunk" → iç collect'i yardımcı fonksiyona taşı (`MT_ScalePts` vb.).
- `copy #()` / `copy #{}` → `OK` döndürdü; düz `#()` kullan. `format` içinde `%%` güvenilmez.
- Dosyalar **UTF-8 BOM** ile kaydedilmeli (`[IO.File]::WriteAllText(p, t, (New-Object System.Text.UTF8Encoding $true))`).
- PowerShell'de kısa fonksiyon adları alias'la çakışır (`R` = Invoke-History).

## Doğrulama (her değişiklikten sonra)
1. `powershell -File dev\check.ps1` → ileri referans, tanımsız MT_ fonksiyonu, büyük/küçük çakışma, anahtar kelime,
   parantez dengesi, buton id ↔ MT_Action, C# CodeDom derlemesi.
2. C# arayüz: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` ile test harness derlenip form açılabilir,
   `DrawToBitmap` ile ekran görüntüsü alınıp kontrol edilir (MaxForm için küçük bir stub `MaxCustomControls.dll`).
3. Kullanıcı Max'te test eder; sol üstteki "build N" etiketi güncel dosyanın çalıştığını gösterir.

## Sürüm ve yayınlama
- Her değişiklikte `MaxTools.ms`: `MT_Version` + `MT_BuildNum` artır.
- **"Yayınla" (kullanıcı onayı şart — herkese açık yayın):** `version.json` (version, build = MT_BuildNum, notes, files)
  güncelle → commit (sonunda `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`) → push.
  Komut satırında GitHub kimliği YOK → kullanıcı **GitHub Desktop → Push origin** yapar.
- Depo: https://github.com/ktycnpkcn/Max-Tools (public, `main`). Kullanıcıların MaxTools'u açılışta
  `https://raw.githubusercontent.com/ktycnpkcn/Max-Tools/main/version.json` okur; build büyükse sorup günceller
  (`_update` → yedek `_update_backup` → yerine koy → `MT_ReloadAfterUpdate`). Raw CDN birkaç dakika gecikebilir.
- v3.8 ve öncesi kendini güncelleyemez (README'de tek seferlik elle geçiş anlatılıyor).

## Yapılabilecekler (konuşulmuş fikirler)
Model Doktoru (n-gon, ters normal, isolated vertex, ölçek, eksik UV tarama + tek tıkla düzeltme), pivot araçları,
hızlı ayna, scatter/rastgeleleştirici, toplu FBX export, polycount paneli, kamera yöneticisi / clay render,
koyu temaya uygun özel kaydırma çubuğu, "Reset UVs" butonu.
