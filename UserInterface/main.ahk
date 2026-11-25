#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include datahandler.ahk
#Include json.ahk
#Include layout.ahk
#Include graphics.ahk
#Include configurator.ahk

try {
    app := SidebarApp()
    app.Start()
} catch as err {
    details := err.Message
    if HasProp(err, "File") && HasProp(err, "Line")
        details .= "`n`nAt " err.File ":" err.Line
    MsgBox("Sidebar Metrics could not start:`n`n" details, "Sidebar Metrics", "Iconx")
    ExitApp()
}

trayMenu := A_TrayMenu
trayMenu.Delete()
trayMenu.Add("Configure Sidebar", app.ShowConfigurator.Bind(app))
trayMenu.Add("Reload Daemon", app.ReloadDaemon.Bind(app))
trayMenu.Add("Reload UI", (*) => Reload())
trayMenu.Add()
trayMenu.Add("Exit", app.ExitWithPrompt.Bind(app))
trayMenu.Default := "Configure Sidebar"
