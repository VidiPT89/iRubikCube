import Foundation

/// Mirrors settings and learning progress in iCloud key-value storage, so
/// an iPhone and an iPad signed in to the same Apple Account agree. Solve
/// history (SwiftData) stays on each device.
@MainActor
final class CloudSync {

    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    /// Called on the main queue when another device changes a key.
    var onRemoteChange: ((_ key: String, _ data: Data) -> Void)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main) { [weak self] note in
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for key in keys {
                        if let data = self.store.data(forKey: key) { self.onRemoteChange?(key, data) }
                    }
                }
            }
        store.synchronize()
    }

    func pull(_ key: String) -> Data? { store.data(forKey: key) }

    func push(_ data: Data, for key: String) {
        guard store.data(forKey: key) != data else { return }
        store.set(data, forKey: key)
    }
}
