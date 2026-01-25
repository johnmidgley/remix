import SwiftUI

@main
struct RemixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioEngine = AudioEngine()
    @State private var showingHelp = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioEngine)
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowAccessor())
                .sheet(isPresented: $showingHelp) {
                    HelpView(onDismiss: { showingHelp = false })
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
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
            }
            
            CommandMenu("Transport") {
                Button(audioEngine.isPlaying ? "Pause" : "Play") {
                    audioEngine.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!audioEngine.hasSession)
                
                Button("Stop") {
                    audioEngine.stop()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!audioEngine.hasSession)
                
                Divider()
                
                Toggle("Cycle", isOn: $audioEngine.isLooping)
                    .keyboardShortcut("l", modifiers: .command)
            }
            
            CommandGroup(replacing: .help) {
                Button("Remix Help") {
                    showingHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

// MARK: - Help View
struct HelpView: View {
    let onDismiss: () -> Void
    
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
            }
            .padding()
            .background(Color(hex: "2d2d2d"))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Overview
                    helpSection(title: "Overview") {
                        Text("Remix separates audio files into individual instrument stems using AI (Demucs) or spectral analysis (PCA). You can then mix, solo, mute, and export the separated tracks.")
                            .foregroundColor(.secondary)
                    }
                    
                    // Getting Started
                    helpSection(title: "Getting Started") {
                        VStack(alignment: .leading, spacing: 8) {
                            helpStep("1", "Drop an audio file (WAV or MP3) onto the app, or use File → Open")
                            helpStep("2", "Select separation mode: Demucs (AI) or PCA (Spectral)")
                            helpStep("3", "Click Analyze to separate the tracks")
                            helpStep("4", "Use the mixer to adjust levels, solo, or mute tracks")
                            helpStep("5", "Export your mix with File → Bounce Mix")
                        }
                    }
                    
                    // Keyboard Shortcuts
                    helpSection(title: "Keyboard Shortcuts") {
                        VStack(spacing: 4) {
                            shortcutRow("Open File", "⌘O")
                            shortcutRow("Bounce Mix", "⌘B")
                            shortcutRow("Re-analyze", "⇧⌘R")
                            shortcutRow("Play / Pause", "Space")
                            shortcutRow("Stop", "Return")
                            shortcutRow("Toggle Loop", "⌘L")
                            shortcutRow("Reset Faders", "⌘R")
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
                    
                    // Separation Modes
                    helpSection(title: "Separation Modes") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Demucs (AI)")
                                    .font(.headline)
                                Text("Uses deep learning to separate into Drums, Bass, Vocals, Guitar, Keys, and Other. Requires Python and downloads ~4GB of models on first run. Best quality for music.")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PCA (Spectral)")
                                    .font(.headline)
                                Text("Uses Principal Component Analysis on the spectrogram. Faster but experimental. Separates by spectral patterns rather than instruments.")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
