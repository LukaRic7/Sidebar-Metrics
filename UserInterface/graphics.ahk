#Requires AutoHotkey v2.0

class SidebarApp {
    __New() {
        this.layout := HM_LoadLayout()
        this.sensors := []
        this.sensorById := Map()
        this.sidebar := 0
        this.statusControl := 0
        this.widgets := []
        this.history := Map()
        this.configurator := 0
        this.refreshing := false
        this.rebuildPending := false
    }

    Start() {
        HardwareMonitor_StartDaemon()
        this.RefreshSensors(false)
        this.BuildSidebar()
        SetTimer(this.RefreshValues.Bind(this), 1000)
        this.RefreshValues()
    }

    RefreshSensors(refreshHardware := true) {
        if refreshHardware
            HM_EnsureDaemonSuccess(
                HM_JsonParse(HardwareMonitor_Request("refresh_hardware")),
                "HardwareMonitor could not refresh hardware")

        response := HM_EnsureDaemonSuccess(
            HM_JsonParse(HardwareMonitor_Request("get_sensors")),
            "HardwareMonitor could not return its sensor list")

        this.sensors := response["data"]
        this.sensorById := Map()
        for sensor in this.sensors
            this.sensorById[sensor["id"]] := sensor
        this.ApplyActiveSensors()
        this.RefreshValues()
    }

    ApplyActiveSensors() {
        ids := HM_LayoutSensorIds(this.layout, this.sensors)
        HM_EnsureDaemonSuccess(
            HM_JsonParse(HardwareMonitor_SetActiveSensors(ids)),
            "HardwareMonitor rejected the configured sensor selection")
    }

    LayoutChanged() {
        HM_SaveLayout(this.layout)
        this.ApplyActiveSensors()
        if this.refreshing {
            this.rebuildPending := true
            return
        }
        this.RebuildSidebar()
        this.RefreshValues()
    }

    RebuildSidebar() {
        this.refreshing := true
        try {
            this.BuildSidebar()
        } finally {
            this.refreshing := false
        }
    }

    ShowConfigurator(*) {
        if IsObject(this.configurator) {
            this.configurator.gui.Show()
            return
        }
        this.configurator := SidebarConfigurator(this)
        this.configurator.Show()
    }

