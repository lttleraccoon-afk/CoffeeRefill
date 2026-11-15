import Foundation
import IOKit

enum PowerManagement {
    enum ChangeError: Error {
        case cancelled
        case authorizationFailed(String)
        case stateMismatch
    }

    struct DisplayCommandError: LocalizedError {
        let detail: String

        var errorDescription: String? { detail.isEmpty ? "命令未成功完成。" : detail }
    }

    static func sleepDisabled() -> Bool? {
        readRootDomain { rootDomainFlag("SleepDisabled", from: $0) }
    }

    static func lidMonitorState() -> (sleepDisabled: Bool?, lidClosed: Bool?) {
        readRootDomain { service in
            let disabled = rootDomainFlag("SleepDisabled", from: service)
            let closed = disabled == false ? nil : rootDomainFlag("AppleClamshellState", from: service)
            return (disabled, closed)
        } ?? (nil, nil)
    }

    private static func readRootDomain<T>(_ read: (io_service_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return read(service)
    }

    private static func rootDomainFlag(_ key: String, from service: io_service_t) -> Bool? {
        let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return property?.takeRetainedValue() as? Bool
    }

    static func setSleepDisabled(_ disabled: Bool) async throws {
        try await AdministratorSession.shared.setSleepDisabled(disabled)

        for _ in 0..<20 {
            if sleepDisabled() == disabled { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ChangeError.stateMismatch
    }

    static func setDisplayAwake(_ awake: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            let result = awake
                ? try runCommand("/usr/bin/caffeinate", arguments: ["-u", "-t", "1"])
                : try runCommand("/usr/bin/pmset", arguments: ["displaysleepnow"])

            // pmset may report a display error on stderr with a zero exit status.
            guard result.status == 0, result.detail.isEmpty else {
                throw DisplayCommandError(detail: result.detail)
            }
        }.value
    }

    private static func runCommand(_ executable: String, arguments: [String]) throws -> (status: Int32, detail: String) {
        let process = Process()
        let errorOutput = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput

        try process.run()
        let data = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let detail = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, detail)
    }
}
