import SwiftUI

@main
struct RemixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var audioEngine = AudioEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioEngine)
                .frame(minWidth: 900, minHeight: 600)
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
    }
}
