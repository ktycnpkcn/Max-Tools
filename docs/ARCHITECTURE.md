# MaxTools — Teknik Mimari (tam referans)

> Bu doküman yeni bir Claude oturumunun projeyi sıfırdan, eksiksiz anlaması için yazıldı.
> Kısa kurallar ve tuzaklar `CLAUDE.md`'de; burası ayrıntılı referans. Son güncelleme: v4.6 · build 35 (2026-10-11).

---

## 1. Genel bakış

- **Ne:** 3ds Max 2024+ için tek panelli araç paketi (modelleme, UV, isimlendirme, LOD/collision, kablo üretici,
  parke/seramik kaplama). Arayüz C# (WinForms), araçlar MAXScript.
- **Kullanıcı:** Kutay (3D artist, Türkçe konuşur). Uygulama içi metinler İngilizce, kod yorumları Türkçe.
- **Desteklenen Max:** 2024 (.NET Framework 4.8, CodeDom) ve 2025/2026 (.NET 8, Autodesk `CSharpCompilationHelper`).
  Kullanıcının kendi makinesinde 2024 (ana) + 2026 (lisans bitmiş, ama `3dsmaxbatch.exe` çalışıyor) kurulu.
- **Depo / dağıtım:** https://github.com/ktycnpkcn/Max-Tools (public, `main`). Çalışma klasörü = git deposu =
  kullanıcının Max'inin yüklediği kurulum: `D:\3Ds Max Element Detach\Max Tools`. Kullanıcılar panel açılışında
  `raw.githubusercontent.com/.../main/version.json` okuyup daha büyük build varsa güncellenir.
- **Sürüm:** `MaxTools.ms` başında `MT_Version` ("v4.6  ·  build 35") ve `MT_BuildNum` (35). `dev\check.ps1` ikisinin
  build numarasının tuttuğunu kontrol eder.

## 2. Dosya yapısı

| Yol | Görev |
|---|---|
| `MaxTools.ms` (~4800 satır) | Tüm araçlar + C# köprüsü + panel kurulumu (`MT_Build`). UTF-8 BOM. |
| `MaxToolsUI.cs` (~2200 satır) | Panel (`MTForm`), kontroller, yerleşim, online güncelleyici. Max içinde derlenir. |
| `MaxToolsPacker.cs` | Raster tabanlı UV paketleyici (`MTPacker`), Pack butonu kullanır. |
| `MaxTools_SideBar.ms` | Viewport soluna yapışan "M" butonlu cui dialog bar (rollout `MaxToolsBar`). |
| `MaxTools_Install.ms` | Kurulum (bir kez): ikonlar, başlatıcı, menü. |
| `MaxTools_Uninstall.ms` | Kaldırma: başlatıcı, macro (.mcr), menü, ikonlar, ini; klasöre dokunmaz. |
| `icons\` | `MaxTools_16/24i/a.bmp` (eski ikon sistemi), `MaxTools\MaxTools_16..48.png` (yeni), `MaxTools_bar_24i/m.bmp` (sol çubuk; maske siyah=görünür). |
| `version.json` | Güncelleme manifesti: `version`, `build`, `notes`, `files` (indirilecek dosyalar, yeni dosya eklenince buraya!). |
| `README.txt` | Kullanıcı dokümanı (İngilizce): kurulum, güncelleme, kaldırma, özellik listesi. |
| `CLAUDE.md` | Claude için kısa kurallar (her oturumda otomatik yüklenir). |
| `docs\ARCHITECTURE.md` | Bu doküman. |
| `dev\check.ps1` | Statik kontroller (dağıtılmaz). |
| `MaxTools_diag.txt` | Teşhis çıktısı (gitignore). |
| `.gitignore` | diag, `_update/`, `_update_backup/`, `*.zip`. |

Kurulum dışı yollar (kullanıcı makinesi):
- `<userStartupScripts>\MaxTools_Startup.ms` — başlatıcı (Install yazar).
- `<userMacros>\MaxTools-MaxTools_Open.mcr` — Max'in macroScript kopyası.
- `<userIcons>\MaxTools\*.png` (+ Dark\, Light\) ve kökte BMP'ler.
- `<plugcfg>\MaxTools.ini` — `[Window] X,Y,W,H,Page`, `[Update] AutoCheck`, `[SideBar] Show`.
- Üst klasör `D:\3Ds Max Element Detach\` eski dosyalar + `_backup\` (zip yedekler); dokunma.

## 3. Yükleme akışı

1. `MaxTools_Install.ms` (bir kez): ikonları kopyalar, `MaxTools_Startup.ms` yazar ve çalıştırır.
   Başlatıcı: `macroScript MaxTools_Open category:"MaxTools"` (→ `fileIn <klasör>\MaxTools.ms`), menü
   (2024-: `menuMan`; 2025+: `callbacks.addScript #cuiRegisterMenus MaxTools_RegisterMenu id:#MaxToolsMenu`,
   `CreateSubMenu` + `CreateAction <guid> 647394 "MaxTools_Open`MaxTools"` — menü Max yeniden açılınca görünür),
   sol çubuk (`fileIn MaxTools_SideBar.ms`).
