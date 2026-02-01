import Foundation
import AVFoundation
import Combine
import AppKit
import UniformTypeIdentifiers
import CryptoKit

// MARK: - Cache Manager
/// Manages caching of analyzed audio stems
class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    /// Metadata stored with cached analysis
    struct CacheMetadata: Codable {
        let originalPath: String
        let fileSize: Int64
        let modificationDate: Date
        let stemNames: [String]
        let sampleRate: UInt32
        let duration: Double
        let createdAt: Date
    }
    
    private init() {
        // Create cache directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("Remix/cache", isDirectory: true)
        
        // Ensure cache directory exists
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Generate a unique cache key for a file based on path, size, and modification date
    func cacheKey(for fileURL: URL) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64,
              let modDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        
        let identifier = "\(fileURL.path)|\(fileSize)|\(modDate.timeIntervalSince1970)"
        let hash = SHA256.hash(data: Data(identifier.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }
    
    /// Get the cache directory for a specific file
    func cacheDirectory(for key: String) -> URL {
        return cacheDirectory.appendingPathComponent(key, isDirectory: true)
    }
    
    /// Check if valid cache exists for a file
    func hasValidCache(for fileURL: URL) -> Bool {
        guard let key = cacheKey(for: fileURL) else { return false }
        let dir = cacheDirectory(for: key)
        let metadataURL = dir.appendingPathComponent("metadata.json")
        
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return false
        }
        
        // Verify stem files exist
        for stemName in metadata.stemNames {
            let stemPath = dir.appendingPathComponent("\(stemName).wav")
            if !fileManager.fileExists(atPath: stemPath.path) {
                return false
            }
        }
        
        return true
    }
    
    /// Load cached metadata
    func loadMetadata(for fileURL: URL) -> CacheMetadata? {
        guard let key = cacheKey(for: fileURL) else { return nil }
        let dir = cacheDirectory(for: key)
        let metadataURL = dir.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        
        return metadata
    }
    
    /// Get stem file URLs from cache
    func getStemURLs(for fileURL: URL) -> [(name: String, url: URL)]? {
        guard let key = cacheKey(for: fileURL),
              let metadata = loadMetadata(for: fileURL) else {
            return nil
        }
        
        let dir = cacheDirectory(for: key)
        var stems: [(name: String, url: URL)] = []
        
        for stemName in metadata.stemNames {
            let stemURL = dir.appendingPathComponent("\(stemName).wav")
            if fileManager.fileExists(atPath: stemURL.path) {
                stems.append((stemName, stemURL))
            }
        }
        
        return stems.isEmpty ? nil : stems
    }
    
    /// Save stems to cache
    func saveStems(
        for fileURL: URL,
        stems: [(name: String, displayName: String, url: URL)],
        sampleRate: UInt32,
        duration: Double
    ) -> Bool {
        guard let key = cacheKey(for: fileURL),
              let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64,
              let modDate = attributes[.modificationDate] as? Date else {
            return false
        }
        
        let dir = cacheDirectory(for: key)
        
        // Create cache directory
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create cache directory: \(error)")
            return false
        }
        
        // Copy stem files
        var savedNames: [String] = []
        for stem in stems {
            let destURL = dir.appendingPathComponent("\(stem.displayName).wav")
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: stem.url, to: destURL)
                savedNames.append(stem.displayName)
            } catch {
                print("Failed to copy stem \(stem.displayName): \(error)")
            }
        }
        
        // Save metadata
        let metadata = CacheMetadata(
            originalPath: fileURL.path,
            fileSize: fileSize,
            modificationDate: modDate,
            stemNames: savedNames,
            sampleRate: sampleRate,
            duration: duration,
            createdAt: Date()
        )
        
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: dir.appendingPathComponent("metadata.json"))
            return true
        } catch {
            print("Failed to save metadata: \(error)")
            return false
        }
    }
    
    /// Clear cache for a specific file
    func clearCache(for fileURL: URL) {
        guard let key = cacheKey(for: fileURL) else { return }
        let dir = cacheDirectory(for: key)
        try? fileManager.removeItem(at: dir)
    }
    
    /// Clear all cache
    func clearAllCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Get total cache size in bytes
    func totalCacheSize() -> Int64 {
        var size: Int64 = 0
        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }
    
    /// Get all cached files with their metadata
    func getAllCachedFiles() -> [(metadata: CacheMetadata, key: String)] {
        var results: [(CacheMetadata, String)] = []
        
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return results
        }
        
        for itemURL in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            let metadataURL = itemURL.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
                continue
            }
            
            let key = itemURL.lastPathComponent
            results.append((metadata, key))
        }
        
        return results
    }
    
    /// Load stems directly from cache key (when original file may not exist)
    func getStemURLsFromKey(_ key: String) -> [(name: String, url: URL)]? {
        let dir = cacheDirectory(for: key)
        let metadataURL = dir.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        
        var stems: [(name: String, url: URL)] = []
        
        for stemName in metadata.stemNames {
            let stemURL = dir.appendingPathComponent("\(stemName).wav")
            if fileManager.fileExists(atPath: stemURL.path) {
                stems.append((stemName, stemURL))
            }
        }
        
        return stems.isEmpty ? nil : stems
    }
    
    /// Get metadata from cache key
    func getMetadataFromKey(_ key: String) -> CacheMetadata? {
        let dir = cacheDirectory(for: key)
        let metadataURL = dir.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        
        return metadata
    }
}

