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
