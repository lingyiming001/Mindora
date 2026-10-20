import AppKit
import UniformTypeIdentifiers
import CryptoKit

/// The workspace schedules saving; a single coordinated writer owns each document.
final class MindoraDocument: NSDocument {
    var map = MindMapDocument()
    var didWrite: (() -> Void)?
    private var savedDigest: SHA256.Digest?
    private(set) var conflictCopyURL: URL?
    override class var autosavesInPlace: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        map = try MapInterchange.decodeJSON(data)
        savedDigest = SHA256.hash(data: data)
    }
    func loadPrepared(_ prepared: MindMapDocument, data: Data, url: URL) {
        map = prepared; savedDigest = SHA256.hash(data: data)
        fileURL = url; fileType = UTType.mindora.identifier
        fileModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    override func data(ofType typeName: String) throws -> Data { try MapInterchange.encodeJSON(map) }
    override func makeWindowControllers() {
        Task { @MainActor in WorkspaceStore.shared.adopt(self) }
    }
    func saveImmediately() throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try MapInterchange.encodeJSON(map)
        var coordinationError: NSError?, writeError: Error?
        conflictCopyURL = nil
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= MapInterchange.maximumFileBytes else { throw DocumentError.oversizedFile }
                    let disk = try Data(contentsOf: destination, options: .mappedIfSafe)
                    if let savedDigest, SHA256.hash(data: disk) != savedDigest, disk != data {
                        let conflict = destination.deletingLastPathComponent().appendingPathComponent(destination.deletingPathExtension().lastPathComponent + " 外部修改 " + UUID().uuidString + ".mindora")
                        // Preserve the exact external bytes before updating the managed original.
                        try FileManager.default.copyItem(at: destination, to: conflict)
                        self.conflictCopyURL = conflict
                    }
                }
                try data.write(to: destination, options: .atomic)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        savedDigest = SHA256.hash(data: data)
        fileModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        updateChangeCount(.changeCleared)
        let snapshot = map
        DispatchQueue.main.async { [weak self] in
            BackupStore.shared.write(snapshot)
            self?.didWrite?()
        }
    }
}
