import Darwin
import Foundation

/// posix_spawn with piped stdout and stderr, and TCC responsibility disclaimed for the child
public struct PosixSpawner: Spawner {
    /// Private libsystem symbol, looked up at run time so a missing symbol is a soft failure
    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    private static let setDisclaim: SetDisclaim? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
        .map { unsafeBitCast($0, to: SetDisclaim.self) }

    public init() {}

    public func spawn(_ request: SpawnRequest) throws -> SpawnedProcess {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            throw SpawnError(description: "cannot create a pipe: \(String(cString: strerror(errno)))")
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        var responsibilityDisclaimed = false
        if let setDisclaim = PosixSpawner.setDisclaim {
            let status = setDisclaim(&attributes, 1)
            responsibilityDisclaimed = status == 0
            if status != 0 {
                log.error("responsibility_spawnattrs_setdisclaim failed with \(status), spawning without it")
            }
        } else {
            log.error("responsibility_spawnattrs_setdisclaim is missing, spawning without it")
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], STDERR_FILENO)

        var pid: pid_t = 0
        let argv = [request.executablePath] + request.arguments
        let status = withCStringArray(argv) { argvPointers in
            withCStringArray(request.environment.map { "\($0.key)=\($0.value)" }) { envPointers in
                posix_spawn(&pid, request.executablePath, &fileActions, &attributes, argvPointers, envPointers)
            }
        }

        close(outPipe[1])
        close(errPipe[1])

        guard status == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw SpawnError(description: "posix_spawn \(request.executablePath) failed: \(String(cString: strerror(status)))")
        }

        return SpawnedProcess(
            pid: pid,
            standardOutput: outPipe[0],
            standardError: errPipe[0],
            responsibilityDisclaimed: responsibilityDisclaimed
        )
    }

    public func signal(_ signal: Int32, to pid: pid_t) {
        kill(pid, signal)
    }

    public func wait(for pid: pid_t, completion: @escaping @Sendable (ExitReason) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}

            if status & 0x7f == 0 {
                completion(.exited(code: (status >> 8) & 0xff))
            } else {
                completion(.signaled(signal: status & 0x7f))
            }
        }
    }
}

/// Builds the NULL-terminated char* array posix_spawn wants, valid only inside `body`
private func withCStringArray<R>(_ values: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    let pointers: [UnsafeMutablePointer<CChar>?] = values.map { strdup($0) } + [nil]
    defer { pointers.forEach { free($0) } }
    var mutable = pointers
    return body(&mutable)
}
