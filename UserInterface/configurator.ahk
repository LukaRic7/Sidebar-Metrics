#Requires AutoHotkey v2.0

class SidebarConfigurator {
    __New(app) {
        this.app := app
        this.sensorItems := Map()
        this.layoutItems := Map()
        this.gui := Gui("+Resize", "Configure Sidebar")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.AddText("x12 y12 w110", "Screen")
        monitorNames := []
        Loop MonitorGetCount()
            monitorNames.Push("Screen " A_Index)
        this.screenChoice := this.gui.AddDropDownList("x66 y9 w125 Choose1", monitorNames)
        this.screenChoice.Value := Min(Max(1, app.layout["screen"]), monitorNames.Length)
        this.screenChoice.OnEvent("Change", this.OnScreenChanged.Bind(this))
        this.gui.AddText("x207 y12 w55", "Side")
        this.sideChoice := this.gui.AddDropDownList("x252 y9 w110", ["Left", "Right"])
        this.sideChoice.Value := app.layout["side"] = "left" ? 1 : 2
        this.sideChoice.OnEvent("Change", this.OnSideChanged.Bind(this))

        this.gui.AddText("x12 y47 w42 h20", "Width")
        this.widthEdit := this.gui.AddEdit(
            "x55 y43 w58 h22 +Number",
            app.layout["sidebarWidth"])
        this.gui.AddText("x124 y47 w50 h20", "Text pt")
        this.textSizeEdit := this.gui.AddEdit("x174 y43 w52 h22 +Number", app.layout["textSize"])
        this.gui.AddText("x240 y47 w58 h20", "Header pt")
        this.headerSizeEdit := this.gui.AddEdit(
            "x298 y43 w55 h22 +Number",
            app.layout["headerSize"])
        this.gui.AddText("x365 y47 w72 h20", "Section gap")
        this.sectionSpacingEdit := this.gui.AddEdit(
            "x438 y43 w48 h22 +Number",
            app.layout["sectionSpacing"])
        this.gui.AddText("x489 y47 w20 h20", "px")
        this.applySettingsButton := this.gui.AddButton("x514 y42 w102 h25", "Apply settings")
        this.applySettingsButton.OnEvent("Click", this.ApplySidebarSettings.Bind(this))

        this.gui.AddText("x12 y78 w300 h20", "Detected sensors (latest raw value)")
        this.sensorTree := this.gui.AddTreeView("x12 y100 w950 h264")

        this.refreshButton := this.gui.AddButton("x12 y374 w112 h28", "Refresh sensors")
        this.sectionButton := this.gui.AddButton("x132 y374 w105 h28", "New section")
        this.rowButton := this.gui.AddButton("x245 y374 w112 h28", "Add sensor row")
        this.emptyRowButton := this.gui.AddButton("x365 y374 w104 h28", "Add empty row")
        this.columnButton := this.gui.AddButton("x477 y374 w112 h28", "Add sensor column")
        this.formulaButton := this.gui.AddButton("x597 y374 w126 h28", "Add formula column")
        this.barButton := this.gui.AddButton("x731 y374 w108 h28", "Add row bars")
        this.spacerButton := this.gui.AddButton("x847 y374 w102 h28", "Add bar spacer")
        this.refreshButton.OnEvent("Click", app.RefreshSensorsForConfigurator.Bind(app))
        this.sectionButton.OnEvent("Click", this.NewSection.Bind(this))
        this.rowButton.OnEvent("Click", this.AddSensorRow.Bind(this))
        this.emptyRowButton.OnEvent("Click", this.AddEmptyRow.Bind(this))
        this.columnButton.OnEvent("Click", this.AddSensorColumn.Bind(this))
        this.formulaButton.OnEvent("Click", this.AddFormulaColumn.Bind(this))
        this.barButton.OnEvent("Click", this.AddHeaderBar.Bind(this))
        this.spacerButton.OnEvent("Click", this.AddSpacer.Bind(this))

        this.gui.AddText("x12 y410 w300 h20", "Sidebar layout (sections > rows > columns)")
        this.layoutTree := this.gui.AddTreeView("x12 y432 w950 h245")

        this.editButton := this.gui.AddButton("x12 y690 w115 h28", "Edit section")
        this.graphButton := this.gui.AddButton("x135 y690 w145 h28", "Set row graph")
        this.removeButton := this.gui.AddButton("x288 y690 w115 h28", "Remove selected")
        this.scaleButton := this.gui.AddButton("x412 y690 w125 h28", "Row scales")
        this.warningButton := this.gui.AddButton("x545 y690 w145 h28", "Column warning")
        this.closeButton := this.gui.AddButton("x847 y690 w115 h28", "Done")
        this.editButton.OnEvent("Click", this.EditSection.Bind(this))
        this.graphButton.OnEvent("Click", this.SetGraph.Bind(this))
        this.removeButton.OnEvent("Click", this.RemoveSelected.Bind(this))
        this.scaleButton.OnEvent("Click", this.EditRowScales.Bind(this))
        this.warningButton.OnEvent("Click", this.SetColumnWarning.Bind(this))
        this.closeButton.OnEvent("Click", (*) => this.Close())
        this.gui.OnEvent("Close", this.OnClose.Bind(this))

        this.PopulateSensors()
        this.PopulateLayout()
    }

