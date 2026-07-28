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

    /// Current working directory of `pid`, read straight from the kernel via libproc.
    ///
    /// `proc_pidinfo` fills a `proc_vnodepathinfo`; `pvi_cdir.vip_path` is a fixed-size C
    /// char tuple, so it is read through `withUnsafeBytes` rather than indexed member by member.
    /// A short return (anything other than the full struct size) means the pid is gone or
    /// not ours, and yields nil.
    nonisolated static func currentWorkingDirectory(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }

        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let path = String(cString: base.assumingMemoryBound(to: CChar.self))
            return path.isEmpty ? nil : path
        }
    }

    /// True while `pid` still exists. A zombie (exited but not yet reaped) also counts as
    /// existing, which is what the SIGTERM -> SIGKILL escalation wants: it reaps in that case.
    /// Only valid for our own children — for foreign processes `kill` may fail with EPERM.
    nonisolated static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}

/// Reads the foreground command of a shell's controlling terminal.
///
/// `proc_bsdinfo.e_tpgid` is the kernel's own answer to `tcgetpgrp(masterFD)` — the
/// foreground process group of the shell's controlling tty — so the pty master descriptor
/// never has to be plumbed out of `SessionManager` just to name the running command.
enum ForegroundProcessProbe {

    /// Name of the process group leader that owns the terminal right now.
    /// nil when the shell itself is in the foreground (no command is running) or the pid is gone.
    nonisolated static func foregroundCommandName(shellPID: pid_t) -> String? {
        guard shellPID > 0, let shell = bsdInfo(pid: shellPID) else { return nil }
        let foregroundGroup = pid_t(bitPattern: shell.e_tpgid)
        guard foregroundGroup > 0,
              foregroundGroup != pid_t(bitPattern: shell.pbi_pgid),
              foregroundGroup != shellPID,
              let leader = bsdInfo(pid: foregroundGroup) else { return nil }
        return commandName(of: leader)
    }

    nonisolated private static func bsdInfo(pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    /// `pbi_name` is the long (up to 32 char) name and is empty for some processes;
    /// `pbi_comm` is the truncated `argv[0]` basename and is always populated.
    nonisolated private static func commandName(of info: proc_bsdinfo) -> String? {
        var info = info
        let long = withUnsafeBytes(of: &info.pbi_name) { cString(in: $0) }
        if !long.isEmpty { return long }
        let short = withUnsafeBytes(of: &info.pbi_comm) { cString(in: $0) }
        return short.isEmpty ? nil : short
    }

    nonisolated private static func cString(in raw: UnsafeRawBufferPointer) -> String {
        guard let base = raw.baseAddress else { return "" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }
}
