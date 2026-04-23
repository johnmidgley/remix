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
        let bpm: Double?  // Average BPM (nil for old cache)
        let clickAlignmentOffset: Double?  // DEPRECATED: Time offset in seconds (nil for old cache)
        let beatTimes: [Double]?  // DEPRECATED: Replaced by tempoMap
        let tempoMap: [[Double]]?  // Tempo map: [[time, bpm], [time, bpm], ...] (nil for old cache)
    }
    
    private init() {
        // Create cache directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("Remix/cache", isDirectory: true)
        
        // Ensure cache directory exists
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Generate a unique cache key for a file based on its content hash
    func cacheKey(for fileURL: URL) -> String? {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let hash = SHA256.hash(data: fileData)
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
            createdAt: Date(),
            bpm: nil,
            clickAlignmentOffset: nil,
            beatTimes: nil,
            tempoMap: nil
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
    @Published var showEQWindow: Bool = false
    @Published var eqSettings: [String: EQBandSettings] = [:]  // Key: stem name or "master"
    @Published var eqResetCounter: Int = 0  // Increments to force UI refresh
    @Published var eqBandLevels: [Float] = Array(repeating: 0, count: 8)  // Real-time levels for 8 EQ bands
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
    @Published var playbackRate: Float = 1.0
    @Published var pitch: Float = 0.0  // Pitch shift in cents (-200 to +200)
    @Published var masterFaderValue: Double = 1.0  // Master gain applied to stem path only; stored as linear amp (0..~1.995 with +6 dB ceiling)
    @Published var isNormalizingStems: Bool = false
    @Published private(set) var stemsNormalized: Bool = false
    @Published var originalEnabled: Bool = false
    @Published private(set) var stemNormalizeGainsDB: [Float] = []
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
    // Sits between the per-stem meter taps and mixerNode. We silence its
    // output (not the stems themselves) when the pristine original takes
    // over, so per-stem meters still animate with their real signal.
    private var stemOutputGate: AVAudioMixerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var eqNodes: [AVAudioUnitEQ] = []  // EQ for each stem
    private var masterEQNode: AVAudioUnitEQ?   // Master EQ
    private var eqMeterNode: AVAudioMixerNode? // Meter node for EQ analysis
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var meterTapNodes: [AVAudioMixerNode] = []  // For metering
    private var eqBandPeakLevels: [Float] = Array(repeating: 0, count: 8)
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
    
    // Click track is now managed as a regular audio buffer in audioBuffers[]

    // Pending per-stem mixer values loaded from persisted song settings.
    // loadSongSettings() runs before the stems are actually wired up, so we
    // stash the values here and apply them keyed by stem display name once
    // the stems appear.
    private var pendingFaderValues: [String: Double] = [:]
    private var pendingPanValues: [String: Double] = [:]
    private var pendingMuteStates: [String: Bool] = [:]
    private var pendingSoloStates: [String: Bool] = [:]
    private var pendingStemNormalizeGains: [String: Float] = [:]
    // Playhead/selection are also loaded before duration is known, so we stash
    // them here and clamp-apply once the audio is wired up.
    private var pendingPlayheadPosition: Double = 0
    private var pendingSelectionStart: Double = 0
    private var pendingSelectionEnd: Double = 0

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
        var eqSettings: [String: EQBandSettings] = [:]  // Key: stem name or "master"
        // Per-stem mixer state, keyed by stem display name so order changes
        // don't misalign values. Missing keys fall back to defaults when
        // applied to a fresh stem set.
        var faderValues: [String: Double] = [:]
        var panValues: [String: Double] = [:]
        var muteStates: [String: Bool] = [:]
        var soloStates: [String: Bool] = [:]
        // Playhead and loop-region state so a song reopens where it was left.
        var playheadPosition: Double = 0
        var selectionStart: Double = 0
        var selectionEnd: Double = 0
        // Per-stem normalize gains keyed by display name.
        var stemNormalizeGains: [String: Float] = [:]
        // Whether the user has switched the mixer to play the pristine original.
        var originalEnabled: Bool = false
        // Master fader (stem-path only). Stored as linear amp, default 1.0 = 0 dB.
        var masterFaderValue: Double = 1.0

        init(
            playbackRate: Float = 1.0,
            pitch: Float = 0.0,
            isLooping: Bool = false,
            eqSettings: [String: EQBandSettings] = [:],
            faderValues: [String: Double] = [:],
            panValues: [String: Double] = [:],
            muteStates: [String: Bool] = [:],
            soloStates: [String: Bool] = [:],
            playheadPosition: Double = 0,
            selectionStart: Double = 0,
            selectionEnd: Double = 0,
            stemNormalizeGains: [String: Float] = [:],
            originalEnabled: Bool = false,
            masterFaderValue: Double = 1.0
        ) {
            self.playbackRate = playbackRate
            self.pitch = pitch
            self.isLooping = isLooping
            self.eqSettings = eqSettings
            self.faderValues = faderValues
            self.panValues = panValues
            self.muteStates = muteStates
            self.soloStates = soloStates
            self.playheadPosition = playheadPosition
            self.selectionStart = selectionStart
            self.selectionEnd = selectionEnd
            self.stemNormalizeGains = stemNormalizeGains
            self.originalEnabled = originalEnabled
            self.masterFaderValue = masterFaderValue
        }

        // Custom decoder: every field is decodeIfPresent so saved blobs from
        // earlier app versions (missing the newer fields) still load without
        // losing the fields they do contain.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            playbackRate = try c.decodeIfPresent(Float.self, forKey: .playbackRate) ?? 1.0
            pitch = try c.decodeIfPresent(Float.self, forKey: .pitch) ?? 0.0
            isLooping = try c.decodeIfPresent(Bool.self, forKey: .isLooping) ?? false
            eqSettings = try c.decodeIfPresent([String: EQBandSettings].self, forKey: .eqSettings) ?? [:]
            faderValues = try c.decodeIfPresent([String: Double].self, forKey: .faderValues) ?? [:]
            panValues = try c.decodeIfPresent([String: Double].self, forKey: .panValues) ?? [:]
            muteStates = try c.decodeIfPresent([String: Bool].self, forKey: .muteStates) ?? [:]
            soloStates = try c.decodeIfPresent([String: Bool].self, forKey: .soloStates) ?? [:]
            playheadPosition = try c.decodeIfPresent(Double.self, forKey: .playheadPosition) ?? 0
            selectionStart = try c.decodeIfPresent(Double.self, forKey: .selectionStart) ?? 0
            selectionEnd = try c.decodeIfPresent(Double.self, forKey: .selectionEnd) ?? 0
            stemNormalizeGains = try c.decodeIfPresent([String: Float].self, forKey: .stemNormalizeGains) ?? [:]
            originalEnabled = try c.decodeIfPresent(Bool.self, forKey: .originalEnabled) ?? false
            masterFaderValue = try c.decodeIfPresent(Double.self, forKey: .masterFaderValue) ?? 1.0
        }
    }
    
    struct EQBandSettings: Codable {
        var bands: [EQBand] = []
        
        init() {
            // Initialize 8 bands with default frequencies
            let frequencies: [Float] = [60, 150, 400, 1000, 2500, 6000, 12000, 16000]
            bands = frequencies.map { freq in
                EQBand(frequency: freq, gain: 0, q: 1.0, bypass: false)
            }
        }
    }
    
    struct EQBand: Codable, Identifiable {
        let id = UUID()
        var frequency: Float
        var gain: Float  // -12 to +12 dB
        var q: Float     // 0.1 to 10
        var bypass: Bool
        
        enum CodingKeys: String, CodingKey {
            case frequency, gain, q, bypass
        }
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

        // Save the current track's settings on app quit. Together with the
        // save at the top of cleanup() (which runs when the user switches
        // tracks), this covers every way a track can be "left".
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveCurrentSongSettings()
        }
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

        // Project the runtime arrays onto stem-name-keyed dicts. If arrays
        // and stemNames drift out of sync for any reason we just skip the
        // missing entries rather than write garbage.
        var savedFaders: [String: Double] = [:]
        var savedPans: [String: Double] = [:]
        var savedMutes: [String: Bool] = [:]
        var savedSolos: [String: Bool] = [:]
        var savedStemNorm: [String: Float] = [:]
        for (i, name) in stemNames.enumerated() {
            if i < faderValues.count { savedFaders[name] = faderValues[i] }
            if i < panValues.count { savedPans[name] = panValues[i] }
            if i < muteStates.count { savedMutes[name] = muteStates[i] }
            if i < soloStates.count { savedSolos[name] = soloStates[i] }
            if i < stemNormalizeGainsDB.count { savedStemNorm[name] = stemNormalizeGainsDB[i] }
        }

        let settings = SongSettings(
            playbackRate: playbackRate,
            pitch: pitch,
            isLooping: isLooping,
            eqSettings: eqSettings,
            faderValues: savedFaders,
            panValues: savedPans,
            muteStates: savedMutes,
            soloStates: savedSolos,
            // Prefer pauseTime when paused (slightly more precise than the
            // display-throttled currentTime); otherwise currentTime.
            playheadPosition: isPlaying ? currentTime : max(pauseTime, currentTime),
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            stemNormalizeGains: savedStemNorm,
            originalEnabled: originalEnabled,
            masterFaderValue: masterFaderValue
        )

        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "song_settings_\(songKey)")
        }
    }

    private func loadSongSettings() {
        guard let songKey = currentSongKey else {
            resetSongSettingsToDefaults()
            return
        }

        // Try to load saved settings for this song
        if let data = UserDefaults.standard.data(forKey: "song_settings_\(songKey)"),
           let settings = try? JSONDecoder().decode(SongSettings.self, from: data) {
            playbackRate = settings.playbackRate
            pitch = settings.pitch
            isLooping = settings.isLooping
            eqSettings = settings.eqSettings
            pendingFaderValues = settings.faderValues
            pendingPanValues = settings.panValues
            pendingMuteStates = settings.muteStates
            pendingSoloStates = settings.soloStates
            pendingStemNormalizeGains = settings.stemNormalizeGains
            pendingPlayheadPosition = settings.playheadPosition
            pendingSelectionStart = settings.selectionStart
            pendingSelectionEnd = settings.selectionEnd
            timePitchNode?.rate = settings.playbackRate
            timePitchNode?.pitch = settings.pitch
            applyEQSettings()
            originalEnabled = settings.originalEnabled
            masterFaderValue = settings.masterFaderValue
        } else {
            resetSongSettingsToDefaults()
        }
    }

    private func resetSongSettingsToDefaults() {
        playbackRate = 1.0
        pitch = 0.0
        isLooping = false
        eqSettings = [:]
        pendingFaderValues = [:]
        pendingPanValues = [:]
        pendingMuteStates = [:]
        pendingSoloStates = [:]
        pendingStemNormalizeGains = [:]
        pendingPlayheadPosition = 0
        pendingSelectionStart = 0
        pendingSelectionEnd = 0
        timePitchNode?.rate = 1.0
        timePitchNode?.pitch = 0.0
        originalEnabled = false
        masterFaderValue = 1.0
    }

    /// Applies the pending playhead/selection values clamped to the current
    /// duration. Call after duration has been set from the loaded audio.
    private func applyPendingPlaybackPosition() {
        guard duration > 0 else {
            currentTime = 0
            pauseTime = 0
            selectionStart = 0
            selectionEnd = 0
            return
        }
        let clampedPos = max(0, min(duration, pendingPlayheadPosition))
        let clampedSelStart = max(0, min(duration, pendingSelectionStart))
        let clampedSelEnd = max(0, min(duration, pendingSelectionEnd))
        currentTime = clampedPos
        pauseTime = clampedPos
        // Only keep a selection if it's still a non-empty range after clamp.
        if clampedSelEnd > clampedSelStart {
            selectionStart = clampedSelStart
            selectionEnd = clampedSelEnd
        } else {
            selectionStart = 0
            selectionEnd = 0
        }
    }

    /// Produces mixer arrays aligned to the given stem names, drawing from
    /// the last-loaded persisted settings (pending*) and filling gaps with
    /// defaults.
    private func mixerArrays(for names: [String]) -> (faders: [Double], pans: [Double], mutes: [Bool], solos: [Bool]) {
        let faders = names.map { pendingFaderValues[$0] ?? 1.0 }
        let pans = names.map { pendingPanValues[$0] ?? 0.0 }
        let mutes = names.map { pendingMuteStates[$0] ?? false }
        let solos = names.map { pendingSoloStates[$0] ?? false }
        return (faders, pans, mutes, solos)
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
        masterEQNode = AVAudioUnitEQ(numberOfBands: 8)
        eqMeterNode = AVAudioMixerNode()
        
        guard let engine = audioEngine, let mixer = mixerNode, let timePitch = timePitchNode, let masterEQ = masterEQNode, let eqMeter = eqMeterNode else { return }
        
        engine.attach(mixer)
        engine.attach(timePitch)
        engine.attach(masterEQ)
        engine.attach(eqMeter)
        
        // Initialize master EQ bands
        configureMasterEQ()
        
        // Connect mixer -> masterEQ -> eqMeter -> timePitch -> mainMixer (output)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: masterEQ, format: format)
        engine.connect(masterEQ, to: eqMeter, format: format)
        engine.connect(eqMeter, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        
        // Install tap for EQ band metering
        setupEQMeterTap()
    }
    
    private func setupEQMeterTap() {
        guard let eqMeter = eqMeterNode, let engine = audioEngine else { return }
        
        // Remove existing tap if any
        eqMeter.removeTap(onBus: 0)
        
        // Ensure engine is running
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Failed to start engine for EQ tap: \(error)")
                return
            }
        }
        
        let tapFormat = eqMeter.outputFormat(forBus: 0)
        if tapFormat.sampleRate > 0 {
            eqMeter.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
                guard let self = self, self.isPlaying else { return }
                self.analyzeEQBands(buffer: buffer)
            }
        }
    }
    
    private func analyzeEQBands(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        guard frameLength > 0 else { return }
        
        // Simple band energy estimation using RMS with frequency weighting
        // For more accurate results, we'd use FFT, but this provides a good approximation
        var bandLevels: [Float] = Array(repeating: 0, count: 8)
        
        for channel in 0..<channelCount {
            let data = channelData[channel]
            
            // Calculate RMS for the entire signal
            var totalEnergy: Float = 0
            for frame in 0..<frameLength {
                let sample = data[frame]
                totalEnergy += sample * sample
            }
            let rms = sqrt(totalEnergy / Float(frameLength))
            
            // Distribute energy across bands with weighting
            // This is a simplified approach - ideally we'd use FFT
            for bandIndex in 0..<8 {
                // Apply a weighting factor based on typical frequency content
                let weight: Float
                if bandIndex < 2 {
                    weight = 0.9 // Low frequencies (60, 150 Hz)
                } else if bandIndex < 4 {
                    weight = 1.3 // Low-mid frequencies (400, 1k Hz) - typically louder
                } else if bandIndex < 6 {
                    weight = 1.1 // Mid-high frequencies (2.5k, 6k Hz)
                } else {
                    weight = 0.7 // High frequencies (12k, 16k Hz)
                }
                
                bandLevels[bandIndex] += rms * weight
            }
        }
        
        // Average across channels and normalize
        for i in 0..<bandLevels.count {
            bandLevels[i] = bandLevels[i] / Float(channelCount)
            bandLevels[i] = min(1.0, bandLevels[i] * 3.0) // Scale and clamp
            
            // Apply peak hold with decay
            eqBandPeakLevels[i] = max(bandLevels[i], eqBandPeakLevels[i] * meterDecay)
        }
        
        // Update published values on main thread
        DispatchQueue.main.async {
            self.eqBandLevels = self.eqBandPeakLevels
        }
    }
    
    private func configureMasterEQ() {
        guard let masterEQ = masterEQNode else { return }
        
        let frequencies: [Float] = [60, 150, 400, 1000, 2500, 6000, 12000, 16000]
        for (index, freq) in frequencies.enumerated() where index < masterEQ.bands.count {
            let band = masterEQ.bands[index]
            band.frequency = freq
            band.gain = 0
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.bypass = false
        }
    }
    
    private func configureEQNode(_ eqNode: AVAudioUnitEQ) {
        let frequencies: [Float] = [60, 150, 400, 1000, 2500, 6000, 12000, 16000]
        for (index, freq) in frequencies.enumerated() where index < eqNode.bands.count {
            let band = eqNode.bands[index]
            band.frequency = freq
            band.gain = 0
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.bypass = false
        }
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

                let mixer = self.mixerArrays(for: names)
                self.faderValues = mixer.faders
                self.panValues = mixer.pans
                self.muteStates = mixer.mutes
                self.soloStates = mixer.solos
                self.meterLevels = Array(repeating: 0.0, count: buffers.count)
                self.applyPendingPlaybackPosition()

                self.setupPlayerNodes()
                self.setupEQMeterTap()  // Reinstall tap after engine is started
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
                self.audioBuffers = buffers
                self.stemNames = names
                self.componentCount = buffers.count
                self.sampleRate = metadata.sampleRate
                self.duration = metadata.duration

                let mixer = self.mixerArrays(for: names)
                self.faderValues = mixer.faders
                self.panValues = mixer.pans
                self.muteStates = mixer.mutes
                self.soloStates = mixer.solos
                self.meterLevels = Array(repeating: 0.0, count: buffers.count)
                self.applyPendingPlaybackPosition()

                self.setupPlayerNodes()
                self.setupEQMeterTap()  // Reinstall tap after engine is started
                self.computeWaveformSamples()

                self.hasLoadedFile = false
                self.hasSession = true
                self.loadedFromCache = true
                self.isProcessing = false
                self.processingStatus = ""
                self.processingProgress = 1
                self.estimatedTimeRemaining = 0

                // Also load the pristine original so the "all faders at top"
                // shortcut can bypass the stem sum.
                self.loadOriginalBufferForSession(url: url)
            }
        }
    }

    /// Loads the pristine original audio file into the original player node
    /// so it can be used as a bypass source when the mixer has no
    /// modifications. Safe to call when the session is already active —
    /// unlike loadOriginalAudio(url:), this leaves hasSession/hasLoadedFile
    /// untouched.
    ///
    /// If the user is already playing when this finishes, shouldPlayOriginal()
    /// will keep returning false (the original isn't scheduled) until the next
    /// play cycle — simpler than reconciling a mid-playback start.
    private func loadOriginalBufferForSession(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let frameCount = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
                try file.read(into: buffer)

                DispatchQueue.main.async {
                    self.originalAudioBuffer = buffer
                    self.setupOriginalPlayerNode(buffer: buffer)
                    self.updateMasterSource()
                }
            } catch {
                NSLog("Failed to load original for session: %@", error.localizedDescription)
            }
        }
    }

    /// Re-analyze the file, ignoring cache
    func reanalyze() {
        NSLog("🎵 === RE-ANALYZE CALLED ===")
        guard let url = currentInputURL else {
            NSLog("🎵 ERROR: No current input URL")
            return
        }
        
        NSLog("🎵 Re-analyzing file: %@", url.lastPathComponent)
        
        // Clear cache for this file
        CacheManager.shared.clearCache(for: url)
        NSLog("🎵 Cache cleared for file")
        
        // Reset state to allow re-analysis, then run analyze
        // We need hasLoadedFile = true for analyze() to work
        DispatchQueue.main.async {
            self.hasCachedAnalysis = false
            self.loadedFromCache = false
            self.hasSession = false
            self.hasLoadedFile = true
            self.cacheModifiedCounter += 1  // Signal UI to refresh cache list
            
            NSLog("🎵 Starting fresh analysis...")
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
                self.applyPendingPlaybackPosition()

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

            // Keep the original player alive — it's used when the mixer is
            // in a "no modifications" state (see shouldPlayOriginal()).

            self.audioBuffers = buffers
            self.stemNames = names
            self.componentCount = buffers.count
            self.sampleRate = detectedSampleRate
            self.duration = detectedDuration

            let mixer = self.mixerArrays(for: names)
            self.faderValues = mixer.faders
            self.panValues = mixer.pans
            self.muteStates = mixer.mutes
            self.soloStates = mixer.solos
            self.meterLevels = Array(repeating: 0.0, count: buffers.count)
            self.applyPendingPlaybackPosition()

            self.setupPlayerNodes()
            self.setupEQMeterTap()  // Reinstall tap after engine is started
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
        for node in eqNodes {
            engine.detach(node)
        }
        if let gate = stemOutputGate {
            engine.detach(gate)
        }
        playerNodes.removeAll()
        meterTapNodes.removeAll()
        eqNodes.removeAll()
        peakLevels = Array(repeating: 0, count: audioBuffers.count)

        // Shared output gate for all stems. Lives between the per-stem meter
        // taps and mixerNode so we can silence the downstream audio via
        // outputVolume without starving the taps (which run at the stage
        // before this gate and therefore see the real stem signal).
        let gate = AVAudioMixerNode()
        engine.attach(gate)
        stemOutputGate = gate

        for (index, buffer) in audioBuffers.enumerated() {
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 8)
            let meterMixer = AVAudioMixerNode()

            engine.attach(player)
            engine.attach(eq)
            engine.attach(meterMixer)

            // Configure EQ bands
            configureEQNode(eq)

            // Player -> EQ -> MeterMixer -> StemOutputGate -> MainMixer
            engine.connect(player, to: eq, format: buffer.format)
            engine.connect(eq, to: meterMixer, format: buffer.format)
            engine.connect(meterMixer, to: gate, format: buffer.format)

            // Install tap for metering (before the gate so the meter animates
            // even while the original is taking over the audio).
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
            eqNodes.append(eq)
            meterTapNodes.append(meterMixer)
        }

        // Single connection from the gate down to the main mixer chain.
        engine.connect(gate, to: mixer, format: nil)

        // Apply the current master-source state (may silence the gate
        // immediately if shouldPlayOriginal() is already true).
        updateMasterSource()

        // Load EQ settings if available
        applyEQSettings()
        applyPendingStemNormalizeGains()
        updateAllGains()

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

        // Also run the pristine original in parallel. It plays silently
        // unless the mixer is in a "no modifications" state (see
        // shouldPlayOriginal()), in which case it takes over from the sum
        // of stems.
        if let origPlayer = originalPlayerNode, let origBuffer = originalAudioBuffer {
            let origTotalFrames = Int(origBuffer.frameLength)
            let origStartFrame: Int
            let origLength: Int
            if hasRegion {
                let regionStartFrame = Int(Double(origTotalFrames) * (selectionStart / duration))
                let regionEndFrame = Int(Double(origTotalFrames) * (selectionEnd / duration))
                let currentFrame = Int(Double(origTotalFrames) * (pauseTime / duration))
                origStartFrame = max(regionStartFrame, min(regionEndFrame, currentFrame))
                origLength = regionEndFrame - origStartFrame
            } else {
                origStartFrame = duration > 0 ? Int(Double(origTotalFrames) * (pauseTime / duration)) : 0
                origLength = origTotalFrames - origStartFrame
            }
            let clampedOrigStart = max(0, min(origTotalFrames, origStartFrame))
            let clampedOrigLength = max(0, min(origTotalFrames - clampedOrigStart, origLength))

            origPlayer.stop()
            if clampedOrigLength > 0, let sliced = sliceBuffer(origBuffer, start: clampedOrigStart, length: clampedOrigLength) {
                origPlayer.scheduleBuffer(sliced, at: nil, options: [])
            } else {
                origPlayer.scheduleBuffer(origBuffer, at: nil, options: [])
            }
            updateMasterSource()
            origPlayer.play()
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
            originalPlayerNode?.pause()
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
            originalPlayerNode?.stop()
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

        // A single fader move can cross the "all at max" threshold, so we
        // re-evaluate every stem gain plus the master-source toggle.
        updateAllGains()
    }

    func setMasterFaderValue(_ value: Double) {
        masterFaderValue = max(0, min(faderMaxAmp(maxBoostDB: faderMasterMaxBoostDB), value))
        updateAllGains()
    }

    func setPanValue(_ value: Double, for index: Int) {
        guard index < panValues.count else { return }
        panValues[index] = max(-1.0, min(1.0, value))
        updatePan(for: index)
        updateAllGains()
    }

    func toggleSolo(for index: Int) {
        guard index < soloStates.count else { return }
        soloStates[index].toggle()
        updateAllGains()
    }

    func toggleMute(for index: Int) {
        guard index < muteStates.count else { return }
        muteStates[index].toggle()
        updateAllGains()
    }

    func resetAllFaders() {
        for i in 0..<componentCount {
            faderValues[i] = 1.0
            panValues[i] = 0.0
            soloStates[i] = false
            muteStates[i] = false
        }
        masterFaderValue = 1.0
        clearStemNormalizeGains()
        updateAllGains()
        updateAllPans()
    }

    func resetAllSettings() {
        resetAllFaders()
        setPlaybackRate(1.0)
        setPitch(0.0)
        resetEQ(target: "Master")
        for stemName in stemNames {
            resetEQ(target: stemName)
        }
    }

    // MARK: - Mixer Presets

    /// Snapshots the current per-stem mixer state (faders, pans, solo/mute,
    /// EQ including master, stem normalize gains) into a reusable preset.
    func currentMixerPreset() -> MixerPreset {
        var preset = MixerPreset()
        for (i, name) in stemNames.enumerated() {
            if i < faderValues.count { preset.faderValues[name] = faderValues[i] }
            if i < panValues.count { preset.panValues[name] = panValues[i] }
            if i < muteStates.count { preset.muteStates[name] = muteStates[i] }
            if i < soloStates.count { preset.soloStates[name] = soloStates[i] }
            if i < stemNormalizeGainsDB.count { preset.stemNormalizeGains[name] = stemNormalizeGainsDB[i] }
        }
        preset.eqSettings = eqSettings
        return preset
    }

    /// Overwrites current mixer state with the preset. Stems missing from the
    /// preset get sensible defaults (unity / centered / off / 0 dB).
    func applyMixerPreset(_ preset: MixerPreset) {
        for (i, name) in stemNames.enumerated() {
            if i < faderValues.count { faderValues[i] = preset.faderValues[name] ?? 1.0 }
            if i < panValues.count { panValues[i] = preset.panValues[name] ?? 0.0 }
            if i < muteStates.count { muteStates[i] = preset.muteStates[name] ?? false }
            if i < soloStates.count { soloStates[i] = preset.soloStates[name] ?? false }
        }

        eqSettings = preset.eqSettings
        applyEQSettings()

        stemNormalizeGainsDB = stemNames.map { preset.stemNormalizeGains[$0] ?? 0 }
        applyStemNormalizeGains()  // calls updateAllGains, which also updates the master source
        updateAllPans()
    }

    /// Toggles stem normalization. If currently applied, clears it; otherwise
    /// triggers analysis + gain application.
    func toggleStemNormalize() {
        if stemsNormalized {
            clearStemNormalizeGains()
        } else {
            normalizeStemLevels()
        }
    }

    /// Measures integrated LUFS per stem and applies per-stem gain (via each
    /// stem's EQ globalGain) to bring them toward the median, capped at ±12 dB.
    /// Runs asynchronously; sets `isNormalizingStems` while in flight.
    func normalizeStemLevels() {
        guard !audioBuffers.isEmpty, !isNormalizingStems else { return }
        let buffers = audioBuffers
        isNormalizingStems = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let perStemLUFS: [Float?] = buffers.map {
                LoudnessAnalyzer.analyze(buffer: $0)?.integratedLUFS
            }
            let valid = perStemLUFS.compactMap { $0 }.sorted()

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isNormalizingStems = false
                guard !valid.isEmpty else { return }
                let median = valid[valid.count / 2]
                let gains: [Float] = perStemLUFS.map { lufs in
                    guard let l = lufs else { return 0 }
                    return max(-12, min(12, median - l))
                }
                self.stemNormalizeGainsDB = gains
                self.applyStemNormalizeGains()
            }
        }
    }

    private func applyStemNormalizeGains() {
        stemsNormalized = stemNormalizeGainsDB.contains { abs($0) > 0.01 }
        updateAllGains()
    }

    /// Aligns the pending (by-name) stem normalize gains to the current
    /// stemNames order and applies them. No-op if no pending gains.
    private func applyPendingStemNormalizeGains() {
        guard !pendingStemNormalizeGains.isEmpty else { return }
        stemNormalizeGainsDB = stemNames.map { pendingStemNormalizeGains[$0] ?? 0 }
        applyStemNormalizeGains()
        pendingStemNormalizeGains = [:]
    }

    private func clearStemNormalizeGains() {
        stemNormalizeGainsDB = Array(repeating: 0, count: stemNormalizeGainsDB.count)
        stemsNormalized = false
        updateAllGains()
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
    
    // MARK: - EQ Control
    func updateEQBand(target: String, bandIndex: Int, gain: Float, q: Float) {
        // Initialize EQ settings for this target if not exists
        if eqSettings[target] == nil {
            eqSettings[target] = EQBandSettings()
        }
        
        // Update stored settings
        if bandIndex < eqSettings[target]!.bands.count {
            eqSettings[target]!.bands[bandIndex].gain = gain
            eqSettings[target]!.bands[bandIndex].q = q
        }
        
        // Apply to audio nodes immediately
        applyEQToNode(target: target, bandIndex: bandIndex, gain: gain, q: q)
    }
    
    private func applyEQToNode(target: String, bandIndex: Int, gain: Float, q: Float) {
        if target == "Master" {
            if let masterEQ = masterEQNode, bandIndex < masterEQ.bands.count {
                let band = masterEQ.bands[bandIndex]
                band.gain = gain
                band.bandwidth = q
                band.bypass = false
            }
        } else if let stemIndex = stemNames.firstIndex(of: target), stemIndex < eqNodes.count {
            let eq = eqNodes[stemIndex]
            if bandIndex < eq.bands.count {
                let band = eq.bands[bandIndex]
                band.gain = gain
                band.bandwidth = q
                band.bypass = false
            }
        }
    }
    
    private func applyEQSettings() {
        // Initialize default EQ settings if they don't exist
        if eqSettings["Master"] == nil {
            eqSettings["Master"] = EQBandSettings()
        }
        
        for stemName in stemNames {
            if eqSettings[stemName] == nil {
                eqSettings[stemName] = EQBandSettings()
            }
        }
        
        // Apply master EQ
        if let masterSettings = eqSettings["Master"], let masterEQ = masterEQNode {
            for (index, bandSettings) in masterSettings.bands.enumerated() where index < masterEQ.bands.count {
                let band = masterEQ.bands[index]
                band.gain = bandSettings.gain
                band.bandwidth = bandSettings.q
                band.bypass = bandSettings.bypass
            }
        }
        
        // Apply stem EQs
        for (stemIndex, stemName) in stemNames.enumerated() {
            if let stemSettings = eqSettings[stemName], stemIndex < eqNodes.count {
                let eq = eqNodes[stemIndex]
                for (bandIndex, bandSettings) in stemSettings.bands.enumerated() where bandIndex < eq.bands.count {
                    let band = eq.bands[bandIndex]
                    band.gain = bandSettings.gain
                    band.bandwidth = bandSettings.q
                    band.bypass = bandSettings.bypass
                }
            }
        }
    }
    
    func resetEQ(target: String) {
        // Create fresh default settings
        let defaultSettings = EQBandSettings()
        eqSettings[target] = defaultSettings
        
        // Apply directly to audio nodes to ensure immediate effect
        if target == "Master" {
            if let masterEQ = masterEQNode {
                for (index, _) in defaultSettings.bands.enumerated() where index < masterEQ.bands.count {
                    let band = masterEQ.bands[index]
                    band.gain = 0
                    band.bandwidth = 1.0
                    band.bypass = false
                }
            }
        } else if let stemIndex = stemNames.firstIndex(of: target), stemIndex < eqNodes.count {
            let eq = eqNodes[stemIndex]
            for (index, _) in defaultSettings.bands.enumerated() where index < eq.bands.count {
                let band = eq.bands[index]
                band.gain = 0
                band.bandwidth = 1.0
                band.bypass = false
            }
        }
        
        // Increment counter to force UI refresh
        eqResetCounter += 1
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        timePitchNode?.rate = rate
    }

    func setPitch(_ cents: Float) {
        pitch = max(-200, min(200, cents))
        timePitchNode?.pitch = pitch
    }

    func toggleLooping() {
        isLooping.toggle()
    }

    func setSelection(start: Double, end: Double) {
        let clampedStart = max(0, min(duration, start))
        let clampedEnd = max(0, min(duration, end))
        // Ignore selections shorter than 1 second — they're almost always
        // accidental clicks or tiny drags and looping a sub-second region is
        // rarely useful.
        if clampedEnd - clampedStart < 1.0 {
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
        var amp = faderValues[index]
        if muteStates[index] || (hasSolo && !soloStates[index]) {
            amp = 0
        }

        // AVAudioPlayerNode.volume is capped at 1.0, so boosts above unity ride
        // on the EQ node's globalGain (in dB) downstream. Attenuation stays on
        // the player's volume. We keep the player volume's signal flowing even
        // while the pristine original takes over so per-stem meter taps remain
        // animated; stemOutputGate silences the audio downstream.
        playerNodes[index].volume = Float(min(amp, 1.0))

        let boostDB: Float = amp > 1.0 ? 20 * log10f(Float(amp)) : 0
        let normalizeDB: Float = index < stemNormalizeGainsDB.count ? stemNormalizeGainsDB[index] : 0
        let masterDB: Float = masterFaderValue > 0 ? 20 * log10f(Float(masterFaderValue)) : -96
        if index < eqNodes.count {
            // Clamp to AVAudioUnitEQ.globalGain's valid range (-96 to +24 dB).
            eqNodes[index].globalGain = max(-96, min(24, boostDB + normalizeDB + masterDB))
        }
    }

    private func updatePan(for index: Int) {
        guard index < playerNodes.count, index < panValues.count else { return }
        // AVAudioPlayerNode pan: -1.0 (left) to 1.0 (right)
        playerNodes[index].pan = Float(panValues[index])
    }

    private func updateAllGains() {
        for i in 0..<playerNodes.count { updateGain(for: i) }
        updateMasterSource()
    }

    /// Returns true when the user has made no audible modifications in the
    /// mixer — in that case we play the pristine original file instead of
    /// summing the demucs-separated stems (which introduces small artifacts).
    private func shouldPlayOriginal() -> Bool {
        guard hasSession, originalEnabled else { return false }
        // The original buffer may not be loaded (e.g. cached-by-key sessions
        // where the source file is unavailable). Fall back to summed stems.
        guard originalAudioBuffer != nil, let origPlayer = originalPlayerNode else { return false }
        // If playback is active, the original must also be actively playing —
        // otherwise silencing the stems would produce silence. This handles the
        // case where the original loads asynchronously after play() was called.
        if isPlaying && !origPlayer.isPlaying { return false }
        return true
    }

    func toggleOriginal() {
        originalEnabled.toggle()
        updateMasterSource()
    }

    /// Cross-fades between the pristine original player and the stem sum.
    /// Driving this through the shared stemOutputGate (instead of the
    /// individual stem players' volumes) keeps the per-stem meters
    /// animated with the real signal even while the original is audible.
    private func updateMasterSource() {
        let playOriginal = shouldPlayOriginal()
        originalPlayerNode?.volume = playOriginal ? 1.0 : 0.0
        stemOutputGate?.outputVolume = playOriginal ? 0.0 : 1.0
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
            originalPlayerNode?.stop()
        } else {
            originalPlayerNode?.stop()
        }
        isPlaying = false
        
        // Set new position and restart
        pauseTime = position
        currentTime = position
        play()
    }
    
    // MARK: - Click Track (Metronome)
    
    /// Generate click track buffer based on BPM and duration
    
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
        // Persist the current track's settings before we tear state down —
        // this is the "leaving a track" save point. All mutation functions
        // rely on this and on app termination; they don't save per-change.
        saveCurrentSongSettings()

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
            
            // Clean up EQ nodes
            for node in eqNodes {
                engine.detach(node)
            }

            // Clean up stem output gate
            if let gate = stemOutputGate {
                engine.detach(gate)
            }

            // Clean up EQ meter node
            if let eqMeter = eqMeterNode {
                eqMeter.removeTap(onBus: 0)
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
        eqNodes.removeAll()
        meterTapNodes.removeAll()
        peakLevels.removeAll()
        audioBuffers.removeAll()
        stemOutputGate = nil

        // Clear original audio
        originalAudioBuffer = nil
        originalPlayerNode = nil
        originalMeterNode = nil

        stemNormalizeGainsDB = []
        stemsNormalized = false

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
        eqBandLevels = Array(repeating: 0, count: 10)
        eqBandPeakLevels = Array(repeating: 0, count: 8)
        
        // Clear current input URL (this will prevent saving settings after cleanup)
        currentInputURL = nil
    }
}
