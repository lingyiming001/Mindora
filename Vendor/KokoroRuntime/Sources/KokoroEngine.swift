import Foundation
import SherpaOnnxC

public struct KokoroAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
}

public enum KokoroError: LocalizedError {
    case missingModel, initialization, synthesis

    public var errorDescription: String? {
        switch self {
        case .missingModel: "找不到离线朗读模型，请使用包含模型的 Mindora 安装包。"
        case .initialization: "无法加载离线朗读模型，请检查应用是否安装完整。"
        case .synthesis: "无法为这段文字生成音频。"
        }
    }
}

/// Keeps native model construction and inference serialized off the UI actor.
public actor KokoroEngine {
    public static let shared = KokoroEngine()

    private final class Handle {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { SherpaOnnxDestroyOfflineTts(pointer) }
    }

    private var handle: Handle?
    private var loadedRoot: URL?
    private var idleRelease: Task<Void, Never>?

    public func render(_ text: String, speaker: Int32, root: URL) throws -> KokoroAudio {
        try Task.checkCancellation()
        idleRelease?.cancel()
        defer {
            idleRelease = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await self?.unload()
            }
        }

        if handle == nil || loadedRoot != root {
            unload()
            handle = try load(root)
            loadedRoot = root
        }
        guard let handle else { throw KokoroError.initialization }
        try Task.checkCancellation()

        var config = SherpaOnnxGenerationConfig()
        config.sid = speaker
        config.speed = 1
        config.silence_scale = 0.2
        guard let audio = text.withCString({ SherpaOnnxOfflineTtsGenerateWithConfig(handle.pointer, $0, &config, nil, nil) }) else {
            throw KokoroError.synthesis
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        try Task.checkCancellation()

        let result = audio.pointee
        guard let samples = result.samples, result.n > 0, result.sample_rate > 0 else { throw KokoroError.synthesis }
        let values = Array(UnsafeBufferPointer(start: samples, count: Int(result.n)))
        guard values.allSatisfy(\.isFinite), values.contains(where: { abs($0) > 0.00001 }) else { throw KokoroError.synthesis }
        return KokoroAudio(samples: values, sampleRate: Int(result.sample_rate))
    }

    private func unload() {
        handle = nil
        loadedRoot = nil
    }

    private func load(_ root: URL) throws -> Handle {
        func path(_ name: String) -> String { root.appendingPathComponent(name).path }
        let rules = ["date-zh.fst", "number-zh.fst", "phone-zh.fst"]
        let required = ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data", "lexicon-us-en.txt", "lexicon-zh.txt"] + rules
        guard required.allSatisfy({ FileManager.default.fileExists(atPath: path($0)) }) else { throw KokoroError.missingModel }

        var strings: [UnsafeMutablePointer<CChar>] = []
        defer { strings.forEach { free($0) } }
        func cString(_ value: String) -> UnsafePointer<CChar>? {
            guard let pointer = strdup(value) else { return nil }
            strings.append(pointer)
            return UnsafePointer(pointer)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = cString(path("model.onnx"))
        config.model.kokoro.voices = cString(path("voices.bin"))
        config.model.kokoro.tokens = cString(path("tokens.txt"))
        config.model.kokoro.data_dir = cString(path("espeak-ng-data"))
        config.model.kokoro.lexicon = cString(["lexicon-us-en.txt", "lexicon-zh.txt"].map(path).joined(separator: ","))
        config.model.kokoro.length_scale = 1
        config.model.provider = cString("cpu")
        config.model.num_threads = Int32(min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)))
        config.max_num_sentences = 1
        config.rule_fsts = cString(rules.map(path).joined(separator: ","))
        guard let pointer = SherpaOnnxCreateOfflineTts(&config) else { throw KokoroError.initialization }
        return Handle(pointer)
    }
}
