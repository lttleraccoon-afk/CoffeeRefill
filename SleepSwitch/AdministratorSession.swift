import Darwin
import Foundation

/// Owns one short-lived, authenticated power-management connection.
final class AdministratorSession: @unchecked Sendable {
    static let shared = AdministratorSession()

    private let queue = DispatchQueue(label: "SleepSwitch.AdministratorSession")
    // Accessed only on queue. The connection closes automatically if the app exits.
    private var channel: FileHandle?

    private init() {}

    func setSleepDisabled(_ disabled: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { try self.setPowerState(disabled) })
            }
        }
    }

    private func setPowerState(_ disabled: Bool) throws {
        if channel == nil {
            channel = try openChannel()
        }
        guard let channel else { throw connectionError }

        let reply: String
        do {
            try channel.write(contentsOf: Data(disabled ? "1\n".utf8 : "0\n".utf8))
            reply = try readReply(from: channel)
        } catch {
            try? channel.close()
            self.channel = nil
            throw connectionError
        }

        if reply != "OK" {
            throw PowerManagement.ChangeError.authorizationFailed("管理员会话中的 pmset 执行失败。")
        }
    }

    private var connectionError: PowerManagement.ChangeError {
        .authorizationFailed("管理员会话已断开，请再次切换以重新授权。")
    }

    private func openChannel() throws -> FileHandle {
        let directory = "/tmp/sleep-switch.\(UUID().uuidString)"
        let path = directory + "/control"
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        defer {
            unlink(path)
            rmdir(directory)
        }

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw posixError() }
        defer { Darwin.close(listener) }
        guard fcntl(listener, F_SETFD, FD_CLOEXEC) == 0 else { throw posixError() }

        var address = sockaddr_un()
        let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        address.sun_len = UInt8(addressSize)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.utf8CString.withUnsafeBytes { destination.copyMemory(from: $0) }
        }

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, addressSize) }
        }
        guard bound == 0, listen(listener, 4) == 0 else { throw posixError() }

        let authorization = Process()
        let errorOutput = Pipe()
        authorization.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        authorization.arguments = ["-e", Self.authorize, "--", Self.worker, path]
        authorization.standardOutput = FileHandle.nullDevice
        authorization.standardError = errorOutput
        try authorization.run()
        var connected = false
        defer {
            if !connected, authorization.isRunning { authorization.terminate() }
        }

        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: .seconds(180))
        var finishedAuthorization = false
        while clock.now < deadline {
            if !finishedAuthorization, !authorization.isRunning {
                finishedAuthorization = true
                if authorization.terminationStatus != 0 {
                    let detail = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if detail.hasSuffix("(-128)") { throw PowerManagement.ChangeError.cancelled }
                    throw PowerManagement.ChangeError.authorizationFailed(detail)
                }
                deadline = min(deadline, clock.now.advanced(by: .seconds(5)))
            }

            guard try readable(listener, timeout: 200) else { continue }
            let peer = accept(listener, nil, nil)
            guard peer >= 0 else { throw posixError() }
            let handle = FileHandle(fileDescriptor: peer, closeOnDealloc: true)

            var uid = uid_t.max
            var gid: gid_t = 0
            guard getpeereid(peer, &uid, &gid) == 0, uid == 0 else {
                try handle.close()
                continue
            }

            var noSignal: Int32 = 1
            guard fcntl(peer, F_SETFD, FD_CLOEXEC) == 0,
                  setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0
            else { throw posixError() }

            guard try readReply(from: handle) == "READY" else { throw connectionError }
            connected = true
            return handle
        }

        throw PowerManagement.ChangeError.authorizationFailed("等待管理员授权或会话连接超时。")
    }

    private func readReply(from handle: FileHandle) throws -> String {
        var bytes: [UInt8] = []
        while bytes.count < 16 {
            guard try readable(handle.fileDescriptor, timeout: 5_000),
                  let byte = try handle.read(upToCount: 1)?.first else { throw connectionError }
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        throw connectionError
    }

    private func readable(_ descriptor: Int32, timeout: Int32) throws -> Bool {
        var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let result = poll(&event, 1, timeout)
        if result < 0, errno != EINTR { throw posixError() }
        return result > 0
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private static let authorize = """
        on run argv
            set workerProgram to item 1 of argv
            set socketPath to item 2 of argv
            do shell script ("/usr/bin/env -i PATH=/usr/bin:/bin /bin/zsh -fc " & quoted form of workerProgram & " -- " & quoted form of socketPath & " </dev/null >/dev/null 2>&1 &") with administrator privileges
        end run
        """

    // Only literal messages 0 and 1 reach the two fixed system commands.
    private static let worker = """
        [[ $EUID == 0 ]] || exit 1
        zmodload zsh/net/socket || exit 1
        zsocket -d 3 "$1" || exit 1
        restore_sleep=0
        TRAPEXIT() {
            if [[ $restore_sleep == 1 ]]; then
                /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1
            fi
        }

        print -r -u 3 -- READY || exit 1
        while IFS= read -r -u 3 requested; do
            case "$requested" in
                1)
                    restore_sleep=1
                    /usr/bin/pmset -a disablesleep 1 && reply=OK || reply=ERROR
                    ;;
                0)
                    if /usr/bin/pmset -a disablesleep 0; then
                        restore_sleep=0
                        reply=OK
                    else
                        reply=ERROR
                    fi
                    ;;
                *) reply=ERROR ;;
            esac
            print -r -u 3 -- "$reply" || exit 1
        done
        """
}
