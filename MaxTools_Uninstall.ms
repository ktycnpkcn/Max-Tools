-- =========================================
-- MaxTools kaldırma
-- Bu dosyayı bir kez çalıştırın (sürükle-bırak ya da Scripting > Run Script).
-- Kurulumun Max'e eklediklerini temizler: panel, sol çubuk, başlatıcı, macro, menü, ikonlar, ayarlar.
-- MaxTools klasörünün kendisine dokunmaz (isterseniz sonra elle silin).
-- =========================================
(
    local startupFile = (getDir #userStartupScripts) + "\\MaxTools_Startup.ms"
    local msg = "Uninstall MaxTools?\n\n" + \
                "This removes the panel, the side bar, the startup script, the menu,\n" + \
                "the toolbar action, the icons and the MaxTools settings from 3ds Max.\n\n" + \
                "The MaxTools folder itself is not deleted."
    if queryBox msg title:"MaxTools Uninstall" do
    (
        local removed = #()

        -- Açık panel ve sol çubuk
        try (MT_UI.Close()) catch()
        try (cui.unRegisterDialogBar MaxToolsBar) catch()
        try (destroyDialog MaxToolsBar) catch()

        -- Kayıtlı callback'ler (oturum içi)
        for cbId in #(#MaxToolsShutdown, #MaxToolsCable, #MaxToolsBarShutdown, #MaxToolsMenu) do
            try (callbacks.removeScripts id:cbId) catch()

        -- Başlatıcı (Max her açılışta MaxTools'u bununla yüklüyordu)
        if doesFileExist startupFile do
            if deleteFile startupFile do append removed "startup script"

        -- Macro (toolbar / kısayol eylemi): Max değerlendirilen macroScript'leri usermacros'a kaydeder
        local nMcr = 0
        for f in (getFiles ((getDir #userMacros) + "\\MaxTools-*.mcr")) do if deleteFile f do nMcr += 1
        if nMcr > 0 do append removed "toolbar action"

        -- Eski menü sistemi (3ds Max 2024 ve öncesi); 2025+ menüsü başlatıcı silinince yeniden açılışta kaybolur
        if menuMan != undefined do
        (
            try
            (
                local mainBar = menuMan.getMainMenuBar()
                for i = mainBar.numItems() to 1 by -1 do
                    if (mainBar.getItem i).getTitle() == "MaxTools" do mainBar.removeItemByPosition i
                local m = menuMan.findMenu "MaxTools"
                if m != undefined do menuMan.unRegisterMenu m
                menuMan.updateMenuBar()
                append removed "menu"
            )
            catch (print ("MaxTools: could not remove menu: " + (getCurrentException()) as string))
        )

        -- İkonlar
        local userIcons = getDir #userIcons
        local nIco = 0
        for sub in #("", "Dark\\", "Light\\") do
        (
            local d = userIcons + "\\" + sub + "MaxTools\\"
            for f in (getFiles (d + "*.png")) do if deleteFile f do nIco += 1
            try ((dotNetClass "System.IO.Directory").Delete d) catch()
        )
        for nm in #("MaxTools_16i.bmp", "MaxTools_16a.bmp", "MaxTools_24i.bmp", "MaxTools_24a.bmp") do
            if deleteFile (userIcons + "\\" + nm) do nIco += 1
        if nIco > 0 do append removed "icons"
        try (colorMan.reInitIcons()) catch()

        -- Ayarlar (pencere konumu, güncelleme, sol çubuk)
        local ini = (getDir #plugcfg) + "\\MaxTools.ini"
        if doesFileExist ini do if deleteFile ini do append removed "settings"

        MT_UI = undefined

        local doneTxt = ""
        for i = 1 to removed.count do doneTxt += (if i > 1 then ", " else "") + removed[i]
        if doneTxt == "" do doneTxt = "nothing was installed"
        messageBox ("MaxTools uninstalled.\n\nRemoved: " + doneTxt + ".\n\n" + \
                    "• Restart 3ds Max to finish (the menu disappears after the restart).\n" + \
                    "• If you added the MaxTools button to a toolbar or a hotkey, remove it there.\n" + \
                    "• You can now delete the MaxTools folder:\n" + (getFilenamePath (getThisScriptFilename()))) title:"MaxTools Uninstall"
    )
)
