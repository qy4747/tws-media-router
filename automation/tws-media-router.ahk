#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

PROJECT_DIR := A_ScriptDir "\.."
CONFIG_FILE := PROJECT_DIR "\config\router.ini"

DETECTOR_COMMAND := IniRead(CONFIG_FILE, "detector", "command", "npm start")
POLL_INTERVAL_MS := ReadInteger("detector", "poll_interval_ms", 100, 1)

TRANSCRIPTION_PRESS := IniRead(CONFIG_FILE, "transcription_shortcut", "press", "{LCtrl down}{LAlt down}{Up down}")
TRANSCRIPTION_RELEASE := IniRead(CONFIG_FILE, "transcription_shortcut", "release", "{Up up}{LAlt up}{LCtrl up}")
TRANSCRIPTION_HOLD_MS := ReadInteger("transcription_shortcut", "hold_ms", 50)

CLEAR_SELECT := IniRead(CONFIG_FILE, "clear", "select", "^a")
CLEAR_DELETE := IniRead(CONFIG_FILE, "clear", "delete", "{Backspace}")
CLEAR_DELAY_MS := ReadInteger("clear", "delay_ms", 30)

OUTPUT_FILE := A_Temp "\tws-media-router-" DllCall("GetCurrentProcessId") ".log"
CloudMusicPlaying := false
DetectorReady := false
NextPressCount := 0
PrevPressCount := 0
LastReadPosition := 0
DetectorPid := 0

try FileDelete(OUTPUT_FILE)
command := A_ComSpec ' /D /S /C "' DETECTOR_COMMAND ' > ""' OUTPUT_FILE '"" 2>&1"'
Run(command, PROJECT_DIR, "Hide", &DetectorPid)
OnExit(StopDetector)
SetTimer(ReadDetectorOutput, POLL_INTERVAL_MS)

#HotIf ShouldRouteMediaKeys()
Media_Next::{
    global NextPressCount, PrevPressCount
    PrevPressCount := 0
    NextPressCount := Mod(NextPressCount, 3) + 1

    if NextPressCount <= 2
        TriggerTranscriptionShortcut()
    else
        SendInput("{Enter}")
}

Media_Prev::{
    global NextPressCount, PrevPressCount
    PrevPressCount := Mod(PrevPressCount, 2) + 1

    if PrevPressCount = 1
        NextPressCount := 0
    else
        ClearCurrentInput()
}
#HotIf

ShouldRouteMediaKeys() {
    global DetectorReady, DetectorPid, CloudMusicPlaying
    return DetectorReady && DetectorPid && ProcessExist(DetectorPid) && !CloudMusicPlaying
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
    global CloudMusicPlaying, DetectorReady
    global NextPressCount, PrevPressCount
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
            if line = "Playing" || line = "true"
                newState := true
            else if line = "Idle" || line = "false"
                newState := false
            else if line = "Unknown" {
                DetectorReady := false
                NextPressCount := 0
                PrevPressCount := 0
                continue
            }
            else
                continue

            if !DetectorReady || CloudMusicPlaying != newState {
                DetectorReady := true
                CloudMusicPlaying := newState
                NextPressCount := 0
                PrevPressCount := 0
            }
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
