class RouterState {
    __New() {
        this.Reset()
    }

    Reset() {
        this.NextPressCount := 0
        this.PrevPressCount := 0
        this.PrevWindowHwnd := 0
    }

    Next() {
        this.PrevPressCount := 0
        this.PrevWindowHwnd := 0
        this.NextPressCount := Mod(this.NextPressCount, 3) + 1
        return this.NextPressCount <= 2 ? "voice" : "enter"
    }

    Prev(activeHwnd) {
        this.PrevPressCount := Mod(this.PrevPressCount, 2) + 1

        if this.PrevPressCount = 1 {
            this.NextPressCount := 0
            this.PrevWindowHwnd := activeHwnd
            return "reset"
        }

        if !this.PrevWindowHwnd || activeHwnd != this.PrevWindowHwnd {
            this.PrevPressCount := 0
            this.PrevWindowHwnd := 0
            return "cancel"
        }

        this.PrevWindowHwnd := 0
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

    GetRouteDecision(pidAlive, tick) {
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

        return this.PlayerPlaying ? "pass" : "route"
    }
}


class SmtcCompatState {
    __New(cycleTimeoutMs := 3000, echoTimeoutMs := 2000) {
        this.CycleTimeoutMs := cycleTimeoutMs
        this.EchoTimeoutMs := echoTimeoutMs
        this.ExpectedActions := []
        this.ExpectedDeadlineTick := 0
        this.ResetCycle()
    }

    ResetCycle() {
        this.Active := false
        this.PendingAction := ""
        this.AwaitIdle := false
        this.StartedTick := 0
    }

    Reset() {
        this.ResetCycle()
        this.ExpectedActions := []
        this.ExpectedDeadlineTick := 0
    }

    NormalizeAction(action) {
        normalized := StrLower(action)
        return normalized = "previous" ? "prev" : normalized
    }

    Expire(tick) {
        cycleExpired := false

        if this.Active && tick - this.StartedTick > this.CycleTimeoutMs {
            this.ResetCycle()
            cycleExpired := true
        }

        if this.ExpectedActions.Length && tick > this.ExpectedDeadlineTick {
            this.ExpectedActions := []
            this.ExpectedDeadlineTick := 0
        }

        return cycleExpired
    }

    HandleAction(action, canRoute, tick) {
        this.Expire(tick)
        action := this.NormalizeAction(action)

        if this.ExpectedActions.Length {
            if action = this.ExpectedActions[1] {
                this.ExpectedActions.RemoveAt(1)
                if !this.ExpectedActions.Length
                    this.ExpectedDeadlineTick := 0
                return "echo"
            }

            this.ExpectedActions := []
            this.ExpectedDeadlineTick := 0
        }

        if action != "next" && action != "prev"
            return "ignore"

        if !canRoute || this.Active
            return "ignore"

        this.Active := true
        this.PendingAction := action
        this.AwaitIdle := false
        this.StartedTick := tick
        return action = "next" ? "pending-next" : "pending-prev"
    }

    HandleState(state, tick) {
        if this.Expire(tick)
            return "expired"

        if state = "Unknown" {
            this.Reset()
            return "abort"
        }

        if !this.Active
            return "normal"

        if state = "Playing" && this.PendingAction != "" {
            action := this.PendingAction
            this.PendingAction := ""
            this.AwaitIdle := true

            if action = "next"
                this.Expect(["prev", "pause"], tick)
            else
                this.Expect(["next", "pause"], tick)

            return action = "next" ? "compensate-next" : "compensate-prev"
        }

        if state = "Idle" && this.AwaitIdle {
            this.ResetCycle()
            return "complete"
        }

        return "active"
    }

    Expect(actions, tick) {
        this.ExpectedActions := []
        for action in actions
            this.ExpectedActions.Push(this.NormalizeAction(action))

        this.ExpectedDeadlineTick := tick + this.EchoTimeoutMs
    }
}
