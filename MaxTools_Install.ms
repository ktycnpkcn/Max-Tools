-- =========================================
-- MaxTools kurulum
-- Bu dosyayı bir kez çalıştırın (sürükle-bırak ya da Scripting > Run Script).
-- Max'in başlangıç klasörüne bir başlatıcı koyar ve üst menüye "MaxTools" ekler.
-- Başlatıcı her seferinde BU klasördeki MaxTools.ms'yi açtığı için güncellemeler otomatik gelir.
-- =========================================
(
    local dir = getFilenamePath (getThisScriptFilename())
    local mainScript = dir + "MaxTools.ms"

    if not (doesFileExist mainScript) then
        messageBox ("MaxTools.ms not found:\n" + mainScript) title:"MaxTools Setup"
    else
    (
        -- İkonları Max'in kullanıcı ikon klasörüne kopyala
        -- (yeni PNG sistemi: <usericons>\MaxTools, Dark ve Light tema klasörleri; eski sistem: BMP'ler kökte)
        local iconSrc = dir + "icons\\"
        local userIcons = getDir #userIcons
        local copied = 0
        if doesFileExist iconSrc do
        (
            for sub in #("", "Dark\\", "Light\\") do
            (
                local dst = userIcons + "\\" + sub + "MaxTools\\"
                makeDir dst all:true
                for sz in #(16, 24, 32, 48) do
                (
                    local srcFile = iconSrc + "MaxTools\\MaxTools_" + sz as string + ".png"
                    local dstFile = dst + "MaxTools_" + sz as string + ".png"
                    if doesFileExist dstFile do deleteFile dstFile
                    if copyFile srcFile dstFile do copied += 1
                )
            )
            for nm in #("MaxTools_16i.bmp", "MaxTools_16a.bmp", "MaxTools_24i.bmp", "MaxTools_24a.bmp") do
            (
                local dstFile = userIcons + "\\" + nm
                if doesFileExist dstFile do deleteFile dstFile
                if copyFile (iconSrc + nm) dstFile do copied += 1
            )
            try (colorMan.reInitIcons()) catch()
        )

        local startupDir = getDir #userStartupScripts
        makeDir startupDir all:true
        local startupFile = startupDir + "\\MaxTools_Startup.ms"

        -- Başlatıcı içeriği (yalnızca ASCII karakterler)
        local f = createFile startupFile
        format "-- MaxTools baslatici (MaxTools_Install.ms tarafindan olusturuldu)\n" to:f
        format "-- Kaldirmak icin bu dosyayi silin.\n\n" to:f
        format "macroScript MaxTools_Open category:\"MaxTools\" buttonText:\"MaxTools\" toolTip:\"Open MaxTools panel\" iconName:\"MaxTools/MaxTools\" icon:#(\"MaxTools\", 1)\n" to:f
        format "(\n" to:f
        format "    on execute do\n" to:f
        format "    (\n" to:f
        format "        local p = @\"%\"\n" mainScript to:f
        format "        if doesFileExist p then fileIn p else messageBox (\"MaxTools.ms not found: \" + p) title:\"MaxTools\"\n" to:f
        format "    )\n" to:f
        format ")\n\n" to:f
        format "(\n" to:f
        format "    -- Ust menuye MaxTools menusunu ekle (yoksa)\n" to:f
        format "    try\n" to:f
        format "    (\n" to:f
        format "        if menuMan.findMenu \"MaxTools\" == undefined do\n" to:f
        format "        (\n" to:f
        format "            local mainBar = menuMan.getMainMenuBar()\n" to:f
        format "            local sub = menuMan.createMenu \"MaxTools\"\n" to:f
        format "            sub.addItem (menuMan.createActionItem \"MaxTools_Open\" \"MaxTools\") -1\n" to:f
        format "            mainBar.addItem (menuMan.createSubMenuItem \"MaxTools\" sub) -1\n" to:f
        format "            menuMan.updateMenuBar()\n" to:f
        format "        )\n" to:f
        format "    )\n" to:f
        format "    catch (print (\"MaxTools: could not add menu: \" + (getCurrentException()) as string))\n" to:f
        format ")\n\n" to:f
        format "-- Sol kenar arac cubugu (proje klasorunden; guncellemeler otomatik gelir)\n" to:f
        format "try (fileIn @\"%\") catch (print (\"MaxTools: could not load side bar: \" + (getCurrentException()) as string))\n" (dir + "MaxTools_SideBar.ms") to:f
        close f

        -- Hemen etkinleştir (Max'i yeniden başlatmaya gerek yok)
        fileIn startupFile

        messageBox ("MaxTools installed.\n\n" + \
                    "• A 'MaxTools' menu was added to the main menu bar.\n" + \
                    "• Icon installed (" + copied as string + " files). To add it to a toolbar:\n" + \
                    "   Customize > Customize User Interface > Toolbars > Category: MaxTools\n" + \
                    "   and drag 'MaxTools' onto any toolbar.\n" + \
                    "• A MaxTools side bar was docked to the left of the viewport (loads on every start).\n" + \
                    "• Hotkeys: Customize > Hotkey Editor > category 'MaxTools'.\n" + \
                    "• This file runs each time (updates are picked up automatically):\n" + mainScript + "\n\n" + \
                    "To uninstall, delete this file:\n" + startupFile) title:"MaxTools Setup"
    )
)
