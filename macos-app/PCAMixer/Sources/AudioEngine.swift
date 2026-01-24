import Foundation
import AVFoundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// Separation mode
enum SeparationMode: String, CaseIterable {
    case demucs = "Demucs (Instruments)"
    case pca = "PCA (Spectral)"
}

/// Wrapper for audio separation and mixing
class AudioEngine: ObservableObject {
    // MARK: - Published Properties
    @Published var hasLoadedFile: Bool = false  // File loaded for playback but not analyzed
    @Published var hasSession: Bool = false      // File has been analyzed and ready for mixing
    @Published var componentCount: Int = 0
    @Published var sampleRate: UInt32 = 44100
    @Published var isProcessing: Bool = false
    @Published var isPlaying: Bool = false
    @Published var isLooping: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var errorMessage: String?
    @Published var fileName: String?
    @Published var processingStatus: String = ""
    @Published var processingProgress: Double = 0
    @Published var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser {
        didSet {
            // Persist the last used directory
            UserDefaults.standard.set(currentDirectory.path, forKey: "lastDirectory")
        }
    }
    @Published var showFileBrowser: Bool = true
    @Published var playbackRate: Float = 1.0
    @Published var waveformSamples: [Float] = []
    @Published var selectionStart: Double = 0
    @Published var selectionEnd: Double = 0
    
    // Mode selection
    @Published var separationMode: SeparationMode = .demucs
    @Published var selectedComponentCount: Int = 8  // For PCA mode
    
    // Stem data
    @Published var stemNames: [String] = []
    @Published var faderValues: [Double] = []
    @Published var soloStates: [Bool] = []
    @Published var muteStates: [Bool] = []
    @Published var meterLevels: [Float] = []
    
    // For PCA mode - variance info
    @Published var varianceRatios: [Double] = []
    
    // MARK: - Private Properties
    private var sessionPtr: OpaquePointer?  // For PCA mode
    private var audioEngine: AVAudioEngine?
    private var playerNodes: [AVAudioPlayerNode] = []
    private var mixerNode: AVAudioMixerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var meterTapNodes: [AVAudioMixerNode] = []  // For metering
    private var startTime: Double = 0
    private var pauseTime: Double = 0
    private var timer: Timer?
    private var tempDirectory: URL?
    private var currentInputURL: URL?
    private var peakLevels: [Float] = []  // Raw peak levels from taps
    private let meterDecay: Float = 0.85  // How fast meters fall
    private let waveformMaxSamples: Int = 1000
    
    // Original audio for pre-analysis playback
    private var originalAudioBuffer: AVAudioPCMBuffer?
    private var originalPlayerNode: AVAudioPlayerNode?
    private var originalMeterNode: AVAudioMixerNode?
    
    // Demucs stem order
    static let demucsStems = ["drums", "bass", "vocals", "guitar", "piano", "other"]
    static let demucsDisplayNames = ["Drums", "Bass", "Vocals", "Guitar", "Keys", "Other"]
    
    // MARK: - Initialization
    init() {
        // Restore last used directory if available
        if let savedPath = UserDefaults.standard.string(forKey: "lastDirectory") {
            let savedURL = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                currentDirectory = savedURL
            }
        }
        
        setupAudioEngine()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        timePitchNode = AVAudioUnitTimePitch()
        
        guard let engine = audioEngine, let mixer = mixerNode, let timePitch = timePitchNode else { return }
        
        engine.attach(mixer)
        engine.attach(timePitch)
        
        // Connect mixer -> timePitch -> mainMixer (output)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }
    
