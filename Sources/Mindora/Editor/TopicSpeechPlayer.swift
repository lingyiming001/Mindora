import AVFoundation
import Combine
import MindoraKokoroRuntime

@MainActor
final class TopicSpeechPlayer: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var isPreparing = false

    private var session = UUID()
    private var synthesis: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var output: AVAudioPlayerNode?

    static func canRead(_ node: MindMapNode) -> Bool {
        node.title.contains(where: \.isLetterOrNumber) || node.note.contains(where: \.isLetterOrNumber)
    }

    func start(_ node: MindMapNode, onError: @escaping (String) -> Void) {
        stop()
        let chunks = [node.title, node.note].flatMap(Self.chunks)
        guard !chunks.isEmpty else { return }
        let root = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Kokoro")
        activeID = node.id
        play(chunks[...], root: root, session: session, onError: onError)
    }

    func stop() {
        session = UUID()
        synthesis?.cancel()
        synthesis = nil
        output?.stop()
        engine?.stop()
        output = nil
        engine = nil
        activeID = nil
        isPreparing = false
    }

    private func play(_ chunks: ArraySlice<String>, root: URL, session: UUID, onError: @escaping (String) -> Void) {
        guard let text = chunks.first else { stop(); return }
        isPreparing = true
        synthesis = Task { [weak self] in
            do {
                let speaker: Int32 = text.unicodeScalars.contains { $0.properties.isIdeographic } ? 56 : 0
                let audio = try await KokoroEngine.shared.render(text, speaker: speaker, root: root)
                guard let self, self.session == session else { return }
                try self.play(audio) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.session == session else { return }
                        self.play(chunks.dropFirst(), root: root, session: session, onError: onError)
                    }
                }
                self.isPreparing = false
            } catch {
                guard let self, self.session == session else { return }
                self.stop()
                onError(error.localizedDescription)
            }
        }
    }

    private func play(_ audio: KokoroAudio, onCompletion: @escaping @Sendable () -> Void) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw KokoroError.synthesis }
        buffer.frameLength = buffer.frameCapacity
        audio.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { channel.update(from: base, count: samples.count) }
        }

        if engine == nil {
            let engine = AVAudioEngine()
            let output = AVAudioPlayerNode()
            engine.attach(output)
            engine.connect(output, to: engine.mainMixerNode, format: format)
            try engine.start()
            self.engine = engine
            self.output = output
        }
        output?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in onCompletion() }
        if output?.isPlaying == false { output?.play() }
    }

    static func chunks(_ text: String) -> [String] {
        let punctuation: Set<Character> = ["。", "！", "？", "；", ".", "!", "?", ";", "\n"]
        var remaining = text[...]
        var chunks: [String] = []
        while !remaining.isEmpty {
            let prefix = remaining.prefix(160)
            var end = prefix.endIndex
            if end != remaining.endIndex {
                let latterHalf = prefix.dropFirst(80)
                if let boundary = latterHalf.lastIndex(where: { punctuation.contains($0) })
                    ?? latterHalf.lastIndex(where: \.isWhitespace) {
                    end = prefix.index(after: boundary)
                }
            }
            let chunk = remaining[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if chunk.contains(where: \.isLetterOrNumber) { chunks.append(chunk) }
            remaining = remaining[end...]
        }
        return chunks
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