/// Wrapper for audio separation and mixing
class AudioEngine: ObservableObject {
    // MARK: - Published Properties
    @Published var hasLoadedFile: Bool = false  // File loaded for playback but not analyzed
    @Published var hasSession: Bool = false      // File has been analyzed and ready for mixing
    @Published var loadedFromCache: Bool = false // Whether current session was loaded from cache
    @Published var hasCachedAnalysis: Bool = false // Whether cache exists for current file
    @Published var cacheModifiedCounter: Int = 0  // Increments when cache is cleared, to trigger UI refresh
    @Published var componentCount: Int = 0
    @Published var sampleRate: UInt32 = 44100
    @Published var isProcessing: Bool = false
    @Published var isPlaying: Bool = false
    @Published var isLooping: Bool = false {
        didSet {
            saveCurrentSongSettings()
        }
    }
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var errorMessage: String?
    @Published var fileName: String?
    @Published var processingStatus: String = ""
    @Published var processingProgress: Double = 0
    @Published var analysisStartTime: Date?
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var estimatedTotalTime: TimeInterval = 0
    @Published var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser {
        didSet {
            // Persist the last used directory
            UserDefaults.standard.set(currentDirectory.path, forKey: "lastDirectory")
        }
    }
    @Published var showFileBrowser: Bool = true {
        didSet {
            UserDefaults.standard.set(showFileBrowser, forKey: "showFileBrowser")
        }
    }
    @Published var playbackRate: Float = 1.0 {
        didSet {
            saveCurrentSongSettings()
        }
    }
    @Published var pitch: Float = 0.0 {  // Pitch shift in cents (-200 to +200)
        didSet {
            saveCurrentSongSettings()
        }
    }
    @Published var waveformSamples: [Float] = []
    @Published var selectionStart: Double = 0
    @Published var selectionEnd: Double = 0
    
    // Stem data
    @Published var stemNames: [String] = []
    @Published var faderValues: [Double] = []
    @Published var panValues: [Double] = []  // -1.0 (left) to 1.0 (right), 0 = center
    @Published var soloStates: [Bool] = []
    @Published var muteStates: [Bool] = []
    @Published var meterLevels: [Float] = []
    
    // Original audio meter level (for pre-analysis playback)
    @Published var originalMeterLevel: Float = 0
    
    // MARK: - Private Properties
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
    private var originalPeakLevel: Float = 0  // Raw peak level for original audio
    private let meterDecay: Float = 0.85  // How fast meters fall
    private let waveformMaxSamples: Int = 1000
    
    // Original audio for pre-analysis playback
    private var originalAudioBuffer: AVAudioPCMBuffer?
    private var originalPlayerNode: AVAudioPlayerNode?
    private var originalMeterNode: AVAudioMixerNode?
    
