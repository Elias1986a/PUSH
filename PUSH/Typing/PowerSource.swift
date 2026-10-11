import Foundation
import IOKit.ps

/// Whether the Mac is running on battery, or in Low Power Mode — when "Pause
/// on battery" is on, Type stands down in either.
enum PowerSource {
    static var shouldConserve: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || onBattery
    }

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
