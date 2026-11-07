import AVFoundation
import Combine
import MindoraKokoroRuntime

@MainActor
final class TopicSpeechPlayer: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var isPreparing = false

    private var session = UUID()
    private var synthesis: Task<Void, Never>?
    private var remaining: ArraySlice<String> = []
    private var queuedBuffers = 0
    private static let modelRoot = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Kokoro")
    private var engine: AVAudioEngine?
    private var output: AVAudioPlayerNode?

    static func canRead(_ node: MindMapNode) -> Bool {
        node.title.contains(where: \.isLetterOrNumber) || node.note.contains(where: \.isLetterOrNumber)
    }

    func prepare() async {
        try? await KokoroEngine.shared.prepare(root: Self.modelRoot)
    }

    func start(_ node: MindMapNode, onError: @escaping (String) -> Void) {
        stop()
        let title = Self.chunks(node.title)
        let note = Self.chunks(node.note)
        remaining = (title + note)[...]
        guard !remaining.isEmpty else { return }
        activeID = node.id
        fillQueue(session: session, onError: onError)
    }

    func stop() {
        session = UUID()
        synthesis?.cancel()
        synthesis = nil
        remaining = []
        queuedBuffers = 0
        output?.stop()
        engine?.stop()
        output = nil
        engine = nil
        activeID = nil
        isPreparing = false
    }

    // Keep one buffer ahead of playback so inference overlaps the current audio.
    private func fillQueue(session: UUID, onError: @escaping (String) -> Void) {
        if queuedBuffers == 0 && remaining.isEmpty && synthesis == nil {
            stop()
            return
        }
        isPreparing = queuedBuffers == 0
        guard queuedBuffers < 2, synthesis == nil, let text = remaining.popFirst() else { return }
        synthesis = Task { [weak self] in
            do {
                let speaker: Int32 = text.unicodeScalars.contains { $0.properties.isIdeographic } ? 56 : 0
                let audio = try await KokoroEngine.shared.render(text, speaker: speaker, root: Self.modelRoot)
                guard let self, self.session == session else { return }
                try self.play(audio) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.session == session else { return }
                        self.queuedBuffers -= 1
                        self.fillQueue(session: session, onError: onError)
                    }
                }
                self.queuedBuffers += 1
                self.synthesis = nil
                self.fillQueue(session: session, onError: onError)
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
        let sentenceEnds: Set<Character> = ["。", "！", "？", "；", "\n"]
        let spacedEnds: Set<Character> = [".", "!", "?", ";"]
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
        var chunks: [String] = []
        while !remaining.isEmpty {
            let limit = 48
            let prefix = remaining.prefix(limit)
            let sentenceEnd = prefix.indices.first { index in
                let character = prefix[index]
                let next = remaining.index(after: index)
                return sentenceEnds.contains(character)
                    || (spacedEnds.contains(character) && (next == remaining.endIndex || remaining[next].isWhitespace))
            }
            let end: String.Index
            if let boundary = sentenceEnd {
                end = prefix.index(after: boundary)
            } else if prefix.endIndex != remaining.endIndex,
                      let boundary = prefix.dropFirst(limit / 2).lastIndex(where: { $0.isWhitespace || $0 == "，" || $0 == "," }) {
                end = prefix.index(after: boundary)
            } else {
                end = prefix.endIndex
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