    // Demucs stem order
    static let demucsStems = ["drums", "bass", "guitar", "piano", "vocals", "other"]
    static let demucsDisplayNames = ["Drums", "Bass", "Guitar", "Keys", "Voice", "Other"]
    
    // Map legacy display names to current ones (for cache compatibility)
    static let displayNameAliases: [String: String] = ["Vocals": "Voice"]
    
    /// Normalize a display name (handles legacy names from cache)
    static func normalizeDisplayName(_ name: String) -> String {
        return displayNameAliases[name] ?? name
    }
    
    // Demucs model handle (loaded once on first use)
    private var demucsModel: OpaquePointer?
    private var modelLoadError: String?
    
    // Processing time estimation
    private var processingRate: Double {
        get { UserDefaults.standard.double(forKey: "processingRate") }
        set { UserDefaults.standard.set(newValue, forKey: "processingRate") }
    }
    private var progressTimer: Timer?
    
    // Per-song settings storage
    struct SongSettings: Codable {
        var playbackRate: Float = 1.0
        var pitch: Float = 0.0
        var isLooping: Bool = false
    }
    
    private var currentSongKey: String? {
        currentInputURL?.path
    }
    
    // MARK: - Initialization
    init() {
        // Restore last used directory if available
        if let savedPath = UserDefaults.standard.string(forKey: "lastDirectory") {
            let savedURL = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                currentDirectory = savedURL
            }
        }
        
        // Initialize processing rate if not set (default: 1 minute processing per 1 minute audio)
        if processingRate == 0 {
            processingRate = 1.0
        }
        
        setupAudioEngine()
        
