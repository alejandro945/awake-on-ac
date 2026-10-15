// awake-on-ac: keep a MacBook awake with the lid closed while it is on AC power,
// and let it sleep normally on battery.
//
// Why: with the lid closed, macOS only stays awake in clamshell mode (AC power plus an active
// external display). When a KVM switch moves the display to another computer, clamshell mode
// ends and the MacBook goes to sleep. `pmset disablesleep 1` prevents that; this agent turns
// it on only while the Mac is on AC power.
//
// How: it subscribes to IOKit power-source notifications, so it reacts instantly and does not
// poll.
//   on AC power -> sudo -n pmset -a disablesleep 1
//   on battery  -> sudo -n pmset -a disablesleep 0; if the lid is already closed and macOS says
//                  that would put it to sleep (no external display), pmset sleepnow. This covers
//                  "unplugged it, closed it, put it in the bag".
//   on SIGTERM  -> sudo -n pmset -a disablesleep 0, so stopping or uninstalling the agent never
//                  leaves the Mac unable to sleep.
//
// Requires /etc/sudoers.d/awake-on-ac (NOPASSWD for exactly those two pmset commands).
// Build: swiftc -O src/awake-on-ac.swift -o build/awake-on-ac

import Foundation
import IOKit
import IOKit.ps

let version = "1.0.0"

let usage = """
    usage: awake-on-ac [--dry-run] [--once] [--no-notify] [--version] [--help]

      --dry-run    log what it would do, change nothing (no pmset, no notifications)
      --once       apply the current power state and exit (no subscription)
      --no-notify  do not show macOS notifications
    """

// MARK: - Options

struct Options {
    var dryRun = false
    var once = false
    var notify = true
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    for argument in arguments.dropFirst() {
        switch argument {
        case "--dry-run": options.dryRun = true
        case "--once": options.once = true
        case "--no-notify": options.notify = false
        case "--version": print("awake-on-ac \(version)"); exit(0)
        case "--help", "-h": print(usage); exit(0)
        default:
            FileHandle.standardError.write(Data("unknown option: \(argument)\n\(usage)\n".utf8))
            exit(64)
        }
    }
    return options
}

let options = parseOptions(CommandLine.arguments)

// MARK: - Helpers

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter.string(
        from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
    print("\(timestamp) \(message)")
    fflush(stdout)
}

@discardableResult
func run(_ command: [String]) -> Int32 {
    if options.dryRun {
        log("dry-run: \(command.joined(separator: " "))")
        return 0
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())
    do {
        try process.run()
    } catch {
        log("could not run \(command[0]): \(error)")
        return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
}

func notify(_ title: String, _ text: String) {
    guard options.notify, !options.dryRun else { return }
    run(["/usr/bin/osascript", "-e", "display notification \"\(text)\" with title \"\(title)\""])
}

func isOnACPower() -> Bool {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    return source == kIOPSACPowerValue
}

/// Reads a boolean from IOPMrootDomain. AppleClamshellState: the lid is closed.
/// AppleClamshellCausesSleep: macOS would sleep because of it (lid closed, no external display).
func powerManagementFlag(_ name: String) -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    let value = IORegistryEntryCreateCFProperty(root, name as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    return (value as? Bool) ?? false
}

@discardableResult
func setSleepDisabled(_ disabled: Bool) -> Bool {
    let status = run(["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"])
    if status != 0 {
        log("pmset exited with \(status): check /etc/sudoers.d/awake-on-ac")
        notify("awake-on-ac", "Could not change sleep settings: check the sudoers rule")
    }
    return status == 0
}

// MARK: - Main logic

/// The power-source notification also fires on every battery percentage change: act only when
/// the source itself changes.
var lastOnAC: Bool?

func apply() {
    let onAC = isOnACPower()
    if onAC == lastOnAC { return }
    lastOnAC = onAC

    guard setSleepDisabled(onAC) else { return }

    if onAC {
        log("on AC power -> disablesleep 1")
        notify("Always awake", "On AC power: stays awake even with the lid closed")
        return
    }

    log("on battery -> disablesleep 0")
    notify("Normal sleep", "On battery: sleeps as usual")

    // Unplugged with the lid already closed: macOS does not always go to sleep by itself.
    Thread.sleep(forTimeInterval: 2)
    if powerManagementFlag("AppleClamshellState"),
        powerManagementFlag("AppleClamshellCausesSleep"),
        !isOnACPower()
    {
        log("lid closed with no external display -> pmset sleepnow")
        run(["/usr/bin/pmset", "sleepnow"])
    }
}

log("starting awake-on-ac \(version)\(options.dryRun ? " (dry run)" : "")")
apply()
if options.once { exit(0) }

// Restore normal sleep when launchd stops the agent (logout, bootout, uninstall).
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalSources = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        log("stopping (signal \(number)) -> disablesleep 0")
        setSleepDisabled(false)
        exit(0)
    }
    source.resume()
    return source
}

guard let runLoopSource = IOPSNotificationCreateRunLoopSource({ _ in apply() }, nil)?.takeRetainedValue()
else {
    log("could not subscribe to power-source notifications")
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
CFRunLoopRun()