    BuildSidebar() {
        if IsObject(this.sidebar) {
            this.DestroyGraphBitmaps()
            this.sidebar.Destroy()
        }

        this.widgets := []
        width := this.layout["sidebarWidth"]
        textSize := this.layout["textSize"]
        headerSize := this.layout["headerSize"]
        rowHeight := Max(20, Ceil(textSize * 1.8))
        graphHeight := 28
        this.sidebar := Gui(
            "+AlwaysOnTop +ToolWindow -Caption -DPIScale +E0x80000 +E0x20",
            "Sidebar Metrics")
        this.sidebar.BackColor := "000000"
        this.sidebar.SetFont("s" textSize " cFFFFFF", "Segoe UI")

        y := 10
        if (this.layout["sections"].Length = 0) {
            this.sidebar.AddText(
                "x12 y12 w" (width - 24) " h42",
                "No sections configured.`nOpen the tray menu to configure the sidebar.")
            y := 62
        } else {
            for sectionIndex, section in this.layout["sections"] {
                iconPath := section["icon"]
                headerHeight := Max(20, Ceil(headerSize * 1.8))
                descriptorHeight := Max(16, Ceil(Max(7, textSize - 1) * 1.8))
                iconSize := Min(40, Max(24, headerHeight))
                if (iconPath != "" && FileExist(iconPath))
                    this.sidebar.AddPicture(
                        "x20 y" (y + Floor((headerHeight - iconSize) / 2))
                        " w" iconSize " h" iconSize,
                        iconPath)
                headerX := iconPath != "" && FileExist(iconPath) ? 58 : 26
                this.sidebar.SetFont("s" headerSize " bold cFFFFFF", "Segoe UI")
                this.sidebar.AddText(
                    "x" headerX " y" y " w" (width - headerX - 18) " h" headerHeight,
                    section["name"])
                this.sidebar.SetFont("s" Max(7, textSize - 1) " cD0D0D0 norm", "Segoe UI")
                this.sidebar.AddText(
                    "x" headerX " y" (y + headerHeight - 1)
                    " w" (width - headerX - 18) " h" descriptorHeight,
                    section["descriptor"])
                y += headerHeight + descriptorHeight + 7

                for row in section["rows"] {
                    this.sidebar.SetFont("s" textSize " cFFFFFF", "Segoe UI")
                    rowLabelWidth := Max(62, Ceil(textSize * 6.9))
                    rowLabel := this.sidebar.AddText(
                        "x26 y" y " w" rowLabelWidth " h" rowHeight " +0x200",
                        row["name"] ":")
                    hasBars := row.Has("bars") && row["bars"].Length > 0
                    reservesBarArea := row.Has("spacer") && row["spacer"]
                    barsWidth := (hasBars || reservesBarArea)
                        ? HM_BarRegionWidth(width)
                        : 0
                    valueStart := 26 + rowLabelWidth + 3
                    valueEnd := barsWidth > 0 ? width - 14 - barsWidth : width - 12
                    valueWidth := Max(1, valueEnd - valueStart)
                    cellWidth := row["columns"].Length > 0
                        ? Max(1, Floor(valueWidth / row["columns"].Length))
                        : valueWidth
                    valueControls := []
                    for index, column in row["columns"] {
                        x := valueStart + (index - 1) * cellWidth
                        valueControls.Push(this.sidebar.AddText(
                            "x" x " y" y " w" cellWidth " h" rowHeight " +0x200",
                            "--"))
                    }

                    if hasBars
                        this.AddBarWidgets(row["bars"], y + 1, width, rowHeight - 2, row)

                    graphControl := 0
                    graphWidth := width - 41
                    if (row["graphColumn"] > 0) {
                        graphY := y + rowHeight
                        this.sidebar.AddText(
                            "x26 y" graphY " w1 h" (graphHeight + 1) " Background707070",
                            "")
                        this.sidebar.AddText(
                            "x26 y" (graphY + graphHeight) " w" (width - 40)
                            " h1 Background707070",
                            "")
                        graphControl := this.sidebar.AddPicture(
                            "x27 y" graphY " w" graphWidth " h" graphHeight " +0xE",
                            "")
                    }
                    this.widgets.Push(Map(
                        "kind", "row",
                        "row", row,
                        "values", valueControls,
                        "graph", graphControl,
                        "graphWidth", graphWidth,
                        "graphHeight", graphHeight))
                    y += rowHeight + (row["graphColumn"] > 0 ? graphHeight + 6 : 4)
                }

                if section.Has("bars") && section["bars"].Length > 0 {
                    this.sidebar.SetFont("s" textSize " cFFFFFF", "Segoe UI")
                    this.sidebar.AddText(
                        "x26 y" y " w62 h" rowHeight " +0x200",
                        "Bars:")
                    this.AddBarWidgets(section["bars"], y + 1, width, rowHeight - 2)
                    y += rowHeight + 4
                }
                if (sectionIndex < this.layout["sections"].Length)
                    y += this.layout["sectionSpacing"]
            }
        }

        statusHeight := Max(18, Ceil(Max(7, textSize - 1) * 1.8))
        this.statusHeight := statusHeight
        this.sidebar.SetFont("s" Max(7, textSize - 1) " cA0A0A0", "Segoe UI")
        this.statusControl := this.sidebar.AddText(
            "x12 y" y " w" (width - 24) " h" statusHeight,
            "Connecting to HardwareMonitor...")
        this.PositionSidebar(width)
        WinSetTransparent(255, "ahk_id " this.sidebar.Hwnd)
        this.sidebar.Show("NoActivate")
    }

    DestroyGraphBitmaps() {
        for widget in this.widgets {
            if (widget["kind"] != "row" || !IsObject(widget["graph"]))
                continue
            bitmap := DllCall(
                "SendMessageW",
                "Ptr", widget["graph"].Hwnd,
                "UInt", 0x172,
                "Ptr", 0,
                "Ptr", 0,
                "Ptr")
            if bitmap
                DllCall("DeleteObject", "Ptr", bitmap)
        }
    }

    AddBarWidgets(barGroup, y, width, maxHeight, row := 0) {
        count := barGroup.Length
        if (count = 0)
            return
        regionWidth := HM_BarRegionWidth(width)
        startX := width - 14 - regionWidth
        slotWidth := Max(1, Floor(regionWidth / count))
        barWidth := Max(1, Min(14, slotWidth - 2))
        for index, bar in barGroup {
            x := startX + (index - 1) * slotWidth + Floor((slotWidth - barWidth) / 2)
            barControl := this.sidebar.AddText(
                "x" x " y" (y + maxHeight - 1)
                " w" barWidth " h1 BackgroundFFFFFF",
                "")
            this.widgets.Push(Map(
                "kind", "bar",
                "barGroup", barGroup,
                "bar", bar,
                "row", row,
                "x", x,
                "width", barWidth,
                "baseY", y,
                "maxHeight", maxHeight,
                "control", barControl))
        }
    }

