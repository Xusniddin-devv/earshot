import Darwin

public protocol ProcessTree {
    func parent(of pid: Int32) -> Int32?
    /// Device name without `/dev/`, e.g. `ttys002`, or nil when the process has no terminal.
    func tty(of pid: Int32) -> String?
}

/// Reads the real process table with sysctl.
public struct SysctlProcessTree: ProcessTree {
    public init() {}

    private func info(_ pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        return proc
    }

    public func parent(of pid: Int32) -> Int32? {
        guard let p = info(pid)?.kp_eproc.e_ppid, p > 0 else { return nil }
        return p
    }

    /// Last path component of the process's argv[0], e.g. `claude` (what `ps -o comm=` shows).
    /// Not `p_comm`: Claude Code's binary is a version-named file, so that reads e.g. `2.1.303`.
    public func name(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        // Layout: argc (Int32), exec path, NUL padding, argv[0], …
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }
        while i < size, buf[i] == 0 { i += 1 }
        var j = i
        while j < size, buf[j] != 0 { j += 1 }
        guard j > i else { return nil }
        return String(decoding: buf[i..<j], as: UTF8.self).split(separator: "/").last.map(String.init)
    }

    public func tty(of pid: Int32) -> String? {
        // NODEV (-1) means no controlling terminal.
        guard let dev = info(pid)?.kp_eproc.e_tdev, dev != -1, dev != 0 else { return nil }
        guard let name = devname(dev, S_IFCHR) else { return nil }
        let s = String(cString: name)
        return s.isEmpty || s == "??" ? nil : s
    }
}

/// Walks up from `start` to the first process that owns a terminal.
/// Claude Code runs hooks without a terminal, but the `claude` process itself has one.
public func resolveTTY(start: Int32, tree: ProcessTree) -> String? {
    var pid = start
    var seen = Set<Int32>()
    for _ in 0..<32 {
        guard seen.insert(pid).inserted else { return nil }
        if let t = tree.tty(of: pid) { return "/dev/" + t }
        guard let p = tree.parent(of: pid) else { return nil }
        pid = p
    }
    return nil
}
