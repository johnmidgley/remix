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
