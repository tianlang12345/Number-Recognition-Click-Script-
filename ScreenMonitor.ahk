; ============================================================
; Screen Number Monitor & Auto-Clicker (AutoHotkey v2)
; Description: Monitors defined screen regions for numbers and
;              clicks a specified position when a condition is met.
; Config file: ScreenMonitorConfig.ini (in the same folder)
; Hotkeys:
;   F5          - Reload configuration
;   F6          - Open config file in Notepad
;   F7          - Start / Stop monitoring
;   F8          - Calibrate a new region (press twice)
;   F9          - Delete the zone under mouse cursor
;   F10         - Toggle loop click
;   F4          - Show and copy current mouse position
;   Ctrl+Shift+S - Exit script
; Requirements: Windows 10/11 with PowerShell 5.1+ for built-in OCR.
;               Alternatively set OCRMethod=tesseract and install Tesseract.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; Make the script per-monitor DPI aware so screen coordinates and captures use physical pixels
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")

global ConfigFile := A_ScriptDir "\ScreenMonitorConfig.ini"
global IsMonitoring := false
global Zones := []
global LoopClick := {}
global ClickSequenceDelay := 50
global GdipToken := 0
global CalibStep := 0
global CalibX1 := 0, CalibY1 := 0

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

if (!FileExist(ConfigFile))
    CreateDefaultConfig()

LoadConfig()
LoadLoopClickConfig()
ClickSequenceDelay := GetIniValue("Settings", "ClickSequenceDelay", "50")
GdipToken := Gdip_Startup()

IsMonitoring := Integer(GetIniValue("Settings", "Enabled", 1))
interval := Integer(GetIniValue("Settings", "Interval", 1000))

if (IsMonitoring)
    SetTimer(MonitorLoop, interval)

if (LoopClick.Enabled)
    SetTimer(LoopClickTimer, LoopClick.Interval)

OnExit(ExitSub)

ToolTip("Screen monitor started`nF4=MousePos  F5=Reload  F6=Edit  F7=Toggle  F8=Add zone  F9=Del  F10=Loop  Ctrl+Shift+S=Exit")
SetTimer(RemoveToolTip, -5000)

; ============================================================
; Hotkeys
; ============================================================

F5::
{
    global LoopClick, ClickSequenceDelay
    LoadConfig()
    LoadLoopClickConfig()
    ClickSequenceDelay := GetIniValue("Settings", "ClickSequenceDelay", "50")
    SetTimer(LoopClickTimer, LoopClick.Enabled ? LoopClick.Interval : 0)
    ToolTip("Configuration reloaded")
    SetTimer(RemoveToolTip, -1500)
}

F6::
{
    if (!FileExist(ConfigFile))
        CreateDefaultConfig()
    Run('notepad.exe "' . ConfigFile . '"')
}

F7::
{
    global IsMonitoring
    IsMonitoring := !IsMonitoring
    if (IsMonitoring) {
        interval := Integer(GetIniValue("Settings", "Interval", 1000))
        SetTimer(MonitorLoop, interval)
    } else {
        SetTimer(MonitorLoop, 0)
    }
    ToolTip(IsMonitoring ? "Monitoring ON" : "Monitoring PAUSED")
    SetTimer(RemoveToolTip, -1500)
}