    // MARK: - File Operations
    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.wav, UTType.mp3, UTType.audio].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an audio file to process"
        
        panel.begin { [weak self] (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url {
                self?.loadFile(url: url)
            }
        }
    }
    
    func loadFile(url: URL) {
        cleanup()
        currentInputURL = url
        
        // Update current directory to the file's parent
        let parentDir = url.deletingLastPathComponent()
        
        DispatchQueue.main.async {
            self.currentDirectory = parentDir
            self.errorMessage = nil
            self.fileName = url.lastPathComponent
        }
        
        // Load original audio file for playback (without analysis)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadOriginalAudio(url: url)
        }
    }
    
    /// Loads original audio file for playback before analysis
    private func loadOriginalAudio(url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                handleError("Failed to create audio buffer")
                return
            }
            
            try file.read(into: buffer)
            
            let detectedSampleRate = UInt32(format.sampleRate)
            let detectedDuration = Double(file.length) / format.sampleRate
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.originalAudioBuffer = buffer
                self.sampleRate = detectedSampleRate
                self.duration = detectedDuration
                
                self.setupOriginalPlayerNode(buffer: buffer)
                self.computeWaveformFromOriginal(buffer: buffer)
                
                self.hasLoadedFile = true
                self.hasSession = false
            }
        } catch {
            handleError("Failed to load audio file: \(error.localizedDescription)")
        }
    }
    
    /// Sets up the player node for original audio playback
    private func setupOriginalPlayerNode(buffer: AVAudioPCMBuffer) {
        guard let engine = audioEngine, let mixer = mixerNode else { return }
        
        // Remove existing original player if any
        if let player = originalPlayerNode {
            engine.detach(player)
        }
        if let meter = originalMeterNode {
            meter.removeTap(onBus: 0)
            engine.detach(meter)
        }
        
        let player = AVAudioPlayerNode()
        let meterMixer = AVAudioMixerNode()
        
        engine.attach(player)
        engine.attach(meterMixer)
        
        engine.connect(player, to: meterMixer, format: buffer.format)
        engine.connect(meterMixer, to: mixer, format: buffer.format)
        
        originalPlayerNode = player
        originalMeterNode = meterMixer
        
        do {
            try engine.start()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
    
    /// Computes waveform samples from original buffer
    private func computeWaveformFromOriginal(buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            DispatchQueue.main.async { self.waveformSamples = [] }
            return
        }
        
        let channelCount = Int(buffer.format.channelCount)
        let targetSamples = min(waveformMaxSamples, frameCount)
        let strideSize = max(1, frameCount / targetSamples)
        
        var samples: [Float] = []
        samples.reserveCapacity(targetSamples)
        
        if let channelData = buffer.floatChannelData {
            var maxVal: Float = 0
            for i in stride(from: 0, to: frameCount, by: strideSize) {
                var sum: Float = 0
                let end = min(i + strideSize, frameCount)
                let count = end - i
                for ch in 0..<channelCount {
                    let data = channelData[ch]
                    for frame in i..<end {
                        let v = data[frame]
                        sum += v * v
                    }
                }
                let rms = sqrt(sum / Float(max(1, count * channelCount)))
                maxVal = max(maxVal, rms)
                samples.append(rms)
            }
            if maxVal > 0 {
                samples = samples.map { min(1.0, $0 / maxVal) }
            }
        }
        
        DispatchQueue.main.async { self.waveformSamples = samples }
    }
    
    /// Triggers analysis/separation of the loaded file
    func analyze() {
        guard let url = currentInputURL, hasLoadedFile else { return }
        
        // Stop any playback
        stopOriginalPlayback()
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingStatus = "Starting..."
            self.processingProgress = 0
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            switch self.separationMode {
            case .demucs:
                self.processWithDemucs(url: url)
            case .pca:
                self.processWithPCA(url: url)
            }
        }
    }
    
    /// Stops original audio playback (used before analysis)
    private func stopOriginalPlayback() {
        originalPlayerNode?.stop()
        isPlaying = false
        pauseTime = 0
        currentTime = 0
        stopTimer()
    }
    
    // MARK: - Demucs Processing
    private func processWithDemucs(url: URL) {
        updateStatus("Checking Demucs installation...")
        updateProgress(0)
        
        // Create temp directory for output
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCAMixer_\(UUID().uuidString)")
        tempDirectory = tempDir
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            handleError("Failed to create temp directory: \(error.localizedDescription)")
            return
        }
        
        // Find Python
        let pythonPaths = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        var pythonPath: String?
        for path in pythonPaths {
            if FileManager.default.fileExists(atPath: path) {
                pythonPath = path
                break
            }
        }
        
        guard let python = pythonPath else {
            handleError("Python 3 not found. Please install Python 3.")
            return
        }
        
        // Get script path (in app bundle or development location)
        var scriptPath: String?
        
        // Check in app bundle Resources
        if let bundlePath = Bundle.main.path(forResource: "demucs_separate", ofType: "py") {
            scriptPath = bundlePath
        }
        
        // Check in development location
        if scriptPath == nil {
            let devPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/demucs_separate.py")
            if FileManager.default.fileExists(atPath: devPath.path) {
                scriptPath = devPath.path
            }
        }
        
        guard let script = scriptPath else {
            handleError("Demucs script not found")
            return
        }
        
        // Convert input to WAV using our Rust library (avoids FFmpeg dependency)
        updateStatus("Converting audio to WAV...")
        
        let inputPath: String
        let fileExtension = url.pathExtension.lowercased()
        
        if fileExtension == "wav" {
            // Already WAV, use directly
            inputPath = url.path
        } else {
            // Convert to WAV using our Rust library
            guard let audioData = try? Data(contentsOf: url) else {
                handleError("Failed to read input file")
                return
            }
            
            let convertResult = audioData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> ConvertResultFFI in
                let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return pca_convert_to_wav(ptr, audioData.count)
            }
            
            if let error = convertResult.error {
                let errorMsg = String(cString: error)
                pca_free_error(error)
                handleError("Failed to convert audio: \(errorMsg)")
                return
            }
            
            guard let wavData = convertResult.data else {
                handleError("Failed to convert audio: no data returned")
                return
            }
            
            // Write converted WAV to temp directory
            let wavURL = tempDir.appendingPathComponent("input.wav")
            let wavBytes = Data(bytes: wavData, count: convertResult.length)
            pca_free_bytes(wavData, convertResult.length)
            
            do {
                try wavBytes.write(to: wavURL)
                inputPath = wavURL.path
            } catch {
                handleError("Failed to write converted WAV: \(error.localizedDescription)")
                return
            }
        }
        
        updateStatus("Running Demucs (this may take a few minutes)...")
        updateProgress(0)
        
        // Run demucs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [
            script,
            inputPath,
            "-o", tempDir.path,
            "-m", "htdemucs_6s",
            "--install",
            "--json"
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        var stderrBuffer = ""
        let stderrHandle = errorPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            if let chunk = String(data: data, encoding: .utf8) {
                stderrBuffer.append(chunk)
                let lines = stderrBuffer.components(separatedBy: "\n")
                // Keep the last partial line in the buffer
                stderrBuffer = lines.last ?? ""
                
                for line in lines.dropLast() {
                    if let progress = self.parseDemucsProgress(line) {
                        self.updateProgress(progress)
                    }
                }
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            stderrHandle.readabilityHandler = nil
            handleError("Failed to run Demucs: \(error.localizedDescription)")
            return
        }
        
        stderrHandle.readabilityHandler = nil
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        let stdOutput = String(data: outputData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            // Combine stdout and stderr for full error context
            var fullError = "Demucs failed (exit \(process.terminationStatus)):\n"
            if !errorOutput.isEmpty {
                fullError += "\n--- stderr ---\n\(errorOutput)"
            }
            if !stdOutput.isEmpty {
                fullError += "\n--- stdout ---\n\(stdOutput)"
            }
            handleError(fullError)
            return
        }
        
        updateProgress(1)
        // Parse JSON output from stdout
        guard let jsonData = stdOutput.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let stems = result["stems"] as? [String: String] else {
            handleError("Failed to parse Demucs output.\n\nstdout: \(stdOutput)\n\nstderr: \(errorOutput)")
            return
        }
        
        updateStatus("Loading stems...")
        
        // Load stem files in order
        var loadedStems: [(name: String, displayName: String, url: URL)] = []
        for (i, stemName) in Self.demucsStems.enumerated() {
            if let stemPath = stems[stemName] {
                let stemURL = URL(fileURLWithPath: stemPath)
                if FileManager.default.fileExists(atPath: stemURL.path) {
                    loadedStems.append((stemName, Self.demucsDisplayNames[i], stemURL))
                }
            }
        }
        
        if loadedStems.isEmpty {
            handleError("No stems were produced by Demucs")
            return
        }
        
        // Load audio buffers
        loadStemFiles(stems: loadedStems)
    }
    
    private func loadStemFiles(stems: [(name: String, displayName: String, url: URL)]) {
        var buffers: [AVAudioPCMBuffer] = []
        var names: [String] = []
        var detectedSampleRate: UInt32 = 44100
        var detectedDuration: Double = 0
        
        for stem in stems {
            do {
                let file = try AVAudioFile(forReading: stem.url)
                detectedSampleRate = UInt32(file.processingFormat.sampleRate)
                
                let frameCount = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                    continue
                }
                
                try file.read(into: buffer)
                buffers.append(buffer)
                names.append(stem.displayName)
                
                if detectedDuration == 0 {
                    detectedDuration = Double(file.length) / file.processingFormat.sampleRate
                }
            } catch {
                print("Failed to load stem \(stem.name): \(error)")
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up original audio player (no longer needed after analysis)
            self.cleanupOriginalPlayer()
            
            self.audioBuffers = buffers
            self.stemNames = names
            self.componentCount = buffers.count
            self.sampleRate = detectedSampleRate
            self.duration = detectedDuration
            self.varianceRatios = []  // Not applicable for Demucs
            
            self.faderValues = Array(repeating: 1.0, count: buffers.count)
            self.soloStates = Array(repeating: false, count: buffers.count)
            self.muteStates = Array(repeating: false, count: buffers.count)
            self.meterLevels = Array(repeating: 0.0, count: buffers.count)
            self.selectionStart = 0
            self.selectionEnd = 0
            
            self.setupPlayerNodes()
            self.computeWaveformSamples()
            
            self.hasLoadedFile = false  // No longer in pre-analysis state
            self.hasSession = true
            self.isProcessing = false
            self.processingStatus = ""
            self.processingProgress = 1
        }
    }
    
    /// Cleans up the original audio player (used when transitioning to analyzed state)
    private func cleanupOriginalPlayer() {
        if let engine = audioEngine {
            if let player = originalPlayerNode {
                player.stop()
                engine.detach(player)
            }
            if let meter = originalMeterNode {
                meter.removeTap(onBus: 0)
                engine.detach(meter)
            }
        }
        
        originalAudioBuffer = nil
        originalPlayerNode = nil
        originalMeterNode = nil
    }
    
    // MARK: - PCA Processing
    private func processWithPCA(url: URL) {
        updateStatus("Loading audio...")
        updateProgress(0.1)
        
        do {
            let data = try Data(contentsOf: url)
            
            updateStatus("Computing PCA decomposition...")
            updateProgress(0.2)
            
            let result = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> PcaResultFFI in
                let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return pca_process_audio(ptr, data.count, UInt32(selectedComponentCount), 2048, 512)
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isProcessing = false
                self.processingStatus = ""
                self.processingProgress = 1
                
                if let error = result.error {
                    self.errorMessage = String(cString: error)
                    pca_free_error(error)
                    return
                }
                
                guard let session = result.session else {
                    self.errorMessage = "Unknown error occurred"
                    return
                }
                
                // Clean up original audio player (no longer needed after analysis)
                self.cleanupOriginalPlayer()
                
                self.sessionPtr = session
                self.hasLoadedFile = false  // No longer in pre-analysis state
                self.hasSession = true
                self.componentCount = Int(result.num_components)
                self.sampleRate = result.sample_rate
                
                // Initialize stem names and variance ratios
                self.stemNames = (0..<self.componentCount).map { "PC \($0 + 1)" }
                self.varianceRatios = (0..<self.componentCount).map { i in
                    let info = pca_get_component_info(session, UInt32(i))
                    return info.variance_ratio
                }
                
                self.faderValues = Array(repeating: 1.0, count: self.componentCount)
                self.soloStates = Array(repeating: false, count: self.componentCount)
                self.muteStates = Array(repeating: false, count: self.componentCount)
                self.meterLevels = Array(repeating: 0.0, count: self.componentCount)
                
                self.loadPCABuffers(session: session)
            }
        } catch {
            handleError("Failed to read file: \(error.localizedDescription)")
        }
    }
    
    private func loadPCABuffers(session: OpaquePointer) {
        audioBuffers.removeAll()
        playerNodes.removeAll()
        
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        
        for i in 0..<componentCount {
            let buffer = pca_get_component_audio(session, UInt32(i))
            
            if buffer.error != nil {
                pca_free_audio_buffer(buffer)
                continue
            }
            
            guard let data = buffer.data else {
                pca_free_audio_buffer(buffer)
                continue
            }
            
            let frameCount = AVAudioFrameCount(buffer.length)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                pca_free_audio_buffer(buffer)
                continue
            }
            
            pcmBuffer.frameLength = frameCount
            
            if let channelData = pcmBuffer.floatChannelData?[0] {
                for j in 0..<Int(buffer.length) {
                    channelData[j] = Float(data[j])
                }
            }
            
            audioBuffers.append(pcmBuffer)
            
            if i == 0 {
                duration = Double(buffer.length) / Double(sampleRate)
            }
            
            pca_free_audio_buffer(buffer)
        }
        
        setupPlayerNodes()
        computeWaveformSamples()
    }
    
    // MARK: - Helper Methods
    private func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.processingStatus = status
        }
    }
    
    private func computeWaveformSamples() {
        guard let firstBuffer = audioBuffers.first else {
            DispatchQueue.main.async { self.waveformSamples = [] }
            return
        }
        
        let frameCount = Int(firstBuffer.frameLength)
        guard frameCount > 0 else {
            DispatchQueue.main.async { self.waveformSamples = [] }
            return
        }
        
        let channelCount = Int(firstBuffer.format.channelCount)
        let targetSamples = min(waveformMaxSamples, frameCount)
        let strideSize = max(1, frameCount / targetSamples)
        
        var samples: [Float] = []
        samples.reserveCapacity(targetSamples)
        
        if let channelData = firstBuffer.floatChannelData {
            var maxVal: Float = 0
            for i in stride(from: 0, to: frameCount, by: strideSize) {
                var sum: Float = 0
                let end = min(i + strideSize, frameCount)
                let count = end - i
                for ch in 0..<channelCount {
                    let data = channelData[ch]
                    for frame in i..<end {
                        let v = data[frame]
                        sum += v * v
                    }
                }
                let rms = sqrt(sum / Float(max(1, count * channelCount)))
                maxVal = max(maxVal, rms)
                samples.append(rms)
            }
            if maxVal > 0 {
                samples = samples.map { min(1.0, $0 / maxVal) }
            }
        }
        
        DispatchQueue.main.async { self.waveformSamples = samples }
    }

    private func selectionFrameRange() -> (start: Int, length: Int) {
        guard let firstBuffer = audioBuffers.first, duration > 0 else {
            return (0, audioBuffers.first.map { Int($0.frameLength) } ?? 0)
        }
        let totalFrames = Int(firstBuffer.frameLength)
        let startFrame = Int(Double(totalFrames) * (selectionStart / duration))
        let endFrame = Int(Double(totalFrames) * (selectionEnd / duration))
        let clampedStart = max(0, min(totalFrames, startFrame))
        let clampedEnd = max(0, min(totalFrames, endFrame))
        let length = max(0, clampedEnd - clampedStart)
        return (clampedStart, length)
    }
    
    private func updateProgress(_ progress: Double) {
        let clamped = max(0, min(1, progress))
        DispatchQueue.main.async {
            self.processingProgress = clamped
        }
    }
    
    private func parseDemucsProgress(_ line: String) -> Double? {
        // Parse tqdm-like progress lines, e.g. "  1%|...| 0.6/58.5 [00:01<...]"
        let tokens = line.split(separator: " ")
        for token in tokens {
            if token.contains("/") {
                let parts = token.split(separator: "/")
                if parts.count == 2,
                   let current = Double(parts[0].filter { "0123456789.".contains($0) }),
                   let total = Double(parts[1].filter { "0123456789.".contains($0) }),
                   total > 0 {
                    return current / total
                }
            }
        }
        return nil
    }
    
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.processingStatus = ""
            self.processingProgress = 0
            self.errorMessage = message
        }
    }
    
    private func setupPlayerNodes() {
        guard let engine = audioEngine, let mixer = mixerNode else { return }
        
        // Remove existing nodes
        for node in playerNodes {
            engine.detach(node)
        }
        for node in meterTapNodes {
            node.removeTap(onBus: 0)
            engine.detach(node)
        }
        playerNodes.removeAll()
        meterTapNodes.removeAll()
        peakLevels = Array(repeating: 0, count: audioBuffers.count)
        
        for (index, buffer) in audioBuffers.enumerated() {
            let player = AVAudioPlayerNode()
            let meterMixer = AVAudioMixerNode()
            
            engine.attach(player)
            engine.attach(meterMixer)
            
            // Player -> MeterMixer -> MainMixer
            engine.connect(player, to: meterMixer, format: buffer.format)
            engine.connect(meterMixer, to: mixer, format: buffer.format)
            
            // Install tap for metering
            let tapFormat = meterMixer.outputFormat(forBus: 0)
            if tapFormat.sampleRate > 0 {
                meterMixer.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] tapBuffer, _ in
                    guard let self = self else { return }
                    let level = self.calculateRMS(buffer: tapBuffer)
                    if index < self.peakLevels.count {
                        self.peakLevels[index] = max(level, self.peakLevels[index] * self.meterDecay)
                    }
                }
            }
            
            playerNodes.append(player)
            meterTapNodes.append(meterMixer)
        }
        
        do {
            try engine.start()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength > 0 else { return 0 }
        
        var sum: Float = 0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let sample = data[frame]
                sum += sample * sample
            }
        }
        
        let rms = sqrt(sum / Float(frameLength * channelCount))
        // Convert to 0-1 range with some headroom
        return min(1.0, rms * 2.5)
    }
    
    private func sliceBuffer(_ buffer: AVAudioPCMBuffer, start: Int, length: Int) -> AVAudioPCMBuffer? {
        guard length > 0 else { return nil }
        let frameCount = Int(buffer.frameLength)
        let clampedStart = max(0, min(frameCount, start))
        let clampedEnd = max(clampedStart, min(frameCount, start + length))
        let sliceLength = clampedEnd - clampedStart
        guard sliceLength > 0 else { return nil }
        
        guard let newBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(sliceLength)) else {
            return nil
        }
        newBuffer.frameLength = AVAudioFrameCount(sliceLength)
        
        let channelCount = Int(buffer.format.channelCount)
        for ch in 0..<channelCount {
            if let src = buffer.floatChannelData?[ch], let dst = newBuffer.floatChannelData?[ch] {
                for i in 0..<sliceLength {
                    dst[i] = src[clampedStart + i]
                }
            }
        }
        return newBuffer
    }
    
    // MARK: - Playback Control
    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }
    
    func play() {
        // Use analyzed stems if available, otherwise use original audio
        if hasSession {
            playMixedAudio()
        } else if hasLoadedFile {
            playOriginalAudio()
        }
    }
    
    private func playMixedAudio() {
        guard !audioBuffers.isEmpty else { return }
        if isPlaying { return }
        
        let hasSelection = selectionEnd > selectionStart
        let selectionRange = hasSelection ? selectionFrameRange() : nil
        
        if hasSelection {
            let start = selectionStart
            if pauseTime < start || pauseTime > selectionEnd {
                pauseTime = start
                currentTime = start
            }
        }
        
        for (i, player) in playerNodes.enumerated() {
            guard i < audioBuffers.count else { continue }
            let buffer = audioBuffers[i]
            
            player.stop()
            
            if let range = selectionRange {
                if let sliced = sliceBuffer(buffer, start: range.start, length: range.length) {
                    player.scheduleBuffer(sliced, at: nil, options: isLooping ? .loops : [])
                } else {
                    player.scheduleBuffer(buffer, at: nil, options: isLooping ? .loops : [])
                }
            } else {
                player.scheduleBuffer(buffer, at: nil, options: isLooping ? .loops : [])
            }
            
            updateGain(for: i)
            player.play()
        }
        
        isPlaying = true
        startTime = CACurrentMediaTime() - pauseTime
        startTimer()
    }
    
    private func playOriginalAudio() {
        guard let buffer = originalAudioBuffer, let player = originalPlayerNode else { return }
        if isPlaying { return }
        
        let hasSelection = selectionEnd > selectionStart
        
        if hasSelection {
            let start = selectionStart
            if pauseTime < start || pauseTime > selectionEnd {
                pauseTime = start
                currentTime = start
            }
        }
        
        player.stop()
        
        if hasSelection {
            let range = selectionFrameRangeForOriginal()
            if let sliced = sliceBuffer(buffer, start: range.start, length: range.length) {
                player.scheduleBuffer(sliced, at: nil, options: isLooping ? .loops : [])
            } else {
                player.scheduleBuffer(buffer, at: nil, options: isLooping ? .loops : [])
            }
        } else {
            player.scheduleBuffer(buffer, at: nil, options: isLooping ? .loops : [])
        }
        
        player.play()
        
        isPlaying = true
        startTime = CACurrentMediaTime() - pauseTime
        startTimer()
    }
    
    private func selectionFrameRangeForOriginal() -> (start: Int, length: Int) {
        guard let buffer = originalAudioBuffer, duration > 0 else {
            return (0, originalAudioBuffer.map { Int($0.frameLength) } ?? 0)
        }
        let totalFrames = Int(buffer.frameLength)
        let startFrame = Int(Double(totalFrames) * (selectionStart / duration))
        let endFrame = Int(Double(totalFrames) * (selectionEnd / duration))
        let clampedStart = max(0, min(totalFrames, startFrame))
        let clampedEnd = max(0, min(totalFrames, endFrame))
        let length = max(0, clampedEnd - clampedStart)
        return (clampedStart, length)
    }
    
    func pause() {
        pauseTime = CACurrentMediaTime() - startTime
        
        if hasSession {
            for player in playerNodes { player.pause() }
        } else {
            originalPlayerNode?.pause()
        }
        
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        if hasSession {
            for player in playerNodes { player.stop() }
        } else {
            originalPlayerNode?.stop()
        }
        
        isPlaying = false
        pauseTime = 0
        currentTime = 0
        stopTimer()
    }
    
    func seek(to time: Double) {
        let wasPlaying = isPlaying
        stop()
        pauseTime = time
        currentTime = time
        if wasPlaying { play() }
    }
    
    // MARK: - Mixer Control
    func setFaderValue(_ value: Double, for index: Int) {
        guard index < faderValues.count else { return }
        faderValues[index] = value
        updateGain(for: index)
    }
    
    func toggleSolo(for index: Int) {
        guard index < soloStates.count else { return }
        soloStates[index].toggle()
        updateAllGains()
    }
    
    func toggleMute(for index: Int) {
        guard index < muteStates.count else { return }
        muteStates[index].toggle()
        updateGain(for: index)
    }
    
    func resetAllFaders() {
        for i in 0..<componentCount {
            faderValues[i] = 1.0
            soloStates[i] = false
            muteStates[i] = false
        }
        updateAllGains()
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        timePitchNode?.rate = rate
    }

    func setSelection(start: Double, end: Double) {
        let clampedStart = max(0, min(duration, start))
        let clampedEnd = max(0, min(duration, end))
        if clampedEnd <= clampedStart {
            selectionStart = 0
            selectionEnd = 0
            return
        }
        selectionStart = clampedStart
        selectionEnd = clampedEnd
    }

    func clearSelection() {
        selectionStart = 0
        selectionEnd = 0
    }
    
    private func updateGain(for index: Int) {
        guard index < playerNodes.count else { return }
        
        let hasSolo = soloStates.contains(true)
        var gain = faderValues[index]
        
        if muteStates[index] || (hasSolo && !soloStates[index]) {
            gain = 0
        }
        
        playerNodes[index].volume = Float(gain)
    }
    
    private func updateAllGains() {
        for i in 0..<playerNodes.count { updateGain(for: i) }
    }
    
    // MARK: - Timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTime() {
        guard isPlaying else { return }
        
        var time = CACurrentMediaTime() - startTime
        if selectionEnd > selectionStart {
            let loopLength = selectionEnd - selectionStart
            if isLooping && loopLength > 0 {
                let relative = (time - selectionStart).truncatingRemainder(dividingBy: loopLength)
                time = selectionStart + max(0, relative)
            }
        } else if isLooping && duration > 0 {
            time = time.truncatingRemainder(dividingBy: duration)
        }
        currentTime = min(time, duration)
        
        // Update meters from real audio levels
        for i in 0..<meterLevels.count {
            if i < peakLevels.count {
                meterLevels[i] = peakLevels[i]
            } else {
                meterLevels[i] = 0
            }
        }
        
        if selectionEnd > selectionStart {
            if !isLooping && currentTime >= selectionEnd { stop() }
        } else if !isLooping && currentTime >= duration {
            stop()
        }
    }
    
    // MARK: - Bounce/Export
    func bounceToFile() {
        guard hasSession else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.wav].compactMap { $0 }
        panel.nameFieldStringValue = "bounced_mix.wav"
        panel.message = "Save mixed audio"
        
        panel.begin { [weak self] (response: NSApplication.ModalResponse) in
            guard let self = self, response == .OK, let url = panel.url else { return }
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.performBounce(to: url)
            }
        }
    }
    
    private func performBounce(to url: URL) {
        // Build volumes array
        var volumes = faderValues
        let hasSolo = soloStates.contains(true)
        
        for i in 0..<volumes.count {
            if muteStates[i] || (hasSolo && !soloStates[i]) {
                volumes[i] = 0
            }
        }
        
        // Mix audio buffers
        guard let firstBuffer = audioBuffers.first else { return }
        let frameCount = Int(firstBuffer.frameLength)
        let channelCount = Int(firstBuffer.format.channelCount)
        let hasSelection = selectionEnd > selectionStart
        let range = hasSelection ? selectionFrameRange() : (start: 0, length: frameCount)
        guard range.length > 0 else { return }
        
        var mixedSamples = [Float](repeating: 0, count: range.length * channelCount)
        
        for (i, buffer) in audioBuffers.enumerated() {
            guard i < volumes.count else { continue }
            let volume = Float(volumes[i])
            
            for ch in 0..<channelCount {
                if let channelData = buffer.floatChannelData?[ch] {
                    let endFrame = min(range.start + range.length, Int(buffer.frameLength))
                    if endFrame <= range.start { continue }
                    for frame in range.start..<endFrame {
                        let outIndex = (frame - range.start) * channelCount + ch
                        mixedSamples[outIndex] += channelData[frame] * volume
                    }
                }
            }
        }
        
        // Normalize
        let maxVal = mixedSamples.map { abs($0) }.max() ?? 1.0
        if maxVal > 1.0 {
            for i in 0..<mixedSamples.count {
                mixedSamples[i] /= maxVal
            }
        }
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: firstBuffer.format, frameCapacity: AVAudioFrameCount(range.length)) else {
            handleError("Failed to create output buffer")
            return
        }
        outputBuffer.frameLength = AVAudioFrameCount(range.length)
        
        for ch in 0..<channelCount {
            if let channelData = outputBuffer.floatChannelData?[ch] {
                for frame in 0..<range.length {
                    channelData[frame] = mixedSamples[frame * channelCount + ch]
                }
            }
        }
        
        // Write to file
        do {
            let outputFile = try AVAudioFile(forWriting: url, settings: firstBuffer.format.settings)
            try outputFile.write(from: outputBuffer)
        } catch {
            handleError("Failed to write file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        stop()
        
        if let engine = audioEngine {
            engine.stop()
            
            // Clean up meter tap nodes
            for node in meterTapNodes {
                node.removeTap(onBus: 0)
                engine.detach(node)
            }
            
            // Clean up player nodes
            for node in playerNodes {
                engine.detach(node)
            }
            
            // Clean up original audio player
            if let player = originalPlayerNode {
                engine.detach(player)
            }
            if let meter = originalMeterNode {
                meter.removeTap(onBus: 0)
                engine.detach(meter)
            }
        }
        
        playerNodes.removeAll()
        meterTapNodes.removeAll()
        peakLevels.removeAll()
        audioBuffers.removeAll()
        
        // Clear original audio
        originalAudioBuffer = nil
        originalPlayerNode = nil
        originalMeterNode = nil
        
        if let session = sessionPtr {
            pca_session_free(session)
        }
        sessionPtr = nil
        
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
        
        hasLoadedFile = false
        hasSession = false
        componentCount = 0
        stemNames.removeAll()
        varianceRatios.removeAll()
        faderValues.removeAll()
        soloStates.removeAll()
        muteStates.removeAll()
        meterLevels.removeAll()
        duration = 0
        currentTime = 0
        waveformSamples.removeAll()
        selectionStart = 0
        selectionEnd = 0
    }
}