    Show() {
        this.gui.Show("w975 h735")
    }

    OnClose(*) {
        this.Close()
    }

    Close() {
        if IsObject(this.gui)
            this.gui.Destroy()
        this.app.configurator := 0
    }

    OnScreenChanged(*) {
        this.app.layout["screen"] := this.screenChoice.Value
        HM_SaveLayout(this.app.layout)
        if IsObject(this.app.sidebar)
            this.app.PositionSidebar()
    }

    OnSideChanged(*) {
        this.app.layout["side"] := this.sideChoice.Value = 1 ? "left" : "right"
        HM_SaveLayout(this.app.layout)
        if IsObject(this.app.sidebar)
            this.app.PositionSidebar()
    }

    ApplySidebarSettings(*) {
        if (!IsNumber(this.widthEdit.Value)
            || !IsNumber(this.textSizeEdit.Value)
            || !IsNumber(this.headerSizeEdit.Value)
            || !IsNumber(this.sectionSpacingEdit.Value)) {
            MsgBox("Enter numeric values for the sidebar settings.", "Sidebar Metrics", "Icon!")
            return
        }

        width := Round(this.widthEdit.Value + 0)
        textSize := Round(this.textSizeEdit.Value + 0)
        headerSize := Round(this.headerSizeEdit.Value + 0)
        sectionSpacing := Round(this.sectionSpacingEdit.Value + 0)
        if (width < 320 || width > 900
            || textSize < 7 || textSize > 18
            || headerSize < 9 || headerSize > 26
            || sectionSpacing < 0 || sectionSpacing > 100) {
            MsgBox(
                "Choose a width from 320 to 900 px, text size from 7 to 18 pt, "
                "header size from 9 to 26 pt, and section gap from 0 to 100 px.",
                "Sidebar Metrics",
                "Icon!")
            return
        }

        this.app.layout["sidebarWidth"] := width
        this.app.layout["textSize"] := textSize
        this.app.layout["headerSize"] := headerSize
        this.app.layout["sectionSpacing"] := sectionSpacing
        HM_SaveLayout(this.app.layout)
        this.app.RebuildSidebar()
        this.app.RefreshValues()
    }

    PopulateSensors() {
        this.sensorTree.Delete()
        this.sensorItems := Map()
        groups := Map()
        for sensor in this.app.sensors {
            groupKey := sensor["hardwareType"] " - " sensor["hardwareName"]
            if !groups.Has(groupKey)
                groups[groupKey] := this.sensorTree.Add(groupKey)

            valueText := sensor["isAvailable"] && IsNumber(sensor["value"])
                ? sensor["value"] ""
                : "--"
            sensorText := sensor["name"] "  [" sensor["sensorType"] "] = " valueText
            item := this.sensorTree.Add(sensorText, groups[groupKey])
            this.sensorItems[item] := sensor["id"]
        }
    }

    UpdateSensorValues() {
        for item, sensorId in this.sensorItems {
            if !this.app.sensorById.Has(sensorId)
                continue
            sensor := this.app.sensorById[sensorId]
            valueText := sensor["isAvailable"] && IsNumber(sensor["value"])
                ? sensor["value"] ""
                : "--"
            this.sensorTree.Modify(
                item,
                "",
                sensor["name"] "  [" sensor["sensorType"] "] = " valueText)
        }
    }

    NewSection(*) {
        HMSectionDialog(this)
    }