        // Restore global UI settings only
        restoreGlobalSettings()
    }
    
    private func restoreGlobalSettings() {
        let defaults = UserDefaults.standard
        
        // Restore sidebar visibility (global UI setting)
        if defaults.object(forKey: "showFileBrowser") != nil {
            showFileBrowser = defaults.bool(forKey: "showFileBrowser")
        }
    }
    
    private func saveCurrentSongSettings() {
        guard let songKey = currentSongKey else { return }
        
        let settings = SongSettings(
            playbackRate: playbackRate,
            pitch: pitch,
            isLooping: isLooping
        )
        
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "song_settings_\(songKey)")
        }
    }
    
    private func loadSongSettings() {
        guard let songKey = currentSongKey else {
            // Reset to defaults if no song
            playbackRate = 1.0
            pitch = 0.0
            isLooping = false
            timePitchNode?.rate = 1.0
            timePitchNode?.pitch = 0.0
            return
        }
        
        // Try to load saved settings for this song
        if let data = UserDefaults.standard.data(forKey: "song_settings_\(songKey)"),
           let settings = try? JSONDecoder().decode(SongSettings.self, from: data) {
            playbackRate = settings.playbackRate
            pitch = settings.pitch
            isLooping = settings.isLooping
            timePitchNode?.rate = settings.playbackRate
            timePitchNode?.pitch = settings.pitch
        } else {
            // Use defaults for new song
            playbackRate = 1.0
            pitch = 0.0
            isLooping = false
            timePitchNode?.rate = 1.0
            timePitchNode?.pitch = 0.0
        }
    }
    
    deinit {
        cleanup()
        stopProgressTimer()
        // Free Demucs model
        if let model = demucsModel {
            demucs_free_model(model)
            demucsModel = nil
        }
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
        
        // Check if cache exists for this file
        let hasCache = CacheManager.shared.hasValidCache(for: url)
        
        DispatchQueue.main.async {
            self.currentDirectory = parentDir
            self.errorMessage = nil
            self.fileName = url.lastPathComponent
            self.hasCachedAnalysis = hasCache
            self.loadedFromCache = false
            
            // Load settings for this song
            self.loadSongSettings()
        }
        
        // Auto-load from cache if available, otherwise load original for preview
        if hasCache {
            loadFromCache(url: url)
        } else {
            // Load original audio file for playback (without analysis)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.loadOriginalAudio(url: url)
            }
        }
    }
    
    /// Load analysis from cache if available
    func loadFromCache() {
        guard let url = currentInputURL else { return }
        loadFromCache(url: url)
    }
    
    /// Load directly from cache key (when original file may not exist)
    func loadFromCacheKey(_ key: String) {
        guard let metadata = CacheManager.shared.getMetadataFromKey(key),
              let stems = CacheManager.shared.getStemURLsFromKey(key) else {
            handleError("Could not load cached analysis")
            return
        }
        
        cleanup()
        
        // Set the input URL for settings tracking
        currentInputURL = URL(fileURLWithPath: metadata.originalPath)
        
        DispatchQueue.main.async {
            self.fileName = URL(fileURLWithPath: metadata.originalPath).lastPathComponent
            self.isProcessing = true
            self.processingStatus = "Loading from cache..."
            self.processingProgress = 0.5
            self.estimatedTimeRemaining = 0
            
            // Load settings for this song
            self.loadSongSettings()
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Convert to expected format, normalize names, and sort by display name order
            var loadedStems = stems.map { (name: $0.name, displayName: Self.normalizeDisplayName($0.name), url: $0.url) }
            loadedStems.sort { stem1, stem2 in
                let idx1 = Self.demucsDisplayNames.firstIndex(of: stem1.displayName) ?? Int.max
                let idx2 = Self.demucsDisplayNames.firstIndex(of: stem2.displayName) ?? Int.max
                return idx1 < idx2
            }
            
            // Load buffers
            var buffers: [AVAudioPCMBuffer] = []
            var names: [String] = []
            
            for stem in loadedStems {
                do {
                    let file = try AVAudioFile(forReading: stem.url)
                    let frameCount = AVAudioFrameCount(file.length)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                        continue
                    }
                    try file.read(into: buffer)
                    buffers.append(buffer)
                    names.append(stem.displayName)
                } catch {
                    print("Failed to load cached stem \(stem.name): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.cleanupOriginalPlayer()
                
                self.audioBuffers = buffers
                self.stemNames = names
                self.componentCount = buffers.count
                self.sampleRate = metadata.sampleRate
                self.duration = metadata.duration
                
                self.faderValues = Array(repeating: 1.0, count: buffers.count)
                self.panValues = Array(repeating: 0.0, count: buffers.count)
                self.soloStates = Array(repeating: false, count: buffers.count)
                self.muteStates = Array(repeating: false, count: buffers.count)
                self.meterLevels = Array(repeating: 0.0, count: buffers.count)
                self.selectionStart = 0
                self.selectionEnd = 0
                
                self.setupPlayerNodes()
                self.computeWaveformSamples()
                
                self.hasLoadedFile = false
                self.hasSession = true
                self.loadedFromCache = true
                self.isProcessing = false
                self.processingStatus = ""
                self.processingProgress = 1
                self.estimatedTimeRemaining = 0
            }
        }
    }
    
    /// Load stems from cache
    private func loadFromCache(url: URL) {
        guard let metadata = CacheManager.shared.loadMetadata(for: url),
              let stems = CacheManager.shared.getStemURLs(for: url) else {
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingStatus = "Loading from cache..."
            self.processingProgress = 0.5
            self.estimatedTimeRemaining = 0
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Convert to expected format, normalize names, and sort by display name order
            var loadedStems = stems.map { (name: $0.name, displayName: Self.normalizeDisplayName($0.name), url: $0.url) }
            loadedStems.sort { stem1, stem2 in
                let idx1 = Self.demucsDisplayNames.firstIndex(of: stem1.displayName) ?? Int.max
                let idx2 = Self.demucsDisplayNames.firstIndex(of: stem2.displayName) ?? Int.max
                return idx1 < idx2
            }
            
            // Load buffers
            var buffers: [AVAudioPCMBuffer] = []
            var names: [String] = []
            
            for stem in loadedStems {
                do {
                    let file = try AVAudioFile(forReading: stem.url)
                    let frameCount = AVAudioFrameCount(file.length)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                        continue
                    }
                    try file.read(into: buffer)
                    buffers.append(buffer)
                    names.append(stem.displayName)
                } catch {
                    print("Failed to load cached stem \(stem.name): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                // Clean up original audio player
                self.cleanupOriginalPlayer()
                
                self.audioBuffers = buffers
                self.stemNames = names
                self.componentCount = buffers.count
                self.sampleRate = metadata.sampleRate
                self.duration = metadata.duration
                
                self.faderValues = Array(repeating: 1.0, count: buffers.count)
                self.panValues = Array(repeating: 0.0, count: buffers.count)
                self.soloStates = Array(repeating: false, count: buffers.count)
                self.muteStates = Array(repeating: false, count: buffers.count)
                self.meterLevels = Array(repeating: 0.0, count: buffers.count)
                self.selectionStart = 0
                self.selectionEnd = 0
                
                self.setupPlayerNodes()
                self.computeWaveformSamples()
                
                self.hasLoadedFile = false
                self.hasSession = true
                self.loadedFromCache = true
                self.isProcessing = false
                self.processingStatus = ""
                self.processingProgress = 1
                self.estimatedTimeRemaining = 0
            }
        }
    }
    
    /// Re-analyze the file, ignoring cache
    func reanalyze() {
        guard let url = currentInputURL else { return }
        
        // Clear cache for this file
        CacheManager.shared.clearCache(for: url)
        
        // Reset state to allow re-analysis, then run analyze
        // We need hasLoadedFile = true for analyze() to work
        DispatchQueue.main.async {
            self.hasCachedAnalysis = false
            self.loadedFromCache = false
            self.hasSession = false
            self.hasLoadedFile = true
            self.cacheModifiedCounter += 1  // Signal UI to refresh cache list
            
            // Run fresh analysis after state is set
            self.analyze()
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
        
        // Install tap for metering original audio
        let tapFormat = meterMixer.outputFormat(forBus: 0)
        if tapFormat.sampleRate > 0 {
            meterMixer.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] tapBuffer, _ in
                guard let self = self else { return }
                let level = self.calculateRMS(buffer: tapBuffer)
                self.originalPeakLevel = max(level, self.originalPeakLevel * self.meterDecay)
            }
        }
        
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
            self.analysisStartTime = Date()
            
            // Calculate estimated total time based on audio duration and processing rate
            let audioDurationMinutes = self.duration / 60.0
            self.estimatedTotalTime = audioDurationMinutes * self.processingRate * 60.0 // Convert back to seconds
            self.estimatedTimeRemaining = self.estimatedTotalTime
            
            // Start progress timer
            self.startProgressTimer()
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processWithDemucs(url: url)
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
    
    /// Initialize Demucs (verifies Python and demucs package are available)
    private func loadDemucsModel() -> Bool {
        // Already loaded?
        if demucsModel != nil {
            return true
        }
        
        // Already failed?
        if modelLoadError != nil {
            return false
        }
        
        // Initialize demucs (model path is ignored, uses Python subprocess)
        demucsModel = demucs_load_model(nil)
        
        if demucsModel == nil {
            modelLoadError = "Demucs not available. Please install Python 3 and run: pip install demucs"
            return false
        }
        
        return true
    }
    
    private func processWithDemucs(url: URL) {
        // Initialize demucs if not already done
        if !loadDemucsModel() {
            handleError(modelLoadError ?? "Failed to initialize Demucs")
            return
        }
        
        // Create temp directory for output
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Remix_\(UUID().uuidString)")
        tempDirectory = tempDir
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            handleError("Failed to create temp directory: \(error.localizedDescription)")
            return
        }
        
        // Convert input to WAV if needed using our Rust library
        
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
        
        // Run Demucs separation via Rust FFI
        let result = demucs_separate(demucsModel, inputPath, tempDir.path)
        
        // Check for errors
        if let errorPtr = result.error {
            let errorMsg = String(cString: errorPtr)
            demucs_free_result(result)
            handleError("Demucs separation failed: \(errorMsg)")
            return
        }
        
        // Collect stem paths
        var loadedStems: [(name: String, displayName: String, url: URL)] = []
        
        for i in 0..<Int(result.stem_count) {
            guard let namePtr = result.stem_names?[i],
                  let pathPtr = result.stem_paths?[i] else {
                continue
            }
            
            let name = String(cString: namePtr)
            let path = String(cString: pathPtr)
            let stemURL = URL(fileURLWithPath: path)
            
            // Find display name
            let displayName: String
            if let idx = Self.demucsStems.firstIndex(of: name) {
                displayName = Self.demucsDisplayNames[idx]
            } else {
                displayName = name.capitalized
            }
            
            if FileManager.default.fileExists(atPath: stemURL.path) {
                loadedStems.append((name, displayName, stemURL))
            }
        }
        
        // Free the result
        demucs_free_result(result)
        
        if loadedStems.isEmpty {
            handleError("No stems were produced by Demucs")
            return
        }
        
        // Sort stems in expected order
        loadedStems.sort { stem1, stem2 in
            let idx1 = Self.demucsStems.firstIndex(of: stem1.name) ?? Int.max
            let idx2 = Self.demucsStems.firstIndex(of: stem2.name) ?? Int.max
            return idx1 < idx2
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
        
        // Save to cache
        if let inputURL = currentInputURL, !stems.isEmpty {
            let saved = CacheManager.shared.saveStems(
                for: inputURL,
                stems: stems,
                sampleRate: detectedSampleRate,
                duration: detectedDuration
            )
            if saved {
                print("Saved stems to cache")
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update processing rate based on actual time taken
            if let startTime = self.analysisStartTime {
                let actualTime = Date().timeIntervalSince(startTime)
                let audioDurationMinutes = detectedDuration / 60.0
                if audioDurationMinutes > 0 {
                    let newRate = (actualTime / 60.0) / audioDurationMinutes
                    // Smooth the rate with exponential moving average (80% old, 20% new)
                    self.processingRate = self.processingRate * 0.8 + newRate * 0.2
                }
            }
            
            // Stop progress timer
            self.stopProgressTimer()
            
            // Clean up original audio player (no longer needed after analysis)
            self.cleanupOriginalPlayer()
            
            self.audioBuffers = buffers
            self.stemNames = names
            self.componentCount = buffers.count
            self.sampleRate = detectedSampleRate
            self.duration = detectedDuration
            
            self.faderValues = Array(repeating: 1.0, count: buffers.count)
            self.panValues = Array(repeating: 0.0, count: buffers.count)
            self.soloStates = Array(repeating: false, count: buffers.count)
            self.muteStates = Array(repeating: false, count: buffers.count)
            self.meterLevels = Array(repeating: 0.0, count: buffers.count)
            self.selectionStart = 0
            self.selectionEnd = 0
            
            self.setupPlayerNodes()
            self.computeWaveformSamples()
            
            self.hasLoadedFile = false  // No longer in pre-analysis state
            self.hasSession = true
            self.loadedFromCache = false  // Fresh analysis
            self.hasCachedAnalysis = true  // Now cached
            self.cacheModifiedCounter += 1  // Signal UI to refresh cache list
            self.isProcessing = false
            self.processingStatus = ""
            self.processingProgress = 1
            self.estimatedTimeRemaining = 0
            self.analysisStartTime = nil
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
    
    // MARK: - Helper Methods
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
    
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.stopProgressTimer()
            self.isProcessing = false
            self.processingStatus = ""
            self.processingProgress = 0
            self.estimatedTimeRemaining = 0
            self.analysisStartTime = nil
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
        
        let totalFrames = audioBuffers.first.map { Int($0.frameLength) } ?? 0
        let hasRegion = selectionEnd > selectionStart
        
        // If there's a region and pauseTime is outside it, jump to region start
        if hasRegion {
            if pauseTime < selectionStart || pauseTime >= selectionEnd {
                pauseTime = selectionStart
                currentTime = selectionStart
            }
        }
        
        // Calculate frame range to play
        let startFrame: Int
        let length: Int
        
        if hasRegion {
            // Play from current position to end of region (will loop back to region start)
            let regionStartFrame = Int(Double(totalFrames) * (selectionStart / duration))
            let regionEndFrame = Int(Double(totalFrames) * (selectionEnd / duration))
            let currentFrame = Int(Double(totalFrames) * (pauseTime / duration))
            startFrame = max(regionStartFrame, min(regionEndFrame, currentFrame))
            length = regionEndFrame - startFrame
        } else {
            // Play from current position to end
            startFrame = duration > 0 ? Int(Double(totalFrames) * (pauseTime / duration)) : 0
            length = totalFrames - startFrame
        }
        
        let clampedStartFrame = max(0, min(totalFrames, startFrame))
        let clampedLength = max(0, min(totalFrames - clampedStartFrame, length))
        
        for (i, player) in playerNodes.enumerated() {
            guard i < audioBuffers.count else { continue }
            let buffer = audioBuffers[i]
            
            player.stop()
            
            if clampedLength > 0 {
                if let sliced = sliceBuffer(buffer, start: clampedStartFrame, length: clampedLength) {
                    player.scheduleBuffer(sliced, at: nil, options: [])
                } else {
                    player.scheduleBuffer(buffer, at: nil, options: [])
                }
            } else {
                player.scheduleBuffer(buffer, at: nil, options: [])
            }
            
            updateGain(for: i)
            updatePan(for: i)
            player.play()
        }
        
        isPlaying = true
        startTime = CACurrentMediaTime() - pauseTime
        startTimer()
    }
    
    private func playOriginalAudio() {
        guard let buffer = originalAudioBuffer, let player = originalPlayerNode else { return }
        if isPlaying { return }
        
        let totalFrames = Int(buffer.frameLength)
        let hasRegion = selectionEnd > selectionStart
        
        // If there's a region and pauseTime is outside it, jump to region start
        if hasRegion {
            if pauseTime < selectionStart || pauseTime >= selectionEnd {
                pauseTime = selectionStart
                currentTime = selectionStart
            }
        }
        
        // Calculate frame range to play
        let startFrame: Int
        let length: Int
        
        if hasRegion {
            let regionStartFrame = Int(Double(totalFrames) * (selectionStart / duration))
            let regionEndFrame = Int(Double(totalFrames) * (selectionEnd / duration))
            let currentFrame = Int(Double(totalFrames) * (pauseTime / duration))
            startFrame = max(regionStartFrame, min(regionEndFrame, currentFrame))
            length = regionEndFrame - startFrame
        } else {
            startFrame = duration > 0 ? Int(Double(totalFrames) * (pauseTime / duration)) : 0
            length = totalFrames - startFrame
        }
        
        let clampedStartFrame = max(0, min(totalFrames, startFrame))
        let clampedLength = max(0, min(totalFrames - clampedStartFrame, length))
        
        player.stop()
        
        if clampedLength > 0 {
            if let sliced = sliceBuffer(buffer, start: clampedStartFrame, length: clampedLength) {
                player.scheduleBuffer(sliced, at: nil, options: [])
            } else {
                player.scheduleBuffer(buffer, at: nil, options: [])
            }
        } else {
            player.scheduleBuffer(buffer, at: nil, options: [])
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
        // Don't stop timer - let meters decay naturally
        startMeterDecayTimer()
    }
    
    func stop() {
        if hasSession {
            for player in playerNodes { player.stop() }
        } else {
            originalPlayerNode?.stop()
        }
        
        isPlaying = false
        // Don't stop timer - let meters decay naturally
        startMeterDecayTimer()
    }
    
    func stopAndReset() {
        stop()
        pauseTime = 0
        currentTime = 0
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
    
    func setPanValue(_ value: Double, for index: Int) {
        guard index < panValues.count else { return }
        panValues[index] = max(-1.0, min(1.0, value))
        updatePan(for: index)
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
            panValues[i] = 0.0
            soloStates[i] = false
            muteStates[i] = false
        }
        updateAllGains()
        updateAllPans()
    }
    
    func zeroAllFaders() {
        for i in 0..<componentCount {
            faderValues[i] = 0.0
        }
        updateAllGains()
    }
    
    func centerAllPans() {
        for i in 0..<componentCount {
            panValues[i] = 0.0
        }
        updateAllPans()
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        timePitchNode?.rate = rate
    }
    
    func setPitch(_ cents: Float) {
        pitch = max(-200, min(200, cents))
        timePitchNode?.pitch = pitch
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
    
    private func updatePan(for index: Int) {
        guard index < playerNodes.count, index < panValues.count else { return }
        // AVAudioPlayerNode pan: -1.0 (left) to 1.0 (right)
        playerNodes[index].pan = Float(panValues[index])
    }
    
    private func updateAllGains() {
        for i in 0..<playerNodes.count { updateGain(for: i) }
    }
    
    private func updateAllPans() {
        for i in 0..<playerNodes.count { updatePan(for: i) }
    }
    
    // MARK: - Timer
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Start a timer that decays meters to zero after playback stops
    private func startMeterDecayTimer() {
        // Stop any existing timer (e.g. from playback) and start decay timer
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.updateMeterDecay()
        }
    }
    
    /// Update meter decay when not playing
    private func updateMeterDecay() {
        var allZero = true
        
        if hasSession {
            // Decay stem meters
            for i in 0..<peakLevels.count {
                peakLevels[i] *= meterDecay
                if peakLevels[i] < 0.001 {
                    peakLevels[i] = 0
                }
            }
            for i in 0..<meterLevels.count {
                meterLevels[i] = peakLevels.indices.contains(i) ? peakLevels[i] : 0
                if meterLevels[i] > 0.001 {
                    allZero = false
                }
            }
        } else {
            // Decay original audio meter
            originalPeakLevel *= meterDecay
            if originalPeakLevel < 0.001 {
                originalPeakLevel = 0
            }
            originalMeterLevel = originalPeakLevel
            if originalMeterLevel > 0.001 {
                allZero = false
            }
        }
        
        // Stop timer once all meters have decayed to zero
        if allZero {
            stopTimer()
        }
    }
    
    // MARK: - Progress Timer
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgressEstimate()
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgressEstimate() {
        guard let startTime = analysisStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        if estimatedTotalTime > 0 {
            // Calculate progress (cap at 0.95 until actually complete)
            let progress = min(0.95, elapsed / estimatedTotalTime)
            processingProgress = progress
            
            // Calculate time remaining
            let remaining = max(0, estimatedTotalTime - elapsed)
            estimatedTimeRemaining = remaining
            
            // Update status with time estimate
            if remaining > 60 {
                let mins = Int(remaining / 60)
                processingStatus = "Processing... ~\(mins)m remaining"
            } else if remaining > 0 {
                let secs = Int(remaining)
                processingStatus = "Processing... ~\(secs)s remaining"
            } else {
                processingStatus = "Processing... almost done"
            }
        }
    }
    
    private func updateTime() {
        guard isPlaying else { return }
        
        let time = CACurrentMediaTime() - startTime
        let hasRegion = selectionEnd > selectionStart
        
        // Check if we've reached the end of region/track
        if hasRegion {
            if time >= selectionEnd {
                // Region playback - loop back to start of region
                restartFromPosition(selectionStart)
                return
            }
        } else if time >= duration {
            if isLooping {
                // Full track looping
                restartFromPosition(0)
                return
            } else {
                stopAndReset()
                return
            }
        }
        
        currentTime = min(time, duration)
        
        // Update meters from real audio levels
        if hasSession {
            // Analyzed mode: update per-stem meters
            for i in 0..<meterLevels.count {
                if i < peakLevels.count {
                    meterLevels[i] = peakLevels[i]
                } else {
                    meterLevels[i] = 0
                }
            }
        } else {
            // Pre-analysis mode: update original meter level
            originalMeterLevel = originalPeakLevel
        }
    }
    
    private func restartFromPosition(_ position: Double) {
        // Stop current playback without resetting state
        if hasSession {
            for player in playerNodes { player.stop() }
        } else {
            originalPlayerNode?.stop()
        }
        isPlaying = false
        
        // Set new position and restart
        pauseTime = position
        currentTime = position
        play()
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
        stopProgressTimer()
        
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
        
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
        
        hasLoadedFile = false
        hasSession = false
        loadedFromCache = false
        hasCachedAnalysis = false
        componentCount = 0
        stemNames.removeAll()
        faderValues.removeAll()
        panValues.removeAll()
        soloStates.removeAll()
        muteStates.removeAll()
        meterLevels.removeAll()
        duration = 0
        currentTime = 0
        waveformSamples.removeAll()
        selectionStart = 0
        selectionEnd = 0
        processingProgress = 0
        estimatedTimeRemaining = 0
        estimatedTotalTime = 0
        
        // Clear current input URL (this will prevent saving settings after cleanup)
        currentInputURL = nil
    }
}
