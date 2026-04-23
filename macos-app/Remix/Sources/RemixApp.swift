import SwiftUI

private func stemNormalizeMenuTitle(isNormalizing: Bool, applied: Bool) -> String {
    if isNormalizing { return "Normalizing Stems…" }
    return applied ? "✓ Normalize Stem Levels" : "Normalize Stem Levels"
}

@main
struct RemixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var presetStore = MixerPresetStore()
    @State private var showingHelp = false
    @State private var showingAbout = false
    @State private var showingPreferences = false
    @State private var showingSavePreset = false
    @State private var showingManagePresets = false
    
    init() {
        // This will be called after @NSApplicationDelegateAdaptor initializes appDelegate
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioEngine)
                .environmentObject(presetStore)
                .frame(minWidth: 800, minHeight: 500)
                .background(WindowAccessor(audioEngine: audioEngine))
                .sheet(isPresented: $showingHelp) {
                    HelpView(onDismiss: { showingHelp = false })
                }
                .sheet(isPresented: $showingAbout) {
                    LicensesView()
                }
                .sheet(isPresented: $showingPreferences) {
                    PreferencesView()
                }
                .sheet(isPresented: $showingSavePreset) {
                    SavePresetSheet(isPresented: $showingSavePreset)
                        .environmentObject(audioEngine)
                        .environmentObject(presetStore)
                }
                .sheet(isPresented: $showingManagePresets) {
                    ManagePresetsSheet(isPresented: $showingManagePresets)
                        .environmentObject(presetStore)
                }
                .onAppear {
                    // Connect the audio engine to the app delegate
                    appDelegate.audioEngine = audioEngine
                }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            // About menu (replaces default "About" with our custom one)
            CommandGroup(replacing: .appInfo) {
                Button("About Remix...") {
                    showingAbout = true
                }
            }
            
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    audioEngine.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Divider()
                Button("Bounce Mix...") {
                    audioEngine.bounceToFile()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!audioEngine.hasSession)
                
                Button("Open EQ...") {
                    audioEngine.showEQWindow = true
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!audioEngine.hasSession)
                
                Divider()
                Button("Re-analyze") {
                    audioEngine.reanalyze()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!audioEngine.hasSession)
                
                Divider()
                Button("Clear Cache...") {
                    CacheManager.shared.clearAllCache()
                }
            }
            
            CommandGroup(replacing: .pasteboard) {
                Button("Reset All Faders") {
                    audioEngine.resetAllFaders()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!audioEngine.hasSession)

                Button("Reset All Settings") {
                    audioEngine.resetAllSettings()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!audioEngine.hasSession)

                Divider()

                Button(stemNormalizeMenuTitle(
                    isNormalizing: audioEngine.isNormalizingStems,
                    applied: audioEngine.stemsNormalized
                )) {
                    audioEngine.toggleStemNormalize()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!audioEngine.hasSession || audioEngine.isNormalizingStems)
            }
            
            // Preferences menu (standard location in app menu on macOS)
            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    showingPreferences = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Mixer") {
                Button("Save Preset…") {
                    showingSavePreset = true
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!audioEngine.hasSession)

                Button("Manage Presets…") {
                    showingManagePresets = true
                }

                Divider()

                if presetStore.sortedNames.isEmpty {
                    Button("No Presets Saved") {}.disabled(true)
                } else {
                    Section("Load Preset") {
                        ForEach(presetStore.sortedNames, id: \.self) { name in
                            Button(name) {
                                if let preset = presetStore.presets[name] {
                                    audioEngine.applyMixerPreset(preset)
                                }
                            }
                            .disabled(!audioEngine.hasSession)
                        }
                    }
                }
            }

            CommandMenu("Transport") {
                Button(audioEngine.isPlaying ? "Pause" : "Play") {
                    audioEngine.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!audioEngine.hasSession)
                
                Button("Stop") {
                    audioEngine.stopAndReset()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!audioEngine.hasSession)
                
                Divider()
                
                Button(audioEngine.isLooping ? "Disable Loop" : "Enable Loop") {
                    audioEngine.toggleLooping()
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            
            CommandGroup(replacing: .help) {
                Button("Remix Help") {
                    showingHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
                
                Divider()
                
                Button("Acknowledgments") {
                    showingAbout = true
                }
                
                Link("GitHub Repository", destination: URL(string: "https://github.com/yourusername/remix")!)
            }
            
            // Window menu (standard macOS window management)
            CommandGroup(after: .windowArrangement) {
                Button("Enter Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}

// MARK: - Help View
struct HelpView: View {
    let onDismiss: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title)
                    .foregroundColor(Color(hex: "0a84ff"))
                Text("Remix Help")
                    .font(.title2.bold())
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(hex: "2d2d2d"))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Overview
                    helpSection(title: "Overview") {
                        Text("Remix separates audio files into individual instrument stems using AI (Demucs). You can then mix, solo, mute, and export the separated tracks.")
                            .foregroundColor(.secondary)
                    }
                    
                    // Getting Started
                    helpSection(title: "Getting Started") {
                        VStack(alignment: .leading, spacing: 8) {
                            helpStep("1", "Drop an audio file (WAV, MP3, M4A, FLAC, AIFF, or OGG) onto the app, or use File → Open")
                            helpStep("2", "Click Analyze to separate the tracks")
                            helpStep("3", "Use the mixer to adjust levels, solo, or mute tracks")
                            helpStep("4", "Export your mix with File → Bounce Mix")
                        }
                    }
                    
                    // Keyboard Shortcuts
                    helpSection(title: "Keyboard Shortcuts") {
                        VStack(spacing: 4) {
                            shortcutRow("Open File", "⌘O")
                            shortcutRow("Bounce Mix", "⌘B")
                            shortcutRow("Open EQ", "⌘E")
                            shortcutRow("Re-analyze", "⇧⌘R")
                            shortcutRow("Play / Pause", "Space")
                            shortcutRow("Stop", "Return")
                            shortcutRow("Toggle Loop", "⌘L")
                            shortcutRow("Reset Faders", "⌘R")
                            shortcutRow("Reset All Settings", "⌥⌘R")
                            shortcutRow("Normalize Stem Levels", "⇧⌘N")
                            shortcutRow("Show Help", "⌘?")
                        }
                    }
                    
                    // Mixer Controls
                    helpSection(title: "Mixer Controls") {
                        VStack(alignment: .leading, spacing: 8) {
                            controlRow("Fader", "Drag to adjust track volume")
                            controlRow("S (Solo)", "Hear only this track (click multiple for multi-solo)")
                            controlRow("M (Mute)", "Silence this track")
                            controlRow("Meter", "Shows real-time audio level")
                        }
                    }
                    
                    // Timeline
                    helpSection(title: "Timeline") {
                        VStack(alignment: .leading, spacing: 8) {
                            controlRow("Click", "Seek to position")
                            controlRow("Drag", "Create loop region")
                            controlRow("Clear Loop", "Remove loop region")
                        }
                    }
                    
                    // How It Works
                    helpSection(title: "How It Works") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Demucs uses deep learning to separate audio into Drums, Bass, Vocals, Guitar, Keys, and Other. Requires Python and downloads ~4GB of models on first run. Provides the best quality for music separation.")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(hex: "1e1e1e"))
        }
        .frame(width: 500, height: 600)
        .background(Color(hex: "1e1e1e"))
    }
    
    func helpSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(Color(hex: "0a84ff"))
            content()
        }
    }
    
    func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(hex: "0a84ff")))
            Text(text)
                .foregroundColor(.secondary)
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
                        .fill(Color(hex: "3a3a3a"))
                )
        }
    }
    
    func controlRow(_ control: String, _ description: String) -> some View {
        HStack(alignment: .top) {
            Text(control)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .leading)
            Text(description)
                .foregroundColor(.secondary)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var audioEngine: AudioEngine?
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if audio is currently playing
        if let engine = audioEngine, engine.isPlaying {
            let alert = NSAlert()
            alert.messageText = "Audio is Playing"
            alert.informativeText = "Are you sure you want to quit? Playback will be stopped."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return .terminateNow
            } else {
                return .terminateCancel
            }
        }
        
        return .terminateNow
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up app appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        
        // Disable window tabbing globally
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}