F8::
{
    global CalibStep, CalibX1, CalibY1, Zones, ConfigFile
    if (CalibStep = 0) {
        MouseGetPos(&CalibX1, &CalibY1)
        CalibStep := 1
        ToolTip("Top-left corner recorded: " . CalibX1 . ", " . CalibY1 . "`nMove to bottom-right and press F8 again")
    } else {
        MouseGetPos(&x2, &y2)
        x := Min(CalibX1, x2)
        y := Min(CalibY1, y2)
        w := Abs(x2 - CalibX1)
        h := Abs(y2 - CalibY1)
        CalibStep := 0

        nextIndex := Zones.Length > 0 ? Zones.Length + 1 : 1
        section := "Zone" . nextIndex

        IniWrite("Zone" . nextIndex, ConfigFile, section, "Name")
        IniWrite(String(x), ConfigFile, section, "X")
        IniWrite(String(y), ConfigFile, section, "Y")
        IniWrite(String(w), ConfigFile, section, "W")
        IniWrite(String(h), ConfigFile, section, "H")
        IniWrite("50", ConfigFile, section, "Threshold")
        IniWrite("<", ConfigFile, section, "Operator")
        IniWrite(String(x) . ",1980,1980,1980,1980,1980,1980,1875,1565,1565", ConfigFile, section, "ClickX")
        IniWrite(String(y) . ",1034,1034,1034,1034,1034,1034,1188,1196,1196", ConfigFile, section, "ClickY")
        IniWrite("L,L,L,L,L,L,L,L,L,L", ConfigFile, section, "ClickButton")
        IniWrite("2000", ConfigFile, section, "Cooldown")
        IniWrite("100,100,100,100,100,100,500,1000,500", ConfigFile, section, "ClickSequenceDelay")
        IniWrite("1", ConfigFile, section, "Enabled")

        LoadConfig()
        ToolTip("Added Zone" . nextIndex . "`nX=" . x . " Y=" . y . " W=" . w . " H=" . h . "`nPress F6 to edit threshold and click position")
        SetTimer(RemoveToolTip, -3000)
    }
}

F9::
{
    global Zones, ConfigFile
    MouseGetPos(&mx, &my)
    targetIndex := 0
    for index, zone in Zones {
        if (zone.Enabled && mx >= zone.X && mx <= zone.X + zone.W && my >= zone.Y && my <= zone.Y + zone.H) {
            targetIndex := index
            break
        }
    }
    if (targetIndex = 0) {
        ToolTip("当前鼠标位置没有监控区域")
        SetTimer(RemoveToolTip, -1500)
        return
    }
    removedName := Zones[targetIndex].Name
    Zones.RemoveAt(targetIndex)
    SaveAllZones()
    LoadConfig()
    ToolTip("已删除区域: " . removedName)
    SetTimer(RemoveToolTip, -2000)
}

F10::
{
    global LoopClick, ConfigFile
    LoopClick.Enabled := !LoopClick.Enabled
    IniWrite(LoopClick.Enabled ? "1" : "0", ConfigFile, "Settings", "LoopClickEnabled")
    if (LoopClick.Enabled)
        SetTimer(LoopClickTimer, LoopClick.Interval)
    else
        SetTimer(LoopClickTimer, 0)
    ToolTip("Loop click " . (LoopClick.Enabled ? "ON" : "OFF"))
    SetTimer(RemoveToolTip, -1500)
}

F4::
{
    MouseGetPos(&mx, &my)
    A_Clipboard := mx . "," . my
    ToolTip("Mouse position copied to clipboard`nX=" . mx . "  Y=" . my)
    SetTimer(RemoveToolTip, -2000)
}

^+s::ExitApp()

; ============================================================
; Timer / Callback functions
; ============================================================

MonitorLoop() {
    global Zones, ConfigFile
    for index, z in Zones
    {
        if (!z.Enabled)
            continue
        if (z.W <= 0 || z.H <= 0)
            continue
        if (A_TickCount - z.LastClick < z.Cooldown)
            continue

        imgPath := A_Temp "\ScreenMonitor_Zone" . index . ".png"
        CaptureRegion(z.X, z.Y, z.W, z.H, imgPath)
        text := OcrImage(imgPath, GetIniValue("Settings", "OCRLanguage", "zh-Hans"))
        SafeDelete(imgPath)

        num := ExtractFirstNumber(text)
        if (num = "")
            continue

        if (Compare(num, z.Threshold, z.Operator))
        {
            ClickAt(z.ClickX, z.ClickY, z.ClickButton, z.ClickSequenceDelay)
            z.LastClick := A_TickCount
            ToolTip("[" . z.Name . "] Detected: " . num . "  Condition: " . z.Operator . " " . z.Threshold . "  Clicked")
            SetTimer(RemoveToolTip, -2000)
            Log("Click " . z.Name . ": " . num . " " . z.Operator . " " . z.Threshold)
        }
    }
}

LoopClickTimer() {
    global LoopClick
    if (!LoopClick.Enabled)
        return
    ClickAt(LoopClick.X, LoopClick.Y, LoopClick.Button)
}

