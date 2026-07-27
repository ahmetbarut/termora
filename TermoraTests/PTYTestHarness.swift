//
//  PTYTestHarness.swift
//  TermoraTests
//

import Darwin
import Foundation

/// A child process running on the far side of a real pseudo-terminal.
struct PTYChild {
    let master: Int32
    let pid: pid_t
}

/// Spawns real processes on real PTYs so `ProcessProbe` can be tested against the kernel
/// behaviour it actually wraps, instead of against a mock of our own assumptions.
///
/// `forkpty` is used rather than `posix_spawn`: only forkpty gives the child a controlling
/// terminal with `setsid` + `TIOCSCTTY`, which is the precondition for shell job control —
/// and job control is exactly what `hasForegroundJob` observes.
enum PTYTestHarness {

    static func spawn(
        executable: String,
        args: [String] = [],
        environment: [String] = [
            "TERM=xterm-256color",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
        ]
    ) -> PTYChild {
        // Everything the child touches is allocated before the fork: after fork() in a
        // multithreaded process only async-signal-safe work is legal until exec.
        let path = strdup(executable)!
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
        envp.append(nil)

        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = 0
        let pid = forkpty(&master, nil, nil, &size)
        precondition(pid >= 0, "forkpty failed: \(String(cString: strerror(errno)))")

        if pid == 0 {
            execve(path, &argv, &envp)
            _exit(127)
        }

        free(path)
        for pointer in argv { free(pointer) }
        for pointer in envp { free(pointer) }
        return PTYChild(master: master, pid: pid)
    }

    /// Reads whatever the child wrote for `seconds`. A real terminal always drains its master
    /// descriptor; without this the PTY buffer fills, the shell blocks on write, and the
    /// command under test never actually starts.
    @discardableResult
    static func drain(_ child: PTYChild, seconds: Double) -> String {
        var text = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        let flags = fcntl(child.master, F_GETFL, 0)
        _ = fcntl(child.master, F_SETFL, flags | O_NONBLOCK)

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let count = read(child.master, &buffer, buffer.count)
            if count > 0 {
                text += String(decoding: buffer[0..<count], as: UTF8.self)
            } else {
                usleep(20_000)
            }
        }

        _ = fcntl(child.master, F_SETFL, flags)
        return text
    }

    static func write(_ child: PTYChild, _ text: String) {
        text.withCString { _ = Darwin.write(child.master, $0, strlen($0)) }
    }

    /// Polls `condition` while draining, up to `timeout` seconds.
    static func waitUntil(_ child: PTYChild, timeout: Double, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            drain(child, seconds: 0.05)
        }
        return condition()
    }

    /// SIGKILL, reap, close the master descriptor. Safe to call more than once per test run
    /// only through `defer` — the descriptor is closed here.
    static func kill(_ child: PTYChild) {
        Darwin.kill(child.pid, SIGKILL)
        var status: Int32 = 0
        waitpid(child.pid, &status, 0)
        close(child.master)
    }
}
