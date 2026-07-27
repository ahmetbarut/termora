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
}