RemoveToolTip() {
    ToolTip()
}

ExitSub(Reason, Code) {
    global GdipToken
    Gdip_Shutdown(GdipToken)
    ExitApp()
}

; ============================================================
; Configuration functions
; ============================================================

CreateDefaultConfig() {
    global ConfigFile
    content := "
    (LTrim
    [Settings]
    Enabled=1
    Interval=1000
    OCRLanguage=zh-Hans
    OCRMethod=powershell
    TesseractPath=C:\Program Files\Tesseract-OCR\tesseract.exe
    LoopClickEnabled=0
    LoopClickX=500
    LoopClickY=500
    LoopClickInterval=100
    LoopClickButton=L
    ClickSequenceDelay=50

    [Zone1]
    Name=Zone1
    X=100
    Y=200
    W=120
    H=40
    Threshold=50
    Operator=<
    ClickX=300
    ClickY=400
    ClickButton=L
    Cooldown=2000
    ClickSequenceDelay=0
    Enabled=1
    )"
    SafeDelete(ConfigFile)
    FileAppend(content, ConfigFile)
}

LoadConfig() {
    global Zones, ConfigFile
    Zones := []
    i := 1
    Loop {
        section := "Zone" . i
        if (!IniExist(section))
            break

        z := {}
        z.Name := GetIniValue(section, "Name", "Zone" . i)
        z.X := Integer(GetIniValue(section, "X", 0))
        z.Y := Integer(GetIniValue(section, "Y", 0))
        z.W := Integer(GetIniValue(section, "W", 100))
        z.H := Integer(GetIniValue(section, "H", 30))
        z.Threshold := Number(GetIniValue(section, "Threshold", 0))
        z.Operator := GetIniValue(section, "Operator", "<")
        z.ClickX := GetIniValue(section, "ClickX", "0")
        z.ClickY := GetIniValue(section, "ClickY", "0")
        z.ClickButton := GetIniValue(section, "ClickButton", "L")
        z.Cooldown := Integer(GetIniValue(section, "Cooldown", 1000))
        z.ClickSequenceDelay := GetIniValue(section, "ClickSequenceDelay", "0")
        z.Enabled := Integer(GetIniValue(section, "Enabled", 1))
        z.LastClick := 0

        Zones.Push(z)
        i++
    }
}

LoadLoopClickConfig() {
    global LoopClick
    LoopClick := {}
    LoopClick.Enabled := Integer(GetIniValue("Settings", "LoopClickEnabled", 0))
    LoopClick.X := Integer(GetIniValue("Settings", "LoopClickX", 500))
    LoopClick.Y := Integer(GetIniValue("Settings", "LoopClickY", 500))
    LoopClick.Interval := Integer(GetIniValue("Settings", "LoopClickInterval", 100))
    LoopClick.Button := GetIniValue("Settings", "LoopClickButton", "L")
}

SaveAllZones() {
    global ConfigFile, Zones
    settings := Map()
    settings["Enabled"] := GetIniValue("Settings", "Enabled", "1")
    settings["Interval"] := GetIniValue("Settings", "Interval", "1000")
    settings["OCRLanguage"] := GetIniValue("Settings", "OCRLanguage", "zh-Hans")
    settings["OCRMethod"] := GetIniValue("Settings", "OCRMethod", "powershell")
    settings["TesseractPath"] := GetIniValue("Settings", "TesseractPath", "")
    settings["LoopClickEnabled"] := GetIniValue("Settings", "LoopClickEnabled", "0")
    settings["LoopClickX"] := GetIniValue("Settings", "LoopClickX", "500")
    settings["LoopClickY"] := GetIniValue("Settings", "LoopClickY", "500")
    settings["LoopClickInterval"] := GetIniValue("Settings", "LoopClickInterval", "100")
    settings["LoopClickButton"] := GetIniValue("Settings", "LoopClickButton", "L")
    settings["ClickSequenceDelay"] := GetIniValue("Settings", "ClickSequenceDelay", "50")

    SafeDelete(ConfigFile)

    for key, value in settings {
        IniWrite(value, ConfigFile, "Settings", key)
    }

    for index, zone in Zones {
        section := "Zone" . index
        IniWrite(zone.Name, ConfigFile, section, "Name")
        IniWrite(String(zone.X), ConfigFile, section, "X")
        IniWrite(String(zone.Y), ConfigFile, section, "Y")
        IniWrite(String(zone.W), ConfigFile, section, "W")
        IniWrite(String(zone.H), ConfigFile, section, "H")
        IniWrite(String(zone.Threshold), ConfigFile, section, "Threshold")
        IniWrite(zone.Operator, ConfigFile, section, "Operator")
        IniWrite(String(zone.ClickX), ConfigFile, section, "ClickX")
        IniWrite(String(zone.ClickY), ConfigFile, section, "ClickY")
        IniWrite(zone.ClickButton, ConfigFile, section, "ClickButton")
        IniWrite(String(zone.Cooldown), ConfigFile, section, "Cooldown")
        IniWrite(String(zone.ClickSequenceDelay), ConfigFile, section, "ClickSequenceDelay")
        IniWrite(zone.Enabled ? "1" : "0", ConfigFile, section, "Enabled")
    }
}

