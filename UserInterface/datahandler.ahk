#Requires AutoHotkey v2.0

; Minimal Named Pipe client for HardwareMonitor.Service.
; Messages are a 4-byte big-endian length followed by UTF-8 JSON.

HardwareMonitor_StartDaemon(timeoutMs := 20000) {
    ; Reuse an existing daemon instead of starting another elevated process.
    try {
        return HardwareMonitor_Request("get_status")
    } catch as err {
        if InStr(err.Message, "Windows error 5")
            throw Error("The daemon pipe exists but access is denied. Close old HardwareMonitor.Service processes, rebuild the solution, and run this script again.`n" err.Message)
    }

    daemonPath := HardwareMonitor_FindDaemon()
    pid := 0
    try {
        ; Only the daemon is elevated; this AHK process remains unelevated.
        Run('*RunAs "' daemonPath '"', A_ScriptDir, "Hide", &pid)
    } catch as err {
        throw Error("Could not start the elevated daemon. Approve its UAC prompt and try again.`n" err.Message)
    }

    deadline := A_TickCount + timeoutMs
    lastError := ""
    while (A_TickCount < deadline) {
        try {
            return HardwareMonitor_Request("get_status")
        } catch as err {
            if InStr(err.Message, "Windows error 5")
                throw Error("The daemon pipe exists but access is denied. Close old HardwareMonitor.Service processes, rebuild the solution, and run this script again.`n" err.Message)
            if !ProcessExist(pid)
                throw Error("HardwareMonitor.Service exited before its pipe became available. Check C:\ProgramData\HardwareMonitor\logs\hardware-monitor.log.`n" err.Message)
            lastError := err.Message
            Sleep(250)
        }
    }
    throw Error("The daemon did not become available within " timeoutMs " ms.`n" lastError)
}

HardwareMonitor_FindDaemon() {
    candidates := [
        A_ScriptDir "\..\HardwareMonitor.Service\bin\Release\net8.0-windows\HardwareMonitor.Service.exe",
        A_ScriptDir "\..\HardwareMonitor.Service\bin\Release\net8.0-windows\win-x64\publish\HardwareMonitor.Service.exe",
        A_ScriptDir "\..\HardwareMonitor.Service\bin\Debug\net8.0-windows\HardwareMonitor.Service.exe"
    ]
    for path in candidates {
        path := HardwareMonitor_FullPath(path)
        if FileExist(path)
            return path
    }
    throw Error(
        "Could not find HardwareMonitor.Service.exe. Build or publish the solution first.`n"
        "Expected it under HardwareMonitor.Service\bin\Release.")
}

HardwareMonitor_FullPath(path) {
    pathBuffer := Buffer(32768 * 2, 0)
    length := DllCall("GetFullPathNameW", "WStr", path, "UInt", 32768, "Ptr", pathBuffer.Ptr, "Ptr", 0, "UInt")
    if (!length || length >= 32768)
        throw Error("Could not resolve daemon path: " path)
    return StrGet(pathBuffer, length, "UTF-16")
}

