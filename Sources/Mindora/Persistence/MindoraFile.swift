import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mindora = UTType(exportedAs: "app.mindora.document", conformingTo: .json)
}

struct MindoraFile: FileDocument {
    static var readableContentTypes: [UTType] { [.mindora] }
    static var writableContentTypes: [UTType] { [.mindora] }
    var document: MindMapDocument

    init(document: MindMapDocument = MindMapDocument()) { self.document = document }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        document = try MapInterchange.decodeJSON(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try MapInterchange.encodeJSON(document))
    }
}
