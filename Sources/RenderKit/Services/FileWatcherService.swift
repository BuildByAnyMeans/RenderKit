// ───────────────────────────────────────────────────────────────────────────────
// FileWatcherService.swift — FSEvents-based directory watcher
// ───────────────────────────────────────────────────────────────────────────────
// Uses macOS's FSEventStream API to watch an entire directory tree for changes.
// When any file is created, modified, or deleted, the `onChange` callback fires.
// The callback is coalesced with a 0.3-second latency so rapid saves don't
// trigger dozens of reloads.
//
// Architecture note: FSEvents is a C API. We bridge it using an
// Unmanaged pointer in the stream context so the C callback can reach
// back into our Swift object.
// ───────────────────────────────────────────────────────────────────────────────

import Foundation
import CoreServices

final class FileWatcherService {

    // MARK: - Properties

    /// Called on the main thread whenever a file change is detected.
    var onChange: (() -> Void)?

    /// The directory currently being watched.
    private(set) var watchedPath: String?

    /// The underlying FSEventStream reference.
    private var stream: FSEventStreamRef?

    // MARK: - Public API

    /// Start watching `directory` for changes. Stops any existing watch first.
    func watch(directory: URL) {
        stop()

        let path = directory.path
        watchedPath = path

        // CFArray of paths to watch
        let pathsToWatch = [path] as CFArray

        // Stream context — stores a raw pointer to `self` so the C callback
        // can reach our Swift object.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // The C-function callback that FSEvents invokes
        let callback: FSEventStreamCallback = {
            _, clientCallBackInfo, _, _, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
            // Dispatch to main thread for SwiftUI updates
            DispatchQueue.main.async {
                watcher.onChange?()
            }
        }

        // Create the event stream
        //  - kFSEventStreamCreateFlagUseCFTypes:  Use CFArray for event paths
        //  - kFSEventStreamCreateFlagFileEvents:  Get per-file events (not just dir)
        //  - kFSEventStreamCreateFlagNoDefer:     Fire the first event immediately
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        stream = FSEventStreamCreate(
            nil,                                          // allocator
            callback,                                     // callback
            &context,                                     // context
            pathsToWatch,                                 // paths
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), // since
            0.3,                                          // latency (seconds)
            flags
        )

        guard let stream = stream else {
            print("[FileWatcher] Failed to create FSEventStream for \(path)")
            return
        }

        // Schedule on the main dispatch queue (preferred over RunLoop since macOS 13)
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        print("[FileWatcher] Now watching: \(path)")
    }

    /// Stop watching. Safe to call even if not currently watching.
    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        print("[FileWatcher] Stopped watching: \(watchedPath ?? "nil")")
        watchedPath = nil
    }

    deinit {
        stop()
    }
}