    PositionSidebar(width := 0) {
        if (width <= 0)
            width := this.layout["sidebarWidth"]
        count := MonitorGetCount()
        screen := this.layout["screen"]
        if (screen < 1 || screen > count)
            screen := 1
        MonitorGetWorkArea(screen, &left, &top, &right, &bottom)
        x := this.layout["side"] = "left" ? left : right - width
        this.sidebar.Show("NoActivate x" x " y" top " w" width " h" (bottom - top))
        statusY := Max(12, bottom - top - this.statusHeight - 8)
        this.statusControl.Move(12, statusY, width - 24, this.statusHeight)
    }

    RefreshValues(*) {
        if this.refreshing || !IsObject(this.sidebar)
            return
        this.refreshing := true
        try {
            ids := HM_LayoutSensorIds(this.layout, this.sensors)
            readings := Map()
            if (ids.Length > 0) {
                request := '"sensors":' HM_JsonStringify(ids)
                response := HM_EnsureDaemonSuccess(
                    HM_JsonParse(HardwareMonitor_Request("get_values", request)),
                    "HardwareMonitor rejected the values request")
                for item in response["data"] {
                    if (Type(item["reading"]) = "Map")
                        readings[item["id"]] := item["reading"]
                }
            }

            for widget in this.widgets {
                if (widget["kind"] = "row")
                    this.UpdateRow(widget, readings)
            }
            this.UpdateBars(readings)
            if IsObject(this.configurator)
                this.RefreshSensorValues()
            this.statusControl.Text := (
                "HardwareMonitor | " this.sensors.Length " sensors | "
                FormatTime(, "HH:mm:ss"))
        } catch as err {
            this.statusControl.Text := "HardwareMonitor unavailable: " err.Message
        } finally {
            this.refreshing := false
        }
        if this.rebuildPending {
            this.rebuildPending := false
            this.RebuildSidebar()
            this.RefreshValues()
        }
    }

    UpdateRow(widget, readings) {
        row := widget["row"]
        values := []
        for index, column in row["columns"] {
            value := ""
            if (column["kind"] = "sensor") {
                id := column["sensorId"]
                if (readings.Has(id) && readings[id]["isAvailable"])
                    value := readings[id]["value"]
            } else if (column["kind"] = "aggregate") {
                value := HM_AggregateSensorValues(
                    column["operation"],
                    column["sensorIds"],
                    readings)
            } else {
                formulaInputs := values
                if column.Has("sensorIds") {
                    formulaInputs := []
                    for sensorId in column["sensorIds"] {
                        sensorValue := ""
                        if (readings.Has(sensorId) && readings[sensorId]["isAvailable"])
                            sensorValue := readings[sensorId]["value"]
                        formulaInputs.Push(sensorValue)
                    }
                }
                try value := HM_EvaluateFormula(column["formula"], formulaInputs)
                catch as err
                    value := "ERR"
            }
            values.Push(value)
            shown := value = "ERR" ? "ERR"
                : IsNumber(value) ? HM_FormatNumber(value, column["decimals"]) : "--"
            if (column["unit"] != "") {
                unit := column["unit"]
                space := (SubStr(unit, 1, 1) = "%" || SubStr(unit, 1, 1) = "°") ? "" : " "
                shown .= space unit
            }
            if (column["kind"] != "sensor")
                shown := column["name"] " " shown
            valueControl := widget["values"][index]
            valueControl.Text := shown
            warning := false
            if (column.Has("warningValue") && IsNumber(value)) {
                warningDirection := column.Has("warningDirection")
                    ? column["warningDirection"]
                    : "above"
                warning := warningDirection = "below"
                    ? value < column["warningValue"]
                    : value > column["warningValue"]
            }
            valueControl.SetFont(
                "s" this.layout["textSize"] " c" (warning ? "FF4040" : "FFFFFF"),
                "Segoe UI")
        }

        graphColumn := row["graphColumn"]
        graphControl := widget["graph"]
        if (graphColumn > 0 && graphColumn <= values.Length && IsObject(graphControl)) {
            rowId := row["id"]
            if !this.history.Has(rowId)
                this.history[rowId] := []
            history := this.history[rowId]
            value := values[graphColumn]
            now := A_TickCount
            if IsNumber(value) {
                history.Push(Map("time", now, "value", value))
            }
            while (history.Length > 0 && now - history[1]["time"] > 60000)
                history.RemoveAt(1)
            while (history.Length > 61)
                history.RemoveAt(1)
            HM_DrawLineGraph(
                graphControl,
                history,
                now,
                widget["graphWidth"],
                widget["graphHeight"],
                row.Has("graphMin") ? row["graphMin"] : "",
                row.Has("graphMax") ? row["graphMax"] : "")
        }
    }