; `argsJson` is an optional JSON object body, e.g. '"sensors":["/sensor/id"]'.
; Returned value is the raw response JSON, so no external JSON library is needed.
HardwareMonitor_Request(command, argsJson := "") {
    static pipePath := "\\.\pipe\HardwareMonitorPipe"
    static requestNumber := 0

    if !RegExMatch(command, "^[a-z_]+$")
        throw Error("Invalid daemon command.")

    requestNumber += 1
    requestId := A_TickCount "-" requestNumber
    json := '{"requestId":"' requestId '","command":"' command '"' (argsJson = "" ? "" : "," argsJson) '}'

    handle := DllCall(
        "CreateFileW",
        "WStr", pipePath,
        "UInt", 0xC0000000, ; GENERIC_READ | GENERIC_WRITE
        "UInt", 0,
        "Ptr", 0,
        "UInt", 3, ; OPEN_EXISTING
        "UInt", 0x80, ; FILE_ATTRIBUTE_NORMAL
        "Ptr", 0,
        "Ptr")
    if (handle = -1) {
        errorCode := DllCall("GetLastError", "UInt")
        throw Error("Could not connect to the daemon pipe. Windows error " errorCode)
    }

    try {
        byteCount := StrPut(json, "UTF-8") - 1
        payload := Buffer(byteCount + 1, 0)
        StrPut(json, payload, "UTF-8")

        header := Buffer(4, 0)
        NumPut("UChar", (byteCount >> 24) & 0xFF, header, 0)
        NumPut("UChar", (byteCount >> 16) & 0xFF, header, 1)
        NumPut("UChar", (byteCount >> 8) & 0xFF, header, 2)
        NumPut("UChar", byteCount & 0xFF, header, 3)
        HardwareMonitor_WriteExact(handle, header, 4)
        HardwareMonitor_WriteExact(handle, payload, byteCount)

        responseHeader := Buffer(4, 0)
        HardwareMonitor_ReadExact(handle, responseHeader, 4)
        responseLength :=
            (NumGet(responseHeader, 0, "UChar") << 24)
            | (NumGet(responseHeader, 1, "UChar") << 16)
            | (NumGet(responseHeader, 2, "UChar") << 8)
            | NumGet(responseHeader, 3, "UChar")
        if (responseLength < 1 || responseLength > 4 * 1024 * 1024)
            throw Error("Daemon returned an invalid response length: " responseLength)

        response := Buffer(responseLength, 0)
        HardwareMonitor_ReadExact(handle, response, responseLength)
        return StrGet(response, responseLength, "UTF-8")
    } finally {
        DllCall("CloseHandle", "Ptr", handle)
    }
}

HardwareMonitor_WriteExact(handle, buffer, length) {
    offset := 0
    while (offset < length) {
        written := 0
        ok := DllCall(
            "WriteFile",
            "Ptr", handle,
            "Ptr", buffer.Ptr + offset,
            "UInt", length - offset,
            "UInt*", &written,
            "Ptr", 0,
            "Int")
        if (!ok || written = 0)
            throw Error("Failed writing to daemon pipe. Windows error " DllCall("GetLastError", "UInt"))
        offset += written
    }
}

HardwareMonitor_ReadExact(handle, buffer, length) {
    offset := 0
    while (offset < length) {
        received := 0
        ok := DllCall(
            "ReadFile",
            "Ptr", handle,
            "Ptr", buffer.Ptr + offset,
            "UInt", length - offset,
            "UInt*", &received,
            "Ptr", 0,
            "Int")
        if (!ok || received = 0)
            throw Error("Failed reading from daemon pipe. Windows error " DllCall("GetLastError", "UInt"))
        offset += received
    }
}

HardwareMonitor_GetStatus() {
    return HardwareMonitor_Request("get_status")
}

HardwareMonitor_GetSensors() {
    return HardwareMonitor_Request("get_sensors")
}

HardwareMonitor_GetAllValues() {
    return HardwareMonitor_Request("get_all_values")
}

HardwareMonitor_SetPollingInterval(milliseconds) {
    if (milliseconds < 100 || milliseconds > 60000)
        throw Error("Polling interval must be between 100 and 60000 ms.")
    return HardwareMonitor_Request("set_poll_interval", '"intervalMs":' milliseconds)
}

HardwareMonitor_SetActiveSensors(sensorIds) {
    jsonIds := ""
    for id in sensorIds {
        if (jsonIds != "")
            jsonIds .= ","
        jsonIds .= '"' HardwareMonitor_EscapeJson(id) '"'
    }
    return HardwareMonitor_Request("set_active_sensors", '"sensors":[' jsonIds ']')
}

HardwareMonitor_EscapeJson(value) {
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, "`b", "\b")
    value := StrReplace(value, "`f", "\f")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`t", "\t")
    return value
}