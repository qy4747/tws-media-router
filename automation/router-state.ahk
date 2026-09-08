class RouterState {
    __New() {
        this.Reset()
    }

    Reset() {
        this.NextPressCount := 0
        this.PrevPressCount := 0
        this.PrevWindowHwnd := 0
        this.CommandActive := false
    }

    Next() {
        this.PrevPressCount := 0
        this.PrevWindowHwnd := 0
        this.NextPressCount := Mod(this.NextPressCount, 3) + 1

        if this.NextPressCount = 1 {
            this.CommandActive := true
            return "voice-start"
        }

        if this.NextPressCount = 2 {
            this.CommandActive := true
            return "voice-stop"
        }

        this.CommandActive := false
        return "enter"
    }

    Prev(activeHwnd) {
        this.PrevPressCount := Mod(this.PrevPressCount, 2) + 1

        if this.PrevPressCount = 1 {
            this.NextPressCount := 0
            this.PrevWindowHwnd := activeHwnd
            this.CommandActive := true
            return "reset"
        }

        if !this.PrevWindowHwnd || activeHwnd != this.PrevWindowHwnd {
            this.PrevPressCount := 0
            this.PrevWindowHwnd := 0
            this.CommandActive := false
            return "cancel"
        }

        this.PrevWindowHwnd := 0
        this.CommandActive := false
        return "clear"
    }
}

class DetectorGate {
    __New(staleAfterMs) {
        this.StaleAfterMs := staleAfterMs
        this.Ready := false
        this.PlayerPlaying := false
        this.LastUpdateTick := 0
    }

    ApplyLine(line, tick) {
        if line = "." {
            if this.Ready
                this.LastUpdateTick := tick
            return "heartbeat"
        }

        if line = "Unknown" {
            this.Ready := false
            this.LastUpdateTick := tick
            return "reset"
        }

        if line = "Playing" || line = "true"
            newPlaying := true
        else if line = "Idle" || line = "false"
            newPlaying := false
        else
            return "ignore"

        changed := !this.Ready || this.PlayerPlaying != newPlaying
        this.Ready := true
        this.PlayerPlaying := newPlaying
        this.LastUpdateTick := tick
        return changed ? "reset" : "state"
    }

    GetRouteDecision(pidAlive, tick, allowPlaying := false) {
        if !pidAlive {
            if this.Ready {
                this.Ready := false
                return "reset-pass"
            }
            return "pass"
        }

        if !this.Ready
            return "pass"

        if tick - this.LastUpdateTick > this.StaleAfterMs {
            this.Ready := false
            return "reset-pass"
        }

        return this.PlayerPlaying && !allowPlaying ? "pass" : "route"
    }
}


class SmtcCompatState {
    __New(guardIdleMs := 1500, echoTimeoutMs := 750) {
        this.GuardIdleMs := guardIdleMs
        this.EchoTimeoutMs := echoTimeoutMs
        this.Reset()
    }

    Reset() {
        this.ReleaseGuard()
        this.ExpectedActions := []
        this.ExpectedDeadlineTick := 0
    }

    ReleaseGuard() {
        this.GuardActive := false
        this.GuardDeadlineTick := 0
        this.PendingRestores := []
        this.CompensationInFlight := false
        this.PauseAcknowledged := false
    }

    NormalizeAction(action) {
        normalized := StrLower(action)
        return normalized = "previous" ? "prev" : normalized
    }

    Expire(tick) {
        expired := false

        if this.GuardActive && tick > this.GuardDeadlineTick {
            this.ReleaseGuard()
            expired := true
        }

        if this.ExpectedActions.Length && tick > this.ExpectedDeadlineTick {
            this.ExpectedActions := []
            this.ExpectedDeadlineTick := 0
        }

        return expired
    }

    HandleAction(action, canStart, tick) {
        this.Expire(tick)
        action := this.NormalizeAction(action)

        if this.ExpectedActions.Length && action = this.ExpectedActions[1] {
            this.ExpectedActions.RemoveAt(1)
            pauseConfirmed := action = "pause"
            if pauseConfirmed
                this.PauseAcknowledged := true
            if !this.ExpectedActions.Length
                this.ExpectedDeadlineTick := 0
            return pauseConfirmed ? "pause-confirmed" : "echo"
        }

        if action = "play"
            return this.GuardActive ? "force-pause" : "ignore"

        if action = "pause"
            return "ignore"

        if action != "next" && action != "prev"
            return "ignore"

        if !this.GuardActive {
            if !canStart
                return "ignore"

            this.GuardActive := true
        }

        this.GuardDeadlineTick := tick + this.GuardIdleMs
        this.PendingRestores.Push(action = "next" ? "prev" : "next")
        return action = "next" ? "route-next" : "route-prev"
    }

    HandleState(state, tick) {
        expired := this.Expire(tick)

        if state = "Unknown" {
            this.Reset()
            return "abort"
        }

        if !this.GuardActive
            return expired ? "expired" : "normal"

        if state = "Playing" {
            if this.CompensationInFlight {
                if !this.PauseAcknowledged
                    return "guard"

                this.CompensationInFlight := false
                this.PauseAcknowledged := false
            }

            if this.PendingRestores.Length {
                restore := this.PendingRestores.RemoveAt(1)
                this.CompensationInFlight := true
                this.PauseAcknowledged := false
                return restore = "prev" ? "compensate-prev" : "compensate-next"
            }

            this.CompensationInFlight := true
            this.PauseAcknowledged := false
            return "force-pause"
        }

        if state = "Idle" && this.CompensationInFlight {
            this.CompensationInFlight := false
            this.PauseAcknowledged := false

            if this.PendingRestores.Length {
                restore := this.PendingRestores.RemoveAt(1)
                this.CompensationInFlight := true
                return restore = "prev" ? "compensate-prev" : "compensate-next"
            }

            return "settled"
        }

        return "guard"
    }

    Expect(actions, tick) {
        this.ExpectedActions := []
        for action in actions
            this.ExpectedActions.Push(this.NormalizeAction(action))

        this.ExpectedDeadlineTick := tick + this.EchoTimeoutMs
    }
}
