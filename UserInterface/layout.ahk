#Requires AutoHotkey v2.0

HM_DefaultLayout() {
    return Map(
        "version", 1,
        "screen", 1,
        "side", "right",
        "sidebarWidth", 360,
        "textSize", 9,
        "headerSize", 11,
        "sectionSpacing", 8,
        "sections", [])
}

HM_LoadLayout() {
    path := HM_LayoutPath()
    if !FileExist(path)
        return HM_DefaultLayout()

    try {
        layout := HM_JsonParse(FileRead(path, "UTF-8"))
        if (Type(layout) != "Map" || !layout.Has("sections") || Type(layout["sections"]) != "Array")
            throw Error("The layout file has an invalid structure.")
        if !layout.Has("screen")
            layout["screen"] := 1
        if !layout.Has("side")
            layout["side"] := "right"
        HM_NormalizeLayoutSettings(layout)
        return layout
    } catch as err {
        MsgBox(
            "The sidebar layout could not be loaded. A default layout will be used.`n`n"
            err.Message,
            "Sidebar Metrics",
            "Icon!")
        return HM_DefaultLayout()
    }
}

HM_NormalizeLayoutSettings(layout) {
    settings := [
        ["sidebarWidth", 360, 320, 900],
        ["textSize", 9, 7, 18],
        ["headerSize", 11, 9, 26],
        ["sectionSpacing", 8, 0, 100]]
    for setting in settings {
        key := setting[1]
        if !layout.Has(key) || !IsNumber(layout[key])
            layout[key] := setting[2]
        layout[key] := Round(Min(Max(layout[key] + 0, setting[3]), setting[4]))
    }
}

HM_SaveLayout(layout) {
    path := HM_LayoutPath()
    directory := RegExReplace(path, "\\[^\\]+$")
    DirCreate(directory)
    temporary := path ".tmp"
    if FileExist(temporary)
        FileDelete(temporary)
    FileAppend(HM_JsonStringify(layout), temporary, "UTF-8-RAW")
    FileMove(temporary, path, 1)
}

HM_LayoutPath() {
    return A_AppData "\SidebarMetrics\layout.json"
}

HM_NewId() {
    static counter := 0
    counter += 1
    return A_TickCount "-" counter
}

HM_LayoutSensorIds(layout, availableSensors := unset) {
    known := Map()
    if IsSet(availableSensors) {
        for sensor in availableSensors
            known[sensor["id"]] := true
    }
    ids := []
    seen := Map()
    for section in layout["sections"] {
        for row in section["rows"] {
            for column in row["columns"] {
                if (column["kind"] = "sensor")
                    HM_AddUniqueSensor(ids, seen, known, column["sensorId"], IsSet(availableSensors))
                else if (column["kind"] = "aggregate") {
                    for sensorId in column["sensorIds"]
                        HM_AddUniqueSensor(ids, seen, known, sensorId, IsSet(availableSensors))
                } else if (column["kind"] = "formula" && column.Has("sensorIds")) {
                    for sensorId in column["sensorIds"]
                        HM_AddUniqueSensor(ids, seen, known, sensorId, IsSet(availableSensors))
                }
            }
            if row.Has("bars") {
                for bar in row["bars"]
                    HM_AddUniqueSensor(ids, seen, known, bar["sensorId"], IsSet(availableSensors))
            }
        }
        if section.Has("bars") {
            for bar in section["bars"]
                HM_AddUniqueSensor(ids, seen, known, bar["sensorId"], IsSet(availableSensors))
        }
    }
    return ids
}

HM_AddUniqueSensor(ids, seen, known, sensorId, filterKnown) {
    if (sensorId = "" || seen.Has(sensorId))
        return
    if (filterKnown && !known.Has(sensorId))
        return
    seen[sensorId] := true
    ids.Push(sensorId)
}

HM_DefaultUnit(sensorType) {
    switch sensorType {
        case "Temperature": return "°C"
        case "Load": return "%"
        case "Fan": return "RPM"
        case "Clock": return "MHz"
        case "Voltage": return "V"
        case "Power": return "W"
        case "Data": return "GB"
        case "Throughput": return "MB/s"
        default: return ""
    }
}

HM_FormatNumber(value, decimals) {
    if !IsNumber(value)
        return "--"
    factor := 10 ** decimals
    rounded := Round(value * factor) / factor
    return Format("{:." decimals "f}", rounded)
}

HM_EvaluateFormula(formula, priorValues) {
    expanded := ""
    position := 1
    while RegExMatch(formula, "\{(\d+)\}", &match, position) {
        expanded .= SubStr(formula, position, match.Pos - position)
        index := match[1] + 0
        if (index < 1 || index > priorValues.Length || !IsNumber(priorValues[index]))
            throw Error("Formula reference {" index "} has no numeric value.")
        expanded .= priorValues[index]
        position := match.Pos + match.Len
    }
    expanded .= SubStr(formula, position)
    parser := HMExpressionParser(expanded)
    return parser.Parse()
}

class HMExpressionParser {
    __New(expression) {
        this.expression := expression
        this.position := 1
        this.length := StrLen(expression)
    }

    Parse() {
        value := this.ReadExpression()
        this.SkipSpaces()
        if (this.position <= this.length)
            throw Error("Unexpected character in formula.")
        return value
    }

    ReadExpression() {
        value := this.ReadTerm()
        loop {
            this.SkipSpaces()
            operator := SubStr(this.expression, this.position, 1)
            if (operator != "+" && operator != "-")
                return value
            this.position += 1
            right := this.ReadTerm()
            value := operator = "+" ? value + right : value - right
        }
    }

    ReadTerm() {
        value := this.ReadUnary()
        loop {
            this.SkipSpaces()
            operator := SubStr(this.expression, this.position, 1)
            if (operator != "*" && operator != "/")
                return value
            this.position += 1
            right := this.ReadUnary()
            if (operator = "/" && right = 0)
                throw Error("Division by zero in formula.")
            value := operator = "*" ? value * right : value / right
        }
    }

    ReadUnary() {
        this.SkipSpaces()
        operator := SubStr(this.expression, this.position, 1)
        if (operator = "+" || operator = "-") {
            this.position += 1
            value := this.ReadUnary()
            return operator = "-" ? -value : value
        }
        return this.ReadPrimary()
    }

    ReadPrimary() {
        this.SkipSpaces()
        if (SubStr(this.expression, this.position, 1) = "(") {
            this.position += 1
            value := this.ReadExpression()
            this.SkipSpaces()
            if (SubStr(this.expression, this.position, 1) != ")")
                throw Error("Missing closing parenthesis in formula.")
            this.position += 1
            return value
        }

        remaining := SubStr(this.expression, this.position)
        if !RegExMatch(remaining, "^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", &match)
            throw Error("Expected a number in formula.")
        this.position += match.Len
        return match[0] + 0
    }

    SkipSpaces() {
        while (this.position <= this.length && SubStr(this.expression, this.position, 1) = " ")
            this.position += 1
    }
}
