#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
#Include router-state.ahk

PROJECT_DIR := A_ScriptDir "\.."
CONFIG_FILE := PROJECT_DIR "\config\router.ini"

DETECTOR_COMMAND := IniRead(CONFIG_FILE, "detector", "command", "npm start")
POLL_INTERVAL_MS := ReadInteger("detector", "poll_interval_ms", 100, 1)
DETECTOR_STALE_AFTER_MS := ReadInteger("detector", "stale_after_ms", 3000, 1)
SMTC_GUARD_IDLE_MS := ReadInteger("smtc", "guard_idle_ms", 1500, 100)

TRANSCRIPTION_PRESS := IniRead(CONFIG_FILE, "transcription_shortcut", "press", "{LCtrl down}{LAlt down}{Up down}")
TRANSCRIPTION_RELEASE := IniRead(CONFIG_FILE, "transcription_shortcut", "release", "{Up up}{LAlt up}{LCtrl up}")
TRANSCRIPTION_HOLD_MS := ReadInteger("transcription_shortcut", "hold_ms", 50)

CLEAR_SELECT := IniRead(CONFIG_FILE, "clear", "select", "^a")
CLEAR_DELETE := IniRead(CONFIG_FILE, "clear", "delete", "{Backspace}")
CLEAR_DELAY_MS := ReadInteger("clear", "delay_ms", 30)

PROCESS_ID := DllCall("GetCurrentProcessId")
OUTPUT_FILE := A_Temp "\tws-media-router-" PROCESS_ID ".log"
TRACE_FLAG := A_Temp "\tws-media-router-trace.flag"
TRACE_FILE := A_Temp "\tws-media-router-trace-" PROCESS_ID ".log"
Router := RouterState()
Detector := DetectorGate(DETECTOR_STALE_AFTER_MS)
SmtcCompat := SmtcCompatState(SMTC_GUARD_IDLE_MS)
DeferredNextAction := ""
LastReadPosition := 0
DetectorPid := 0

try FileDelete(OUTPUT_FILE)
command := A_ComSpec ' /D /S /C "' DETECTOR_COMMAND ' > ""' OUTPUT_FILE '"" 2>&1"'
Run(command, PROJECT_DIR, "Hide", &DetectorPid)
OnExit(StopDetector)
SetTimer(ReadDetectorOutput, POLL_INTERVAL_MS)

#HotIf ShouldRouteMediaKeys()
Media_Next::{
    Trace("direct_media", "next")
    ApplyNextRouterAction()
}
Media_Prev::{
    Trace("direct_media", "prev")
    ApplyPrevRouterAction()
}
#HotIf

ShouldRouteMediaKeys() {
    global Detector, DetectorPid, Router
    pidAlive := DetectorPid && ProcessExist(DetectorPid)

    if DetectorPid && !pidAlive
        DetectorPid := 0

    decision := Detector.GetRouteDecision(pidAlive, A_TickCount, Router.CommandActive)

    if decision = "reset-pass"
        Router.Reset()

    return decision = "route"
}

ApplyNextRouterAction() {
    global Router
    action := Router.Next()
    Trace("router_next", action)
    ExecuteNextRouterAction(action)
}

ExecuteNextRouterAction(action) {
    if action = "voice-start" || action = "voice-stop" {
        TriggerTranscriptionShortcut()
        return
    }

    if action = "enter" {
        Trace("send", "Enter")
        SendInput("{Enter}")
    }
}

ApplyPrevRouterAction() {
    global Router
    action := Router.Prev(WinExist("A"))
    Trace("router_prev", action)

    if action = "clear"
        ClearCurrentInput()
}

HandleSmtcAction(action) {
    global SmtcCompat
    tick := A_TickCount
    Trace("smtc_action", action)
    decision := SmtcCompat.HandleAction(action, ShouldRouteMediaKeys(), tick)
    Trace("smtc_decision", decision)

    if decision = "route-next"
        SetTimer(BeginSmtcNextRouterAction, -1)
    else if decision = "route-prev"
        SetTimer(ApplyPrevRouterAction, -1)
    else if decision = "force-pause"
        SetTimer(ForceGuardPause, -1)
}

BeginSmtcNextRouterAction() {
    global Router, DeferredNextAction
    action := Router.Next()
    Trace("router_next", action)

    if action = "voice-start" {
        DeferredNextAction := action
        Trace("router_deferred", action)
        return
    }

    ExecuteNextRouterAction(action)
}

PerformSmtcRestorePrev() {
    global SmtcCompat
    SmtcCompat.Expect(["prev", "pause"], A_TickCount)
    Trace("compensate_send", "Media_Prev")
    SendInput("{Media_Prev}")
    Sleep(80)
    Trace("compensate_send", "Media_Play_Pause")
    SendInput("{Media_Play_Pause}")
}

