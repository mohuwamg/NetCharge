import Foundation
import Darwin

public final class SingleInstanceLock {
    public enum LockError: Error, Equatable {
        case alreadyRunning
        case unavailable(Int32)
    }

    private let descriptor: Int32

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetCharge", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    public init(fileURL: URL = SingleInstanceLock.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let fd = open(fileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LockError.unavailable(errno) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK { throw LockError.alreadyRunning }
            throw LockError.unavailable(code)
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
