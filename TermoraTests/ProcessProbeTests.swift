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
}