    PopulateLayout() {
        state := this.CaptureLayoutTreeState()
        this.layoutTree.Delete()
        this.layoutItems := Map()
        for section in this.app.layout["sections"] {
            sectionItem := this.layoutTree.Add(
                section["name"] " — " section["descriptor"])
            this.layoutItems[sectionItem] := Map("kind", "section", "section", section)

            for row in section["rows"] {
                rowItem := this.layoutTree.Add(row["name"], sectionItem)
                this.layoutItems[rowItem] := Map(
                    "kind", "row", "section", section, "row", row)
                for index, column in row["columns"] {
                    if (column["kind"] = "sensor")
                        description := column["name"] " (" column["unit"] ") - " column["sensorId"]
                    else if (column["kind"] = "aggregate")
                        description := column["name"] " (" column["operation"] ", " column["sensorIds"].Length " sensors)"
                    else
                        description := column["name"] " (" column["unit"] ") = " column["formula"]
                    if (column["kind"] = "formula" && column.Has("sensorIds"))
                        description .= " [" column["sensorIds"].Length " selected sensors]"
                    if column.Has("warningValue") {
                        warningDirection := column.Has("warningDirection")
                            ? column["warningDirection"]
                            : "above"
                        description .= " [warn " warningDirection " " column["warningValue"] "]"
                    }
                    columnItem := this.layoutTree.Add(description, rowItem)
                    this.layoutItems[columnItem] := Map(
                        "kind", "column", "section", section,
                        "row", row, "column", column, "index", index)
                }
                if row.Has("bars") && row["bars"].Length > 0 {
                    barsItem := this.layoutTree.Add("Column bars", rowItem)
                    this.layoutItems[barsItem] := Map(
                        "kind", "barGroup", "section", section,
                        "row", row, "owner", row)
                    for bar in row["bars"] {
                        barItem := this.layoutTree.Add(
                            bar["name"] " (" bar["unit"] ") - " bar["sensorId"], barsItem)
                        this.layoutItems[barItem] := Map(
                            "kind", "bar", "section", section, "row", row,
                            "barGroup", row["bars"], "bar", bar)
                    }
                }
                if row.Has("spacer") && row["spacer"] {
                    spacerItem := this.layoutTree.Add(
                        "Spacer (reserves bar area)",
                        rowItem)
                    this.layoutItems[spacerItem] := Map(
                        "kind", "spacer",
                        "section", section,
                        "row", row)
                }
            }

            if section.Has("bars") && section["bars"].Length > 0 {
                barsItem := this.layoutTree.Add("Legacy section bars", sectionItem)
                this.layoutItems[barsItem] := Map(
                    "kind", "barGroup", "section", section,
                    "barGroup", section["bars"], "owner", section)
                for bar in section["bars"] {
                    barItem := this.layoutTree.Add(
                        bar["name"] " (" bar["unit"] ") - " bar["sensorId"], barsItem)
                    this.layoutItems[barItem] := Map(
                        "kind", "bar", "section", section,
                        "barGroup", section["bars"], "bar", bar)
                }
            }
        }

        for item, context in this.layoutItems {
            key := this.LayoutTreeStateKey(context)
            if (key != "" && state["expanded"].Has(key))
                this.layoutTree.Modify(item, "Expand")
        }
        if (state["selected"] != "") {
            for item, context in this.layoutItems {
                if (this.LayoutTreeStateKey(context) = state["selected"]) {
                    if (context["kind"] = "row")
                        this.layoutTree.Modify(item, "Expand")
                    this.layoutTree.Modify(item, "Select")
                    break
                }
            }
        }
    }

    CaptureLayoutTreeState() {
        state := Map("expanded", Map(), "selected", "")
        if !IsObject(this.layoutTree)
            return state
        selectedItem := this.layoutTree.GetSelection()
        item := 0
        while (item := this.layoutTree.GetNext(item, "Full")) {
            if !this.layoutItems.Has(item)
                continue
            context := this.layoutItems[item]
            key := this.LayoutTreeStateKey(context)
            if (key = "")
                continue
            if this.layoutTree.Get(item, "Expanded")
                state["expanded"][key] := true
            if (item = selectedItem)
                state["selected"] := key
        }
        return state
    }

    LayoutTreeStateKey(context) {
        switch context["kind"] {
            case "section":
                if context["section"].Has("id")
                    return "section:" context["section"]["id"]
            case "row":
                if context["row"].Has("id")
                    return "row:" context["row"]["id"]
            case "spacer":
                if context["row"].Has("id")
                    return "spacer:" context["row"]["id"]
            case "column":
                if context["column"].Has("id")
                    return "column:" context["column"]["id"]
            case "bar":
                if context["bar"].Has("id")
                    return "bar:" context["bar"]["id"]
            case "barGroup":
                if context.Has("row") && context["row"].Has("id")
                    return "barGroup:row:" context["row"]["id"]
                if context["section"].Has("id")
                    return "barGroup:section:" context["section"]["id"]
        }
        return ""
    }

    SelectedSensor() {
        item := this.sensorTree.GetSelection()
        return this.sensorItems.Has(item) ? this.app.sensorById[this.sensorItems[item]] : 0
    }

    SelectedLayout() {
        item := this.layoutTree.GetSelection()
        return this.layoutItems.Has(item) ? this.layoutItems[item] : 0
    }

    SelectLayoutRow(rowId) {
        for item, context in this.layoutItems {
            if (context["kind"] = "row" && context["row"]["id"] = rowId) {
                this.layoutTree.Modify(item, "Expand")
                this.layoutTree.Modify(item, "Select")
                return
            }
        }
    }

