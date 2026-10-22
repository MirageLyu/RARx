import Foundation
import Darwin

/// Runs an executable without a shell. Passwords are supplied through stdin,
/// never through argv. Reads stdout/stderr concurrently so large listings cannot
/// deadlock the child process.
final class ProcessRunner: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let stdinData: Data?
    private let environment: [String: String]
    private let currentDirectoryURL: URL?

    private let stateLock = NSLock()
    private var process: Process?
    private var cancellationRequested = false
    private var finished = false

    init(
        executableURL: URL,
        arguments: [String],
        stdin: Data? = nil,
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.stdinData = stdin
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }

    func run(
        onStdout: ((Data) -> Void)? = nil,
        onStderr: ((Data) -> Void)? = nil
    ) throws -> EngineRunOutput {
        stateLock.lock()
        if cancellationRequested {
            stateLock.unlock()
            throw CancellationError()
        }
        let child = Process()
        process = child
        stateLock.unlock()

        child.executableURL = executableURL
        child.arguments = arguments
        if let currentDirectoryURL {
            child.currentDirectoryURL = currentDirectoryURL
        }

        var childEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            childEnvironment[key] = value
        }
        childEnvironment["LC_ALL"] = "en_US.UTF-8"
        childEnvironment["LANG"] = "en_US.UTF-8"
        child.environment = childEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe

        var stdinPipe: Pipe?
        if stdinData != nil {
            let pipe = Pipe()
            stdinPipe = pipe
            child.standardInput = pipe
        } else {
            child.standardInput = FileHandle.nullDevice
        }

        do {
            try child.run()
        } catch {
            stateLock.lock()
            finished = true
            process = nil
            stateLock.unlock()
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stdinPipe?.fileHandleForReading.close()
            throw error
        }

        if let stdinData, let stdinPipe {
            // The password is tiny and the pipe is close to empty. If unrar does
            // not need it (for example, headers are not encrypted), EPIPE is
            // harmless.
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
            } catch {
                AppLog.debug("stdin write ended early: \(error.localizedDescription)")
            }
            try? stdinPipe.fileHandleForWriting.close()
        }

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [stdoutPipe] in
            defer { group.leave() }
            let handle = stdoutPipe.fileHandleForReading
            defer { try? handle.close() }
            while true {
                let data: Data
                do {
                    guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
                    data = chunk
                } catch {
                    break
                }
                stdoutBox.append(data)
                onStdout?(data)
            }
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [stderrPipe] in
            defer { group.leave() }
            let handle = stderrPipe.fileHandleForReading
            defer { try? handle.close() }
            while true {
                let data: Data
                do {
                    guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
                    data = chunk
                } catch {
                    break
                }
                stderrBox.append(data)
                onStderr?(data)
            }
        }

        child.waitUntilExit()
        group.wait()

        stateLock.lock()
        finished = true
        let wasCancelled = cancellationRequested
        let terminationReason = child.terminationReason
        process = nil
        stateLock.unlock()

        let output = EngineRunOutput(
            status: child.terminationStatus,
            stdout: String(decoding: stdoutBox.snapshot(), as: UTF8.self),
            stderr: String(decoding: stderrBox.snapshot(), as: UTF8.self),
            wasCancelled: wasCancelled,
            terminationReason: terminationReason
        )

        if wasCancelled {
            throw CancellationError()
        }
        return output
    }

    /// Suspends the caller while the child runs on a background queue. Task
    /// cancellation terminates the child through the cancellation handler.
    func runAsync(
        onStdout: ((Data) -> Void)? = nil,
        onStderr: ((Data) -> Void)? = nil
    ) async throws -> EngineRunOutput {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    do {
                        let output = try run(onStdout: onStdout, onStderr: onStderr)
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        stateLock.lock()
        cancellationRequested = true
        let child = process
        let isFinished = finished
        stateLock.unlock()

        guard !isFinished, let child, child.isRunning else { return }
        AppLog.debug("Sending SIGTERM to pid \(child.processIdentifier)")
        child.terminate()

        let pid = child.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let stillRunning = !self.finished && child.isRunning
            self.stateLock.unlock()
            if stillRunning {
                AppLog.warning("Engine did not exit after SIGTERM; sending SIGKILL")
                kill(pid, SIGKILL)
            }
        }
    }

    var processIdentifier: Int32? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process?.processIdentifier
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}
