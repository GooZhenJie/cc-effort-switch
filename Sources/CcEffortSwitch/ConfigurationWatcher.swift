import Foundation

@MainActor
final class ConfigurationWatcher {
    private let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?

    init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    func start() {
        directorySource = makeSource(path: fileURL.deletingLastPathComponent().path, events: .write)
        watchFile()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: fileURL.path, events: [.write, .extend, .delete, .rename])
    }

    private func makeSource(path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.watchFile()
                self?.onChange()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }
}
