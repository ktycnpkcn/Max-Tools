-- =========================================
-- MaxTools sol kenar araç çubuğu
-- Max açılırken başlatıcı tarafından çalıştırılır; viewport'un soluna yapışan dikey bir çubuk oluşturur.
-- Kapatmak için: MaxTools.ini > [SideBar] Show=false  (ya da bu dosyayı silin)
-- =========================================

global MaxToolsBar
-- İkonlar bu dosyanın yanındaki icons klasöründen okunur (kurulum gerektirmez)
global MaxToolsBarDir = try (getFilenamePath (getThisScriptFilename())) catch ""

-- Önceki çubuğu kaldır (tekrar çalıştırmada çift olmasın)
(
    try (cui.unRegisterDialogBar MaxToolsBar) catch()
    try (destroyDialog MaxToolsBar) catch()
)

rollout MaxToolsBar "MaxTools" width:34 height:38
(
    button btnOpen "M" pos:[3,4] width:28 height:28 tooltip:"Open MaxTools panel"

    on MaxToolsBar open do
    (
        -- Buton ikonu: renk + maske (maskede SİYAH = görünür, BEYAZ = saydam). Yoksa "M" yazısı kalır.
        local ic = MaxToolsBarDir + "icons\\MaxTools_bar_24i.bmp"
        local im = MaxToolsBarDir + "icons\\MaxTools_bar_24m.bmp"
        if (doesFileExist ic) and (doesFileExist im) do
            try (btnOpen.images = #(ic, im, 1, 1, 1, 1, 1)) catch()
    )

    on btnOpen pressed do
        try (macros.run "MaxTools" "MaxTools_Open") catch (format "MaxTools: could not open panel: %\n" (getCurrentException()))
)

-- Max kapanırken çubuğu düzgün kaldır (her açılışta yeniden oluşturuluyor)
callbacks.removeScripts id:#MaxToolsBarShutdown
callbacks.addScript #preSystemShutdown "try (cui.unRegisterDialogBar MaxToolsBar) catch(); try (destroyDialog MaxToolsBar) catch()" id:#MaxToolsBarShutdown

(
    local showFlag = getINISetting ((getDir #plugcfg) + "\\MaxTools.ini") "SideBar" "Show"
    if showFlag != "false" do
    (
        createDialog MaxToolsBar style:#(#style_toolwindow, #style_sysmenu)
        cui.registerDialogBar MaxToolsBar style:#(#cui_dock_left, #cui_dock_right, #cui_dock_vert, #cui_floatable, #cui_handles)
        cui.dockDialogBar MaxToolsBar #cui_dock_left
    )
)