2. Panel açılışı = `fileIn MaxTools.ms`: eski paneli kapatır, globaller, tüm fonksiyonlar tanımlanır, en sonda `MT_Build()`.
3. `MT_Build`: `MT_GetUIAsm()` (C# derle, dosya tarihine göre önbellek) → `asm.CreateInstance "MTForm"` →
   `Build version startPage` → `SetStartSize` (ini) → `dotNet.loadAssembly ManagedServices.dll` + `SetMaxRoot` →
   köprü yoksa yedek olay (`dotNet.addEventHandler MT_UI "UIEvent" MT_OnUIEvent`, tek olay) → `ShowWith hwnd x y` →
   `MT_CableRefreshUI()` + (eski: `MT_InstShowSource()`) → `ConfigureUpdates MT_UpdateBase MT_ScriptDir MT_BuildNum` →
   ini AutoCheck != false ise `CheckForUpdates true`.
4. Callback'ler: `#preSystemShutdown` → `MT_Shutdown`; `#filePostOpen/#systemPostReset/#systemPostNew` → `MT_CableRefreshUI`.

## 4. C# derleme (`MT_CompileCS code defs refs tag`)

- 2026+ (.NET 8, CodeDom yok): `(dotNetClass "CSharpUtilities.CSharpCompilationHelper").Compile code #()` — Max'te yüklü
  tüm assembly'leri kendisi referanslar. `defs` ("MAXFORM") kaynağın başına `#define MAXFORM\n` eklenir.
- Eski sürümler: `Microsoft.CSharp.CSharpCodeProvider` + `CompilerParameters` (refs: System, System.Drawing,
  System.Windows.Forms, MAXFORM'da `MaxCustomControls.dll`; `/define:MAXFORM`).
- `MT_GetUIAsm`: önce MAXFORM (MaxForm'dan türer, Max klavye/odak davranışı), olmazsa düz `Form`. Hatalar diag'a.
- C# her iki derleyicide derlenmeli: `HashSet` yok (System.Core yok) → `List`; .NET 8'de `MethodInvoker` belirsiz →
  `System.Windows.Forms.MethodInvoker`; lambda/anonim metot serbest; `Action<int>` kullanılabilir.

## 5. Köprü (C# ↔ MAXScript)

### C# → MAXScript
- `Exec(cmd)`: `ManagedServices.MaxscriptSDK.ExecuteMaxscriptCommand` reflection ile. 2024: `(string)`; **2026:
  `(string, ScriptSource)`** → `FindBridge` iki parametreliyi de bulur, ek parametreyi varsayılan/0 (`NotSpecified`) doldurur
  (`execExtra`). Bulunamazsa yedek `UIEvent` + `PendingCmd`.
- `execDepth`: Exec içindeyken (ör. viewport'ta pickPoint sürerken) yeni buton komutları yok sayılır.
- Gönderilen komutlar: `MT_UIAction "<id>"`, `MT_UIAction "<id>Live"` (canlı güncelleme), `MT_UIClosed()`,
  `MT_ReloadAfterUpdate()`, `enableAccelerators = true/false` (metin kutusu odak alınca Max kısayollarını kapatır).

### MAXScript → C# (MTForm public API)
`Build(version,startPage)`, `SetStartSize(w,h)`, `ShowWith(hwnd,x,y)`, `SetMaxRoot`, `BridgeOK()`, `BridgeInfo()`,
`Alive()`, `SetStatus(msg,type 0 bilgi/1 ok/2 uyarı/3 hata/4 çalışıyor)`, `SetProgress(pct)`, `GetInt(name)` (Num: sınırlı
sayı; Segment: 1..n; Toggle: 1/0), `GetText(name)`, `SetLabelText(key,text)`, `ConfigureUpdates(base,dir,build)`,
`CheckForUpdates(silent)`, `LastX/LastY/LastW/LastH/Page` (kapanışta ini'ye), Kablo: `CableArg(i)`,
`CableSetRoutes(csv,cur)`, `CableSetList(items)`, `CableSelNames()`, `CableNames()`, `CableShow(data,label,pointMode)`,
`CablePointMoved()`.

### MAXScript tarafı
- `MT_Num/MT_State/MT_Flag/MT_Text name` panel değerini okur (panel yoksa varsayılan).
- `MT_UIAction id`: sonu "Live" ise `MT_LiveRun = true` ve eki atar; `try (MT_Action id) catch` (hata durum çubuğuna +
  Listener'a); sonunda `MT_LiveRun = false`.
- `MT_Action id`: büyük `case` — buton id → fonksiyon (tam liste §8).
- `MaxTools_Status msg type:#ok/#warn/#error/#busy/#info`, `MaxTools_Progress pct`.
- **Kural:** MAXScript'te `dotNet.addEventHandler` YOK (yedek köprü hariç). Eskiden yüzlerce .NET olayı GC hatası veriyordu.

## 6. Arayüz çatısı (MaxToolsUI.cs)

- **Pencere:** kenarlıksız, `WM_NCHITTEST` ile kenardan boyutlandırma, sol menü + başlık + içerik + durum çubuğu.
  `#if MAXFORM` `MaxCustomControls.MaxForm`, değilse `Form`. Koyu tema renkleri sınıf başında (`cBg, cCard, cAccent`...).
- **Sayfalar:** `PageCount = 6`: 1 Modeling, 2 UV, 3 Naming, 4 LOD & Collision, 5 Cables, 6 Tiles. `PageInfo` (başlık/alt
  başlık), `PageIcons` (Segoe MDL2). `NewPage(idx)` → `NoJumpPanel` (AutoScroll; `ScrollToControl` override: odak
  değişince sayfa zıplamasın — yoksa tıklanan buton imlecin altından kayıyordu).
- **Kart / bölüm:** `Card(pg, col, title, sub, h)` 305px kart; `col` 2 sütunlu düzende tercih. `Section(pg, "Title")`
  bölüm başlığı (sonraki kartlar o bölüme girer). `PlaceCards`: her bölüm = blok (başlık + kartları); bloklar sığdığı kadar
  yan yana satırlara dizilir; bölümsüz sayfa tek blok. `LayoutCards` kaydırma çubuğu payını hesaba katar.
- **Sol menü:** `navs[]`; aktif sayfanın bölümleri altında alt madde (`navSubs`), tıklayınca `ScrollToSection` yumuşak
  kaydırma; aktif sayfa adına tekrar tıklama aç/kapa (▾/▸). Dar pencerede (`compact`, <640px) ikonlara küçülür.
- **Kontroller:** `Btn(par,txt,x,y,w,h,actionId,primary)` (Label tabanlı; `action null` → yalnızca C# Click; `SetBtnEnabled`),
  `Txt(...)` metin, `Num(...)` sınırlı tamsayı + **Spinner**, `Segment(...)` (states 1..n), `Toggle(...)` (states 1/0),
  `Combo(...)` (hazır değer → hedef metin kutusu), `Lbl/Muted`. Yazı tipleri **`PxFont`** (piksel; DPI ölçeklemede taşmasın).
- **Spinner** (`Spinner(bg,x,begin,delta)`): sağda ▲▼; basılı tut + yukarı/aşağı çek (4px = 1 adım, Shift ×10), tıklama üst
  +1 / alt −1. `FloatSpinner`: `FloatFields` (uzunluklar + `tlRotJit`, `tlTilt`) için; adım değerin büyüklüğüne göre
  (≥10: 1, ≥1: 0.1, <1: 0.01); birim korunur.
- **Uzunluk alanları** (`lenFields`): odaktan çıkınca `NormLen` → "1" → "1.0cm" (birim yoksa cm).
- **Değer değişimi:** `ValueChanged(name)` (Num/Spinner/Segment/Toggle/metin onayı) → `notify` kümesindeyse (kablo
  anahtarları) `cblSet` gönderir; sonra `LiveTrigger(name)`.
- **Metin onayı:** `HookCommit` (LostFocus/Enter), `HookCommitOnClick` (odak almayan yere tıklayınca odağı bırak),
  `Deactivate` → `CommitEdit()` (viewport'a geçerken de onaylanır).
- **Durum dizileri:** `texts` (ad→TextBox), `limits` (Num sınırları), `states` (Segment/Toggle/özel durumlar), `segLabels`,
  `toggles`, `namedLabels` (`SetLabelText`).
- **Online güncelleyici:** `CheckForUpdates` (arka plan iş parçacığı, `version.json` regex ile okunur) → build büyükse
  sor → `StartUpdate` (`_update\` klasörüne indir) → `ApplyUpdate` (eski dosyalar `_update_backup\`'a, yenileri yerine;
  hata olursa geri al) → `MT_ReloadAfterUpdate()`. Sadece `files` listesindeki dosyalar indirilir (alt klasör oluşturur).

## 7. Live update (canlı güncelleme)

- Kartlarda `LiveToggle` ("Live update"): `tlLive` (Tiles, varsayılan açık), `cblLive` (Cables, açık), `uvwLive` (UVW Map,
  kapalı), `lodLive` (LOD, kapalı), `colLive` (Collision, kapalı).
- `LiveTrigger(name)`: ada göre grup (`tl*`→tlGen, `uvw*`→uvwApply, `lod*`→lod, `col*`→col, kablo notify anahtarları→cblGen);
  anahtar açıksa `liveTimer` (350 ms) yeniden başlar → tick'te `Exec("MT_UIAction \"<act>Live\"")` (arka arkaya
  değişikliklerde tek çalışma).
- MAXScript'te `MT_LiveRun = true` iken: onay pencereleri açılmaz; **yalnızca zaten üretilmiş sonuçlar güncellenir**
  (Tiles: `MT_TileSrc` bağlı sonuç olmalı, seçim boşsa `MT_TlLastSrcs`; Cables: rotanın kablosu olmalı; LOD: `MT_LODSrc`;
  Collision: `MT_ColSrc`). Çok ağır Tiles (>20000 taş) canlıda atlanır.
- **Kablo noktası taşıma:** `MT_CableWatch` tüm `CablePoint_*` dummy'lerine `when transform ... changes id:#MTCablePts
  handleAt:#redrawViews obj do MT_CableMoved obj` bağlar (her `MT_CableRefreshUI`'de yeniden). `MT_CableMoved` rotayı
  `MT_CableDirty`'ye ekler + `MT_UI.CablePointMoved()`; C# `moveTimer` (250 ms) fare bırakılana kadar bekler, sonra
  `cblMovedLive` → `MT_CableRegenMoved` (kirli rotalar, kablosu olanlar, `MT_CableGenerateRun r`).

## 8. Sayfalar, araçlar, buton id → fonksiyon

### 8.1 Modeling (bölümler)
| Bölüm | Kart | id → fonksiyon | Not |
|---|---|---|---|
| Split & Merge | Attach / Detach | `detach`→`MT_Detach`, `attach`→`MT_Attach`, `splDetach`→`MT_SplineDetach`, `splAttach`→`MT_SplineAttach` | Element ayırma (pivot ortalı), attach+center pivot; spline'ları ayır (kopya+diğer spline'ları sil) / birleştir (`addAndWeld base s -1`). |
| Group | Group | `group`→`MT_Group` (yeni grup seçili), `ungroup`→`MT_Ungroup`, `grpOpen/grpOpenR`→`MT_GroupOpen false/true`, `grpClose`→`MT_GroupClose`, `grpAttach`→`max group attach`, `grpDetach`→`max group detach` | Open/Close Max'in kendi komutlarıyla (`max group open/close`; `setGroupOpen` pembe kutuyu çizmiyordu); iç gruplar `setGroupOpen` ile. |
| Instances | Make Instances | `instSrc`→`MT_InstPickSource`, `instMake`→`MT_MakeInstances copyMat`, `instSel`→`MT_SelectInstances` | `instanceReplace t src` (modifier dahil, transform korunur, ışıklarda da); farklı superclass atlanır; kaynak `MT_InstSource` (oturumluk), `SetLabelText "instSrc"`. |
| Transform | Pivot | `pvSet`→`MT_SetPivots xy z inGroups false local`, `pvWorld`→world 0 | 3×3 üstten görünüm (`pvXY` 1..9) + yükseklik (`pvZ` 1 üst/2 orta/3 alt) özel çizimli seçici; `pvSpace` Local (`nodeGetBoundingBox n n.transform`, nokta `* tm`) / World; grup kutusu üyelerden; sonra seçimi tazele + `completeRedraw` (gizmo güncellensin). |
| Transform | Reset XForm | `rxReset`→`MT_ResetXForms scope inGroups collapse` | Grup üyesinde `setGroupMember false`→`ResetXForm`→geri; instance → `InstanceMgr.MakeObjectsUnique`; aynalıda Normal flip; çocuklar yerinde; diğer modifier varsa collapse yok. |
| Transform | Drop to Ground | `drop`→`MT_DropToGround mode` | Z=0 ya da altındaki yüzey (5×5 ışın); kapalı grup bütün. |
| UV | UVW Map | `uvwApply`→`MT_ApplyUVWMap type size` | Box/Planar/Cylinder/Sphere, 100/200/300/Custom; üstte UVW Map varsa günceller. |
| UV | UV Shifter | `uvAll/uvSel`→`MT_UVRandomAll/Sel` | Element başına rastgele UV kaydırma. |
| Material & Color | Random Material ID | `mtidRand`→`MT_RandomMatIDs mode maxId` | Poly (baseObject) / Mesh; diğerine Material modifier. |
| Material & Color | Random Wirecolor | `wcRand`→`MT_RandomWirecolor scope byGroup` | Grup içi aynı renk seçeneği. |
| Scene | Cross-Scene Copy/Paste | `copy/paste`→`MT_Copy/MT_Paste` | temp .max üzerinden. |
| Scene | Reference Image | `ref`→`MT_Ref` | Oranlı dokulu plane. |

### 8.2 UV sayfası
Seams (`seamAdd/seamDel/seamClear/peel`), Hard Edge (`selHard`, `autoUnwrap` — Smoothing/By Angle), Pack (`pack`→
`MT_UV_PackMax` C# raster paketleyici, padding, rotation, texel eşitleme), Straighten (`straight`). Teknik notlar
CLAUDE.md'de (Unwrap kenar numaraları, `MT_UV_PolyToUnwrapEdges`, `MT_UV_PrimeSeams`, quickPeel yok).

### 8.3 Naming
`nameFix` (prefix/suffix, hazır listeler), `nameClean`, `nameRen` (Name_01..), `nameRep` (find/replace).

### 8.4 LOD & Collision
- **LOD** (`lod`): ProOptimizer ile kopyalar (`MT_MakeLOD`), `<ad>_LOD1..4`, `MT_LODSrc` = kaynak handle; tekrar
  üretimde eskiler silinir; LOD kopyası seçiliyse kaynağına döner (`MT_SourcesOf`).
- **Collision** (`col`): Convex (hull), Parts (grid kutular), Box, Sphere; Unreal adları `UCX_/UBX_/USP_<ad>_NN`;
  `MT_ColSrc` = kaynak handle; tekrar üretimde eskiler silinir.

### 8.5 Cables (5. sayfa, `MT_Cable*`)
- **Veri modeli:** Rota noktaları yalnızca `CablePoint_R<rota>_<no>` adlı **Dummy**'ler (`MT_CableParse` kalıbı katı;
  başka dummy alınmaz). Ad oluşturulurken verilir, değişmez (no = rotadaki en büyük + 1). Sıra `MT_CableOrder` user prop.
  Noktaya özel ayar `MT_C_<anahtar>` user prop. Rota ayarları **File Properties > Custom** `MTCable_R<rota>` =
  "anahtar=değer;..." (`MT_CableRouteGet/Set`). Anahtarlar `MT_CableKeys` / varsayılanlar `MT_CableDefs`;
  noktaya özel olabilenler `MT_CablePtKeys` (cSag, cStiff, cTangle, cTwist, cSpread, cSurf).
- **UI:** rota seçici (özel koyu menü), nokta listesi (owner-draw, çoklu seçim, ● = özel ayarlı), Add Points
  (viewport'ta art arda `pickPoint`, yüzeye ışın; seçili noktanın arkasına ekler), Remove, Up/Down (C#'ta sıralayıp
  `cblOrder`), Refresh, Shape kartı (noktaya özel: liste seçiliyken değerler noktaya yazılır, ● ile geri alınır),
  Cable kartı (rota geneli), Live update.
- **Üretim** (`MT_CableGenerateRun r`): uç noktalar (zemin/hava algısı), aralık başına catenary (sarkma) ya da zemin
  çizgisi, zemine oturtma, sertliğe göre değişken pencereli bulanıklaştırma (min. demet genişliği), rota kendini kesiyorsa
  üstten geçme (`MT_CableLiftCrossings`), yerçekimi çerçevesi, eğrilik kısıtı (iç kablolar düğüm atmasın), demet
  (havada halka, yerde yan yana), burgu, karmaşa (noise), uyarlanır nokta yoğunluğu. Çıktı `Cable_R<r>_<nn>`
  (+`MT_CableRoute` prop): yuvarlak = renderable spline, flat = elle kurulan dikdörtgen kesitli poly (bant).
  Her üretim rotanın eski kablolarını siler.

### 8.6 Tiles (6. sayfa, `MT_Tl*`, `MT_TileGenerate o`)
- **Girdi:** seçili geometri / kapalı spline (spline → kopya `convertToMesh`); seçili taş objesi → kaynağı (`MT_TileSrc`).
- **Bölgeler:** snapshot mesh → yüz normal/merkez → kenar haritası (`Dictionary #string`) → aynı düzlem (3°,
  %0.2 boyut toleransı) + kenardan bağlı yüzler BFS → alan ağırlıklı ortalama düzlem. Duvarda U yatay, V yukarı; zeminde
  U = dünya X. Flip side → normal ters.
- **Desenler** (`MT_TlPattern`): 1 Grid, 2 Brick (sabit sıra kayması), 3 Planks (Floor Generator "Standard": her sıra
  öncekine göre min..max % kayar, min uzunluk %, min genişlik %), 4 Herringbone (`s*(L,-L)+k*(W,W)` kafesi), 5 Basket.
  Derz = taş başına g/2 küçültme. Scale % uzunluk+genişliği ölçekler.
- **Kırpma:** taş (dışbükey) × bölge üçgenleri, Sutherland–Hodgman (`MT_TlClipHalf/ClipTri`), kenar bayrakları
  (gerçek kenar = bevel, kesik kenar = düz); tamamı içerideyse tek parça.
- **Hacim** (`MT_TlEmit`): halkalar taban/bevel/üst, kenar başına inset (`MT_TlInset`, sivri köşe 3*bevel sınırı,
  dar parçada bevel yok), eğim (Tilt), dönme sapması, UV (taş ekseninde, rastgele kaydırma/çevirme), rastgele Material ID.
  Mesh `MT_TlBuildMesh` (gizli köşegenler) → isteğe bağlı Editable Poly. Sonuç `<kaynak>_Tiles` + `MT_TileSrc`.
- **Ayarlar** (C# adları): tlPat, tlLen, tlWid, tlScale, tlBrick (row offset min), tlBrickMax, tlMinLen, tlMinW, tlGrout,
  tlBevel, tlHeight, tlHVar, tlRotJit, tlTilt, tlRot, tlOffU, tlOffV, tlFlip, tlIDs, tlSeed, tlRandUV, tlUVFlip, tlPoly,
  tlHide, tlLive. Varsayılanlar tek kaynakta: C# `TileDefaults` (+ Reset to Defaults). MAXScript'e `MT_Action "tlGen"`
  içinde 24 elemanlı dizi olarak geçer (sıra `MT_TileGenerate` yorumunda).

## 9. Sahne veri sözleşmeleri

| Anahtar | Nerede | Anlam |
|---|---|---|
| `CablePoint_R<r>_<n>` | Dummy adı | Kablo rotası noktası |
| `MT_CableOrder` | user prop (nokta) | Sıra |
| `MT_C_<key>` | user prop (nokta) | Noktaya özel kablo ayarı |
| `MTCable_R<r>` | File Properties > Custom | Rota ayarları |
| `MT_CableRoute` | user prop (kablo) | Ait olduğu rota |
| `MT_TileSrc` | user prop (taş objesi) | Kaynak node handle |
| `MT_LODSrc` | user prop (LOD kopyası) | Kaynak node handle |
| `MT_ColSrc` | user prop (collision) | Kaynak node handle |
| `#MTCablePts` | change handler id | Kablo noktası taşıma izleme |

## 10. Test altyapısı

- `dev\check.ps1`: çift tanım, ileri referans (global bildirilmemiş), tanımsız `MT_` adı, fonksiyon içi büyük/küçük
  harf çakışması, anahtar kelime değişken, parantez dengesi, `Btn(c, ..., "id"` ↔ `MT_Action` eşlemesi (ilk 8000
  karakter), C# CodeDom derlemesi, sürüm etiketi = build, BOM.
- **C# arayüz testi:** `csc.exe` (Framework64 v4) ile küçük harness (`MTForm` oluştur, `Build`, `ShowWith(0,..)`,
  `DrawToBitmap` → png, reflection ile `OnClick/OnMouseDown`). Köprü yokken komutlar `MTForm.TestLog`'a düşer.
- **MAXScript testi (Max 2026 arayüzsüz):** `"C:\Program Files\Autodesk\3ds Max 2026\3dsmaxbatch.exe" test.ms`.
  Desen: test betiği `MaxTools.ms`'den ilgili bloğu (fn ... arası) okuyup stub'larla (`MaxTools_Status` dosyaya yazar,
  `MT_UIAlive = false`) birleştirir, sonucu dosyaya yazar. Viewport/arayüz gerektiren şeyler (pickPoint, change
  handler tetiklenmesi, gizmo, matcap) burada test edilemez → kullanıcı Max'te dener.
- Render ile görsel kontrol: batch'te `render camera:... outputfile:... vfb:false` (scanline).
- .NET 8 derleme kontrolü: batch'te `CSharpCompilationHelper.Compile`.

## 11. Yayın süreci

- Değişiklikler yerelde birikir; kullanıcı "yayınla / pushla / commit edelim" deyince:
  `MT_Version`+`MT_BuildNum` (Edit aracıyla!) → `README.txt` (başlık sürümü + özellik listesi) → `version.json`
  (version, build, notes İngilizce, yeni dosyalar `files`'a) → `check.ps1` → commit (mesaj sonu
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; mesajı BOM'suz dosyadan `git commit -F`).
- Push'u kullanıcı **GitHub Desktop → Push origin** ile yapar (komut satırında kimlik yok). Sonra kontrol:
  `git ls-remote origin refs/heads/main` + raw `version.json` (CDN birkaç dakika gecikebilir).
- Elle dağıtım gerekirse: zip (MaxTools.ms, UI.cs, Packer.cs, SideBar, Install, Uninstall, README, icons\).

## 12. Geri çekilen / reddedilen

- **Matcap / Zebra viewport shader'ları** (DX11 .fx + DirectX_9_Shader, kök düğümde materyal saklama): yapıldı, kullanıcı
  beğenmedi, tamamen kaldırıldı. Kullanıcı istemedikçe tekrar önerme.

## 13. Fikir listesi (konuşulmuş, yapılmadı)

Model Doktoru (n-gon, ters normal, isolated vertex, ölçek, eksik UV + tek tıkla düzeltme), hızlı ayna, scatter,
toplu FBX export, polycount paneli, kamera yöneticisi / clay render, özel koyu kaydırma çubuğu, Reset UVs, Tiles:
kavisli yüzey (yüzey UV'si ile), derz boy/en ayrı, preset kaydet/yükle; MultiTexture (Tiles'ın Material ID / UV
kaydırma çıktısını kullanacak; kullanıcı "sonra yapacağız" dedi); kablolar başka kabloların üstüne yatsın.