IniExist(section) {
    global ConfigFile
    try {
        IniRead(ConfigFile, section)
        return true
    } catch Error {
        return false
    }
}

GetIniValue(section, key, default) {
    global ConfigFile
    return IniRead(ConfigFile, section, key, default)
}

; ============================================================
; OCR functions
; ============================================================

OcrImage(imgPath, lang) {
    method := GetIniValue("Settings", "OCRMethod", "powershell")

    if (method = "tesseract") {
        tessPath := GetIniValue("Settings", "TesseractPath", "tesseract.exe")
        outBase := A_Temp "\ScreenMonitor_OCR"
        outFile := outBase . ".txt"
        SafeDelete(outFile)

        ; Try with digit whitelist first
        cmd := '"' . tessPath . '" "' . imgPath . '" "' . outBase . '" --psm 7 -c tessedit_char_whitelist=0123456789,.'
        try {
            RunWait(cmd,, "Hide")
        } catch Error as e {
            Log("Tesseract RunWait error: " . e.Message)
        }
        result := FileExist(outFile) ? FileRead(outFile) : ""
        SafeDelete(outFile)

        ; Fallback: try without whitelist if first attempt returned empty
        if (result = "") {
            SafeDelete(outFile)
            cmd2 := '"' . tessPath . '" "' . imgPath . '" "' . outBase . '" --psm 7'
            try {
                RunWait(cmd2,, "Hide")
            } catch Error as e2 {
                Log("Tesseract fallback RunWait error: " . e2.Message)
            }
            result2 := FileExist(outFile) ? FileRead(outFile) : ""
            SafeDelete(outFile)
            if (result2 != "")
                return result2
        }
        return result
    }

    psScript := "
    (LTrim
    param($path, $lang = ""zh-Hans"")
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        [Windows.Media.Ocr.OcrEngine, Windows.Media, ContentType = WindowsRuntime] | Out-Null
        [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
        [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime] | Out-Null
        [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime] | Out-Null

        $fs = [System.IO.File]::OpenRead($path)
        $ras = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
        $fs.CopyTo($ras.AsStreamForWrite())
        $ras.Seek(0)

        $decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras).AsTask().Result
        $sb = $decoder.GetSoftwareBitmapAsync().AsTask().Result
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new($lang))
        if ($engine -eq $null) {
            Write-Error "Language not supported: $lang"
            return
        }
        $result = $engine.RecognizeAsync($sb).AsTask().Result
        Write-Output $result.Text
    }
    catch {
        Write-Error $_.Exception.Message
    }
    )"

    psFile := A_Temp "\ScreenMonitor_OCR.ps1"
    SafeDelete(psFile)
    FileAppend(psScript, psFile)

    psPath := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    cmd := Chr(34) . psPath . Chr(34) . " -ExecutionPolicy Bypass -File " . Chr(34) . psFile . Chr(34) . " -path " . Chr(34) . imgPath . Chr(34) . " -lang " . Chr(34) . lang . Chr(34)
    result := RunCommand(cmd)

    SafeDelete(psFile)
    return result
}

