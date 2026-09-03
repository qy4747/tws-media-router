#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#Include router-state.ahk

PROJECT_DIR := A_ScriptDir "\.."
CONFIG_FILE := PROJECT_DIR "\config\router.ini"

DETECTOR_COMMAND := IniRead(CONFIG_FILE, "detector", "command", "npm start")
POLL_INTERVAL_MS := ReadInteger("detector", "poll_interval_ms", 100, 1)
DETECTOR_STALE_AFTER_MS := ReadInteger("detector", "stale_after_ms", 3000, 1)

TRANSCRIPTION_PRESS := IniRead(CONFIG_FILE, "transcription_shortcut", "press", "{LCtrl down}{LAlt down}{Up down}")
TRANSCRIPTION_RELEASE := IniRead(CONFIG_FILE, "transcription_shortcut", "release", "{Up up}{LAlt up}{LCtrl up}")
TRANSCRIPTION_HOLD_MS := ReadInteger("transcription_shortcut", "hold_ms", 50)

CLEAR_SELECT := IniRead(CONFIG_FILE, "clear", "select", "^a")
CLEAR_DELETE := IniRead(CONFIG_FILE, "clear", "delete", "{Backspace}")
CLEAR_DELAY_MS := ReadInteger("clear", "delay_ms", 30)

OUTPUT_FILE := A_Temp "\tws-media-router-" DllCall("GetCurrentProcessId") ".log"
Router := RouterState()
Detector := DetectorGate(DETECTOR_STALE_AFTER_MS)
LastReadPosition := 0
DetectorPid := 0

try FileDelete(OUTPUT_FILE)
command := A_ComSpec ' /D /S /C "' DETECTOR_COMMAND ' > ""' OUTPUT_FILE '"" 2>&1"'
Run(command, PROJECT_DIR, "Hide", &DetectorPid)
OnExit(StopDetector)
SetTimer(ReadDetectorOutput, POLL_INTERVAL_MS)

#HotIf ShouldRouteMediaKeys()
Media_Next::{
    global Router
    action := Router.Next()

    if action = "voice"
        TriggerTranscriptionShortcut()
    else
        SendInput("{Enter}")
}

Media_Prev::{
    global Router
    action := Router.Prev(WinExist("A"))

    if action = "clear"
        ClearCurrentInput()
}
#HotIf

ShouldRouteMediaKeys() {
    global Detector, DetectorPid, Router
    pidAlive := DetectorPid && ProcessExist(DetectorPid)
    decision := Detector.GetRouteDecision(pidAlive, A_TickCount)

    if decision = "reset-pass"
        Router.Reset()

    return decision = "route"
}

TriggerTranscriptionShortcut() {
    global TRANSCRIPTION_PRESS, TRANSCRIPTION_RELEASE, TRANSCRIPTION_HOLD_MS
    SendInput(TRANSCRIPTION_PRESS)
    Sleep(TRANSCRIPTION_HOLD_MS)
    SendInput(TRANSCRIPTION_RELEASE)
}

ClearCurrentInput() {
    global CLEAR_SELECT, CLEAR_DELETE, CLEAR_DELAY_MS
    SendInput(CLEAR_SELECT)
    Sleep(CLEAR_DELAY_MS)
    SendInput(CLEAR_DELETE)
}

ReadInteger(section, key, defaultValue, minimum := 0) {
    global CONFIG_FILE
    value := IniRead(CONFIG_FILE, section, key, defaultValue)

    if !RegExMatch(value, "^\d+$") || value + 0 < minimum
        throw Error("Invalid integer in config: " section "." key)

    return value + 0
}

ReadDetectorOutput() {
    global Detector, Router
    global LastReadPosition, OUTPUT_FILE

    if !FileExist(OUTPUT_FILE)
        return

    try {
        output := FileOpen(OUTPUT_FILE, "r")
        if output.Length < LastReadPosition
            LastReadPosition := 0
        output.Pos := LastReadPosition

        while !output.AtEOF {
            line := Trim(output.ReadLine(), " `t`r`n")
            result := Detector.ApplyLine(line, A_TickCount)

            if result = "reset"
                Router.Reset()
        }

        LastReadPosition := output.Pos
        output.Close()
    }
}

StopDetector(*) {
    global DetectorPid, OUTPUT_FILE

    if DetectorPid
        try RunWait("taskkill.exe /PID " DetectorPid " /T /F",, "Hide")

    try FileDelete(OUTPUT_FILE)
}
