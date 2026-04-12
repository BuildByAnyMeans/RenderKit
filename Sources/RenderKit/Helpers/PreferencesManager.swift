// ───────────────────────────────────────────────────────────────────────────────
// PreferencesManager.swift — UserDefaults persistence
// ───────────────────────────────────────────────────────────────────────────────
// Stores and retrieves user preferences like the last opened folder,
// window size, live-reload state, etc. All keys are namespaced under
// "com.renderkit" to avoid collisions.
// ───────────────────────────────────────────────────────────────────────────────

import Foundation

final class PreferencesManager {
    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let lastOpenedFolder  = "com.renderkit.lastOpenedFolder"
        static let liveReloadEnabled = "com.renderkit.liveReloadEnabled"
        static let sidebarWidth      = "com.renderkit.sidebarWidth"
        static let showTerminal      = "com.renderkit.showTerminal"
    }

    // MARK: - Last Opened Folder

    /// Save the path of the most recently opened project folder.
    /// We store the path string because URL bookmark data requires
    /// App Sandbox entitlements for persistent access.
    var lastOpenedFolder: URL? {
        get {
            guard let path = defaults.string(forKey: Key.lastOpenedFolder) else { return nil }
            let url = URL(fileURLWithPath: path)
            // Verify the folder still exists
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
        set {
            defaults.set(newValue?.path, forKey: Key.lastOpenedFolder)
        }
    }

    // MARK: - Live Reload

    /// Whether live-reload is enabled (defaults to true for new installs).
    var isLiveReloadEnabled: Bool {
        get {
            // Use object(forKey:) to distinguish "never set" from "set to false"
            if defaults.object(forKey: Key.liveReloadEnabled) == nil {
                return true // Default: enabled
            }
            return defaults.bool(forKey: Key.liveReloadEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.liveReloadEnabled)
        }
    }

    // MARK: - Sidebar Width

    var sidebarWidth: CGFloat {
        get {
            let value = defaults.double(forKey: Key.sidebarWidth)
            return value > 0 ? CGFloat(value) : 250 // Default width
        }
        set {
            defaults.set(Double(newValue), forKey: Key.sidebarWidth)
        }
    }

    // MARK: - Terminal Visibility

    var showTerminal: Bool {
        get { defaults.bool(forKey: Key.showTerminal) }
        set { defaults.set(newValue, forKey: Key.showTerminal) }
    }
}
