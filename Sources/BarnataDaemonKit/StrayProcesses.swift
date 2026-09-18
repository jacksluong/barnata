import Darwin
import Foundation

/// Finds processes by executable path, so a starting daemon can reap children an older one left behind
public enum StrayProcesses {
    public static func pids(forExecutable path: String) -> [pid_t] {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, size)
        guard written > 0 else { return [] }

        // PROC_PIDPATHINFO_MAXSIZE is not exposed to Swift; it is four times MAXPATHLEN
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(written) / MemoryLayout<pid_t>.size).filter { pid in
            guard pid > 0 else { return false }
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { return false }
            return String(decoding: buffer[..<Int(length)], as: UTF8.self) == path
        }
    }
}
