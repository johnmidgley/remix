import Foundation
import SwiftUI

/// A saved snapshot of per-stem mixer state that can be recalled on any track.
/// Keyed by stem display name so the same preset maps cleanly across tracks
/// (demucs always produces the same six stems).
struct MixerPreset: Codable {
    var faderValues: [String: Double] = [:]
    var panValues: [String: Double] = [:]
    var muteStates: [String: Bool] = [:]
    var soloStates: [String: Bool] = [:]
    var eqSettings: [String: AudioEngine.EQBandSettings] = [:]  // Keys: stem names + "Master"
    var stemNormalizeGains: [String: Float] = [:]
    // Only captured for timeline markers (named presets leave this nil so
    // loading a preset doesn't stomp on the user's master level).
    var masterFaderValue: Double? = nil

    init(
        faderValues: [String: Double] = [:],
        panValues: [String: Double] = [:],
        muteStates: [String: Bool] = [:],
        soloStates: [String: Bool] = [:],
        eqSettings: [String: AudioEngine.EQBandSettings] = [:],
        stemNormalizeGains: [String: Float] = [:],
        masterFaderValue: Double? = nil
    ) {
        self.faderValues = faderValues
        self.panValues = panValues
        self.muteStates = muteStates
        self.soloStates = soloStates
        self.eqSettings = eqSettings
        self.stemNormalizeGains = stemNormalizeGains
        self.masterFaderValue = masterFaderValue
    }

    // Custom decoder so saved blobs from older app versions (missing newer
    // fields) still load instead of failing outright — every field falls
    // back to the struct's default if absent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faderValues = try c.decodeIfPresent([String: Double].self, forKey: .faderValues) ?? [:]
        panValues = try c.decodeIfPresent([String: Double].self, forKey: .panValues) ?? [:]
        muteStates = try c.decodeIfPresent([String: Bool].self, forKey: .muteStates) ?? [:]
        soloStates = try c.decodeIfPresent([String: Bool].self, forKey: .soloStates) ?? [:]
        eqSettings = try c.decodeIfPresent([String: AudioEngine.EQBandSettings].self, forKey: .eqSettings) ?? [:]
        stemNormalizeGains = try c.decodeIfPresent([String: Float].self, forKey: .stemNormalizeGains) ?? [:]
        masterFaderValue = try c.decodeIfPresent(Double.self, forKey: .masterFaderValue)
    }

    /// Linearly blends continuous properties (fader/pan/EQ gain+Q/normalize/
    /// master) between two presets. Discrete states (mute/solo/EQ bypass)
    /// step at the halfway point to avoid weird half-bypass behavior.
    static func lerp(_ a: MixerPreset, _ b: MixerPreset, t: Double) -> MixerPreset {
        var result = MixerPreset()
        let tf = Float(t)
        let stemKeys = Set(a.faderValues.keys)
            .union(b.faderValues.keys)
            .union(a.panValues.keys)
            .union(b.panValues.keys)
            .union(a.stemNormalizeGains.keys)
            .union(b.stemNormalizeGains.keys)
            .union(a.muteStates.keys)
            .union(b.muteStates.keys)
            .union(a.soloStates.keys)
            .union(b.soloStates.keys)

        for name in stemKeys {
            let af = a.faderValues[name] ?? 1.0
            let bf = b.faderValues[name] ?? 1.0
            result.faderValues[name] = af + (bf - af) * t

            let ap = a.panValues[name] ?? 0.0
            let bp = b.panValues[name] ?? 0.0
            result.panValues[name] = ap + (bp - ap) * t

            let an = a.stemNormalizeGains[name] ?? 0
            let bn = b.stemNormalizeGains[name] ?? 0
            result.stemNormalizeGains[name] = an + (bn - an) * tf

            let am = a.muteStates[name] ?? false
            let bm = b.muteStates[name] ?? false
            result.muteStates[name] = t < 0.5 ? am : bm

            let aso = a.soloStates[name] ?? false
            let bso = b.soloStates[name] ?? false
            result.soloStates[name] = t < 0.5 ? aso : bso
        }

        let eqKeys = Set(a.eqSettings.keys).union(b.eqSettings.keys)
        for target in eqKeys {
            let aEq = a.eqSettings[target] ?? AudioEngine.EQBandSettings()
            let bEq = b.eqSettings[target] ?? AudioEngine.EQBandSettings()
            var mergedEq = aEq
            for i in 0..<mergedEq.bands.count where i < bEq.bands.count {
                let aBand = aEq.bands[i]
                let bBand = bEq.bands[i]
                mergedEq.bands[i].gain = aBand.gain + (bBand.gain - aBand.gain) * tf
                mergedEq.bands[i].q = aBand.q + (bBand.q - aBand.q) * tf
                mergedEq.bands[i].bypass = t < 0.5 ? aBand.bypass : bBand.bypass
                // frequency stays fixed per band — not interpolated
            }
            result.eqSettings[target] = mergedEq
        }

        switch (a.masterFaderValue, b.masterFaderValue) {
        case let (am?, bm?): result.masterFaderValue = am + (bm - am) * t
        case (nil, let bm?): result.masterFaderValue = bm
        case (let am?, nil): result.masterFaderValue = am
        default: break
        }

        return result
    }
}

/// A timeline marker: when the playhead crosses `time`, the engine restores
/// the mixer state from `state`.
struct Marker: Codable, Identifiable {
    var id: UUID = UUID()
    var time: Double
    var state: MixerPreset

    enum CodingKeys: String, CodingKey { case id, time, state }
}

final class MixerPresetStore: ObservableObject {
    private static let storageKey = "mixer_presets_v1"

    @Published private(set) var presets: [String: MixerPreset] = [:]

    init() { load() }

    var sortedNames: [String] {
        presets.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func save(_ preset: MixerPreset, name: String) {
        presets[name] = preset
        persist()
    }

    func delete(name: String) {
        presets.removeValue(forKey: name)
        persist()
    }

    func rename(from: String, to: String) {
        let trimmed = to.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, from != trimmed, let preset = presets[from] else { return }
        presets.removeValue(forKey: from)
        presets[trimmed] = preset
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: MixerPreset].self, from: data) else {
            return
        }
        presets = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