    AddSensorRow(*) {
        sensor := this.SelectedSensor()
        context := this.SelectedLayout()
        if !sensor {
            MsgBox("Select a sensor in the upper tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        section := this.SelectedSection(context)
        if !section {
            MsgBox("Select a section in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        HMColumnDialog(this, "row", section, 0, sensor)
    }

    AddEmptyRow(*) {
        section := this.SelectedSection(this.SelectedLayout())
        if !section {
            MsgBox("Select a section in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }

        answer := InputBox("Enter a name for the empty row.", "Add empty row", "w360", "New row")
        if (answer.Result != "OK")
            return
        name := Trim(answer.Value)
        if (name = "") {
            MsgBox("Enter a row name.", "Sidebar Metrics", "Icon!")
            return
        }

        row := Map(
            "id", HM_NewId(),
            "name", name,
            "columns", [],
            "bars", [],
            "graphColumn", 0)
        section["rows"].Push(row)
        this.SaveAndRefresh()
        this.SelectLayoutRow(row["id"])
    }

    AddSensorColumn(*) {
        sensor := this.SelectedSensor()
        context := this.SelectedLayout()
        if !sensor || !context || !context.Has("row") {
            MsgBox("Select a sensor above and a row below first.", "Sidebar Metrics", "Icon!")
            return
        }
        HMColumnDialog(this, "sensor", context["section"], context["row"], sensor)
    }

    AddFormulaColumn(*) {
        context := this.SelectedLayout()
        if !context || !context.Has("row") {
            MsgBox("Select a row in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        HMFormulaDialog(this, context["row"])
    }

    AddHeaderBar(*) {
        context := this.SelectedLayout()
        if !context || !context.Has("row") {
            MsgBox("Select a row in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        HMSensorBarDialog(this, context["row"])
    }

    AddSpacer(*) {
        context := this.SelectedLayout()
        if !context || !context.Has("row") {
            MsgBox("Select a row in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        row := context["row"]
        if (row.Has("bars") && row["bars"].Length > 0) {
            MsgBox("This row already has bars using the reserved area.", "Sidebar Metrics", "Icon!")
            return
        }
        if (row.Has("spacer") && row["spacer"]) {
            MsgBox("This row already has a spacer.", "Sidebar Metrics", "Icon!")
            return
        }
        row["spacer"] := true
        this.SaveAndRefresh()
    }

    SelectedSection(context) {
        if !context
            return 0
        return context["section"]
    }

    EditSection(*) {
        context := this.SelectedLayout()
        if (!context || context["kind"] != "section") {
            MsgBox("Select a section in the lower tree to edit it.", "Sidebar Metrics", "Icon!")
            return
        }
        HMSectionDialog(this, context["section"])
    }

    SetGraph(*) {
        context := this.SelectedLayout()
        if !context || !context.Has("row") {
            MsgBox("Select a row or one of its columns first.", "Sidebar Metrics", "Icon!")
            return
        }
        row := context["row"]
        prompt := "Enter the 1-based column number to graph for 60 seconds, or 0 to turn the graph off.`n`n"
        for index, column in row["columns"]
            prompt .= index ". " column["name"] "`n"
        answer := InputBox(prompt, "Rolling graph", "w380", row["graphColumn"])
        if (answer.Result != "OK")
            return
        graphColumn := answer.Value + 0
        if (graphColumn < 0 || graphColumn > row["columns"].Length) {
            MsgBox("Choose 0 or a valid column number.", "Sidebar Metrics", "Icon!")
            return
        }
        row["graphColumn"] := graphColumn
        if this.app.history.Has(row["id"])
            this.app.history.Delete(row["id"])
        this.SaveAndRefresh()
    }

    EditRowScales(*) {
        context := this.SelectedLayout()
        if !context || !context.Has("row") {
            MsgBox("Select a row in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        HMRowScaleDialog(this, context["row"])
    }

    SetColumnWarning(*) {
        context := this.SelectedLayout()
        if (!context || context["kind"] != "column") {
            MsgBox("Select a value column in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }
        HMColumnWarningDialog(this, context["column"])
    }

    RemoveSelected(*) {
        context := this.SelectedLayout()
        if !context {
            MsgBox("Select an item in the lower tree first.", "Sidebar Metrics", "Icon!")
            return
        }

        switch context["kind"] {
            case "section":
                HM_RemoveObject(this.app.layout["sections"], context["section"])
            case "row":
                HM_RemoveObject(context["section"]["rows"], context["row"])
            case "column":
                HM_RemoveObject(context["row"]["columns"], context["column"])
                graphColumn := context["row"]["graphColumn"]
                if (graphColumn = context["index"])
                    context["row"]["graphColumn"] := 0
                else if (graphColumn > context["index"])
                    context["row"]["graphColumn"] := graphColumn - 1
            case "bar":
                HM_RemoveObject(context["barGroup"], context["bar"])
            case "spacer":
                context["row"].Delete("spacer")
            case "barGroup":
                context["owner"]["bars"] := []
        }
        this.SaveAndRefresh()
    }

    SaveAndRefresh() {
        this.PopulateLayout()
        this.app.LayoutChanged()
    }
}

class HMSectionDialog {
    __New(configurator, section := 0) {
        this.configurator := configurator
        this.section := section
        this.icons := HM_AssetPaths()
        this.gui := Gui("+Owner" configurator.gui.Hwnd, section ? "Edit section" : "New section")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.AddText("x12 y14 w110", "Section name")
        this.nameEdit := this.gui.AddEdit("x126 y11 w270")
        this.gui.AddText("x12 y50 w110", "Descriptor")
        this.descriptorEdit := this.gui.AddEdit("x126 y47 w270")
        this.gui.AddText("x12 y86 w110", "Icon")
        labels := []
        for path in this.icons {
            label := RegExReplace(path, "^.*\\")
            labels.Push(RegExReplace(label, "\.png$", ""))
        }
        if (labels.Length = 0)
            labels.Push("(no icons found)")
        this.iconChoice := this.gui.AddDropDownList("x126 y83 w200", labels)
        this.preview := this.gui.AddPicture("x340 y80 w48 h48")
        this.saveButton := this.gui.AddButton("x206 y145 w90 h28", "Save")
        this.cancelButton := this.gui.AddButton("x306 y145 w90 h28", "Cancel")
        this.iconChoice.OnEvent("Change", this.UpdatePreview.Bind(this))
        this.saveButton.OnEvent("Click", this.Save.Bind(this))
        this.cancelButton.OnEvent("Click", (*) => this.gui.Destroy())
        this.gui.OnEvent("Close", (*) => this.gui.Destroy())

        if section {
            this.nameEdit.Value := section["name"]
            this.descriptorEdit.Value := section["descriptor"]
            for index, path in this.icons {
                if (path = HM_ResolveIconPath(section["icon"]))
                    this.iconChoice.Value := index
            }
        } else if (this.icons.Length > 0) {
            this.iconChoice.Value := 1
        }
        this.UpdatePreview()
        this.gui.Show("w410 h190")
    }

    UpdatePreview(*) {
        index := this.iconChoice.Value
        if (index > 0 && index <= this.icons.Length)
            this.preview.Value := this.icons[index]
    }

    Save(*) {
        name := Trim(this.nameEdit.Value)
        if (name = "") {
            MsgBox("Enter a section name.", "Sidebar Metrics", "Icon!")
            return
        }
        index := this.iconChoice.Value
        iconPath := index > 0 && index <= this.icons.Length ? this.icons[index] : ""
        icon := HM_StoreIconPath(iconPath)
        if this.section {
            this.section["name"] := name
            this.section["descriptor"] := Trim(this.descriptorEdit.Value)
            this.section["icon"] := icon
        } else {
            this.configurator.app.layout["sections"].Push(Map(
                "id", HM_NewId(),
                "name", name,
                "descriptor", Trim(this.descriptorEdit.Value),
                "icon", icon,
                "rows", [],
                "bars", []))
        }
        this.configurator.SaveAndRefresh()
        this.gui.Destroy()
    }
}

class HMColumnDialog {
    __New(configurator, mode, section, row, sensor) {
        this.configurator := configurator
        this.mode := mode
        this.section := section
        this.row := row
        this.sensor := sensor
        title := mode = "row" ? "Add sensor row" : "Add sensor column"
        this.gui := Gui("+Owner" configurator.gui.Hwnd, title)
        this.gui.SetFont("s9", "Segoe UI")

        y := 12
        if (mode = "row") {
            this.gui.AddText("x12 y" y " w110", "Row name")
            this.rowNameEdit := this.gui.AddEdit("x126 y" (y - 3) " w280", sensor["name"])
            y += 36
        }
        this.gui.AddText("x12 y" y " w110", "Value label")
        defaultName := sensor ? sensor["name"] : "Value"
        this.nameEdit := this.gui.AddEdit("x126 y" (y - 3) " w280", defaultName)
        y += 36
        this.gui.AddText("x12 y" y " w110", "Unit")
        defaultUnit := sensor ? HM_DefaultUnit(sensor["sensorType"]) : "%"
        this.unitEdit := this.gui.AddEdit("x126 y" (y - 3) " w120", defaultUnit)
        y += 36
        this.gui.AddText("x12 y" y " w110", "Round decimals")
        this.decimalChoice := this.gui.AddDropDownList("x126 y" (y - 3) " w100", ["0", "1", "2"])
        this.decimalChoice.Value := 2
        y += 40

        this.saveButton := this.gui.AddButton("x206 y" y " w90 h28", "Add")
        this.cancelButton := this.gui.AddButton("x306 y" y " w100 h28", "Cancel")
        this.saveButton.OnEvent("Click", this.Save.Bind(this))
        this.cancelButton.OnEvent("Click", (*) => this.gui.Destroy())
        this.gui.OnEvent("Close", (*) => this.gui.Destroy())
        this.gui.Show("w425 h" (y + 45))
    }

    Save(*) {
        name := Trim(this.nameEdit.Value)
        if (name = "") {
            MsgBox("Enter a value label.", "Sidebar Metrics", "Icon!")
            return
        }
        decimals := this.decimalChoice.Value - 1
        unit := Trim(this.unitEdit.Value)
        newRowId := ""
        if (this.mode = "row") {
            column := this.NewSensorColumn(name, unit, decimals)
            row := Map(
                "id", HM_NewId(),
                "name", Trim(this.rowNameEdit.Value) = "" ? name : Trim(this.rowNameEdit.Value),
                "columns", [column],
                "bars", [],
                "graphColumn", 0)
            newRowId := row["id"]
            this.section["rows"].Push(row)
        } else {
            this.row["columns"].Push(this.NewSensorColumn(name, unit, decimals))
        }
        this.configurator.SaveAndRefresh()
        if (newRowId != "")
            this.configurator.SelectLayoutRow(newRowId)
        this.gui.Destroy()
    }

    NewSensorColumn(name, unit, decimals) {
        return Map(
            "id", HM_NewId(),
            "kind", "sensor",
            "sensorId", this.sensor["id"],
            "name", name,
            "unit", unit,
            "decimals", decimals)
    }
}

class HMFormulaDialog {
    __New(configurator, row) {
        this.configurator := configurator
        this.row := row
        this.gui := Gui("+Owner" configurator.gui.Hwnd, "Add formula column")
        this.gui.SetFont("s9", "Segoe UI")

        this.gui.AddText("x12 y13 w90", "Value label")
        this.nameEdit := this.gui.AddEdit("x104 y10 w285", "Calculated")
        this.gui.AddText("x408 y13 w42", "Unit")
        this.unitEdit := this.gui.AddEdit("x454 y10 w110")
        this.gui.AddText("x582 y13 w65", "Decimals")
        this.decimalChoice := this.gui.AddDropDownList(
            "x648 y10 w90 Choose2",
            ["0", "1", "2"])

        this.gui.AddText("x12 y47 w90", "Calculation")
        this.operationChoice := this.gui.AddDropDownList(
            "x104 y44 w180 Choose1",
            ["Expression", "MIN", "MAX", "AVG"])
        this.gui.AddText(
            "x12 y79 w720 h18",
            "Expressions use selected sensors as {1}, {2}, etc. when selected; otherwise they use earlier columns.")
        this.formulaEdit := this.gui.AddEdit("x12 y99 w736 h34")
        this.gui.AddText(
            "x12 y141 w720 h18",
            "Select sensors for expressions or MIN/MAX/AVG using Ctrl or Shift.")
        this.sensorList := this.gui.AddListView(
            "x12 y162 w736 h270",
            ["Sensor", "Hardware", "Type", "Raw value"])
        this.sensorIds := HM_PopulateSensorList(this.sensorList, configurator.app.sensors)
        this.sensorList.ModifyCol(1, 200)
        this.sensorList.ModifyCol(2, 200)
        this.sensorList.ModifyCol(3, 110)
        this.sensorList.ModifyCol(4, 100)

        this.saveButton := this.gui.AddButton("x548 y447 w90 h28", "Add")
        this.cancelButton := this.gui.AddButton("x648 y447 w100 h28", "Cancel")
        this.saveButton.OnEvent("Click", this.Save.Bind(this))
        this.cancelButton.OnEvent("Click", (*) => this.gui.Destroy())
        this.gui.OnEvent("Close", (*) => this.gui.Destroy())
        this.gui.Show("w760 h490")
    }

    Save(*) {
        name := Trim(this.nameEdit.Value)
        if (name = "") {
            MsgBox("Enter a value label.", "Sidebar Metrics", "Icon!")
            return
        }

        operations := ["Expression", "MIN", "MAX", "AVG"]
        operation := operations[this.operationChoice.Value]
        column := Map(
            "id", HM_NewId(),
            "kind", operation = "Expression" ? "formula" : "aggregate",
            "name", name,
            "unit", Trim(this.unitEdit.Value),
            "decimals", this.decimalChoice.Value - 1)

        if (operation = "Expression") {
            formula := Trim(this.formulaEdit.Value)
            if (formula = "") {
                MsgBox("Enter a formula.", "Sidebar Metrics", "Icon!")
                return
            }
            sensorIds := HM_SelectedSensorIds(this.sensorList, this.sensorIds)
            sampleValues := []
            if (sensorIds.Length > 0) {
                for sensorId in sensorIds {
                    if !this.configurator.app.sensorById.Has(sensorId) {
                        MsgBox("A selected sensor is no longer available. Refresh sensors and try again.",
                            "Sidebar Metrics", "Icon!")
                        return
                    }
                    sampleValues.Push(1)
                }
                column["sensorIds"] := sensorIds
            } else {
                for existingColumn in this.row["columns"]
                    sampleValues.Push(1)
            }
            try HM_EvaluateFormula(formula, sampleValues)
            catch {
                MsgBox("The formula is invalid. Check its syntax and column references.", "Sidebar Metrics", "Icon!")
                return
            }
            column["formula"] := formula
        } else {
            sensorIds := HM_SelectedSensorIds(this.sensorList, this.sensorIds)
            if (sensorIds.Length = 0) {
                MsgBox("Select one or more sensors for this aggregation.", "Sidebar Metrics", "Icon!")
                return
            }
            column["operation"] := operation
            column["sensorIds"] := sensorIds
        }

        this.row["columns"].Push(column)
        this.configurator.SaveAndRefresh()
        this.gui.Destroy()
    }
}

class HMSensorBarDialog {
    __New(configurator, row) {
        this.configurator := configurator
        this.row := row
        if !row.Has("bars")
            row["bars"] := []
        this.gui := Gui("+Owner" configurator.gui.Hwnd, "Add sensor bars")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.AddText(
            "x12 y12 w720 h20",
            "Select one or more sensors. Use Ctrl or Shift to select a range.")
        this.sensorList := this.gui.AddListView(
            "x12 y38 w736 h350",
            ["Sensor", "Hardware", "Type", "Raw value"])
        this.sensorIds := HM_PopulateSensorList(this.sensorList, configurator.app.sensors)
        this.sensorList.ModifyCol(1, 200)
        this.sensorList.ModifyCol(2, 200)
        this.sensorList.ModifyCol(3, 110)
        this.sensorList.ModifyCol(4, 100)

        this.addButton := this.gui.AddButton("x548 y402 w90 h28", "Add")
        this.cancelButton := this.gui.AddButton("x648 y402 w100 h28", "Cancel")
        this.addButton.OnEvent("Click", this.Save.Bind(this))
        this.cancelButton.OnEvent("Click", (*) => this.gui.Destroy())
        this.gui.OnEvent("Close", (*) => this.gui.Destroy())
        this.gui.Show("w760 h445")
    }

    Save(*) {
        sensorIds := HM_SelectedSensorIds(this.sensorList, this.sensorIds)
        if (sensorIds.Length = 0) {
            MsgBox("Select one or more sensors.", "Sidebar Metrics", "Icon!")
            return
        }

        existing := Map()
        for bar in this.row["bars"]
            existing[bar["sensorId"]] := true
        added := 0
        for sensorId in sensorIds {
            if existing.Has(sensorId)
                continue
            if !this.configurator.app.sensorById.Has(sensorId) {
                MsgBox("A selected sensor is no longer available. Refresh sensors and try again.",
                    "Sidebar Metrics", "Icon!")
                return
            }
            sensor := this.configurator.app.sensorById[sensorId]
            this.row["bars"].Push(Map(
                "id", HM_NewId(),
                "sensorId", sensorId,
                "name", sensor["name"],
                "unit", HM_DefaultUnit(sensor["sensorType"]),
                "decimals", 0))
            existing[sensorId] := true
            added += 1
        }
        if (added = 0) {
            MsgBox("The selected sensors already have bars in this row.", "Sidebar Metrics", "Icon!")
            return
        }
        if this.row.Has("spacer")
            this.row.Delete("spacer")
        this.configurator.SaveAndRefresh()
        this.gui.Destroy()
    }
}

class HMRowScaleDialog {
    __New(configurator, row) {
        this.configurator := configurator
        this.row := row
        this.gui := Gui("+Owner" configurator.gui.Hwnd, "Row scale limits")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.AddText("x12 y14 w185 h20", "Bar maximum (blank = auto)")
        this.barMaxEdit := this.gui.AddEdit("x205 y11 w160")
        this.gui.AddText(
            "x12 y37 w350 h30",
            "Bars start at zero and clamp at this value. Auto uses the largest current bar.")
        this.gui.AddText("x12 y77 w185 h20", "Graph minimum (blank = auto)")
        this.graphMinEdit := this.gui.AddEdit("x205 y74 w160")
        this.gui.AddText("x12 y111 w185 h20", "Graph maximum (blank = auto)")
        this.graphMaxEdit := this.gui.AddEdit("x205 y108 w160")
        this.gui.AddText(
            "x12 y138 w350 h30",
            "Set both graph limits to use a fixed range; out-of-range values are clipped.")

        if row.Has("barMax")
            this.barMaxEdit.Value := row["barMax"]
        if row.Has("graphMin")
            this.graphMinEdit.Value := row["graphMin"]
        if row.Has("graphMax")
            this.graphMaxEdit.Value := row["graphMax"]

        this.saveButton := this.gui.AddButton("x185 y177 w85 h28", "Save")
        this.cancelButton := this.gui.AddButton("x278 y177 w85 h28", "Cancel")
        this.saveButton.OnEvent("Click", this.Save.Bind(this))
        this.cancelButton.OnEvent("Click", (*) => this.gui.Destroy())
        this.gui.OnEvent("Close", (*) => this.gui.Destroy())
        this.gui.Show("w380 h220")
    }

    Save(*) {
        barMaxText := Trim(this.barMaxEdit.Value)
        graphMinText := Trim(this.graphMinEdit.Value)
        graphMaxText := Trim(this.graphMaxEdit.Value)

        if (barMaxText != "") {
            if !IsNumber(barMaxText) || (barMaxText + 0) <= 0 {
                MsgBox("The bar maximum must be a positive number.", "Sidebar Metrics", "Icon!")
                return
            }
        }

        if (graphMinText = "" && graphMaxText = "") {
            if this.row.Has("graphMin")
                this.row.Delete("graphMin")
            if this.row.Has("graphMax")
                this.row.Delete("graphMax")
        } else {
            if (!IsNumber(graphMinText) || !IsNumber(graphMaxText)) {
                MsgBox("Enter both graph limits, or leave both blank for automatic scaling.",
                    "Sidebar Metrics", "Icon!")
                return
            }
            graphMin := graphMinText + 0
            graphMax := graphMaxText + 0
            if (graphMin >= graphMax) {
                MsgBox("The graph minimum must be lower than its maximum.", "Sidebar Metrics", "Icon!")
                return
            }
            this.row["graphMin"] := graphMin
            this.row["graphMax"] := graphMax
        }

        if (barMaxText = "") {
            if this.row.Has("barMax")
                this.row.Delete("barMax")
        } else {
            this.row["barMax"] := barMaxText + 0
        }
        this.configurator.SaveAndRefresh()
        this.gui.Destroy()
    }
}

class HMColumnWarningDialog {
    __New(configurator, column) {
        this.configurator := configurator
        this.column := column
        this.gui := Gui(
            "+Owner" configurator.gui.Hwnd,
            "Warning threshold: " column["name"])
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.AddText("x12 y15 w175 h20", "Threshold (blank disables)")
        this.valueEdit := this.gui.AddEdit("x190 y12 w145")
        this.gui.AddText("x12 y51 w175 h20", "Warn when value is")
        this.directionChoice := this.gui.AddDropDownList(
            "x190 y48 w145 Choose1",
            ["Above", "Below"])
        this.gui.AddText(
            "x12 y80 w350 h20",
            "Only this column turns red when its numeric value crosses the threshold.")
        this.saveButton := this.gui.AddButton("x190 y112 w70 h28", "Save")
        this.cancelButton := this.gui.AddButton("x268 y112 w85 h28", "Cancel")

        if column.Has("warningValue")
            this.valueEdit.Value := column["warningValue"]
        if column.Has("warningDirection") && column["warningDirection"] = "below"
            this.directionChoice.Value := 2

        this.saveButton.OnEvent("Click", this.Save.Bind(this))
        this.cancelButton.OnEvent("Click", (*) => this.gui.Destroy())
        this.gui.OnEvent("Close", (*) => this.gui.Destroy())
        this.gui.Show("w370 h155")
    }

    Save(*) {
        valueText := Trim(this.valueEdit.Value)
        if (valueText = "") {
            if this.column.Has("warningValue")
                this.column.Delete("warningValue")
            if this.column.Has("warningDirection")
                this.column.Delete("warningDirection")
        } else {
            if !IsNumber(valueText) {
                MsgBox("Enter a numeric warning threshold, or leave it blank to disable.",
                    "Sidebar Metrics", "Icon!")
                return
            }
            this.column["warningValue"] := valueText + 0
            this.column["warningDirection"] := this.directionChoice.Value = 2
                ? "below"
                : "above"
        }
        this.configurator.SaveAndRefresh()
        this.gui.Destroy()
    }
}

HM_PopulateSensorList(sensorList, sensors) {
    ids := []
    for sensor in sensors {
        value := sensor["isAvailable"] && IsNumber(sensor["value"])
            ? sensor["value"] ""
            : "--"
        sensorList.Add(
            "",
            sensor["name"],
            sensor["hardwareName"],
            sensor["sensorType"],
            value)
        ids.Push(sensor["id"])
    }
    return ids
}

HM_SelectedSensorIds(sensorList, sensorIds) {
    selected := []
    row := 0
    while (row := sensorList.GetNext(row))
        selected.Push(sensorIds[row])
    return selected
}

HM_AssetPaths() {
    paths := []
    directory := A_ScriptDir "\assets"
    Loop Files directory "\*.png", "F"
        paths.Push(A_LoopFileFullPath)
    return paths
}

HM_RemoveObject(array, target) {
    for index, item in array {
        if (item = target) {
            array.RemoveAt(index)
            return
        }
    }
}