// Helper to access and configure NSWindow from SwiftUI
struct WindowAccessor: NSViewRepresentable {
    let audioEngine: AudioEngine
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.tabbingMode = .disallowed
                // Hide the tab bar completely
                if let tabGroup = window.tabGroup {
                    tabGroup.isOverviewVisible = false
                }
                // Remove the new tab button
                window.tab.accessoryView = nil
                
                // Restore last file path if available
                if let lastFilePath = UserDefaults.standard.string(forKey: "lastOpenedFilePath"),
                   FileManager.default.fileExists(atPath: lastFilePath) {
                    let fileURL = URL(fileURLWithPath: lastFilePath)
                    // Load the file in the background after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        audioEngine.loadFile(url: fileURL)
                    }
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.tabbingMode = .disallowed
        }
    }
}

// MARK: - Preset Sheets

struct SavePresetSheet: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var presetStore: MixerPresetStore
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var willOverwrite: Bool {
        !trimmedName.isEmpty && presetStore.presets[trimmedName] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Mixer Preset")
                .font(.headline)

            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(save)

            if willOverwrite {
                Text("A preset named \"\(trimmedName)\" already exists — it will be replaced.")
                    .font(.caption)
                    .foregroundColor(Color(hex: "ff9f0a"))
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(willOverwrite ? "Replace" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { isNameFocused = true }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        presetStore.save(audioEngine.currentMixerPreset(), name: trimmedName)
        isPresented = false
    }
}

struct ManagePresetsSheet: View {
    @EnvironmentObject var presetStore: MixerPresetStore
    @Binding var isPresented: Bool
    @State private var renaming: String? = nil
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Presets").font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if presetStore.sortedNames.isEmpty {
                VStack {
                    Spacer()
                    Text("No saved presets")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(presetStore.sortedNames, id: \.self) { name in
                            HStack {
                                if renaming == name {
                                    TextField("Name", text: $renameText, onCommit: {
                                        commitRename(from: name)
                                    })
                                    .textFieldStyle(.roundedBorder)
                                    Button("Save") { commitRename(from: name) }
                                    Button("Cancel") { renaming = nil }
                                } else {
                                    Text(name)
                                    Spacer()
                                    Button("Rename") {
                                        renameText = name
                                        renaming = name
                                    }
                                    Button("Delete") {
                                        presetStore.delete(name: name)
                                    }
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 440, height: 320)
    }

    private func commitRename(from old: String) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            presetStore.rename(from: old, to: trimmed)
        }
        renaming = nil
    }
}
