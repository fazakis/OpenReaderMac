import AVFoundation
import Combine

@MainActor final class AudioPlayback: ObservableObject {
    @Published private(set) var currentChunk = 0
    @Published private(set) var currentWord: NSRange?
    @Published private(set) var wordChunk = 0
    private var wordSchedule: [(chunk: Int, range: NSRange, start: Int64, end: Int64)] = []
    private var scheduledFrames: Int64 = 0
    private var wordTimer: Timer?

    @Published private(set) var isPaused = false
    @Published private(set) var isActive = false
    @Published private(set) var isBuffering = false
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var ledger = PlaybackLedger()
    private var queue: [(id: UUID, chunk: Int, frames: Int)] = []
    private var inputFinished = false
    private var framer = PCMFramer()
    var didFinish: (() -> Void)?
    var pendingFrames: Int { ledger.pendingFrames }
    var epoch: UUID { ledger.epoch }
    var renderedSampleTime: Int64? { guard let time = player.lastRenderTime else { return nil }; return player.playerTime(forNodeTime: time)?.sampleTime }
    init() {
        engine.attach(player); engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        timePitch.pitch = 0
    }
    func setSpeed(_ speed: Double) { timePitch.rate = Float(min(3, max(0.5, speed))) }
    func setVolume(_ volume: Double) { player.volume = Float(min(1, max(0, volume))) }
    func begin(at index: Int) throws -> UUID {
        stop(); currentChunk = index; isActive = true; isBuffering = true
        if !engine.isRunning { try engine.start() }
        player.play()
        wordTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWord() }
        }
        return ledger.epoch
    }
    func append(_ data: Data, chunk: Int, epoch: UUID, words: [TimedWord]? = nil) async throws {
        while ledger.epoch == epoch && ledger.pendingFrames >= 24_000 * 8 {
            try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(40))
        }
        try Task.checkCancellation()
        guard ledger.epoch == epoch else { throw CancellationError() }
        let pcm = framer.append(data), frames = pcm.count / 2
        guard frames > 0 else { return }
        guard ledger.enqueue(epoch: epoch, chunk: chunk, frames: frames) else { throw CancellationError() }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            for i in 0..<frames {
                let bits = UInt16(b[2*i]) | UInt16(b[2*i+1]) << 8
                buffer.floatChannelData![0][i] = Float(Int16(bitPattern: bits)) / 32768
            }
        }
        let base = queue.isEmpty ? max(scheduledFrames, renderedSampleTime ?? 0) : scheduledFrames
        if let words {
            wordSchedule += words.map { (chunk, $0.range, base+Int64($0.start*24_000), base+Int64($0.end*24_000)) }
        }
        scheduledFrames = base + Int64(frames)
        let id = UUID(); queue.append((id, chunk, frames))
        if queue.count == 1 { currentChunk = chunk }
        isBuffering = false
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.completed(id: id, epoch: epoch, frames: frames) }
        }
    }
    private func updateWord() {
        guard isActive, let rendered = renderedSampleTime else { return }
        let latency = Int64((engine.outputNode.presentationLatency + timePitch.latency) * 24_000 * Double(timePitch.rate))
        let sample = max(0, rendered-latency)
        let word = wordSchedule.first { $0.start <= sample && $0.end > sample }
        if currentWord != word?.range || (word != nil && wordChunk != word!.chunk) {
            currentWord = word?.range
            if let word { wordChunk = word.chunk }
        }
        wordSchedule.removeAll { $0.end < sample-24_000 }
    }
    private func completed(id: UUID, epoch: UUID, frames: Int) {
        guard ledger.completed(epoch: epoch, frames: frames) else { return }
        queue.removeAll { $0.id == id }
        if let next = queue.first { currentChunk = next.chunk }
        if queue.isEmpty {
            if inputFinished { isActive = false; isBuffering = false; currentWord = nil; wordTimer?.invalidate(); wordTimer = nil; player.stop(); engine.pause(); didFinish?() }
            else { isBuffering = true }
        }
    }
    func finish(epoch: UUID) {
        guard ledger.epoch == epoch else { return }
        inputFinished = true
        if queue.isEmpty { isActive = false; isBuffering = false; currentWord = nil; wordTimer?.invalidate(); wordTimer = nil; player.stop(); engine.pause(); didFinish?() }
    }
    func togglePause() {
        guard isActive else { return }
        isPaused.toggle()
        if isPaused { player.pause() } else { player.play() }
    }
    func stop() {
        wordTimer?.invalidate(); wordTimer = nil; currentWord = nil; wordSchedule.removeAll(); scheduledFrames = 0
        ledger.reset(); queue.removeAll(); framer = PCMFramer(); inputFinished = false
        player.stop(); engine.pause(); isActive = false; isPaused = false; isBuffering = false
    }
}
