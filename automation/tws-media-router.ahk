#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

PROJECT_DIR := A_ScriptDir "\.."
CONFIG_FILE := PROJECT_DIR "\config\router.ini"

DETECTOR_COMMAND := IniRead(CONFIG_FILE, "detector", "command", "npm start")
POLL_INTERVAL_MS := ReadInteger("detector", "poll_interval_ms", 100, 1)
NEXT_ACTIONS := ReadActions("next")
PREV_ACTIONS := ReadActions("prev")

VOICE_PRESS := IniRead(CONFIG_FILE, "voice", "press", "{LCtrl down}{LAlt down}{Up down}")
VOICE_RELEASE := IniRead(CONFIG_FILE, "voice", "release", "{Up up}{LAlt up}{LCtrl up}")
VOICE_HOLD_MS := ReadInteger("voice", "hold_ms", 50)

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
    global NextPressCount, PrevPressCount, NEXT_ACTIONS
    PrevPressCount := 0
    RunActionSequence(NEXT_ACTIONS, &NextPressCount)
}

Media_Prev::{
    global PrevPressCount, PREV_ACTIONS
    RunActionSequence(PREV_ACTIONS, &PrevPressCount)
}
#HotIf

ShouldRouteMediaKeys() {
    global DetectorReady, DetectorPid, CloudMusicPlaying
    return DetectorReady && DetectorPid && ProcessExist(DetectorPid) && !CloudMusicPlaying
}

RunActionSequence(actions, &position) {
    position := Mod(position, actions.Length) + 1
    ExecuteAction(actions[position])
}

ExecuteAction(action) {
    switch action {
        case "voice":
            TriggerVoiceTranscription()
        case "enter":
            SendInput("{Enter}")
        case "reset":
            ResetNextState()
        case "clear":
            ClearCurrentInput()
    }
}

TriggerVoiceTranscription() {
    global VOICE_PRESS, VOICE_RELEASE, VOICE_HOLD_MS
    SendInput(VOICE_PRESS)
    Sleep(VOICE_HOLD_MS)
    SendInput(VOICE_RELEASE)
}

ResetNextState() {
    global NextPressCount
    NextPressCount := 0
}

ClearCurrentInput() {
    global CLEAR_SELECT, CLEAR_DELETE, CLEAR_DELAY_MS
    SendInput(CLEAR_SELECT)
    Sleep(CLEAR_DELAY_MS)
    SendInput(CLEAR_DELETE)
}

ReadActions(key) {
    global CONFIG_FILE
    actions := []

    for action in StrSplit(IniRead(CONFIG_FILE, "actions", key), ",") {
        action := Trim(action)
        if action = "voice" || action = "enter" || action = "reset" || action = "clear"
            actions.Push(action)
        else
            throw Error("Unsupported action in config: " action)
    }

    if actions.Length = 0
        throw Error("Action sequence cannot be empty: " key)

    return actions
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