    UpdateBars(readings) {
        for widget in this.widgets {
            if (widget["kind"] != "bar")
                continue
            barGroup := widget["barGroup"]
            row := widget["row"]
            if (IsObject(row) && row.Has("barMax")) {
                maxValue := row["barMax"]
            } else {
                maxValue := 0
                for bar in barGroup {
                    if (readings.Has(bar["sensorId"]) && readings[bar["sensorId"]]["isAvailable"])
                        maxValue := Max(maxValue, Abs(readings[bar["sensorId"]]["value"]))
                }
            }
            bar := widget["bar"]
            value := readings.Has(bar["sensorId"]) && readings[bar["sensorId"]]["isAvailable"]
                ? Abs(readings[bar["sensorId"]]["value"])
                : 0
            height := maxValue > 0
                ? Max(1, Min(widget["maxHeight"], Round(value / maxValue * widget["maxHeight"])))
                : 1
            top := widget["baseY"] + widget["maxHeight"] - height
            widget["control"].Move(widget["x"], top, widget["width"], height)
        }
    }

    RefreshSensorsForConfigurator(*) {
        try {
            this.RefreshSensors(true)
            if IsObject(this.configurator)
                this.configurator.PopulateSensors()
        } catch as err {
            MsgBox("Could not refresh hardware sensors:`n`n" err.Message, "Sidebar Metrics", "Iconx")
        }
    }

    RefreshSensorValues() {
        response := HM_EnsureDaemonSuccess(
            HM_JsonParse(HardwareMonitor_Request("get_sensors")),
            "HardwareMonitor could not refresh sensor readings")
        this.sensors := response["data"]
        this.sensorById := Map()
        for sensor in this.sensors
            this.sensorById[sensor["id"]] := sensor
        if IsObject(this.configurator)
            this.configurator.UpdateSensorValues()
    }

    ReloadDaemon(*) {
        try {
            try HardwareMonitor_Request("shutdown")
            catch as err {
                if !InStr(err.Message, "Windows error 2")
                    this.ShowNotice("Daemon shutdown response: " err.Message)
            }

            deadline := A_TickCount + 15000
            stopped := false
            while (A_TickCount < deadline) {
                try HardwareMonitor_Request("get_status")
                catch {
                    stopped := true
                    break
                }
                Sleep(200)
            }
            if !stopped
                throw Error("The daemon did not stop in time.")

            HardwareMonitor_StartDaemon()
            this.RefreshSensors(false)
            this.RefreshValues()
            this.ShowNotice("HardwareMonitor daemon reloaded.")
        } catch as err {
            this.ShowNotice("Could not reload HardwareMonitor:`n" err.Message)
        }
    }

    ExitWithPrompt(*) {
        choice := MsgBox(
            "Yes: exit the UI and stop HardwareMonitor.`nNo: exit only the UI.`nCancel: keep both running.",
            "Exit Sidebar Metrics",
            "YesNoCancel Icon?")
        if (choice = "Cancel")
            return
        if (choice = "Yes") {
            try HardwareMonitor_Request("shutdown")
            catch as err
                this.ShowNotice("Could not stop HardwareMonitor:`n" err.Message)
        }
        ExitApp()
    }

    ShowNotice(message) {
        MsgBox(message, "Sidebar Metrics", "Icon!")
    }
}

HM_EnsureDaemonSuccess(response, message) {
    if (Type(response) = "Map" && response.Has("success") && response["success"])
        return response
    if (Type(response) = "Map" && response.Has("error")) {
        daemonError := response["error"]
        if (Type(daemonError) = "Map" && daemonError.Has("message"))
            message .= ": " daemonError["message"]
        else if (Type(daemonError) = "String" && daemonError != "")
            message .= ": " daemonError
    }
    throw Error(message)
}

HM_AggregateSensorValues(operation, sensorIds, readings) {
    count := 0
    total := 0
    minimum := 0
    maximum := 0
    for sensorId in sensorIds {
        if (!readings.Has(sensorId) || !readings[sensorId]["isAvailable"])
            continue
        value := readings[sensorId]["value"]
        if !IsNumber(value)
            continue
        if (count = 0) {
            minimum := value
            maximum := value
        } else {
            minimum := Min(minimum, value)
            maximum := Max(maximum, value)
        }
        total += value
        count += 1
    }
    if (count = 0)
        return ""
    switch operation {
        case "MIN": return minimum
        case "MAX": return maximum
        case "AVG": return total / count
    }
    throw Error("Unknown sensor aggregation: " operation)
}