RunCommand(cmd) {
    outputFile := A_Temp "\ScreenMonitor_Output.txt"
    fullCmd := A_ComSpec . ' /c ' . cmd . ' > "' . outputFile . '" 2>&1'
    try {
        RunWait(fullCmd,, "Hide")
        if (!FileExist(outputFile))
            return ""
        result := FileRead(outputFile)
        SafeDelete(outputFile)
        return result
    } catch Error as e {
        Log("RunCommand failed: " . e.Message . "`nCmd: " . fullCmd)
        return ""
    }
}

ExtractFirstNumber(text) {
    ; Match digits possibly containing thousands separators (e.g. 70,000) and decimals
    if (RegExMatch(text, "[0-9][0-9,.]*", &m)) {
        numStr := RegExReplace(m[0], ",", "")
        return Number(numStr)
    }
    return ""
}

; ============================================================
; Action functions
; ============================================================

Compare(a, b, op) {
    if (op = "<")
        return a < b
    if (op = ">")
        return a > b
    if (op = "<=")
        return a <= b
    if (op = ">=")
        return a >= b
    if (op = "=" || op = "==" || op = "eq")
        return a = b
    if (op = "!=" || op = "<>" || op = "ne")
        return a != b
    return false
}

ClickAt(x, y, button, seqDelay := "") {
    global ClickSequenceDelay
    if (seqDelay = "" || seqDelay = "0")
        seqDelay := ClickSequenceDelay

    delays := StrSplit(seqDelay, ",")
    for i, d in delays
        delays[i] := Integer(Trim(d))

    GapDelay(index) {
        if (index <= delays.Length)
            return delays[index]
        if (delays.Length > 0)
            return delays[delays.Length]
        return 0
    }

    if (InStr(x, ",") || InStr(y, ",")) {
        xs := StrSplit(x, ",")
        ys := StrSplit(y, ",")
        btns := StrSplit(button, ",")
        count := Max(xs.Length, ys.Length)
        for index, xi in xs {
            xi := Trim(xi)
            yi := index <= ys.Length ? Trim(ys[index]) : Trim(ys[ys.Length])
            bi := index <= btns.Length ? Trim(btns[index]) : (btns.Length > 0 ? Trim(btns[btns.Length]) : "L")
            if (xi = "" || yi = "")
                continue
            ClickOrSend(Integer(xi), Integer(yi), bi)
            if (index < count)
                Sleep(GapDelay(index))
        }
    } else if (InStr(button, ",")) {
        buttons := StrSplit(button, ",")
        for index, b in buttons {
            b := Trim(b)
            if (b = "")
                continue
            ClickOrSend(x, y, b)
            if (index < buttons.Length)
                Sleep(GapDelay(index))
        }
    } else {
        ClickOrSend(x, y, button)
    }
}

ClickOrSend(x, y, button) {
    upper := StrUpper(button)
    if (upper = "L" || upper = "LEFT" || upper = "R" || upper = "RIGHT" || upper = "M" || upper = "MIDDLE") {
        btn := "LEFT"
        if (upper = "R" || upper = "RIGHT")
            btn := "RIGHT"
        else if (upper = "M" || upper = "MIDDLE")
            btn := "MIDDLE"
        count := (InStr(button, "2") || InStr(button, "D") || InStr(upper, "DOUBLE")) ? 2 : 1
        MouseClick(btn, x, y, count)
    } else {
        Send(button)
    }
}

; ============================================================
; Screen capture functions
; ============================================================

CaptureRegion(x, y, w, h, filePath) {
    if (w <= 0 || h <= 0) {
        Log("CaptureRegion failed: invalid width/height")
        return
    }

    ; Try PowerShell capture first
    CaptureRegionPowerShell(x, y, w, h, filePath)
    if (FileExist(filePath))
        return

    ; Fallback to GDI+ capture
    Log("PowerShell capture failed, trying GDI+ fallback")
    CaptureRegionGDI(x, y, w, h, filePath)
    if (!FileExist(filePath))
        Log("CaptureRegion failed: both PowerShell and GDI+ fallback failed")
}

