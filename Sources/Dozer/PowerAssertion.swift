import Foundation
import IOKit.pwr_mgt

/// Thin wrapper around IOKit power assertions — the same mechanism
/// `caffeinate` uses. Holding an assertion stops idle sleep; releasing it
/// hands control back to macOS' normal Energy settings.
final class PowerAssertion {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0

    var isHoldingSystem: Bool { systemID != 0 }
    var isHoldingDisplay: Bool { displayID != 0 }

    func update(holdSystem: Bool, holdDisplay: Bool, reason: String) {
        set(&systemID, active: holdSystem, type: kIOPMAssertionTypePreventUserIdleSystemSleep, reason: reason)
        set(&displayID, active: holdSystem && holdDisplay, type: kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: reason)
    }

    func releaseAll() {
        update(holdSystem: false, holdDisplay: false, reason: "")
    }

    private func set(_ id: inout IOPMAssertionID, active: Bool, type: String, reason: String) {
        if active, id == 0 {
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess { id = newID }
        } else if !active, id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
    }

    deinit { releaseAll() }
}
