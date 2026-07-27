//
//  ProcessProbeTests.swift
//  TermoraTests
//

import Darwin
import Foundation
import Testing
@testable import Termora

struct ProcessProbeTests {

    @Test func aClosedOrInvalidMasterDescriptorReportsNoForegroundJob() {
        // tcgetpgrp() returns -1 for a closed/invalid descriptor; that must read as "idle",
        // never as "busy", otherwise closing a tab would always ask for confirmation.
        #expect(ProcessProbe.hasForegroundJob(masterFD: -1, shellPID: 1234) == false)
    }

    @Test func livenessFollowsProcessExistence() {
        #expect(ProcessProbe.isAlive(pid: getpid()) == true)
        #expect(ProcessProbe.isAlive(pid: 999_999) == false)
    }

    @Test func nonPositivePidsAreNeverAlive() {
        // kill(0, 0) would signal our own process group, so pid <= 0 must short-circuit.
        #expect(ProcessProbe.isAlive(pid: 0) == false)
        #expect(ProcessProbe.isAlive(pid: -1) == false)
    }

    @Test func readsTheWorkingDirectoryOfThisProcessFromTheKernel() {
        // libproc, not OSC 7: a stock zsh only emits OSC 7 under Terminal.app.
        #expect(ProcessProbe.currentWorkingDirectory(pid: getpid()) == FileManager.default.currentDirectoryPath)
    }

    @Test func theWorkingDirectoryOfAnImpossiblePidIsNil() {
        #expect(ProcessProbe.currentWorkingDirectory(pid: 999_999) == nil)
        #expect(ProcessProbe.currentWorkingDirectory(pid: 0) == nil)
        #expect(ProcessProbe.currentWorkingDirectory(pid: -1) == nil)
    }

    @Test func anIdleShellIsIdleAndAForegroundCommandIsNot() {
        let child = PTYTestHarness.spawn(executable: "/bin/zsh", args: ["-f", "-i"])
        defer { PTYTestHarness.kill(child) }

        PTYTestHarness.drain(child, seconds: 1.0)
        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid) == false)

        PTYTestHarness.write(child, "sleep 5\n")
        let busy = PTYTestHarness.waitUntil(child, timeout: 5) {
            ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid)
        }
        #expect(busy, "zsh puts `sleep` in its own process group and tcsetpgrp's it to the front")
    }

    @Test func theForegroundGroupIsComparedAgainstTheShellPid() {
        // /bin/sleep is the session leader here, so the foreground group *is* the child pid.
        let child = PTYTestHarness.spawn(executable: "/bin/sleep", args: ["5"])
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.3)

        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid) == false)
        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: getpid()) == true)
    }

    @Test func aKilledChildIsDeadAndItsClosedDescriptorIsIdle() {
        let child = PTYTestHarness.spawn(executable: "/bin/sleep", args: ["30"])
        #expect(ProcessProbe.isAlive(pid: child.pid) == true)

        PTYTestHarness.kill(child) // SIGKILL + waitpid + close(master)

        #expect(ProcessProbe.isAlive(pid: child.pid) == false)
        #expect(ProcessProbe.hasForegroundJob(masterFD: child.master, shellPID: child.pid) == false)
    }

    @Test func aChildSeesTheWorkingDirectoryItWasStartedIn() {
        let child = PTYTestHarness.spawn(executable: "/bin/sleep", args: ["5"])
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.3)

        #expect(ProcessProbe.currentWorkingDirectory(pid: child.pid) == FileManager.default.currentDirectoryPath)
    }
}
