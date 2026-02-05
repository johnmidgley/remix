import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("defaultSeparationMode") private var defaultMode = "demucs"
    @AppStorage("cacheEnabled") private var cacheEnabled = true
    @AppStorage("autoLoadCache") private var autoLoadCache = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            // Tabbed content
            TabView {
                GeneralPreferencesView(
                    defaultMode: $defaultMode,
                    cacheEnabled: $cacheEnabled,
                    autoLoadCache: $autoLoadCache
                )
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                
                KeyboardShortcutsView()
                    .tabItem {
                        Label("Shortcuts", systemImage: "keyboard")
                    }
                
                AboutPreferencesView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .frame(height: 400)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - General Preferences
struct GeneralPreferencesView: View {
    @Binding var defaultMode: String
    @Binding var cacheEnabled: Bool
    @Binding var autoLoadCache: Bool
    
    var body: some View {
        Form {
            Section {
                Text("Separation Mode: Demucs (AI)")
                    .font(.body)
                
                Text("Demucs uses deep learning to provide the highest quality separation. Requires Python and downloads models on first use (~4GB).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Separation")
                    .font(.headline)
            }
            
            Section {
                Toggle("Enable analysis caching", isOn: $cacheEnabled)
                    .help("Cache separated stems to disk for faster loading")
                
                Toggle("Auto-load from cache", isOn: $autoLoadCache)
                    .help("Automatically load previously analyzed files from cache")
                    .disabled(!cacheEnabled)
                
                HStack {
                    Text("Cache location:")
                        .foregroundColor(.secondary)
                    Text("~/Library/Caches/com.remix.app")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Button("Clear Cache...") {
                    CacheManager.shared.clearAllCache()
                }
            } header: {
                Text("Cache")
                    .font(.headline)
            }
            
            Section {
                LabeledContent("Sample Rate:", value: "44.1 kHz")
                LabeledContent("Bit Depth:", value: "32-bit float")
                
                Text("Audio quality settings are optimized for professional use.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Audio Quality")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Keyboard Shortcuts Reference
struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                shortcutSection("File") {
                    shortcutRow("Open File", "⌘O")
                    shortcutRow("Bounce Mix", "⌘B")
                }
                
                shortcutSection("Edit") {
                    shortcutRow("Preferences", "⌘,")
                    shortcutRow("Reset All Faders", "⌘R")
                }
                
                shortcutSection("Analyze") {
                    shortcutRow("Open EQ", "⌘E")
                    shortcutRow("Re-analyze", "⇧⌘R")
                }
                
                shortcutSection("Transport") {
                    shortcutRow("Play / Pause", "Space")
                    shortcutRow("Stop", "Return")
                    shortcutRow("Toggle Loop", "⌘L")
                }
                
                shortcutSection("Window") {
                    shortcutRow("Full Screen", "⌃⌘F")
                }
                
                shortcutSection("Help") {
                    shortcutRow("Show Help", "⌘?")
                }
            }
            .padding()
        }
    }
    
    func shortcutSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            content()
            Divider()
        }
    }
    
    func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .foregroundColor(.secondary)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
        }
    }
}

// MARK: - About Preferences Tab
struct AboutPreferencesView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Icon and Name
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 128, height: 128)
                    
                    Text("Remix")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("AI-Powered Music Stem Separation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                Divider()
                
                // Technology
                VStack(alignment: .leading, spacing: 8) {
                    Text("Powered By")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Demucs v4")
                                .font(.subheadline)
                            Text("Hybrid Transformer AI model by Meta Research")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "swift")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Swift & Rust")
                                .font(.subheadline)
                            Text("Native macOS performance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                Divider()
                
                // Links
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/yourusername/remix")!) {
                        Label("View on GitHub", systemImage: "link")
                    }
                    
                    Link(destination: URL(string: "https://github.com/facebookresearch/demucs")!) {
                        Label("Demucs Project", systemImage: "link")
                    }
                }
                
                Divider()
                
                // Copyright
                VStack(spacing: 4) {
                    Text("© 2024-2025")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Licensed under Apache 2.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("See About Remix for full license information")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
    }
}

#Preview {
    PreferencesView()
}
