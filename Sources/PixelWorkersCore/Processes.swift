import Darwin
import Foundation

// Small, dependency-free views of the process table: who started a process, its terminal and its executable.
public enum Processes {
    static func info(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        guard pid > 1, let parent = info(pid)?.kp_eproc.e_ppid, parent > 0 else { return nil }
        return parent
    }

    /// The process's controlling terminal as a device path, such as /dev/ttys004.
    public static func tty(of pid: pid_t) -> String? {
        guard let device = info(pid)?.kp_eproc.e_tdev, device != -1, device != 0, let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// When the process started, in ms since 1970.
    public static func startTime(_ pid: pid_t) -> Double? {
        guard let start = info(pid)?.kp_proc.p_un.__p_starttime else { return nil }
        return (Double(start.tv_sec) * 1000 + Double(start.tv_usec) / 1000).rounded()
    }

    public static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Claude Code's native install runs as ~/.local/share/claude/versions/<version>; others as `claude`.
    public static func isClaude(path: String) -> Bool {
        (path as NSString).lastPathComponent == "claude" || path.contains("/claude/versions/")
    }

    public static func isClaude(_ pid: pid_t) -> Bool { executable(of: pid).map(isClaude(path:)) ?? false }

    /// The process and its ancestors, nearest first.
    public static func lineage(of pid: pid_t, limit: Int = 32) -> [pid_t] {
        var chain: [pid_t] = [], current: pid_t? = pid
        while let p = current, p > 1, chain.count < limit { chain.append(p); current = parent(of: p) }
        return chain
    }
}