PerformSmtcRestoreNext() {
    global SmtcCompat
    SmtcCompat.Expect(["next", "pause"], A_TickCount)
    Trace("compensate_send", "Media_Next")
    SendInput("{Media_Next}")
    Sleep(80)
    Trace("compensate_send", "Media_Play_Pause")
    SendInput("{Media_Play_Pause}")
}

ForceGuardPause() {
    global SmtcCompat
    SmtcCompat.Expect(["pause"], A_TickCount)
    Trace("guard_force", "Media_Play_Pause")
    SendInput("{Media_Play_Pause}")
}

TriggerTranscriptionShortcut() {
    global TRANSCRIPTION_PRESS, TRANSCRIPTION_RELEASE, TRANSCRIPTION_HOLD_MS
    Trace("voice_shortcut", "press")
    SendInput(TRANSCRIPTION_PRESS)
    Sleep(TRANSCRIPTION_HOLD_MS)
    SendInput(TRANSCRIPTION_RELEASE)
    Trace("voice_shortcut", "release")
}

ClearCurrentInput() {
    global CLEAR_SELECT, CLEAR_DELETE, CLEAR_DELAY_MS
    Trace("clear", "select")
    SendInput(CLEAR_SELECT)
    Sleep(CLEAR_DELAY_MS)
    SendInput(CLEAR_DELETE)
    Trace("clear", "delete")
}

ReadInteger(section, key, defaultValue, minimum := 0) {
    global CONFIG_FILE
    value := IniRead(CONFIG_FILE, section, key, defaultValue)

    if !RegExMatch(value, "^\d+$") || value + 0 < minimum
        throw Error("Invalid integer in config: " section "." key)

    return value + 0
}

ApplySmtcStateResult(result) {
    global SmtcCompat, DeferredNextAction
    Trace("guard_state", result)

    if result = "compensate-next"
        SetTimer(PerformSmtcRestoreNext, -1)
    else if result = "compensate-prev"
        SetTimer(PerformSmtcRestorePrev, -1)
    else if result = "force-pause"
        SetTimer(ForceGuardPause, -1)
    else if result = "settled" && DeferredNextAction != "" {
        action := DeferredNextAction
        DeferredNextAction := ""
        SmtcCompat.ReleaseGuard()
        Trace("guard", "released-before-recording")
        SetTimer(() => ExecuteNextRouterAction(action), -1)
    }
}

ReadDetectorOutput() {
    global Detector, Router, SmtcCompat, DeferredNextAction
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
            tick := A_TickCount

            if InStr(line, "SMTC:") = 1 {
                HandleSmtcAction(SubStr(line, 6))
                continue
            }

            if InStr(line, "OBS:") = 1 {
                observedState := SubStr(line, 5)
                Trace("detector_observation", observedState)
                ApplySmtcStateResult(SmtcCompat.HandleState(observedState, tick))
                continue
            }

            if line = "." {
                Detector.ApplyLine(line, tick)
                if SmtcCompat.Expire(tick)
                    Trace("guard", "expired")
                continue
            }

            if line = "Playing" || line = "Idle" || line = "Unknown"
                Trace("detector_state", line)

            result := Detector.ApplyLine(line, tick)

            if line = "Unknown" {
                DeferredNextAction := ""
                ApplySmtcStateResult(SmtcCompat.HandleState(line, tick))
            }

            suppressReset := (SmtcCompat.GuardActive || Router.CommandActive) && line != "Unknown"

            if result = "reset" && !suppressReset {
                Trace("router", "reset")
                Router.Reset()
            }
        }

        LastReadPosition := output.Pos
        output.Close()
    }
}

UnixMillis() {
    fileTime := Buffer(8, 0)
    DllCall("GetSystemTimeAsFileTime", "Ptr", fileTime)
    ticks := NumGet(fileTime, 0, "Int64")
    return (ticks - 116444736000000000) // 10000
}

Trace(event, detail := "") {
    global TRACE_FLAG, TRACE_FILE

    if !FileExist(TRACE_FLAG)
        return

    try FileAppend(UnixMillis() "|" event "|" detail "`n", TRACE_FILE, "UTF-8")
}

StopDetector(*) {
    global DetectorPid, OUTPUT_FILE

    if DetectorPid && ProcessExist(DetectorPid)
        try RunWait("taskkill.exe /PID " DetectorPid " /T /F",, "Hide")

    DetectorPid := 0
    try FileDelete(OUTPUT_FILE)
}
