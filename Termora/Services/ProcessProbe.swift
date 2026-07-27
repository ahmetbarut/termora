//
//  ProcessProbe.swift
//  Termora
//

import Darwin
import Foundation

/// Dependency-free wrappers around the POSIX / libproc calls Termora needs in order to
/// reason about the shell processes it started. Everything here is `nonisolated` on
/// purpose: these are plain syscalls and they are called from GCD blocks that carry no
/// actor isolation.
enum ProcessProbe {

    /// True when the pseudo-terminal's foreground process group is something other than the
    /// shell itself, i.e. the user is running a command right now.
    ///
    /// `tcgetpgrp` returns -1 for a closed or invalid descriptor; per the design doc that
    /// counts as "nothing is running" so a torn-down session never blocks a close.
    nonisolated static func hasForegroundJob(masterFD: Int32, shellPID: pid_t) -> Bool {
        let foregroundGroup = tcgetpgrp(masterFD)
        guard foregroundGroup > 0 else { return false }
        return foregroundGroup != shellPID
    }

    /// True while `pid` still exists. A zombie (exited but not yet reaped) also counts as
    /// existing, which is what the SIGTERM -> SIGKILL escalation wants: it reaps in that case.
    /// Only valid for our own children — for foreign processes `kill` may fail with EPERM.
    nonisolated static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}