CaptureRegionPowerShell(x, y, w, h, filePath) {
    psScript := "
    (LTrim
    param([int]$x, [int]$y, [int]$w, [int]$h, [string]$path)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $bounds = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
        $bitmap = New-Object System.Drawing.Bitmap($w, $h)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    catch {
        Write-Error $_.Exception.Message
    }
    )"

    psFile := A_Temp "\ScreenMonitor_Capture.ps1"
    SafeDelete(psFile)
    FileAppend(psScript, psFile)

    psPath := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    cmd := Chr(34) . psPath . Chr(34) . " -ExecutionPolicy Bypass -File " . Chr(34) . psFile . Chr(34) . " -x " . x . " -y " . y . " -w " . w . " -h " . h . " -path " . Chr(34) . filePath . Chr(34)
    result := RunCommand(cmd)
    if (!FileExist(filePath))
        Log("CaptureRegionPowerShell failed: output file not created`n" . result)

    SafeDelete(psFile)
}

CaptureRegionGDI(x, y, w, h, filePath) {
    hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    if (!hDC) {
        Log("CaptureRegionGDI failed: GetDC returned 0")
        return
    }
    hMemDC := DllCall("CreateCompatibleDC", "Ptr", hDC, "Ptr")
    if (!hMemDC) {
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
        Log("CaptureRegionGDI failed: CreateCompatibleDC returned 0")
        return
    }

    ; Use a 32-bit top-down DIB for reliable GDI+ import
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", w, bi, 4)
    NumPut("Int", -h, bi, 8)   ; negative height = top-down
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)
    bits := 0
    hBitmap := DllCall("CreateDIBSection", "Ptr", hMemDC, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    if (!hBitmap) {
        DllCall("DeleteDC", "Ptr", hMemDC)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)
        Log("CaptureRegionGDI failed: CreateDIBSection returned 0")
        return
    }

    hOld := DllCall("SelectObject", "Ptr", hMemDC, "Ptr", hBitmap, "Ptr")
    if (!DllCall("BitBlt", "Ptr", hMemDC, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hDC, "Int", x, "Int", y, "UInt", 0x00CC0020, "Int")) {
        Log("CaptureRegionGDI warning: BitBlt returned 0")
    }
    DllCall("SelectObject", "Ptr", hMemDC, "Ptr", hOld, "Ptr")
    DllCall("DeleteDC", "Ptr", hMemDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)

    pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
    if (!pBitmap) {
        DllCall("DeleteObject", "Ptr", hBitmap)
        Log("CaptureRegionGDI failed: Gdip_CreateBitmapFromHBITMAP returned 0")
        return
    }
    saveResult := Gdip_SaveBitmapToFile(pBitmap, filePath)
    Gdip_DisposeImage(pBitmap)
    DllCall("DeleteObject", "Ptr", hBitmap)

    if (saveResult != 0)
        Log("CaptureRegionGDI failed: GdipSaveImageToFile returned " . saveResult)
}

Gdip_Startup() {
    hModule := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    if (!hModule) {
        MsgBox("无法加载 gdiplus.dll，请确认系统支持 GDI+")
        ExitApp()
    }
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("Int", 1, si.Ptr)
    token := 0
    result := DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si.Ptr, "Ptr", 0)
    if (result != 0 || token = 0) {
        MsgBox("GDI+ 初始化失败，错误码: " . result)
        ExitApp()
    }
    return token
}

Gdip_Shutdown(token) {
    DllCall("gdiplus\GdiplusShutdown", "Ptr", token)
}

Gdip_CreateBitmapFromHBITMAP(hBitmap, hPalette := 0) {
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hBitmap, "Ptr", hPalette, "Ptr*", &pBitmap)
    return pBitmap
}

Gdip_SaveBitmapToFile(pBitmap, sFile) {
    clsid := Buffer(16, 0)
    if (DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid.Ptr) != 0)
        return 1
    return DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", sFile, "Ptr", clsid.Ptr, "UInt", 0)
}

Gdip_DisposeImage(pBitmap) {
    return DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
}

; ============================================================
; Utility functions
; ============================================================

Log(msg) {
    now := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    FileAppend("[" . now . "] " . msg . "`n", A_ScriptDir "\ScreenMonitorLog.txt")
}

SafeDelete(file) {
    try {
        FileDelete(file)
    } catch {
        ; ignore missing file
    }
}