HM_BarRegionWidth(width) {
    return Min(124, Max(80, Round(width * 0.34)))
}

HM_DrawLineGraph(control, samples, now, width, height, graphMin := "", graphMax := "") {
    bitmapInfo := Buffer(40, 0)
    NumPut("UInt", 40, bitmapInfo, 0)
    NumPut("Int", width, bitmapInfo, 4)
    NumPut("Int", -height, bitmapInfo, 8)
    NumPut("UShort", 1, bitmapInfo, 12)
    NumPut("UShort", 32, bitmapInfo, 14)
    NumPut("UInt", 0, bitmapInfo, 16)
    NumPut("UInt", width * height * 4, bitmapInfo, 20)

    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    if !hdc
        throw Error("Could not create the graph drawing surface.")
    bits := 0
    try {
        bitmap := DllCall(
            "CreateDIBSection",
            "Ptr", hdc,
            "Ptr", bitmapInfo.Ptr,
            "UInt", 0,
            "Ptr*", &bits,
            "Ptr", 0,
            "UInt", 0,
            "Ptr")
    } finally {
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    }
    if (!bitmap || !bits)
        throw Error("Could not allocate the graph bitmap.")

    Loop (width * height)
        NumPut("UInt", 0xFF000000, bits, (A_Index - 1) * 4)

    if (samples.Length > 0) {
        fixedRange := IsNumber(graphMin) && IsNumber(graphMax)
        if fixedRange {
            low := graphMin
            high := graphMax
        } else {
            low := samples[1]["value"]
            high := low
            for sample in samples {
                low := Min(low, sample["value"])
                high := Max(high, sample["value"])
            }
        }

        hasPrevious := false
        for sample in samples {
            x := Round((sample["time"] - (now - 60000)) / 60000 * (width - 1))
            x := Min(width - 1, Max(0, x))
            value := Min(high, Max(low, sample["value"]))
            y := high = low
                ? Floor((height - 1) / 2)
                : Round((high - value) / (high - low) * (height - 1))
            if hasPrevious
                HM_DrawSmoothLine(bits, width, height, previousX, previousY, x, y)
            else
                HM_GraphPixel(bits, width, height, x, y, 255)
            previousX := x
            previousY := y
            hasPrevious := true
        }
    }

    previousBitmap := DllCall(
        "SendMessageW",
        "Ptr", control.Hwnd,
        "UInt", 0x172,
        "Ptr", 0,
        "Ptr", bitmap,
        "Ptr")
    if previousBitmap
        DllCall("DeleteObject", "Ptr", previousBitmap)
    DllCall(
        "RedrawWindow",
        "Ptr", control.Hwnd,
        "Ptr", 0,
        "Ptr", 0,
        "UInt", 0x85)
    return bitmap
}

HM_DrawSmoothLine(bits, width, height, x0, y0, x1, y1) {
    if (x0 = x1 && y0 = y1) {
        HM_GraphPixel(bits, width, height, x0, y0, 255)
        return
    }

    steep := Abs(y1 - y0) > Abs(x1 - x0)
    if steep {
        temp := x0
        x0 := y0
        y0 := temp
        temp := x1
        x1 := y1
        y1 := temp
    }
    if (x0 > x1) {
        temp := x0
        x0 := x1
        x1 := temp
        temp := y0
        y0 := y1
        y1 := temp
    }

    gradient := (y1 - y0) / (x1 - x0)
    x := x0
    while (x <= x1) {
        lineY := y0 + gradient * (x - x0)
        lowerY := Floor(lineY)
        coverage := lineY - lowerY
        if steep {
            HM_GraphPixel(bits, width, height, lowerY, x, Round((1 - coverage) * 255))
            HM_GraphPixel(bits, width, height, lowerY + 1, x, Round(coverage * 255))
        } else {
            HM_GraphPixel(bits, width, height, x, lowerY, Round((1 - coverage) * 255))
            HM_GraphPixel(bits, width, height, x, lowerY + 1, Round(coverage * 255))
        }
        x += 1
    }
}

HM_GraphPixel(bits, width, height, x, y, intensity) {
    if (x < 0 || x >= width || y < 0 || y >= height || intensity <= 0)
        return
    intensity := Min(255, Max(0, intensity))
    offset := (y * width + x) * 4
    if (NumGet(bits, offset, "UChar") < intensity) {
        color := 0xFF000000 | (intensity << 16) | (intensity << 8) | intensity
        NumPut("UInt", color, bits, offset)
    }
}
