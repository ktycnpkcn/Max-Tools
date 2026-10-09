-- =========================================
-- MaxTools v3.5
-- Hızlı modelleme araçları paketi
-- =========================================

global MT_UI, MT_UIAsm, MT_UIAsmStamp
global MT_Version = "v3.9.1  ·  build 27"
-- Online güncelleme: GitHub'daki version.json'daki build bu sayıdan büyükse güncelleme önerilir
global MT_BuildNum = 27
global MT_UpdateBase = "https://raw.githubusercontent.com/ktycnpkcn/Max-Tools/main/"
global MT_OnUIEvent
global MT_UFind
global MT_UVMapCache
global MT_ShellPositions, MT_ScalePts, MT_RotatePts, MT_Pts2D, MT_InflateRects, MT_PickPts, MT_FlipY
global MT_PackerObj, MT_PackerStamp

-- Teşhis notları scriptin yanındaki MaxTools_diag.txt dosyasına yazılır
global MT_ScriptDir = try (getFilenamePath (getThisScriptFilename())) catch (getDir #temp + "\\")
fn MT_DiagWrite txt =
(
    try
    (
        local diagFile = MT_ScriptDir + "MaxTools_diag.txt"
        local f = openFile diagFile mode:"a"
        if f == undefined do f = createFile diagFile
        format "%\n" txt to:f
        close f
    )
    catch()
)

-- Önceki sürümleri kapat (eski MAXScript/.NET arayüz kalıntıları dahil)
try (MT_UI.Close()) catch()
try (MT_Timer.Stop()) catch()
try (MT.form.Close()) catch()
try (destroyDialog MaxTools_Main) catch()
try (destroyDialog MaxToolsUI) catch()

fn MT_Ini = getDir #plugcfg + "\\MaxTools.ini"

-- =========================================
-- DURUM ÇUBUĞU (C# arayüzüne yazar)
-- =========================================
fn MT_UIAlive = (MT_UI != undefined and (try (MT_UI.Alive()) catch false))

fn MaxTools_Status msg type:#info =
(
    if MT_UIAlive() do
    (
        local code = case type of
        (
            #ok:    1
            #warn:  2
            #error: 3
            #busy:  4
            default: 0
        )
        try (MT_UI.SetStatus msg code) catch()
    )
)

fn MaxTools_Progress pct =
(
    if MT_UIAlive() do try (MT_UI.SetProgress (pct as float)) catch()
)

-- =========================================
-- ARAÇLAR: MODELLEME
-- =========================================
fn MT_Explode obj =
(
    if (classOf obj != Editable_Poly) do convertTo obj Editable_Poly

    local totalFaces = polyop.getNumFaces obj
    local currentFaces = #{1..totalFaces}
    local count = 0

    while not currentFaces.isEmpty do
    (
        local faceArr = currentFaces as array
        if faceArr.count == 0 do exit

        local elemFaces = polyop.getElementsUsingFace obj faceArr[1]

        if elemFaces.numberset == currentFaces.numberset then exit
        else
        (
            local newName = uniqueName (obj.name + "_part_")
            polyop.detachFaces obj elemFaces asNode:true name:newName
            local newNode = getNodeByName newName
            if newNode != undefined do centerPivot newNode
            count += 1
        )

        currentFaces = #{1..(polyop.getNumFaces obj)}
        local perc = ((totalFaces - currentFaces.numberset) as float / totalFaces as float) * 100.0
        MaxTools_Progress perc
        MaxTools_Status ("Detach  ·  Detaching... %" + (perc as integer) as string) type:#busy
        windows.processPostedMessages()
    )

    centerPivot obj
    count
)

fn MT_Detach =
(
    if selection.count == 0 then MaxTools_Status "Detach  ·  Please select an object." type:#warn
    else if selection.count > 1 then MaxTools_Status "Detach  ·  Please select only ONE object." type:#warn
    else
    (
        local selObj = selection[1]
        MaxTools_Status "Detach  ·  Preparing (this may take a while)..." type:#busy
        undo "Detach Elements" on
        (
            local n = MT_Explode selObj
            MaxTools_Progress 100
            MaxTools_Status ("Detach  ·  " + n as string + " parts detached.") type:#ok
        )
    )
)

fn MT_ClipPath = getDir #temp + "\\max_clipboard_tool.max"

fn MT_Copy =
(
    if selection.count > 0 then
    (
        MaxTools_Status "Copy  ·  Copying..." type:#busy
        windows.processPostedMessages()
        saveNodes selection (MT_ClipPath()) quiet:true
        MaxTools_Status ("Copy  ·  " + selection.count as string + " objects copied to clipboard.") type:#ok
    )
    else MaxTools_Status "Copy  ·  Select objects to copy." type:#warn
)

fn MT_Paste =
(
    if doesFileExist (MT_ClipPath()) then
    (
        MaxTools_Status "Paste  ·  Pasting..." type:#busy
        windows.processPostedMessages()
        mergeMAXFile (MT_ClipPath()) #select #autoRenameDups #renameMtlDups quiet:true
        MaxTools_Status "Paste  ·  Pasted successfully." type:#ok
    )
    else MaxTools_Status "Paste  ·  Clipboard is empty." type:#warn
)

fn MT_Group =
(
    if selection.count > 1 then
    (
        undo "Quick Group" on
        (
            local newName = uniqueName "QuickGroup_"
            group selection name:newName
            MaxTools_Status ("Merge  ·" + newName + " created.") type:#ok
        )
    )
    else if selection.count == 1 then MaxTools_Status "Merge  ·  Select at least 2 objects." type:#warn
    else MaxTools_Status "Merge  ·  Please select objects." type:#warn
)

fn MT_Attach =
(
    local validObjs = for o in selection where (superClassOf o == GeometryClass or superClassOf o == shape) collect o
    if validObjs.count > 0 then
    (
        MaxTools_Status "Merge  ·  Merging, please wait..." type:#busy
        windows.processPostedMessages()
        undo "Quick Attach" on
        (
            local baseObj = validObjs[1]
            if classOf baseObj != Editable_Poly do convertTo baseObj Editable_Poly
            for i = 2 to validObjs.count do
            (
                local obj = validObjs[i]
                if isValidNode obj do
                (
                    if classOf obj != Editable_Poly do convertTo obj Editable_Poly
                    polyop.attach baseObj obj
                )
            )
            centerPivot baseObj
            select baseObj
        )
        MaxTools_Status "Merge  ·  Merged into one object and centered." type:#ok
    )
    else MaxTools_Status "Merge  ·  No valid geometry in selection." type:#warn
)

fn MT_Ref =
(
    local imgPath = getOpenFileName caption:"Select Reference Image" types:"Image Files (*.jpg;*.jpeg;*.png;*.bmp;*.tif)|*.jpg;*.jpeg;*.png;*.bmp;*.tif|All Files (*.*)|*.*|"
    if imgPath != undefined do
    (
        local bmp = openBitmap imgPath
        if bmp != undefined then
        (
            local w = bmp.width as float
            local h = bmp.height as float
            close bmp
            local pLength = 100.0
            local pWidth = pLength * (w / h)
            local refPlane
            undo "Add Reference Image" on
            (
                refPlane = Plane length:pLength width:pWidth lengthsegs:1 widthsegs:1 pos:[0,0,0]
                refPlane.name = uniqueName "Reference_Image_"
                local bmpTex = Bitmaptexture filename:imgPath
                local mat
                if classOf PhysicalMaterial != undefined then
                (
                    mat = PhysicalMaterial name:(refPlane.name + "_Mat")
                    mat.base_color_map = bmpTex
                    mat.roughness = 1.0
                )
                else
                (
                    mat = Standard name:(refPlane.name + "_Mat")
                    mat.diffuseMap = bmpTex
                )
                refPlane.material = mat
                showTextureMap mat bmpTex on
                select refPlane
            )
            MaxTools_Status ("Reference  ·" + refPlane.name + " added.") type:#ok
        )
        else MaxTools_Status "Reference  ·  Error: could not read image." type:#error
    )
)

-- =========================================
-- ARAÇLAR: ZEMİNE OTURT
-- Gruplar tek obje gibi davranır: en dıştaki grup başı taşınır, en alt nokta tüm üyelerden hesaplanır.
-- =========================================

-- Grup üyesiyse en dıştaki KAPALI grup başına çıkar.
-- Grup Open ile açıldıysa içindeki objeler kendi başına taşınır (açık grubun başında durulur).
fn MT_GroupRoot n =
(
    local r = n
    while r.parent != undefined and (isGroupMember r) and not (isOpenGroupHead r.parent) do r = r.parent
    r
)

-- Ebeveyn zincirinde listedeki bir düğüm var mı (varsa onunla birlikte zaten taşınır)
fn MT_HasAncestorIn n nodeList =
(
    local p = n.parent
    local found = false
    while p != undefined and not found do
    (
        if (findItem nodeList p) > 0 do found = true
        p = p.parent
    )
    found
)

-- Birimin (tek obje ya da tüm grup) görünür geometrileri
fn MT_UnitGeometry root =
(
    local geos = #()
    local stack = #(root)
    while stack.count > 0 do
    (
        local n = stack[stack.count]
        deleteItem stack stack.count
        if superClassOf n == GeometryClass and not (isGroupHead n) and not n.isHidden do append geos n
        if isGroupHead n do
            for ch in n.children where (isGroupMember ch) do append stack ch
    )
    geos
)

-- Geometrilerin dünya uzayındaki ortak sınır kutusu: #(min, max)
fn MT_UnitBounds geos =
(
    local mnx = 1e30, mny = 1e30, mnz = 1e30, mxx = -1e30, mxy = -1e30, mxz = -1e30
    for g in geos do
    (
        local bb = nodeGetBoundingBox g (matrix3 1)
        mnx = amin mnx bb[1].x; mny = amin mny bb[1].y; mnz = amin mnz bb[1].z
        mxx = amax mxx bb[2].x; mxy = amax mxy bb[2].y; mxz = amax mxz bb[2].z
    )
    #([mnx, mny, mnz], [mxx, mxy, mxz])
)

-- Birimin altındaki en yüksek yüzeyin Z'si (taban izdüşümünde 5x5 noktadan aşağı ışın); yoksa undefined
fn MT_SurfaceBelow geos ubounds =
(
    local mn = ubounds[1], mx = ubounds[2]
    local startZ = mn.z + 0.001 * (amax 1.0 (mx.z - mn.z))
    local cands = for o in geometry where not o.isHidden and (findItem geos o) == 0 and \
                  o.min.z < startZ and o.max.x >= mn.x and o.min.x <= mx.x and o.max.y >= mn.y and o.min.y <= mx.y collect o
    local best = undefined
    for i = 0 to 4 do for j = 0 to 4 do
    (
        local px = mn.x + (mx.x - mn.x) * i / 4.0
        local py = mn.y + (mx.y - mn.y) * j / 4.0
        local downRay = ray [px, py, startZ] [0, 0, -1]
        for o in cands do
        (
            local hit = intersectRay o downRay
            if hit != undefined and hit.pos.z <= startZ do
                if best == undefined or hit.pos.z > best do best = hit.pos.z
        )
    )
    best
)

-- mode 1: dünya zemini (Z=0), mode 2: altındaki yüzey
fn MT_DropToGround mode =
(
    if selection.count == 0 then MaxTools_Status "Ground  ·  Please select objects or groups." type:#warn
    else
    (
        local roots = #()
        for o in selection do appendIfUnique roots (MT_GroupRoot o)
        roots = for rt in roots where not (MT_HasAncestorIn rt roots) collect rt

        local moved = 0, skipped = 0
        undo "Drop to Ground" on
        (
            for rt in roots do
            (
                local geos = MT_UnitGeometry rt
                if geos.count == 0 then skipped += 1
                else
                (
                    local ub = MT_UnitBounds geos
                    local targetZ = if mode == 2 then MT_SurfaceBelow geos ub else 0.0
                    if targetZ == undefined then skipped += 1
                    else
                    (
                        move rt [0, 0, targetZ - ub[1].z]
                        moved += 1
                    )
                )
            )
        )
        local msg = "Ground  ·  " + moved as string + " object(s)/group(s) dropped" + (if mode == 2 then " onto surfaces below" else " to Z=0")
        if skipped > 0 do msg += ", " + skipped as string + " skipped" + (if mode == 2 then " (nothing below)" else "")
        MaxTools_Status (msg + ".") type:(if moved == 0 then #warn else #ok)
    )
)

-- =========================================
-- ARAÇLAR: UV KAYDIRICI
-- =========================================
fn MT_RandomizeUVs obj faces =
(
    if (classOf obj != Editable_Poly) do return 0
    local mapChannel = 1
    if not (polyop.getMapSupport obj mapChannel) do
    (
        addModifier obj (Uvwmap maptype:4)
        convertTo obj Editable_Poly
    )

    local remainingFaces = copy faces
    local elemCount = 0
    while not remainingFaces.isEmpty do
    (
        local faceArr = remainingFaces as array
        local elemFaces = polyop.getElementsUsingFace obj faceArr[1]

        local mapVerts = #{}
        for f in elemFaces where f <= polyop.getNumFaces obj do
        (
            local faceMapVerts = polyop.getMapFace obj mapChannel f
            for i = 1 to faceMapVerts.count do mapVerts[faceMapVerts[i]] = true
        )

        local uOffset = random -100.0 100.0
        local vOffset = random -100.0 100.0
        for mv in mapVerts do
        (
            local oldPos = polyop.getMapVert obj mapChannel mv
            polyop.setMapVert obj mapChannel mv [oldPos.x + uOffset, oldPos.y + vOffset, oldPos.z]
        )

        remainingFaces -= elemFaces
        elemCount += 1
    )
    update obj
    elemCount
)

fn MT_UVRandomAll =
(
    if selection.count == 1 then
    (
        local selObj = selection[1]
        undo "UV Randomize All" on
        (
            if classOf selObj != Editable_Poly do convertTo selObj Editable_Poly
            local cnt = MT_RandomizeUVs selObj #{1..(polyop.getNumFaces selObj)}
            MaxTools_Status ("UV  ·  " + cnt as string + " elements' UVs shifted.") type:#ok
        )
    )
    else MaxTools_Status "UV  ·  Please select only 1 object." type:#warn
)

fn MT_UVRandomSel =
(
    local obj = if selection.count == 1 then selection[1] else undefined
    local valid = obj != undefined and classOf obj == Editable_Poly and (subObjectLevel == 4 or subObjectLevel == 5)
    local selFaces = if valid then polyop.getFaceSelection obj else #{}
    if selFaces.isEmpty then
        MaxTools_Status "UV  ·  Select faces in Editable Poly (Polygon/Element mode)." type:#warn
    else
    (
        undo "UV Randomize Selected" on
        (
            local cnt = MT_RandomizeUVs obj selFaces
            MaxTools_Status ("UV  ·  " + cnt as string + " selected elements' UVs shifted.") type:#ok
        )
    )
)

-- =========================================
-- ARAÇLAR: UNWRAP
-- =========================================
fn MT_UV_GetMod create:true =
(
    if selection.count != 1 do
    (
        MaxTools_Status "UV  ·  Please select a single object." type:#warn
        return undefined
    )
    local obj = selection[1]
    if superClassOf obj != GeometryClass do
    (
        MaxTools_Status "UV  ·  Selected object is not geometry." type:#warn
        return undefined
    )

    local um = undefined
    for md in obj.modifiers do if um == undefined and classOf md == Unwrap_UVW do um = md

    if um == undefined do
    (
        if not create do
        (
            MaxTools_Status "UV  ·  No Unwrap UVW on object. Mark seams and unwrap first." type:#warn
            return undefined
        )
        um = Unwrap_UVW()
        addModifier obj um
    )

    max modify mode
    if modPanel.getCurrentObject() != um do modPanel.setCurrentObject um
    um
)

-- Yeni eklenen Unwrap'ta seam dizisi boş (boyutu 0) olabiliyor; setPeltSelectedSeams o zaman yok sayılır.
-- Max'in kendi peltEdgeSelToSeam komutunu boş seçimle çağırmak diziyi hazırlar.
fn MT_UV_PrimeSeams um =
(
    try
    (
        local se = um.getSelectedEdges()
        local ss = um.getPeltSelectedSeams()
        um.selectEdges #{}
        um.peltEdgeSelToSeam false
        um.setPeltSelectedSeams ss
        um.selectEdges se
    )
    catch (format "MaxTools: seam init error: %\n" (getCurrentException()))
)

fn MT_UV_SeamAdd =
(
    local um = MT_UV_GetMod()
    if um != undefined do
    (
        MT_UV_PrimeSeams um
        undo "Mark Seams" on
        (
            local before = um.getPeltSelectedSeams()
            um.peltEdgeSelToSeam false
            local added = ((um.getPeltSelectedSeams()) - before).numberSet

            if added > 0 then
                MaxTools_Status ("UV  ·  " + added as string + " edges marked as seams.") type:#ok
            else
                MaxTools_Status "UV  ·  Select edges in Unwrap UVW Edge mode first." type:#warn
        )
    )
)

fn MT_UV_SeamRemove =
(
    local um = MT_UV_GetMod create:false
    if um != undefined do
    (
        MT_UV_PrimeSeams um
        undo "Remove Seams" on
        (
            local before = um.getPeltSelectedSeams()
            um.peltEdgeSelToSeam true            -- geçici: seam = sadece seçili edge'ler
            local selE = um.getPeltSelectedSeams()
            local removed = (before * selE).numberSet
            um.setPeltSelectedSeams (before - selE)

            if selE.isEmpty then MaxTools_Status "UV  ·  Select seam edges to remove." type:#warn
            else MaxTools_Status ("UV  ·  " + removed as string + " seams removed.") type:#ok
        )
    )
)

fn MT_UV_SeamClear =
(
    local um = MT_UV_GetMod create:false
    if um != undefined do
    (
        MT_UV_PrimeSeams um
        undo "Clear Seams" on
        (
            local n = (um.getPeltSelectedSeams()).numberSet
            um.setPeltSelectedSeams #{}
            MaxTools_Status ("UV  ·  " + n as string + " seams cleared.") type:#ok
        )
    )
)

fn MT_UV_Peel =
(
    local um = MT_UV_GetMod create:false
    if um != undefined do
    (
        MT_UV_PrimeSeams um
        if (um.getPeltSelectedSeams()).isEmpty then
            MaxTools_Status "UV  ·  Mark seams first (Mark Seams or Select Hard Edges)." type:#warn
        else
        (
            MaxTools_Status "UV  ·  Unwrapping from seams..." type:#busy
            windows.processPostedMessages()
            um.selectFaces #{1..(um.numberPolygons())}
            -- Max 2024'te quickPeel yok: önce Unfold3D (RizomUV motoru), olmazsa LSCM
            local used = undefined
            undo "UV Peel" on
            (
                try (um.Unfold3DSolve(); used = "Unfold3D") catch()
                if used == undefined do try (um.LSCMSolve(); used = "LSCM") catch()
            )
            if used != undefined then MaxTools_Status ("UV  ·  Unwrapped from seams (" + used + ").") type:#ok
            else MaxTools_Status "UV  ·  Unwrap command failed (Unfold3D / LSCM)." type:#error
        )
    )
)

fn MT_SafeFaceNormal base f = (local n = polyop.getFaceNormal base f; if n == undefined then [0,0,1] else n)

-- Açıya göre smoothing group'ları kendi hesabımızla atar (hard edge = açı eşiği ve üstü).
-- Yumuşak kenarla bağlı yüzler aynı gruba, hard edge ile komşu adalar farklı gruplara düşer.
-- Kullanılan grup sayısını döndürür.
fn MT_SmoothByAngle base ang =
(
    local nf = polyop.getNumFaces base
    local faceNrm = for f = 1 to nf collect (MT_SafeFaceNormal base f)

    local par = for i = 1 to nf collect i
    local hardPairs = #()
    for e = 1 to polyop.getNumEdges base do
    (
        local fs = polyop.getEdgeFaces base e
        if fs != undefined and fs.count == 2 do
        (
            local d = amin 1.0 (amax (-1.0) (dot faceNrm[fs[1]] faceNrm[fs[2]]))
            if (acos d) < ang then
            (
                local r1 = MT_UFind par fs[1]
                local r2 = MT_UFind par fs[2]
                if r1 != r2 do par[r2] = r1
            )
            else append hardPairs fs
        )
    )

    -- Adalar arası komşuluk (hard edge'ler üzerinden)
    local root = for f = 1 to nf collect (MT_UFind par f)
    local nbr = Dictionary #integer
    for fs in hardPairs do
    (
        local a = root[fs[1]], b = root[fs[2]]
        if a != b do
        (
            if not HasDictValue nbr a do PutDictValue nbr a #()
            if not HasDictValue nbr b do PutDictValue nbr b #()
            appendIfUnique (GetDictValue nbr a) b
            appendIfUnique (GetDictValue nbr b) a
        )
    )

    -- Açgözlü boyama: her adaya komşularında kullanılmayan ilk smoothing grubu (1..32)
    local islandGroup = Dictionary #integer
    local groupFaces = for i = 1 to 32 collect #{}
    for f = 1 to nf do
    (
        local r = root[f]
        if not HasDictValue islandGroup r do
        (
            local usedG = #{}
            if HasDictValue nbr r do
                for nb in (GetDictValue nbr r) where HasDictValue islandGroup nb do usedG[GetDictValue islandGroup nb] = true
            local g = 1
            while g < 32 and usedG[g] do g += 1
            PutDictValue islandGroup r g
        )
        groupFaces[GetDictValue islandGroup r][f] = true
    )
    local usedCount = 0
    for g = 1 to 32 where not groupFaces[g].isEmpty do
    (
        polyop.setFaceSmoothGroup base groupFaces[g] (bit.set 0 g true)
        usedCount += 1
    )
    usedCount
)

-- ----- Unwrap kenar eşlemesi -----
-- Unwrap'ın geometri kenarı numaraları Editable Poly'den tamamen farklı ve dışarıdan okunamıyor.
-- Ama UV kenarlarının uçları okunabiliyor (selectEdges + edgeToVertSelect) ve Unwrap UV kenar seçimini
-- kendi içinde doğru geometri kenarına çeviriyor (peltEdgeSelToSeam). Bu yüzden UV kenarları üzerinden gidiyoruz.
fn MT_EdgeKey a b = if a < b then (a as string + "_" + b as string) else (b as string + "_" + a as string)

fn MT_PolyEdgeKey base e = (local vv = polyop.getEdgeVerts base e; MT_EdgeKey vv[1] vv[2])

-- Teşhis: tek bir Unwrap kenarı üzerinde ilgili tüm komutların ne döndürdüğünü dosyaya yazar.
fn MT_UV_DiagProbe um base u =
(
    MT_DiagWrite ("--- Sonda: Unwrap kenar " + u as string + "  (poly kenar " + u as string + " vertexleri: " + (polyop.getEdgeVerts base u) as string + ")")
    local savedSeams = try (um.getPeltSelectedSeams()) catch #{}
    local savedLevel = subObjectLevel

    try
    (
        subObjectLevel = 2
        um.selectEdges #{}
        um.setSelectedGeomEdges #{u}
        MT_DiagWrite ("A geomKenar=" + (um.getSelectedGeomEdges()) as string + "  tvKenar=" + (um.getSelectedEdges()) as string + \
                      "  geomVertex=" + (um.getSelectedGeomVerts()) as string + "  tvVertex=" + (um.getSelectedVertices()) as string)
    ) catch (MT_DiagWrite ("A hata: " + (getCurrentException()) as string))

    try
    (
        um.expandGeomEdgeSelection()
        MT_DiagWrite ("B büyütme sonrası geomKenar=" + (um.getSelectedGeomEdges()) as string)
        local pv = polyop.getEdgesUsingVert base ((polyop.getEdgeVerts base u) as bitarray)
        MT_DiagWrite ("  poly'de ortak vertexli kenarlar=" + pv as string)
    ) catch (MT_DiagWrite ("B hata: " + (getCurrentException()) as string))

    try
    (
        um.setSelectedGeomEdges #{u}
        subObjectLevel = 1
        MT_DiagWrite ("C vertex moduna geçince geomVertex=" + (um.getSelectedGeomVerts()) as string + "  tvVertex=" + (um.getSelectedVertices()) as string)
        subObjectLevel = 2
    ) catch (MT_DiagWrite ("C hata: " + (getCurrentException()) as string))

    try
    (
        um.setSelectedGeomEdges #{}
        um.selectEdges #{u}
        um.edgeToVertSelect()
        local tvs = um.getSelectedVertices()
        local gvs = #()
        for f = 1 to um.numberPolygons() do
            for j = 1 to (um.numberPointsInFace f) do
                if tvs[um.getVertexIndexFromFace f j] do appendIfUnique gvs (um.getVertexGeomIndexFromFace f j)
        MT_DiagWrite ("D tvKenar " + u as string + " -> tvVertex=" + tvs as string + " -> geomVertex=" + (sort gvs) as string)
    ) catch (MT_DiagWrite ("D hata: " + (getCurrentException()) as string))

    try
    (
        um.setSelectedGeomEdges #{}
        um.selectEdges #{u}
        um.peltEdgeSelToSeam true
        MT_DiagWrite ("E1 sadece tvKenar seçiliyken Seam Yap -> seam=" + (um.getPeltSelectedSeams()) as string)
        um.selectEdges #{}
        um.setSelectedGeomEdges #{u}
        um.peltEdgeSelToSeam true
        MT_DiagWrite ("E2 sadece geomKenar seçiliyken Seam Yap -> seam=" + (um.getPeltSelectedSeams()) as string)
    ) catch (MT_DiagWrite ("E hata: " + (getCurrentException()) as string))

    try (um.setPeltSelectedSeams savedSeams) catch()
    try (um.selectEdges #{}; um.setSelectedGeomEdges #{}) catch()
    subObjectLevel = savedLevel
)

-- Tek bir UV kenarının iki UV vertex'ini Unwrap'a sorar (bulunamazsa undefined)
fn MT_UV_ProbeTVEdge um k =
(
    try
    (
        um.selectEdges #{k}
        um.edgeToVertSelect()
        local tvs = (um.getSelectedVertices()) as array
        if tvs.count == 2 then tvs else undefined
    )
    catch undefined
)

-- UV kenarlarını yüz köşelerinden numaralar (order 1: ileri a->b, 2: önceki köşeyle, 3: köşeler tersten).
-- Sonuç: UV kenar sırası -> #(tvA, tvB)
fn MT_UV_TVEdgeOrder um order =
(
    local d = Dictionary #string
    local pairs = #()
    for f = 1 to um.numberPolygons() do
    (
        local n = um.numberPointsInFace f
        local tv = for j = 1 to n collect (um.getVertexIndexFromFace f j)
        local js = if order == 3 then (for j = n to 1 by -1 collect j) else (for j = 1 to n collect j)
        for j in js do
        (
            local a = tv[j]
            local b = if order == 1 then tv[(if j == n then 1 else j + 1)] else tv[(if j == 1 then n else j - 1)]
            local key = MT_EdgeKey a b
            if not HasDictValue d key do (append pairs #(a, b); PutDictValue d key pairs.count)
        )
    )
    pairs
)

-- Geometri kenar anahtarı ("vA_vB") -> o kenara ait UV kenar indeksleri.
-- Önce hızlı kuralları 16 örnekle doğrular; hiçbiri tutmazsa tüm UV kenarlarını tek tek sorar. Önbellekli.
fn MT_UV_TVEdgeIndex um obj =
(
    local nf = um.numberPolygons()
    local ntv = um.numberVertices()
    local cache = MT_UVMapCache
    if cache != undefined and cache[1] == obj.handle and cache[2] == nf and cache[3] == ntv then cache[4]
    else
    (
        local savedE = um.getSelectedEdges()
        local savedV = um.getSelectedVertices()

        -- UV vertex -> geometri vertex
        local tv2g = #()
        local degSum = 0
        for f = 1 to nf do
        (
            local n = um.numberPointsInFace f
            degSum += n
            for j = 1 to n do tv2g[um.getVertexIndexFromFace f j] = um.getVertexGeomIndexFromFace f j
        )

        -- UV kenar sayısı (fazla bitler kırpılır)
        um.selectEdges #{1..degSum}
        local nT = (um.getSelectedEdges()).numberSet

        -- Hızlı kuralları örneklerle sına
        local samples = for i = 1 to 16 collect (1 + ((i - 1) * (nT - 1)) / 15)
        local truth = for k in samples collect (MT_UV_ProbeTVEdge um k)
        local pairs = undefined
        local bestDesc = "tam tarama"
        for order = 1 to 3 while pairs == undefined do
        (
            local cand = MT_UV_TVEdgeOrder um order
            local hits = 0
            if cand.count == nT do
                for i = 1 to samples.count where truth[i] != undefined do
                (
                    local c = cand[samples[i]]
                    if (MT_EdgeKey c[1] c[2]) == (MT_EdgeKey truth[i][1] truth[i][2]) do hits += 1
                )
            MT_DiagWrite ("  UV kenar kuralı " + order as string + ": " + hits as string + "/16  (aday kenar=" + cand.count as string + ", unwrap UV kenar=" + nT as string + ")")
            if hits == samples.count do (pairs = cand; bestDesc = "kural " + order as string)
        )

        -- Hiçbiri tutmadıysa tüm UV kenarlarını tek tek sor
        if pairs == undefined do
        (
            pairs = #()
            for k = 1 to nT do
            (
                append pairs (MT_UV_ProbeTVEdge um k)
                if (mod k 100) == 0 do
                (
                    MaxTools_Progress (100.0 * k / nT)
                    MaxTools_Status ("UV  ·  Mapping UV edges..." + k as string + " / " + nT as string) type:#busy
                    windows.processPostedMessages()
                )
            )
        )

        -- Geometri kenar anahtarı -> UV kenar indeksleri
        local edgeIndex = Dictionary #string
        local found = 0
        for k = 1 to pairs.count where pairs[k] != undefined do
        (
            local ga = tv2g[pairs[k][1]], gb = tv2g[pairs[k][2]]
            if ga != undefined and gb != undefined do
            (
                local key = MT_EdgeKey ga gb
                if not HasDictValue edgeIndex key do PutDictValue edgeIndex key #()
                append (GetDictValue edgeIndex key) k
                found += 1
            )
        )
        MT_DiagWrite ("----- UV kenar eşleme  ·  " + localTime + "  ·  " + obj.name + "  UV kenar=" + nT as string + \
                      "  eşlenen=" + found as string + "  geometri kenarı=" + edgeIndex.count as string + "  yöntem=" + bestDesc)

        um.selectEdges savedE
        try (um.selectVertices savedV) catch()
        MT_UVMapCache = #(obj.handle, nf, ntv, edgeIndex)
        edgeIndex
    )
)

-- Poly kenar bitarray'ini Unwrap'ın doğru geometri kenarlarına çevirir:
-- ilgili UV kenarlarını seçer, Unwrap'ın kendi dönüştürmesiyle seam'e çevirip okur, seam'leri geri yükler.
-- Sonuç: #(geometri kenar bitarray'i, UV kenar bitarray'i, eşlenemeyen sayısı)
fn MT_UV_PolyToUnwrapEdges um obj base polyBits =
(
    local edgeIndex = MT_UV_TVEdgeIndex um obj
    local tvBits = #{}
    local missing = 0
    for e in polyBits do
    (
        local key = MT_PolyEdgeKey base e
        if HasDictValue edgeIndex key then (for k in (GetDictValue edgeIndex key) do tvBits[k] = true)
        else missing += 1
    )
    MT_UV_PrimeSeams um
    local savedSeams = um.getPeltSelectedSeams()
    um.setSelectedGeomEdges #{}
    um.selectEdges tvBits
    um.peltEdgeSelToSeam true
    local geomBits = um.getPeltSelectedSeams()
    um.setPeltSelectedSeams savedSeams
    #(geomBits, tvBits, missing)
)

-- Hard edge'leri bulur (mode 1: smoothing group sınırı, mode 2: açı eşiği) ve SADECE seçer.
-- Unwrap'ın Edge modunda seçer; kullanıcı isterse Seam Yap ile seam'e çevirir.
-- Editable Poly seviyesinde de seçer.
fn MT_UV_SelectHardEdges mode ang =
(
    local um = MT_UV_GetMod()
    if um != undefined do
    (
        local base = selection[1].baseObject
        if classOf base != Editable_Poly then
            MaxTools_Status "UV  ·  Base object must be Editable Poly to select hard edges." type:#warn
        else
        (
            local bits = #{}
            for e = 1 to polyop.getNumEdges base do
            (
                local fs = polyop.getEdgeFaces base e
                if fs != undefined and fs.count == 2 do
                (
                    local isHard = if mode == 1 then
                        (bit.and (polyop.getFaceSmoothGroup base fs[1]) (polyop.getFaceSmoothGroup base fs[2])) == 0
                    else
                        (acos (amin 1.0 (amax (-1.0) (dot (MT_SafeFaceNormal base fs[1]) (MT_SafeFaceNormal base fs[2]))))) >= ang
                    if isHard do bits[e] = true
                )
            )
            MaxTools_Status "UV  ·  Mapping Unwrap edges..." type:#busy
            windows.processPostedMessages()
            local res = undefined
            undo "Select Hard Edges" on
            (
                polyop.setEdgeSelection base bits
                subObjectLevel = 2
                res = MT_UV_PolyToUnwrapEdges um selection[1] base bits
                -- Hem geometri hem UV kenar seçimi doğru kenarlarda olsun
                um.setSelectedGeomEdges res[1]
                um.selectEdges res[2]
            )
            redrawViews()
            MaxTools_Progress 100
            local msg = "UV  ·  " + (res[1]).numberSet as string + " hard edges selected. Use 'Mark Seams' to turn them into seams."
            if res[3] > 0 do msg += " (" + res[3] as string + " edges could not be mapped)"
            MaxTools_Status msg type:(if res[3] > 0 then #warn else #ok)
        )
    )
)

-- Auto Unwrap'ın oluşturacağı UV adası sayısını önceden hesaplar (Flatten by Smoothing Group mantığıyla).
-- mode 1: ortak smoothing grubu olan komşu yüzler aynı adada (grubu 0 olan her yüz tek başına bir ada)
-- mode 2: açı eşiğinin altındaki kenarlarla bağlı yüzler aynı adada
fn MT_CountUVIslands base mode ang =
(
    local nf = polyop.getNumFaces base
    local par = for i = 1 to nf collect i
    local sgs = if mode == 1 then (for f = 1 to nf collect (polyop.getFaceSmoothGroup base f)) else #()
    local nrm = if mode == 2 then (for f = 1 to nf collect (MT_SafeFaceNormal base f)) else #()
    for e = 1 to polyop.getNumEdges base do
    (
        local fs = polyop.getEdgeFaces base e
        if fs != undefined and fs.count == 2 do
        (
            local joined = if mode == 1 then (bit.and sgs[fs[1]] sgs[fs[2]]) != 0 \
                           else (acos (amin 1.0 (amax (-1.0) (dot nrm[fs[1]] nrm[fs[2]])))) < ang
            if joined do
            (
                local r1 = MT_UFind par fs[1]
                local r2 = MT_UFind par fs[2]
                if r1 != r2 do par[r2] = r1
            )
        )
    )
    local roots = #{}
    for f = 1 to nf do roots[MT_UFind par f] = true
    roots.numberSet
)

-- Bu sayının üstünde Max'in Flatten yerleşimi çok uzun sürebilir; kullanıcıya sorulur
global MT_IslandLimit = 500

-- mode 1: mevcut hard edge'lerden (smoothing group), mode 2: açıya göre.
-- Açı modunda smoothing geçici olarak değişir, UV açıldıktan sonra orijinali geri yüklenir.
fn MT_UV_AutoUnwrap mode ang =
(
    local um = MT_UV_GetMod()
    if um != undefined do
    (
        local obj = selection[1]
        local base = obj.baseObject
        -- Güvenlik kontrolü: çok fazla ada oluşacaksa önce sor
        local proceed = true
        local islandCount = -1
        if classOf base == Editable_Poly do
        (
            MaxTools_Status "UV  ·  Counting UV islands..." type:#busy
            windows.processPostedMessages()
            islandCount = MT_CountUVIslands base mode ang
            if islandCount > MT_IslandLimit do
            (
                local reason = if mode == 1 then \
                    "Many faces share no smoothing group (common for sculpted or imported meshes).\nTry 'By Angle' with a higher angle, or mark seams manually and use 'Unwrap Seams'." \
                else \
                    ("The surface is too detailed for " + ang as string + "°.\nTry a higher angle, or mark seams manually and use 'Unwrap Seams'.")
                proceed = queryBox ("Auto Unwrap would create " + islandCount as string + " UV islands.\n\n" + reason + \
                                    "\n\nThis can take a very long time (Esc cancels). Continue anyway?") title:"MaxTools"
            )
        )

        if not proceed then
            MaxTools_Status ("UV  ·  Cancelled: " + islandCount as string + " islands would be created. Try a higher angle or manual seams.") type:#warn
        else if mode == 2 and classOf base != Editable_Poly then
            MaxTools_Status "UV  ·  Base object must be Editable Poly for angle mode." type:#warn
        else
        (
            MaxTools_Status (if mode == 2 then "UV  ·  " + ang as string + "°+ edges: unwrapping..." else "UV  ·  Unwrapping from hard edges...") type:#busy
            windows.processPostedMessages()
            local relaxed = undefined
            local groups = 0
            undo "Auto Unwrap" on
            (
                local saved = undefined
                if mode == 2 do
                (
                    saved = for f = 1 to polyop.getNumFaces base collect (polyop.getFaceSmoothGroup base f)
                    groups = MT_SmoothByAngle base ang
                    classOf obj   -- modifier yığınını yeni smoothing ile yeniden değerlendir
                )

                um.selectFaces #{1..(um.numberPolygons())}
                um.FlattenBySmoothingGroup true false 0.01
                um.selectFaces #{1..(um.numberPolygons())}
                try (um.Unfold3DSolve(); relaxed = "Unfold3D") catch()
                if relaxed == undefined do try (um.LSCMSolve(); relaxed = "LSCM") catch()

                -- Orijinal smoothing'i geri yükle (UV'ler Unwrap'ta kalır)
                if saved != undefined do
                (
                    for f = 1 to saved.count do polyop.setFaceSmoothGroup base #{f} saved[f]
                    classOf obj
                )
            )
            local msg = if mode == 2 then "UV  ·  " + ang as string + "°+ edges unwrapped (" + groups as string + " smoothing groups)" \
                        else "UV  ·  Unwrapped from hard edges"
            if relaxed != undefined do msg += ", relaxed with " + relaxed
            MaxTools_Status (msg + ".") type:#ok
        )
    )
)

-- 2B convex hull (monotone chain)
fn MT_CmpPt a b = (if a.x < b.x then -1 else if a.x > b.x then 1 else if a.y < b.y then -1 else if a.y > b.y then 1 else 0)
fn MT_Cross2 o a b = (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)

fn MT_Hull2D pts =
(
    local p = for q in pts collect q
    qsort p MT_CmpPt
    if p.count < 3 do return p
    local lower = #()
    for q in p do
    (
        while lower.count >= 2 and (MT_Cross2 lower[lower.count - 1] lower[lower.count] q) <= 0 do deleteItem lower lower.count
        append lower q
    )
    local upper = #()
    for i = p.count to 1 by -1 do
    (
        local q = p[i]
        while upper.count >= 2 and (MT_Cross2 upper[upper.count - 1] upper[upper.count] q) <= 0 do deleteItem upper upper.count
        append upper q
    )
    deleteItem lower lower.count
    deleteItem upper upper.count
    join lower upper
)

-- En küçük alanlı dikdörtgeni veren açı: #(açı, genişlik, yükseklik)
fn MT_BestAngle hull =
(
    local bestA = 1e30, bestAng = 0.0, bestW = 0.0, bestH = 0.0
    for i = 1 to hull.count do
    (
        local a = hull[i]
        local b = hull[(mod i hull.count) as integer + 1]
        local ang = atan2 (b.y - a.y) (b.x - a.x)
        local c = cos ang, s = sin ang
        local mnx = 1e30, mxx = -1e30, mny = 1e30, mxy = -1e30
        for q in hull do
        (
            local rx = q.x * c + q.y * s
            local ry = -q.x * s + q.y * c
            mnx = amin mnx rx; mxx = amax mxx rx
            mny = amin mny ry; mxy = amax mxy ry
        )
        local area = (mxx - mnx) * (mxy - mny)
        if area < bestA - 1e-12 do (bestA = area; bestAng = ang; bestW = mxx - mnx; bestH = mxy - mny)
    )
    #(bestAng, bestW, bestH)
)

fn MT_UFind par x =
(
    while par[x] != x do (par[x] = par[par[x]]; x = par[x])
    x
)

-- Unwrap yüzlerinden UV shell'lerini bulur: #(shell vertex dizileri, shell yüz bitarray'leri)
fn MT_UV_Shells um faces =
(
    local nv = um.numberVertices()
    local par = for i = 1 to nv collect i
    local used = #{}
    for f in faces do
    (
        local k = um.numberPointsInFace f
        local v0 = um.getVertexIndexFromFace f 1
        used[v0] = true
        local r0 = MT_UFind par v0
        for j = 2 to k do
        (
            local vj = um.getVertexIndexFromFace f j
            used[vj] = true
            local r1 = MT_UFind par vj
            if r1 != r0 do par[r1] = r0
        )
    )

    local shellOf = for i = 1 to nv collect 0
    local shellsV = #(), shellsF = #()
    for v in used do
    (
        local r = MT_UFind par v
        if shellOf[r] == 0 do
        (
            append shellsV #()
            append shellsF #{}
            shellOf[r] = shellsV.count
        )
        append shellsV[shellOf[r]] v
    )
    for f in faces do
    (
        local r = MT_UFind par (um.getVertexIndexFromFace f 1)
        shellsF[shellOf[r]][f] = true
    )
    #(shellsV, shellsF)
)

-- Bir shell'i eksene hizalar. mode: 1 otomatik, 2 yatay, 3 dikey. Döndürdüyse true.
fn MT_UV_OrientShell um sh mode =
(
    local P = for v in sh collect (um.getVertexPosition 0 v)
    local hull = MT_Hull2D (MT_Pts2D P)
    if hull.count < 2 then false
    else
    (
        local best = MT_BestAngle hull
        local r = -best[1], w = best[2], h = best[3]
        while r > 45.0 do (r -= 90.0; swap w h)
        while r <= -45.0 do (r += 90.0; swap w h)
        if mode == 2 and w < h do (r += (if r <= 0 then 90.0 else -90.0); swap w h)
        if mode == 3 and h < w do (r += (if r <= 0 then 90.0 else -90.0); swap w h)

        if abs r <= 0.001 then false
        else
        (
            local mnx = 1e30, mxx = -1e30, mny = 1e30, mxy = -1e30
            for q in P do (mnx = amin mnx q.x; mxx = amax mxx q.x; mny = amin mny q.y; mxy = amax mxy q.y)
            local cx = (mnx + mxx) / 2.0, cy = (mny + mxy) / 2.0
            local c = cos r, s = sin r
            for i = 1 to sh.count do
            (
                local q = P[i]
                local dx = q.x - cx, dy = q.y - cy
                um.setVertexPosition 0 sh[i] [cx + dx * c - dy * s, cy + dx * s + dy * c, q.z]
            )
            true
        )
    )
)

fn MT_Flat2D q = [q.x, q.y, 0.0]

fn MT_TurnAngle a b c =
(
    local d1 = b - a, d2 = c - b
    local l1 = length d1, l2 = length d2
    if l1 < 1e-12 or l2 < 1e-12 then 0.0
    else acos (amin 1.0 (amax (-1.0) ((dot d1 d2) / (l1 * l2))))
)

fn MT_PolyLen pts =
(
    local total = 0.0
    for i = 2 to pts.count do total += distance pts[i] pts[i - 1]
    total
)

fn MT_SignedArea pts =
(
    local a = 0.0
    for i = 1 to pts.count do
    (
        local p = pts[i]
        local q = pts[(if i == pts.count then 1 else i + 1)]
        a += p.x * q.y - q.x * p.y
    )
    a / 2.0
)

fn MT_CmpDescX a b = (if a.x > b.x then -1 else if a.x < b.x then 1 else 0)

-- Şerit dikdörtgenleştirme: tüm vertex'leri sınırda olan ve 4 belirgin köşesi olan shell'i
-- (harf yan şeridi, duvar bandı vb.) iç üçgen/n-gon yapısından bağımsız olarak tam dikdörtgene açar.
-- Uzun iki kenar (ray) kendi uzunluklarına göre yatay, kısa kenarlar dikey çizgi olur.
fn MT_UV_RectStrip um shV shF =
(
    -- UV kenarlarını say: bir kez geçen kenar sınırdır
    local cnt = Dictionary #string
    for f in shF do
    (
        local deg = um.numberPointsInFace f
        for j = 1 to deg do
        (
            local a = um.getVertexIndexFromFace f j
            local b = um.getVertexIndexFromFace f (if j == deg then 1 else j + 1)
            local key = if a < b then (a as string + "_" + b as string) else (b as string + "_" + a as string)
            PutDictValue cnt key ((if HasDictValue cnt key then GetDictValue cnt key else 0) + 1)
        )
    )
    local nb = Dictionary #integer
    for key in cnt.keys where (GetDictValue cnt key) == 1 do
    (
        local parts = filterString key "_"
        local a = parts[1] as integer, b = parts[2] as integer
        if not HasDictValue nb a do PutDictValue nb a #()
        if not HasDictValue nb b do PutDictValue nb b #()
        append (GetDictValue nb a) b
        append (GetDictValue nb b) a
    )

    -- Şart: tüm vertex'ler sınırda ve sınır tek bir döngü
    local ok = (nb.count == shV.count) and shV.count >= 4
    if ok do for v in shV while ok do if not (HasDictValue nb v) or (GetDictValue nb v).count != 2 do ok = false
    if not ok then false
    else
    (
        local loop = #(shV[1])
        local prev = 0, cur = shV[1]
        local walking = true
        while walking do
        (
            local ns = GetDictValue nb cur
            local nxt = if ns[1] != prev then ns[1] else ns[2]
            if nxt == shV[1] or loop.count > shV.count then walking = false
            else (append loop nxt; prev = cur; cur = nxt)
        )
        local n = loop.count
        if n != shV.count then false
        else
        (
            local P = for v in loop collect (MT_Flat2D (um.getVertexPosition 0 v))
            local Wz = for v in loop collect (um.getVertexPosition 0 v).z

            -- En keskin 4 köşe
            local turns = for i = 1 to n collect (MT_TurnAngle P[(if i == 1 then n else i - 1)] P[i] P[(if i == n then 1 else i + 1)])
            local tp = for i = 1 to n collect [turns[i], i]
            qsort tp MT_CmpDescX
            if tp[4].x < 45.0 then false
            else
            (
                local corners = sort (for i = 1 to 4 collect (tp[i].y as integer))
                local sides = #()
                for s = 1 to 4 do
                (
                    local a = corners[s]
                    local b = corners[(if s == 4 then 1 else s + 1)]
                    local ids = #()
                    local i = a
                    local going = true
                    while going do
                    (
                        append ids i
                        if i == b then going = false else i = (if i == n then 1 else i + 1)
                    )
                    append sides ids
                )
                local lens = for sd in sides collect (MT_PolyLen (MT_PickPts P sd))
                local railPair = if (lens[1] + lens[3]) >= (lens[2] + lens[4]) then #(1, 3) else #(2, 4)
                local shortPair = if railPair[1] == 1 then #(2, 4) else #(1, 3)
                local railA = sides[railPair[1]]
                local sb = sides[railPair[2]]
                local railB = for i = sb.count to 1 by -1 collect sb[i]
                local W = (lens[railPair[1]] + lens[railPair[2]]) / 2.0
                local H = (lens[shortPair[1]] + lens[shortPair[2]]) / 2.0
                if W < 1e-9 or H < 1e-9 then false
                else
                (
                    local newP = for i = 1 to n collect [0.0, 0.0, 0.0]
                    for pass = 1 to 2 do
                    (
                        local rail = if pass == 1 then railA else railB
                        local vv = if pass == 1 then 0.0 else H
                        local total = MT_PolyLen (MT_PickPts P rail)
                        local acc = 0.0
                        for k = 1 to rail.count do
                        (
                            if k > 1 do acc += distance P[rail[k]] P[rail[k - 1]]
                            newP[rail[k]] = [(if total > 1e-12 then W * acc / total else 0.0), vv, 0.0]
                        )
                    )
                    -- Yön (ayna) korunsun
                    if (MT_SignedArea P) * (MT_SignedArea newP) < 0 do
                        newP = MT_FlipY newP H

                    -- Eski merkezine yerleştir
                    local mnx = 1e30, mxx = -1e30, mny = 1e30, mxy = -1e30
                    for q in P do (mnx = amin mnx q.x; mxx = amax mxx q.x; mny = amin mny q.y; mxy = amax mxy q.y)
                    local ox = (mnx + mxx) / 2.0 - W / 2.0
                    local oy = (mny + mxy) / 2.0 - H / 2.0
                    for i = 1 to n do um.setVertexPosition 0 loop[i] [ox + newP[i].x, oy + newP[i].y, Wz[i]]
                    true
                )
            )
        )
    )
)

-- mode: 1 otomatik, 2 yatay (uzun kenar yatay), 3 dikey
fn MT_UV_Straighten mode rectStrips =
(
    local um = MT_UV_GetMod create:false
    if um != undefined do
    (
        local nf = um.numberPolygons()
        local faces = try (um.getSelectedFaces()) catch #{}
        if faces.isEmpty do faces = #{1..nf}
        local sh = MT_UV_Shells um faces
        local strips = 0, rotated = 0

        MaxTools_Status "UV  ·  Straightening..." type:#busy
        windows.processPostedMessages()
        undo "UV Straighten" on
        (
            for i = 1 to sh[1].count where sh[1][i].count >= 2 do
            (
                if rectStrips and (MT_UV_RectStrip um sh[1][i] sh[2][i]) do strips += 1
                if MT_UV_OrientShell um sh[1][i] mode do rotated += 1
            )
        )
        local msg = "UV  ·  " + sh[1].count as string + " shells:"
        if rectStrips do msg += strips as string + " strips rectangularized,"
        MaxTools_Status (msg + rotated as string + " rotated.") type:#ok
    )
)

-- ----- Nokta dizisi yardımcıları -----
-- İç içe 'for ... collect' döngülerinin dış döngü değişkenlerini yakalaması MAXScript'te
-- "Bad free thunk" hatasına yol açıyor; bu işlemleri ayrı fonksiyonlarda yapıyoruz.
fn MT_ShellPositions um verts = for v in verts collect (um.getVertexPosition 0 v)
fn MT_ScalePts pts factor = for q in pts collect [q.x * factor, q.y * factor, q.z]
fn MT_RotatePts pts ca sa = for q in pts collect [q.x * ca - q.y * sa, q.x * sa + q.y * ca, q.z]
fn MT_Pts2D pts = for q in pts collect [q.x, q.y]
fn MT_InflateRects rects sc pad = for rc in rects collect [rc.x * sc + pad, rc.y * sc + pad]
fn MT_PickPts pts ids = for i in ids collect pts[i]
fn MT_FlipY pts hgt = for q in pts collect [q.x, hgt - q.y, 0.0]

-- ----- Skyline paketleyici (kap: 0..1 kare) -----
-- sky: Point3 dizisi [x, y, genişlik]
fn MT_SkyFit sky i w =
(
    local x = sky[i].x
    if x + w > 1.0 + 1e-9 then -1.0
    else
    (
        local y = sky[i].y
        local left = w
        local j = i
        local fits = true
        while fits and left > 1e-12 do
        (
            if j > sky.count then fits = false
            else
            (
                y = amax y sky[j].y
                left -= sky[j].z
                j += 1
            )
        )
        if fits then y else -1.0
    )
)

fn MT_SkyAdd sky i x y w h =
(
    insertItem [x, y + h, w] sky i
    local endX = x + w
    local j = i + 1
    local trimming = true
    while trimming and j <= sky.count do
    (
        local s = sky[j]
        if s.x < endX - 1e-12 then
        (
            local cut = endX - s.x
            if s.z - cut <= 1e-12 then deleteItem sky j
            else (sky[j] = [s.x + cut, s.y, s.z - cut]; trimming = false)
        )
        else trimming = false
    )
    local k = 1
    while k < sky.count do
    (
        if abs (sky[k].y - sky[k + 1].y) < 1e-12 then
        (
            sky[k] = [sky[k].x, sky[k].y, sky[k].z + sky[k + 1].z]
            deleteItem sky (k + 1)
        )
        else k += 1
    )
)

-- rects: Point2 [genişlik, yükseklik] dizisi. Sonuç: Point3 [x, y, döndürüldü(0/1)] dizisi ya da undefined
fn MT_SkyPack rects allowRot =
(
    local order = for i = 1 to rects.count collect [(if allowRot then amax rects[i].x rects[i].y else rects[i].y), i]
    qsort order MT_CmpDescX
    local sky = #([0.0, 0.0, 1.0])
    local out = for i = 1 to rects.count collect [0.0, 0.0, 0.0]
    local failed = false
    for o in order while not failed do
    (
        local id = o.y as integer
        local best = undefined
        local rotOpts = if allowRot then #(0, 1) else #(0)
        for rt in rotOpts do
        (
            local rw = if rt == 1 then rects[id].y else rects[id].x
            local rh = if rt == 1 then rects[id].x else rects[id].y
            for i = 1 to sky.count do
            (
                local fy = MT_SkyFit sky i rw
                if fy >= 0 and (fy + rh) <= 1.0 + 1e-9 do
                (
                    local top = fy + rh
                    if best == undefined or top < best[1] - 1e-9 or ((abs (top - best[1])) <= 1e-9 and sky[i].x < best[2]) do
                        best = #(top, sky[i].x, i, rt, rw, rh, fy)
                )
            )
        )
        if best == undefined then failed = true
        else
        (
            out[id] = [best[2], best[7], best[4]]
            MT_SkyAdd sky best[3] best[2] best[7] best[5] best[6]
        )
    )
    if failed then undefined else out
)

-- Adaları 0..1 alanına, piksel boşluğu sabit kalacak şekilde mümkün olan en büyük ölçekte yerleştirir.
-- Yedek: sınır kutusu tabanlı skyline paketleyici (C# derlenemezse kullanılır)
fn MT_UV_PackBoxes texSize padPx allowRot equalize =
(
    local um = MT_UV_GetMod create:false
    if um != undefined do
    (
        MaxTools_Status "UV  ·  Packing..." type:#busy
        windows.processPostedMessages()
        local nf = um.numberPolygons()
        local sh = MT_UV_Shells um #{1..nf}
        local shV = sh[1], shF = sh[2]
        local n = shV.count
        if n == 0 then MaxTools_Status "UV  ·  No UV islands to pack." type:#warn
        else
        (
            local P = for sv in shV collect (MT_ShellPositions um sv)

            -- 1) Texel yoğunluğunu eşitle (UV alanı / 3B alan oranı tüm adalarda aynı olsun)
            if equalize do
            (
                for i = 1 to n do
                (
                    local x = 0.0, y = 0.0, w = 0.0, h = 0.0, ua = 0.0, ga = 0.0
                    um.getArea shF[i] &x &y &w &h &ua &ga
                    if ua > 1e-14 and ga > 0 do
                    (
                        P[i] = MT_ScalePts P[i] (sqrt (ga / ua))
                    )
                )
            )

            -- 2) Döndürme serbestse her adayı en küçük alanlı dikdörtgenine hizala
            if allowRot do
            (
                for i = 1 to n where P[i].count >= 3 do
                (
                    local hull = MT_Hull2D (MT_Pts2D P[i])
                    if hull.count >= 3 do
                    (
                        local rotA = -((MT_BestAngle hull)[1])
                        P[i] = MT_RotatePts P[i] (cos rotA) (sin rotA)
                    )
                )
            )

            -- 3) Sınır kutuları
            local mins = #(), rects = #()
            for i = 1 to n do
            (
                local mnx = 1e30, mny = 1e30, mxx = -1e30, mxy = -1e30
                for q in P[i] do (mnx = amin mnx q.x; mxx = amax mxx q.x; mny = amin mny q.y; mxy = amax mxy q.y)
                append mins [mnx, mny]
                append rects [mxx - mnx, mxy - mny]
            )

            -- 4) En büyük ölçeği ikili arama ile bul (boşluk piksel cinsinden sabit)
            local pad = (padPx as float) / texSize
            local area = 0.0, maxDim = 0.0
            for rc in rects do (area += rc.x * rc.y; maxDim = amax maxDim (amax rc.x rc.y))
            if area < 1e-20 or maxDim < 1e-12 then MaxTools_Status "UV  ·  Islands have zero area, cannot pack." type:#warn
            else
            (
                local hi = amin (1.0 / sqrt area) ((1.0 - pad) / maxDim)
                local lo = 0.0, bestS = 0.0, bestPos = undefined
                local searching = true
                for it = 1 to 22 while searching do
                (
                    local sc = if it == 1 then hi else (lo + hi) / 2.0
                    local pos = MT_SkyPack (MT_InflateRects rects sc pad) allowRot
                    if pos != undefined then
                    (
                        lo = sc; bestS = sc; bestPos = pos
                        if it == 1 do searching = false
                    )
                    else hi = sc
                    MaxTools_Progress (100.0 * it / 22)
                    windows.processPostedMessages()
                )

                if bestPos == undefined then MaxTools_Status "UV  ·  No valid layout found (padding may be too large)." type:#error
                else
                (
                    undo "UV Pack" on
                    (
                        for i = 1 to n do
                        (
                            local pl = bestPos[i]
                            local mn = mins[i]
                            local hs = rects[i].y * bestS
                            for k = 1 to shV[i].count do
                            (
                                local q = P[i][k]
                                local u = (q.x - mn.x) * bestS
                                local v = (q.y - mn.y) * bestS
                                if pl.z > 0.5 do (local t = u; u = hs - v; v = t)
                                um.setVertexPosition 0 shV[i][k] [pl.x + pad / 2.0 + u, pl.y + pad / 2.0 + v, q.z]
                            )
                        )
                    )
                    local fill = (area * bestS * bestS * 100.0) as integer
                    MaxTools_Progress 100
                    MaxTools_Status ("UV  ·  " + n as string + " islands packed, area coverage %" + fill as string + \
                                     " (" + texSize as string + " px, " + padPx as string + " px padding).") type:#ok
                )
            )
        )
    )
)

-- ----- Şekil tabanlı (raster) paketleyici: C# çekirdeği -----
-- MaxToolsPacker.cs scriptin yanında durur; ilk kullanımda Max içinde derlenir.
-- Dosya değişirse (tarihinden anlaşılır) yeniden derlenir.
fn MT_GetPacker =
(
    local src = MT_ScriptDir + "MaxToolsPacker.cs"
    if not (doesFileExist src) then
    (
        MT_DiagWrite ("C# packer file missing: " + src)
        undefined
    )
    else
    (
        local stamp = getFileModDate src
        if MT_PackerObj != undefined and MT_PackerStamp == stamp then MT_PackerObj
        else
        (
            local result = undefined
            try
            (
                local code = (dotNetClass "System.IO.File").ReadAllText src
                local provider = dotNetObject "Microsoft.CSharp.CSharpCodeProvider"
                local cparams = dotNetObject "System.CodeDom.Compiler.CompilerParameters"
                cparams.ReferencedAssemblies.Add "System.dll"
                cparams.GenerateInMemory = true
                cparams.GenerateExecutable = false
                local cr = provider.CompileAssemblyFromSource cparams #(code)
                if cr.Errors.HasErrors then
                (
                    for ei = 0 to cr.Errors.Count - 1 do
                        try (MT_DiagWrite ("C# compile error: " + (cr.Errors.item[ei]).ToString())) catch()
                    format "MaxTools: C# packer failed to compile (see MaxTools_diag.txt).\n"
                )
                else
                (
                    result = cr.CompiledAssembly.CreateInstance "MTPacker"
                    MT_PackerObj = result
                    MT_PackerStamp = stamp
                )
            )
            catch
            (
                MT_DiagWrite ("C# packer could not be loaded: " + (getCurrentException()) as string)
                format "MaxTools: C# packer could not be loaded: %\n" (getCurrentException())
            )
            result
        )
    )
)

-- Bir adanın yüzlerini üçgenlere bölüp "x0,y0,x1,y1,x2,y2,..." metnine çevirir
fn MT_IslandCsv um faces posOf =
(
    local ss = stringStream ""
    for f in faces do
    (
        local deg = um.numberPointsInFace f
        local cornerTV = for cj = 1 to deg collect (um.getVertexIndexFromFace f cj)
        for tj = 2 to deg - 1 do
        (
            local pa = posOf[cornerTV[1]], pb = posOf[cornerTV[tj]], pc = posOf[cornerTV[tj + 1]]
            format "%,%,%,%,%,%," pa.x pa.y pb.x pb.y pc.x pc.y to:ss
        )
    )
    ss as string
)

-- Ada noktalarını döndür, ölçekle, taşı ve Unwrap'a yaz
fn MT_ApplyPlacement um verts pts ang tx ty sc =
(
    local ca = cos ang, sa = sin ang
    for k = 1 to verts.count do
    (
        local q = pts[k]
        um.setVertexPosition 0 verts[k] [(q.x * ca - q.y * sa) * sc + tx, (q.x * sa + q.y * ca) * sc + ty, q.z]
    )
)

-- rotMode: 1 yok, 2 90°, 3 serbest (45° adım)
fn MT_UV_PackMax texSize padPx rotMode equalize =
(
    local um = MT_UV_GetMod create:false
    if um != undefined do
    (
        local packer = MT_GetPacker()
        if packer == undefined then
        (
            format "MaxTools: C# packer unavailable, falling back to box packer.\n"
            MT_UV_PackBoxes texSize padPx (rotMode > 1) equalize
        )
        else
        (
            MaxTools_Status (if rotMode == 3 then "UV  ·  Packing (free rotation, may take a while)..." else "UV  ·  Packing...") type:#busy
            windows.processPostedMessages()
            local nf = um.numberPolygons()
            local sh = MT_UV_Shells um #{1..nf}
            local shV = sh[1], shF = sh[2]
            local n = shV.count
            if n == 0 then MaxTools_Status "UV  ·  No UV islands to pack." type:#warn
            else
            (
                local P = for sv in shV collect (MT_ShellPositions um sv)

                -- Texel yoğunluğunu eşitle
                if equalize do
                (
                    for i = 1 to n do
                    (
                        local x = 0.0, y = 0.0, w = 0.0, h = 0.0, ua = 0.0, ga = 0.0
                        um.getArea shF[i] &x &y &w &h &ua &ga
                        if ua > 1e-14 and ga > 0 do P[i] = MT_ScalePts P[i] (sqrt (ga / ua))
                    )
                )

                -- UV vertex -> güncel konum
                local posOf = #()
                for i = 1 to n do for k = 1 to shV[i].count do posOf[shV[i][k]] = P[i][k]

                -- Adaları C# paketleyiciye ver (döndürmede başlangıç: en sıkı dikdörtgen açısı)
                packer.Clear()
                for i = 1 to n do
                (
                    local baseAng = 0.0
                    if rotMode > 1 and P[i].count >= 3 do
                    (
                        local hull = MT_Hull2D (MT_Pts2D P[i])
                        if hull.count >= 3 do baseAng = -((MT_BestAngle hull)[1])
                    )
                    packer.AddIsland (MT_IslandCsv um shF[i] posOf) (baseAng as float)
                )

                local res = packer.Pack texSize (padPx as float) (rotMode - 1) 0.0 512
                if res == undefined or res == "" then
                (
                    format "MaxTools: shape-based layout failed, falling back to box packer.\n"
                    MT_UV_PackBoxes texSize padPx (rotMode > 1) equalize
                )
                else
                (
                    local parts = filterString res "|"
                    local head = filterString parts[1] ","
                    local sc = head[1] as float
                    local fill = ((head[2] as float) * 100.0) as integer
                    undo "UV Pack" on
                    (
                        for i = 1 to n do
                        (
                            local pv = filterString parts[i + 1] ","
                            MT_ApplyPlacement um shV[i] P[i] (pv[1] as float) (pv[2] as float) (pv[3] as float) sc
                        )
                    )
                    MaxTools_Progress 100
                    MaxTools_Status ("UV  ·  " + n as string + " islands packed, area coverage %" + fill as string + \
                                     " (" + texSize as string + " px, " + padPx as string + " px padding).") type:#ok
                )
            )
        )
    )
)

-- =========================================
-- ARAÇLAR: İSİMLENDİRME
-- =========================================
fn MT_CleanName s =
(
    local trPairs = #(#("ç","c"), #("Ç","C"), #("ğ","g"), #("Ğ","G"), #("ı","i"), #("İ","I"), \
                      #("ö","o"), #("Ö","O"), #("ş","s"), #("Ş","S"), #("ü","u"), #("Ü","U"))
    for p in trPairs do s = substituteString s p[1] p[2]

    local valid = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    local out = ""
    for i = 1 to s.count do
    (
        local ch = s[i]
        out += (if findString valid ch != undefined then ch else "_")
    )
    while findString out "__" != undefined do out = substituteString out "__" "_"
    out = trimRight (trimLeft out "_") "_"
    if out == "" do out = "Object"
    out
)

fn MT_NameAddFix pre suf =
(
    local objs = selection as array
    if objs.count == 0 then MaxTools_Status "Name  ·  Please select objects." type:#warn
    else if pre == "" and suf == "" then MaxTools_Status "Name  ·  Enter a prefix or suffix." type:#warn
    else
    (
        undo "Add Prefix / Suffix" on
        (
            for o in objs do
            (
                local n = o.name
                if pre != "" and not (matchPattern n pattern:(pre + "*") ignoreCase:false) do n = pre + n
                if suf != "" and not (matchPattern n pattern:("*" + suf) ignoreCase:false) do n = n + suf
                o.name = n
            )
        )
        MaxTools_Status ("Name  ·" + objs.count as string + " objects updated.") type:#ok
    )
)

fn MT_NameRename base startNum pad =
(
    local objs = selection as array
    if objs.count == 0 then MaxTools_Status "Name  ·  Please select objects." type:#warn
    else if base == "" then MaxTools_Status "Name  ·  Enter a new name." type:#warn
    else
    (
        local fmt = "0" + pad as string + "d"
        undo "Rename + Number" on
        (
            for i = 1 to objs.count do
                objs[i].name = base + "_" + (formattedPrint (startNum + i - 1) format:fmt)
        )
        MaxTools_Status ("Name  ·" + objs.count as string + " objects renamed.") type:#ok
    )
)

fn MT_NameReplace findTxt replTxt =
(
    local objs = selection as array
    if objs.count == 0 then MaxTools_Status "Name  ·  Please select objects." type:#warn
    else if findTxt == "" then MaxTools_Status "Name  ·  Enter text to find." type:#warn
    else
    (
        local cnt = 0
        undo "Find / Replace" on
        (
            for o in objs do
            (
                local n = substituteString o.name findTxt replTxt
                if n != o.name do (o.name = n; cnt += 1)
            )
        )
        MaxTools_Status ("Name  ·" + cnt as string + " names changed.") type:(if cnt > 0 then #ok else #warn)
    )
)

fn MT_NameClean =
(
    local objs = selection as array
    if objs.count == 0 then MaxTools_Status "Name  ·  Please select objects." type:#warn
    else
    (
        local cnt = 0
        undo "Clean Names" on
        (
            for o in objs do
            (
                local n = MT_CleanName o.name
                if n != o.name do (o.name = n; cnt += 1)
            )
        )
        MaxTools_Status ("Name  ·" + cnt as string + " names cleaned.") type:#ok
    )
)

-- =========================================
-- ARAÇLAR: LOD
-- =========================================
-- ProOptimizer özellik adları sürümden sürüme değişebildiği için alternatifleri dener
fn MT_TrySet m props val =
(
    local ok = false
    for p in props while not ok do
        if isProperty m p do ok = (try (setProperty m p val; true) catch false)
    if not ok do format "MaxTools: could not set ProOptimizer property: %\n" props
    ok
)

fn MT_TriCount n =
(
    local m = snapshotAsMesh n
    local t = m.numfaces
    delete m
    t
)

-- opts: #(kenarModu, uvKoru, normalKoru, materyalKoru, polyCevir)
fn MT_MakeLOD src pct newName opts =
(
    local c = copy src
    c.name = newName

    local po = ProOptimizer()
    addModifier c po

    -- 0: Crunch Borders, 1: Protect Borders, 2: Exclude Borders
    MT_TrySet po #(#OptimizationMode) opts[1]
    MT_TrySet po #(#KeepUV, #KeepTextures) opts[2]
    if opts[2] do MT_TrySet po #(#KeepUVBoundaries, #KeepUVBoundary, #UVBoundaries) true
    MT_TrySet po #(#KeepNormals) opts[3]
    MT_TrySet po #(#LockMat, #KeepMaterialBoundaries) opts[4]
    MT_TrySet po #(#PreventFlip) true
    MT_TrySet po #(#VertexPercent) (pct as float)

    -- ProOptimizer hesaplamayı Modify panelinde aktifken yapar
    max modify mode
    select c
    modPanel.setCurrentObject po
    po.Calculate = true
    MT_TrySet po #(#VertexPercent) (pct as float)

    if opts[5] do convertTo c Editable_Poly
    c
)

fn MT_LOD cnt pcts opts renameLOD0 offset =
(
    local srcs = for o in selection where superClassOf o == GeometryClass collect o
    if srcs.count == 0 then MaxTools_Status "LOD  ·  Please select geometry." type:#warn
    else
    (
        local created = #()
        local report = ""
        local total = srcs.count * cnt
        local done = 0

        undo "Create LODs" on
        (
            for src in srcs do
            (
                local baseName = src.name
                if matchPattern baseName pattern:"*_LOD0" do baseName = substring baseName 1 (baseName.count - 5)
                if renameLOD0 do src.name = baseName + "_LOD0"

                local w = src.max.x - src.min.x
                report = "LOD0 " + (MT_TriCount src) as string

                for i = 1 to cnt do
                (
                    MaxTools_Status ("LOD  ·  " + baseName + "_LOD" + i as string + " calculating...") type:#busy
                    windows.processPostedMessages()

                    local c = MT_MakeLOD src pcts[i] (baseName + "_LOD" + i as string) opts
                    if offset do move c [w * 1.25 * i, 0, 0]
                    append created c
                    report += " › " + (MT_TriCount c) as string

                    done += 1
                    MaxTools_Progress (100.0 * done / total)
                )
            )
            select srcs
        )

        MaxTools_Status ("LOD  ·  " + created.count as string + " LODs created. Tris:" + report) type:#ok
        format "MaxTools LOD: %\n" report
    )
)

-- =========================================
-- ARAÇLAR: COLLISION
-- =========================================
fn MT_IsColName n =
(
    matchPattern n pattern:"UCX_*" or matchPattern n pattern:"UBX_*" or matchPattern n pattern:"USP_*"
)

fn MT_ColName prefix src =
(
    local i = 1
    local n
    do
    (
        n = prefix + src.name + "_" + (formattedPrint i format:"02d")
        i += 1
    )
    while getNodeByName n != undefined
    n
)

fn MT_WorldVerts src =
(
    local m = snapshotAsMesh src
    local v = for i = 1 to m.numverts collect getVert m i
    delete m
    v
)

-- Küre üzerine eşit dağılmış yönlerde en uç noktaları seçer
fn MT_SampleExtremes verts nDirs =
(
    local ga = 180.0 * (3.0 - sqrt 5.0)  -- altın açı (derece)
    local picked = #{}
    for k = 0 to nDirs - 1 do
    (
        local y = 1.0 - (k as float / (nDirs - 1)) * 2.0
        local r = sqrt (amax 0.0 (1.0 - y * y))
        local d = [r * cos (ga * k), y, r * sin (ga * k)]

        local maxD = -1e30, minD = 1e30, iMax = 1, iMin = 1
        for i = 1 to verts.count do
        (
            local t = dot verts[i] d
            if t > maxD do (maxD = t; iMax = i)
            if t < minD do (minD = t; iMin = i)
        )
        picked[iMax] = true
        picked[iMin] = true
    )
    for i in picked collect verts[i]
)

fn MT_FaceNormal pts f =
(
    local c = cross (pts[f[2]] - pts[f[1]]) (pts[f[3]] - pts[f[1]])
    local l = length c
    if l < 1e-12 then [0,0,0] else c / l
)

-- Artımlı 3B convex hull. Yüzler dışa bakan #(a,b,c) indeks dizileri.
fn MT_HullFaces pts =
(
    local n = pts.count
    if n < 4 do return #()

    local i0 = 1, i1 = 0, i2 = 0, i3 = 0, best = 0.0
    for i = 1 to n do (local d = distance pts[i] pts[i0]; if d > best do (best = d; i1 = i))
    if best < 1e-6 do return #()
    local eps = best * 1e-5

    local dir = normalize (pts[i1] - pts[i0])
    best = 0.0
    for i = 1 to n do
    (
        local v = pts[i] - pts[i0]
        local d = length (v - dir * (dot v dir))
        if d > best do (best = d; i2 = i)
    )
    if i2 == 0 or best < eps do return #()

    local nrm = normalize (cross (pts[i1] - pts[i0]) (pts[i2] - pts[i0]))
    best = 0.0
    for i = 1 to n do
    (
        local d = abs (dot (pts[i] - pts[i0]) nrm)
        if d > best do (best = d; i3 = i)
    )
    if i3 == 0 or best < eps do return #()

    local cen = (pts[i0] + pts[i1] + pts[i2] + pts[i3]) / 4.0
    local faces = #()
    for f in #(#(i0,i1,i2), #(i0,i2,i3), #(i0,i3,i1), #(i1,i3,i2)) do
    (
        if dot (MT_FaceNormal pts f) (pts[f[1]] - cen) < 0 then append faces #(f[1], f[3], f[2])
        else append faces f
    )

    for p = 1 to n do
    (
        if p == i0 or p == i1 or p == i2 or p == i3 do continue
        local pt = pts[p]
        local vis = for f in faces collect ((dot (MT_FaceNormal pts f) (pt - pts[f[1]])) > eps)
        if findItem vis true == 0 do continue

        local edgeKeys = #()
        for k = 1 to faces.count where vis[k] do
        (
            local f = faces[k]
            append edgeKeys (f[1] * 1000 + f[2])
            append edgeKeys (f[2] * 1000 + f[3])
            append edgeKeys (f[3] * 1000 + f[1])
        )

        local newFaces = for k = 1 to faces.count where not vis[k] collect faces[k]
        for key in edgeKeys do
        (
            local a = key / 1000
            local b = key - a * 1000
            -- karşı yönlü kenar görünür yüzlerde yoksa ufuk kenarıdır
            if findItem edgeKeys (b * 1000 + a) == 0 do append newFaces #(a, b, p)
        )
        faces = newFaces
    )
    faces
)

fn MT_MakeConvex src nDirs =
(
    local verts = MT_WorldVerts src
    if verts.count < 4 do return undefined
    local pts = MT_SampleExtremes verts nDirs
    local faces = MT_HullFaces pts
    if faces.count == 0 do return undefined

    local remap = for i = 1 to pts.count collect 0
    local outV = #()
    for f in faces do
        for idx in f where remap[idx] == 0 do (append outV pts[idx]; remap[idx] = outV.count)
    local outF = for f in faces collect [remap[f[1]], remap[f[2]], remap[f[3]]]

    local c = mesh vertices:outV faces:outF
    c.pivot = src.pivot
    c
)

fn MT_MakeBox src =
(
    local tm = src.transform.rotationPart as matrix3
    tm.row4 = src.transform.pos
    local bb = nodeGetBoundingBox src tm
    local mn = bb[1], mx = bb[2]
    local b = Box width:(amax 0.01 (mx.x - mn.x)) length:(amax 0.01 (mx.y - mn.y)) height:(amax 0.01 (mx.z - mn.z))
    b.transform = (transMatrix [(mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0, mn.z]) * tm
    convertToMesh b
    b
)

fn MT_MakeSphere src =
(
    local verts = MT_WorldVerts src
    local cen = (src.min + src.max) / 2.0
    local r = 0.0
    for v in verts do r = amax r (distance v cen)
    local s = Sphere radius:(amax 0.01 r) segs:16 pos:cen
    convertToMesh s
    s
)

-- Objenin kendi eksenlerinde, vertex koordinatlarından ızgara çizgileri çıkarır.
-- Böylece kapı/pencere kenarları ızgaraya tam oturur.
fn MT_AxisLines vals maxLines =
(
    sort vals
    local mn = vals[1]
    local mx = vals[vals.count]
    local ext = mx - mn
    if ext < 1e-4 do return undefined
    local tol = ext * 0.001
    local lines = #(mn)
    for v in vals where (v - lines[lines.count]) > tol do append lines v
    -- Çok karmaşık modelde eşit aralıklı ızgaraya düş
    if lines.count > maxLines + 1 do
        lines = for i = 0 to maxLines collect (mn + ext * i / maxLines)
    lines
)

fn MT_MakeParts src maxLines =
(
    local tm = src.transform.rotationPart as matrix3
    tm.row4 = src.transform.pos
    local itm = inverse tm

    -- Yerel uzayda vertex ve üçgenler
    local m = snapshotAsMesh src
    local lv = for i = 1 to m.numverts collect ((getVert m i) * itm)
    local tris = #()
    for i = 1 to m.numfaces do
    (
        local f = getFace m i
        local a = lv[f.x as integer], b = lv[f.y as integer], c = lv[f.z as integer]
        local d = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
        -- Yukarıdan bakınca alanı olmayan (dik) yüzler Z ışınını kesmez
        if abs d > 1e-9 do
            append tris #(a, b, c, d, amin a.x b.x c.x, amax a.x b.x c.x, amin a.y b.y c.y, amax a.y b.y c.y)
    )
    delete m
    if lv.count < 4 or tris.count == 0 do return #()

    local lx = MT_AxisLines (for v in lv collect v.x) maxLines
    local ly = MT_AxisLines (for v in lv collect v.y) maxLines
    local lz = MT_AxisLines (for v in lv collect v.z) maxLines
    if lx == undefined or ly == undefined or lz == undefined do return #()

    local nx = lx.count - 1, ny = ly.count - 1, nz = lz.count - 1
    local nxy = nx * ny
    local solid = #{}

    -- Her (x,y) sütununa Z yönünde ışın: kesişim sayısı tekse hücre objenin içinde.
    -- Işın noktası hücre ortasından hafif kaydırıldı ki üçgen köşegenlerine denk gelmesin.
    for i = 1 to nx do
    (
        local px = lx[i] + (lx[i+1] - lx[i]) * 0.637
        for j = 1 to ny do
        (
            local py = ly[j] + (ly[j+1] - ly[j]) * 0.571
            local zs = #()
            for t in tris where px >= t[5] and px <= t[6] and py >= t[7] and py <= t[8] do
            (
                local a = t[1], b = t[2], c = t[3], d = t[4]
                local u = ((b.x - px) * (c.y - py) - (c.x - px) * (b.y - py)) / d
                local v = ((c.x - px) * (a.y - py) - (a.x - px) * (c.y - py)) / d
                local w = 1.0 - u - v
                if u >= 0 and v >= 0 and w >= 0 do append zs (u * a.z + v * b.z + w * c.z)
            )
            if zs.count > 0 do
            (
                for k = 1 to nz do
                (
                    local zc = (lz[k] + lz[k+1]) / 2.0
                    local cnt = 0
                    for z in zs where z > zc do cnt += 1
                    if (mod cnt 2) == 1 do solid[i + (j - 1) * nx + (k - 1) * nxy] = true
                )
            )
        )
        windows.processPostedMessages()
    )

    -- Dolu hücreleri açgözlü (greedy) şekilde en büyük kutulara birleştir
    local used = #{}
    local boxes = #()
    for k = 1 to nz do for j = 1 to ny do for i = 1 to nx do
    (
        local id = i + (j - 1) * nx + (k - 1) * nxy
        if solid[id] and not used[id] do
        (
            local i2 = i
            while i2 < nx and solid[id + (i2 - i) + 1] and not used[id + (i2 - i) + 1] do i2 += 1

            local j2 = j
            local ok = true
            while ok and j2 < ny do
            (
                for ii = i to i2 while ok do
                (
                    local q = ii + j2 * nx + (k - 1) * nxy
                    if not solid[q] or used[q] do ok = false
                )
                if ok do j2 += 1
            )

            local k2 = k
            ok = true
            while ok and k2 < nz do
            (
                for jj = j to j2 while ok do
                    for ii = i to i2 while ok do
                    (
                        local q = ii + (jj - 1) * nx + k2 * nxy
                        if not solid[q] or used[q] do ok = false
                    )
                if ok do k2 += 1
            )

            for kk = k to k2 do for jj = j to j2 do for ii = i to i2 do
                used[ii + (jj - 1) * nx + (kk - 1) * nxy] = true
            append boxes #(i, i2, j, j2, k, k2)
        )
    )

    -- Kutuları objenin yönünde oluştur
    local result = #()
    for bx in boxes do
    (
        local x0 = lx[bx[1]], x1 = lx[bx[2] + 1]
        local y0 = ly[bx[3]], y1 = ly[bx[4] + 1]
        local z0 = lz[bx[5]], z1 = lz[bx[6] + 1]
        local b = Box width:(x1 - x0) length:(y1 - y0) height:(z1 - z0)
        b.transform = (transMatrix [(x0 + x1) / 2.0, (y0 + y1) / 2.0, z0]) * tm
        convertToMesh b
        append result b
    )
    result
)

-- colType: 1 convex, 2 parçalı, 3 box, 4 sphere
fn MT_Collision colType detail grid mergeParts =
(
    local srcs = for o in selection where superClassOf o == GeometryClass and not (MT_IsColName o.name) collect o
    if srcs.count == 0 then MaxTools_Status "Collision  ·  Please select geometry." type:#warn
    else
    (
        local prefix = (#("UCX_", "UCX_", "UBX_", "USP_"))[colType]
        local created = #()
        local failed = 0
        MaxTools_Status "Collision  ·  Creating..." type:#busy
        windows.processPostedMessages()

        undo "Create Collision" on
        (
            for src in srcs do
            (
                local parts = case colType of
                (
                    1: #(MT_MakeConvex src detail)
                    2: MT_MakeParts src grid
                    3: #(MT_MakeBox src)
                    4: #(MT_MakeSphere src)
                )
                parts = for c in parts where c != undefined collect c

                -- Kutuları tek objeye al (meshop.attach weld yapmaz, parçalar ayrık kalır)
                if colType == 2 and mergeParts and parts.count > 1 do
                (
                    for i = 2 to parts.count do meshop.attach parts[1] parts[i]
                    parts[1].pivot = src.pivot
                    parts = #(parts[1])
                )

                if parts.count == 0 then failed += 1
                else
                (
                    for c in parts do
                    (
                        c.name = MT_ColName prefix src
                        c.wirecolor = color 255 110 0
                        c.renderable = false
                        c.xray = true
                        append created c
                    )
                )
            )
            if created.count > 0 do select created
        )

        local msg = "Collision  ·  " + created.count as string + " collision mesh(es) created."
        if failed > 0 do msg += " " + failed as string + " objects skipped (flat/invalid)."
        MaxTools_Status msg type:(if failed > 0 then #warn else #ok)
    )
)

-- =========================================
-- ARAYÜZ KÖPRÜSÜ (C#)
-- Arayüz MaxToolsUI.cs içinde, C# olarak çalışır. MAXScript tarafında .NET olay işleyicisi yoktur;
-- C# butonları MT_UIAction "<id>" komutunu çalıştırır, değerler GetInt / GetText ile okunur.
-- =========================================
fn MT_Num nm = (if MT_UIAlive() then MT_UI.GetInt nm else 0)
fn MT_State nm = (if MT_UIAlive() then MT_UI.GetInt nm else 1)
fn MT_Flag nm = (MT_UIAlive() and (MT_UI.GetInt nm) == 1)
fn MT_Text nm = (if MT_UIAlive() then MT_UI.GetText nm else "")

fn MT_Action id =
(
    case id of
    (
        "detach":    MT_Detach()
        "copy":      MT_Copy()
        "paste":     MT_Paste()
        "group":     MT_Group()
        "attach":    MT_Attach()
        "ref":       MT_Ref()
        "drop":      MT_DropToGround (MT_State "dropMode")
        "uvAll":     MT_UVRandomAll()
        "uvSel":     MT_UVRandomSel()
        "seamAdd":   MT_UV_SeamAdd()
        "seamDel":   MT_UV_SeamRemove()
        "seamClear": MT_UV_SeamClear()
        "selHard":    MT_UV_SelectHardEdges (MT_State "uvAutoMode") (MT_Num "uvAngle")
        "autoUnwrap": MT_UV_AutoUnwrap (MT_State "uvAutoMode") (MT_Num "uvAngle")
        "peel":      MT_UV_Peel()
        "straight":  MT_UV_Straighten (MT_State "uvDir") (MT_Flag "uvRect")
        "pack":      MT_UV_PackMax (#(512, 1024, 2048, 4096))[MT_State "uvTex"] (MT_Num "uvPad") (MT_State "uvRotMode") (MT_Flag "uvEq")
        "nameFix":   MT_NameAddFix (MT_Text "nmPre") (MT_Text "nmSuf")
        "nameRen":   MT_NameRename (MT_Text "nmBase") (MT_Num "nmStart") (MT_Num "nmPad")
        "nameRep":   MT_NameReplace (MT_Text "nmFind") (MT_Text "nmRepl")
        "nameClean": MT_NameClean()
        "lod":
        (
            local pcts = for i = 1 to 4 collect MT_Num ("lodP" + i as string)
            local border = (#(2, 1, 0))[MT_State "lodBorder"]
            local opts = #(border, MT_Flag "lodUV", MT_Flag "lodNorm", MT_Flag "lodMat", MT_Flag "lodColl")
            MT_LOD (MT_Num "lodCount") pcts opts (MT_Flag "lodL0") (MT_Flag "lodOff")
        )
        "col": MT_Collision (MT_State "colType") (MT_Num "colDetail") (MT_Num "colGrid") (MT_Flag "colMerge")
    )
)

-- C# butonları bunu çağırır
fn MT_UIAction id =
(
    try (MT_Action id)
    catch
    (
        local ex = getCurrentException()
        format "MaxTools error [%]: %\n" id ex
        try (format "MaxTools stack:\n%\n" (getCurrentExceptionStackTrace())) catch()
        MaxTools_Status ("Error: " + ex + "  (details: Listener / F11)") type:#error
    )
    OK
)

-- C# pencere kapanırken bunu çağırır: konum ve sayfayı kaydet
fn MT_UIClosed =
(
    try
    (
        setINISetting (MT_Ini()) "Window" "X" (MT_UI.LastX as string)
        setINISetting (MT_Ini()) "Window" "Y" (MT_UI.LastY as string)
        setINISetting (MT_Ini()) "Window" "Page" (MT_UI.Page as string)
        setINISetting (MT_Ini()) "Window" "W" (MT_UI.LastW as string)
        setINISetting (MT_Ini()) "Window" "H" (MT_UI.LastH as string)
    )
    catch()
    -- Yedek köprü kullanıldıysa tek olay işleyicisini kaldır
    try (dotNet.removeAllEventHandlers MT_UI) catch()
    enableAccelerators = true
    OK
)

-- Yedek köprü: ManagedServices bulunamazsa C# bu tek olay üzerinden komut gönderir
fn MT_OnUIEvent s e =
(
    local cmd = try (s.PendingCmd) catch ""
    if cmd != undefined and cmd != "" do execute cmd
)

-- MaxToolsUI.cs'i derler (önbellekli; dosya değişince yeniden derler).
-- Önce Max'in MaxForm sınıfıyla (klavye/odak davranışı için) dener, olmazsa standart Form ile.
fn MT_GetUIAsm =
(
    local src = MT_ScriptDir + "MaxToolsUI.cs"
    if not (doesFileExist src) then
    (
        MT_DiagWrite ("UI source missing: " + src)
        undefined
    )
    else
    (
        local stamp = getFileModDate src
        if MT_UIAsm != undefined and MT_UIAsmStamp == stamp then MT_UIAsm
        else
        (
            local code = (dotNetClass "System.IO.File").ReadAllText src
            local maxCC = (getDir #maxroot) + "MaxCustomControls.dll"
            local asm = undefined
            for attempt = 1 to 2 while asm == undefined do
            (
                local useMaxForm = (attempt == 1)
                if not (useMaxForm and not (doesFileExist maxCC)) do
                (
                    try
                    (
                        local provider = dotNetObject "Microsoft.CSharp.CSharpCodeProvider"
                        local cparams = dotNetObject "System.CodeDom.Compiler.CompilerParameters"
                        cparams.ReferencedAssemblies.Add "System.dll"
                        cparams.ReferencedAssemblies.Add "System.Drawing.dll"
                        cparams.ReferencedAssemblies.Add "System.Windows.Forms.dll"
                        if useMaxForm do
                        (
                            cparams.ReferencedAssemblies.Add maxCC
                            cparams.CompilerOptions = "/define:MAXFORM"
                        )
                        cparams.GenerateInMemory = true
                        cparams.GenerateExecutable = false
                        local cr = provider.CompileAssemblyFromSource cparams #(code)
                        if cr.Errors.HasErrors then
                        (
                            for ei = 0 to cr.Errors.Count - 1 do
                                try (MT_DiagWrite ("UI compile error (attempt " + attempt as string + "): " + (cr.Errors.item[ei]).ToString())) catch()
                        )
                        else asm = cr.CompiledAssembly
                    )
                    catch (MT_DiagWrite ("UI compile failed: " + (getCurrentException()) as string))
                )
            )
            if asm != undefined do
            (
                MT_UIAsm = asm
                MT_UIAsmStamp = stamp
            )
            asm
        )
    )
)

-- Güncelleme bittikten sonra C# bunu çağırır: yeni MaxTools.ms'yi yükler (eski paneli kendisi kapatır)
fn MT_ReloadAfterUpdate =
(
    local f = MT_ScriptDir + "MaxTools.ms"
    if doesFileExist f do fileIn f
    OK
)

-- Max kapanmadan hemen önce: pencereyi kapat ve .NET referanslarını bırak
fn MT_Shutdown =
(
    try (if MT_UIAlive() do MT_UI.Close()) catch()
    MT_UI = undefined
    MT_PackerObj = undefined
)

fn MT_Build =
(
    local asm = MT_GetUIAsm()
    if asm == undefined then
        messageBox "MaxTools: the interface could not be compiled.\nDetails: MaxTools_diag.txt (next to MaxTools.ms)" title:"MaxTools"
    else
    (
        MT_UI = asm.CreateInstance "MTForm"
        local ini = MT_Ini()
        local px = (getINISetting ini "Window" "X") as integer
        local py = (getINISetting ini "Window" "Y") as integer
        if px == undefined do px = -99999
        if py == undefined do py = -99999
        local startPage = (getINISetting ini "Window" "Page") as integer
        if startPage == undefined do startPage = 1

        MT_UI.Build MT_Version startPage
        -- Son pencere boyutu (yoksa varsayılan kalır)
        local pw = (getINISetting ini "Window" "W") as integer
        local ph = (getINISetting ini "Window" "H") as integer
        if pw != undefined and ph != undefined do MT_UI.SetStartSize pw ph

        -- MAXScript köprüsü: ManagedServices'i yükle; bulunamazsa tek olaylık yedek yola geç
        try (dotNet.loadAssembly ((getDir #maxroot) + "ManagedServices.dll")) catch()
        MT_UI.SetMaxRoot (getDir #maxroot)
        if not (MT_UI.BridgeOK()) do
        (
            MT_DiagWrite ("UI bridge not found, using event fallback. Info: " + MT_UI.BridgeInfo())
            format "MaxTools: using event fallback for the UI bridge.\n"
            dotNet.addEventHandler MT_UI "UIEvent" MT_OnUIEvent
        )

        local hwnd = try (windows.getMAXHWND()) catch 0
        MT_UI.ShowWith hwnd px py

        -- Online güncelleme: açılışta arka planda sessiz kontrol (MaxTools.ini > [Update] AutoCheck=false ile kapatılır)
        MT_UI.ConfigureUpdates MT_UpdateBase MT_ScriptDir MT_BuildNum
        if (getINISetting ini "Update" "AutoCheck") != "false" do MT_UI.CheckForUpdates true
    )
)

-- Max kapanırken temizlik yap (tekrar çalıştırmada çift kayıt olmasın diye önce kaldır)
callbacks.removeScripts id:#MaxToolsShutdown
callbacks.addScript #preSystemShutdown "MT_Shutdown()" id:#MaxToolsShutdown

MT_Build()
