import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @FocusState private var focusedField: FocusField?
    
    enum FocusField: Hashable {
        case timeline
        case mixer
        case transport
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView()
            
            // Main content with optional file browser
            HStack(alignment: .top, spacing: 0) {
                // File browser sidebar
                if audioEngine.showFileBrowser {
                    FileBrowserView()
                        .frame(width: 220)
                    
                    Divider()
                        .background(Color(hex: "333333"))
                }
                
                // Main content
                if audioEngine.hasSession {
                    MixerView()
                } else if audioEngine.hasLoadedFile {
                    PreAnalysisView()
                } else {
                    DropZoneView()
                }
            }
        }
        .background(Color(hex: "1a1a1a"))
        .sheet(isPresented: .constant(audioEngine.errorMessage != nil)) {
            ErrorSheet(errorMessage: audioEngine.errorMessage ?? "", onDismiss: {
                audioEngine.errorMessage = nil
            })
        }
        .onChange(of: audioEngine.showEQWindow) { show in
            if show {
                EQWindowManager.shared.showWindow(audioEngine: audioEngine)
            } else {
                EQWindowManager.shared.hideWindow()
            }
        }
        .background(KeyEventHandlingView(audioEngine: audioEngine))
    }
}

// MARK: - Key Event Handling (backward compatible)
struct KeyEventHandlingView: NSViewRepresentable {
    let audioEngine: AudioEngine
    
    func makeNSView(context: Context) -> KeyEventNSView {
        let view = KeyEventNSView(audioEngine: audioEngine)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyEventNSView, context: Context) {
        // No update needed
    }
}

class KeyEventNSView: NSView {
    let audioEngine: AudioEngine
    
    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers != nil else {
            super.keyDown(with: event)
            return
        }
        
        switch event.keyCode {
        case 123: // Left arrow
            if audioEngine.hasSession || audioEngine.hasLoadedFile {
                let newTime = max(0, audioEngine.currentTime - 5.0)
                audioEngine.seek(to: newTime)
            } else {
                super.keyDown(with: event)
            }
            
        case 124: // Right arrow
            if audioEngine.hasSession || audioEngine.hasLoadedFile {
                let newTime = min(audioEngine.duration, audioEngine.currentTime + 5.0)
                audioEngine.seek(to: newTime)
            } else {
                super.keyDown(with: event)
            }
            
        case 53: // Escape
            if audioEngine.selectionEnd > audioEngine.selectionStart {
                audioEngine.clearSelection()
            } else {
                super.keyDown(with: event)
            }
            
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - File Browser
struct FileBrowserView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var directoryContents: [FileItem] = []
    @State private var selectedFile: URL?
    @State private var selectedCacheKey: String?
    @State private var quickAccessLocations: [QuickAccessItem] = []
    @State private var isShowingCache: Bool = false
    @State private var cachedItems: [CachedFileItem] = []
    
    struct FileItem: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let name: String
        let isDirectory: Bool
        let isAudioFile: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
        
        static func == (lhs: FileItem, rhs: FileItem) -> Bool {
            lhs.url == rhs.url
        }
    }
    
    struct CachedFileItem: Identifiable {
        let id = UUID()
        let originalPath: String
        let fileName: String
        let stemCount: Int
        let duration: Double
        let createdAt: Date
        let cacheKey: String
    }
    
    struct QuickAccessItem: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let url: URL?  // nil for special items like Cache
        let isSpecial: Bool
        
        init(name: String, icon: String, url: URL) {
            self.name = name
            self.icon = icon
            self.url = url
            self.isSpecial = false
        }
        
        init(name: String, icon: String, isSpecial: Bool) {
            self.name = name
            self.icon = icon
            self.url = nil
            self.isSpecial = isSpecial
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // File list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Quick Access section
                    if !quickAccessLocations.isEmpty {
                        Text("LOCATIONS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "666666"))
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        
                        ForEach(quickAccessLocations) { location in
                            QuickAccessRowView(
                                item: location,
                                isSelected: location.isSpecial && isShowingCache
                            ) {
                                handleQuickAccessTap(location)
                            }
                        }
                        
                        Divider()
                            .background(Color(hex: "333333"))
                            .padding(.vertical, 8)
                    }
                    
                    // Current directory/cache header
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            if !isShowingCache {
                                Button(action: navigateUp) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Color(hex: "888888"))
                                .disabled(audioEngine.currentDirectory.path == "/")
                            }
                            
                            Text(isShowingCache ? "Cache" : audioEngine.currentDirectory.lastPathComponent)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            if isShowingCache {
                                Text("\(cachedItems.count) item\(cachedItems.count == 1 ? "" : "s")")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "666666"))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(hex: "252525"))
                        
                        Divider()
                            .background(Color(hex: "333333"))
                    }
                    
                    // Content: either cache items or directory contents
                    if isShowingCache {
                        if cachedItems.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(hex: "444444"))
                                Text("No cached analyses")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "666666"))
                                Text("Analyzed files will appear here")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "555555"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(cachedItems) { item in
                                CachedFileRowView(
                                    item: item,
                                    isSelected: selectedCacheKey == item.cacheKey,
                                    onTap: { loadCachedItem(item) }
                                )
                            }
                        }
                    } else {
                        // Current directory contents
                        ForEach(directoryContents) { item in
                            FileRowView(
                                item: item,
                                isSelected: selectedFile == item.url,
                                onSingleClick: { selectFile(item) },
                                onDoubleClick: { openItem(item) }
                            )
                        }
                    }
                }
            }
            .background(Color(hex: "1e1e1e"))
        }
        .onAppear {
            loadQuickAccessLocations()
            if isShowingCache {
                loadCachedFiles()
            } else {
                loadDirectory()
            }
        }
        .onChange(of: audioEngine.currentDirectory) { _ in
            if !isShowingCache {
                selectedFile = nil
                selectedCacheKey = nil
                loadDirectory()
            }
        }
        .onChange(of: audioEngine.cacheModifiedCounter) { _ in
            // Refresh cache list when cache is modified (e.g., reanalyze clears cache)
            if isShowingCache {
                loadCachedFiles()
            }
        }
    }
    
    func loadQuickAccessLocations() {
        var locations: [QuickAccessItem] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        // Home
        locations.append(QuickAccessItem(name: "Home", icon: "house.fill", url: home))
        
        // Desktop
        let desktop = home.appendingPathComponent("Desktop")
        if fm.fileExists(atPath: desktop.path) {
            locations.append(QuickAccessItem(name: "Desktop", icon: "menubar.dock.rectangle", url: desktop))
        }
        
        // Documents
        let documents = home.appendingPathComponent("Documents")
        if fm.fileExists(atPath: documents.path) {
            locations.append(QuickAccessItem(name: "Documents", icon: "doc.fill", url: documents))
        }
        
        // Downloads
        let downloads = home.appendingPathComponent("Downloads")
        if fm.fileExists(atPath: downloads.path) {
            locations.append(QuickAccessItem(name: "Downloads", icon: "arrow.down.circle.fill", url: downloads))
        }
        
        // Music
        let music = home.appendingPathComponent("Music")
        if fm.fileExists(atPath: music.path) {
            locations.append(QuickAccessItem(name: "Music", icon: "music.note", url: music))
        }
        
        // Cache (special item)
        locations.append(QuickAccessItem(name: "Cache", icon: "archivebox.fill", isSpecial: true))
        
        // Cloud Storage (Google Drive, iCloud, Dropbox, OneDrive)
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage")
        if let cloudContents = try? fm.contentsOfDirectory(at: cloudStorage, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for cloudFolder in cloudContents {
                let name = cloudFolder.lastPathComponent
                var displayName = name
                var icon = "cloud.fill"
                
                if name.contains("GoogleDrive") {
                    displayName = "Google Drive"
                    icon = "cloud.fill"
                } else if name.contains("iCloud") {
                    displayName = "iCloud Drive"
                    icon = "icloud.fill"
                } else if name.contains("Dropbox") {
                    displayName = "Dropbox"
                    icon = "shippingbox.fill"
                } else if name.contains("OneDrive") {
                    displayName = "OneDrive"
                    icon = "cloud.fill"
                }
                
                locations.append(QuickAccessItem(name: displayName, icon: icon, url: cloudFolder))
            }
        }
        
        quickAccessLocations = locations
    }
    
    func handleQuickAccessTap(_ location: QuickAccessItem) {
        if location.isSpecial && location.name == "Cache" {
            isShowingCache = true
            selectedFile = nil
            loadCachedFiles()
        } else if let url = location.url {
            isShowingCache = false
            selectedCacheKey = nil
            audioEngine.currentDirectory = url
        }
    }
    
    func loadCachedFiles() {
        cachedItems = CacheManager.shared.getAllCachedFiles().map { metadata, key in
            CachedFileItem(
                originalPath: metadata.originalPath,
                fileName: URL(fileURLWithPath: metadata.originalPath).lastPathComponent,
                stemCount: metadata.stemNames.count,
                duration: metadata.duration,
                createdAt: metadata.createdAt,
                cacheKey: key
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }
    
    func loadCachedItem(_ item: CachedFileItem) {
        selectedCacheKey = item.cacheKey  // Select the cached item
        selectedFile = nil  // Clear file selection
        
        let originalURL = URL(fileURLWithPath: item.originalPath)
        // Check if original file still exists
        if FileManager.default.fileExists(atPath: item.originalPath) {
            audioEngine.loadFile(url: originalURL)
        } else {
            // Try to load from cache directly even if original doesn't exist
            audioEngine.loadFromCacheKey(item.cacheKey)
        }
    }
    
    func clearAllCache() {
        CacheManager.shared.clearAllCache()
        loadCachedFiles()
    }
    
    func loadDirectory() {
        let fm = FileManager.default
        let url = audioEngine.currentDirectory
        
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            directoryContents = []
            return
        }
        
        let audioExtensions = Set(["wav", "mp3", "aiff", "aif", "m4a", "flac", "ogg"])
        
        directoryContents = contents.map { itemURL in
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let ext = itemURL.pathExtension.lowercased()
            let isAudio = audioExtensions.contains(ext)
            
            return FileItem(
                url: itemURL,
                name: itemURL.lastPathComponent,
                isDirectory: isDirectory,
                isAudioFile: isAudio
            )
        }.sorted { lhs, rhs in
            // Directories first, then audio files, then other files, then alphabetically
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            if lhs.isAudioFile != rhs.isAudioFile {
                return lhs.isAudioFile
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    func navigateUp() {
        if isShowingCache {
            isShowingCache = false
            selectedCacheKey = nil
            loadDirectory()
        } else {
            let parent = audioEngine.currentDirectory.deletingLastPathComponent()
            audioEngine.currentDirectory = parent
        }
    }
    
    func selectFile(_ item: FileItem) {
        selectedFile = item.url
        selectedCacheKey = nil  // Clear cache selection
    }
    
    func openItem(_ item: FileItem) {
        if item.isDirectory {
            audioEngine.currentDirectory = item.url
            selectedFile = nil
            selectedCacheKey = nil
        } else if item.isAudioFile {
            selectedFile = item.url  // Select the file before loading
            selectedCacheKey = nil  // Clear cache selection
            audioEngine.loadFile(url: item.url)
        }
    }
}

struct QuickAccessRowView: View {
    let item: FileBrowserView.QuickAccessItem
    var isSelected: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundColor(item.isSpecial ? Color(hex: "ff9f0a") : Color(hex: "0a84ff"))
                .frame(width: 18)
            
            Text(item.name)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color(hex: "0a84ff").opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

struct CachedFileRowView: View {
    let item: FileBrowserView.CachedFileItem
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "30d158"))
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 8) {
                    Text("\(item.stemCount) stems")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "888888"))
                    
                    Text(formatDuration(item.duration))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "666666"))
                    
                    Text(formatDate(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "555555"))
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color(hex: "0a84ff").opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
    
    func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct FileRowView: View {
    let item: FileBrowserView.FileItem
    let isSelected: Bool
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    
    var isClickable: Bool {
        item.isDirectory || item.isAudioFile
    }
    
    private var accessibilityLabelText: String {
        if item.isDirectory {
            return "Folder: \(item.name)"
        } else if item.isAudioFile {
            return "Audio file: \(item.name)"
        } else {
            return "File: \(item.name)"
        }
    }
    
    private var accessibilityHintText: String {
        if item.isDirectory {
            return "Double-tap to open this folder"
        } else if item.isAudioFile {
            return "Double-tap to load this audio file"
        } else {
            return "Not a supported file type"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 18)
            
            Text(item.name)
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected && isClickable ? Color(hex: "0a84ff").opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if isClickable { onDoubleClick() } }
        .onTapGesture(count: 1) { if isClickable { onSingleClick() } }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(isClickable ? accessibilityHintText : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            if isClickable {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                
                if item.isAudioFile {
                    Divider()
                    Button("Load File") {
                        onDoubleClick()
                    }
                }
                
                Divider()
                
                Button("Get Info") {
                    NSWorkspace.shared.open(item.url)
                }
            }
        }
    }
    
    var iconName: String {
        if item.isDirectory {
            return "folder.fill"
        } else if item.isAudioFile {
            return "waveform"
        } else {
            return "doc"
        }
    }
    
    var iconColor: Color {
        if item.isDirectory {
            return Color(hex: "66d4ff")
        } else if item.isAudioFile {
            return Color(hex: "30d158")
        } else {
            return Color(hex: "444444")
        }
    }
    
    var textColor: Color {
        if item.isDirectory || item.isAudioFile {
            return .white
        } else {
            return Color(hex: "555555")
        }
    }
}

// MARK: - Toolbar
struct ToolbarView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        HStack(spacing: 0) {
            // Left section - Sidebar toggle (aligned with transport)
            VStack(spacing: 12) {
                // Spacer to match song title height
                Spacer()
                    .frame(height: 16)
                
                // Sidebar toggle aligned with transport/VU meters
                HStack(spacing: 12) {
                    Button(action: { audioEngine.showFileBrowser.toggle() }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12))
                            .foregroundColor(audioEngine.showFileBrowser ? Color(hex: "0a84ff") : Color(hex: "888888"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(audioEngine.showFileBrowser ? "Hide file browser" : "Show file browser")
                    .accessibilityHint("Toggle the file browser sidebar")
                    .help(audioEngine.showFileBrowser ? "Hide file browser sidebar" : "Show file browser sidebar")
                }
                .frame(width: 220, alignment: .leading)
            }
            .padding(.leading, 12)
            
            Spacer()
            
            // Center - Song name + Transport (fixed layout)
            VStack(spacing: 12) {
                // Always reserve space for song title to keep layout stable
                Text(audioEngine.fileName ?? " ")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(audioEngine.fileName != nil ? 1.0 : 0.0)
                    .frame(height: 16)  // Fixed height for title
                
                TransportView()
            }
            .fixedSize()  // Prevent VStack from shrinking
            
            Spacer()
            
            // Right section - Actions (fixed width, aligned with transport)
            VStack(spacing: 12) {
                // Spacer to match song title height
                Spacer()
                    .frame(height: 16)
                
                // Controls aligned with transport/VU meters
                HStack(spacing: 12) {
                    // Playback speed (always reserve space)
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "888888"))
                        
                        Picker("", selection: Binding(
                            get: { audioEngine.playbackRate },
                            set: { audioEngine.setPlaybackRate($0) }
                        )) {
                            Text("0.5x").tag(Float(0.5))
                            Text("0.75x").tag(Float(0.75))
                            Text("1x").tag(Float(1.0))
                            Text("1.25x").tag(Float(1.25))
                            Text("1.5x").tag(Float(1.5))
                            Text("2x").tag(Float(2.0))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 70)
                        .disabled(!(audioEngine.hasLoadedFile || audioEngine.hasSession))
                        .accessibilityLabel("Playback speed")
                        .accessibilityValue("\(audioEngine.playbackRate)x")
                        .help("Adjust playback speed from 0.5x to 2x")
                    }
                    .opacity((audioEngine.hasLoadedFile || audioEngine.hasSession) ? 1.0 : 0.0)
                    
                    // Pitch control (always reserve space)
                    HStack(spacing: 4) {
                        Image(systemName: "tuningfork")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "888888"))
                        
                        Picker("", selection: Binding(
                            get: { audioEngine.pitch },
                            set: { audioEngine.setPitch($0) }
                        )) {
                            Text("-2").tag(Float(-200))
                            Text("-1").tag(Float(-100))
                            Text("0").tag(Float(0))
                            Text("+1").tag(Float(100))
                            Text("+2").tag(Float(200))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 60)
                        .disabled(!(audioEngine.hasLoadedFile || audioEngine.hasSession))
                        .accessibilityLabel("Pitch shift")
                        .accessibilityValue("\(Int(audioEngine.pitch / 100)) semitones")
                        .help("Shift pitch up or down by semitones")
                    }
                    .opacity((audioEngine.hasLoadedFile || audioEngine.hasSession) ? 1.0 : 0.0)
                    
                    // Bounce (always reserve space)
                    Button(action: { audioEngine.bounceToFile() }) {
                        Label("Bounce", systemImage: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .disabled(!audioEngine.hasSession)
                    .opacity(audioEngine.hasSession ? 1.0 : 0.0)
                    .accessibilityLabel("Bounce mix")
                    .accessibilityHint("Export the mixed audio to a file")
                    .help("Export your mix to an audio file (⌘B)")
                    
                    // EQ button (only available after analysis)
                    Button(action: { audioEngine.showEQWindow = true }) {
                        Label("EQ", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .disabled(!audioEngine.hasSession)
                    .opacity(audioEngine.hasSession ? 1.0 : 0.0)
                    .accessibilityLabel("Open equalizer")
                    .accessibilityHint("Open the parametric EQ window")
                    .help("Open the parametric EQ window (⌘E)")
                }
                .frame(width: 370, alignment: .trailing)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 76)
        .background(
            LinearGradient(
                colors: [Color(hex: "3d3d3d"), Color(hex: "2d2d2d")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.black),
            alignment: .bottom
        )
    }
}

// MARK: - Transport Controls
struct TransportView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        HStack(spacing: 16) {
            // Transport buttons
            HStack(spacing: 2) {
                TransportButton(
                    icon: "backward.end.fill",
                    action: { audioEngine.seek(to: 0) },
                    label: "Go to beginning"
                )
                .help("Jump to the beginning of the track")
                
                TransportButton(
                    icon: "stop.fill",
                    action: { audioEngine.stop() },
                    label: "Stop"
                )
                .help("Stop playback and reset to beginning")
                
                TransportButton(
                    icon: audioEngine.isPlaying ? "pause.fill" : "play.fill",
                    isActive: audioEngine.isPlaying,
                    action: { audioEngine.togglePlayback() },
                    label: audioEngine.isPlaying ? "Pause" : "Play"
                )
                .help(audioEngine.isPlaying ? "Pause playback (Space)" : "Start playback (Space)")
                
                TransportButton(
                    icon: "repeat",
                    isActive: audioEngine.isLooping,
                    action: { audioEngine.toggleLooping() },
                    label: audioEngine.isLooping ? "Disable loop" : "Enable loop"
                )
                .help(audioEngine.isLooping ? "Disable loop region (⌘L)" : "Enable loop region (⌘L)")
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "1a1a1a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "333333"), lineWidth: 1)
                    )
            )
            
            // LCD Time Display
            LCDDisplay(time: audioEngine.currentTime, duration: audioEngine.duration)
            
            // Stereo VU meters
            StereoVUMetersView(leftLevel: masterLevel, rightLevel: masterLevel)
        }
    }
    
    var masterLevel: Float {
        if audioEngine.hasSession {
            // Analyzed mode: sum of stem levels
            guard !audioEngine.meterLevels.isEmpty else { return 0 }
            let sum = audioEngine.meterLevels.reduce(0, +)
            return min(1.0, sum / Float(audioEngine.meterLevels.count) * 1.5)
        } else {
            // Pre-analysis mode: original audio level
            return audioEngine.originalMeterLevel
        }
    }
}

// MARK: - Stereo VU Meters
struct StereoVUMetersView: View {
    let leftLevel: Float
    let rightLevel: Float
    
    private var accessibilityDescription: String {
        let leftPercent = Int(leftLevel * 100)
        let rightPercent = Int(rightLevel * 100)
        return "Left channel: \(leftPercent)%. Right channel: \(rightPercent)%"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            VUMeterView(level: leftLevel, channel: "Left")
            VUMeterView(level: rightLevel, channel: "Right")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Master stereo meters")
        .accessibilityValue(accessibilityDescription)
    }
}

// MARK: - Analog VU Meter (needle-style level meter)
struct VUMeterView: View {
    let level: Float
    var channel: String = "Channel"
    
    // Needle angle: -45° (min) to +45° (max)
    private var needleAngle: Double {
        let clampedLevel = Double(max(0, min(1, level)))
        // Map 0-1 to -45 to +45 degrees
        return -45 + (clampedLevel * 90)
    }
    
    private var levelDescription: String {
        let percent = Int(level * 100)
        return "\(percent)%"
    }
    
    var body: some View {
        ZStack {
            // Meter face background
            MeterFaceView()
            
            // Needle
            NeedleView(angle: needleAngle)
            
            // Pivot point cover
            Circle()
                .fill(Color(hex: "2a2a2a"))
                .frame(width: 6, height: 6)
                .offset(y: 12)
        }
        .frame(width: 50, height: 28)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1a1a1a"), Color(hex: "0f0f0f")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: "3a3a3a"), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .accessibilityLabel("\(channel) VU meter")
        .accessibilityValue(levelDescription)
    }
}

// VU Meter face with tick marks
struct MeterFaceView: View {
    var body: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY = size.height + 2  // Pivot below visible area
            let radius: CGFloat = 22
            
            // Green zone (-20 to -6 dB, roughly 0-60% of arc)
            let greenArc = Path { path in
                path.addArc(
                    center: CGPoint(x: centerX, y: centerY),
                    radius: radius - 2,
                    startAngle: .degrees(-135),
                    endAngle: .degrees(-81),
                    clockwise: false
                )
            }
            context.stroke(greenArc, with: .color(Color(hex: "30d158").opacity(0.6)), lineWidth: 3)
            
            // Yellow zone (-6 to 0 dB)
            let yellowArc = Path { path in
                path.addArc(
                    center: CGPoint(x: centerX, y: centerY),
                    radius: radius - 2,
                    startAngle: .degrees(-81),
                    endAngle: .degrees(-63),
                    clockwise: false
                )
            }
            context.stroke(yellowArc, with: .color(Color(hex: "ffcc00").opacity(0.6)), lineWidth: 3)
            
            // Red zone (0 to +3 dB)
            let redArc = Path { path in
                path.addArc(
                    center: CGPoint(x: centerX, y: centerY),
                    radius: radius - 2,
                    startAngle: .degrees(-63),
                    endAngle: .degrees(-45),
                    clockwise: false
                )
            }
            context.stroke(redArc, with: .color(Color(hex: "ff3b30").opacity(0.6)), lineWidth: 3)
            
            // Draw tick marks
            let tickAngles: [(angle: Double, length: CGFloat)] = [
                (-135, 4),
                (-117, 3),
                (-99, 3),
                (-81, 3),
                (-72, 4),
                (-54, 3),
                (-45, 4),
            ]
            
            for tick in tickAngles {
                let angleRad = tick.angle * .pi / 180
                let innerRadius = radius - 6
                let outerRadius = radius - 6 + tick.length
                
                let innerX = centerX + innerRadius * cos(CGFloat(angleRad))
                let innerY = centerY + innerRadius * sin(CGFloat(angleRad))
                let outerX = centerX + outerRadius * cos(CGFloat(angleRad))
                let outerY = centerY + outerRadius * sin(CGFloat(angleRad))
                
                var tickPath = Path()
                tickPath.move(to: CGPoint(x: innerX, y: innerY))
                tickPath.addLine(to: CGPoint(x: outerX, y: outerY))
                
                context.stroke(tickPath, with: .color(Color(hex: "888888")), lineWidth: 1)
            }
        }
    }
}

// Animated needle
struct NeedleView: View {
    let angle: Double
    
    var body: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY = size.height + 2
            let needleLength: CGFloat = 18
            
            let angleRad = (angle - 90) * .pi / 180
            let tipX = centerX + needleLength * cos(CGFloat(angleRad))
            let tipY = centerY + needleLength * sin(CGFloat(angleRad))
            
            // Needle shadow
            var shadowPath = Path()
            shadowPath.move(to: CGPoint(x: centerX + 0.5, y: centerY + 0.5))
            shadowPath.addLine(to: CGPoint(x: tipX + 0.5, y: tipY + 0.5))
            context.stroke(shadowPath, with: .color(.black.opacity(0.5)), lineWidth: 1.5)
            
            // Needle body
            var needlePath = Path()
            needlePath.move(to: CGPoint(x: centerX, y: centerY))
            needlePath.addLine(to: CGPoint(x: tipX, y: tipY))
            context.stroke(needlePath, with: .color(Color(hex: "ff6b6b")), lineWidth: 1)
            
            // Needle tip highlight
            let highlightLength: CGFloat = 4
            let highlightX = tipX - highlightLength * cos(CGFloat(angleRad))
            let highlightY = tipY - highlightLength * sin(CGFloat(angleRad))
            var highlightPath = Path()
            highlightPath.move(to: CGPoint(x: highlightX, y: highlightY))
            highlightPath.addLine(to: CGPoint(x: tipX, y: tipY))
            context.stroke(highlightPath, with: .color(Color(hex: "ffffff")), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.1), value: angle)
    }
}

struct TransportButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    var label: String = ""
    
    private var accessibilityLabelText: String {
        if !label.isEmpty {
            return label
        }
        // Fallback to icon-based label
        switch icon {
        case "backward.end.fill":
            return "Go to beginning"
        case "stop.fill":
            return "Stop"
        case "play.fill":
            return "Play"
        case "pause.fill":
            return "Pause"
        case "repeat":
            return "Loop"
        default:
            return "Transport control"
        }
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? Color(hex: "30d158") : Color(hex: "888888"))
                .frame(width: 32, height: 26)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color(hex: "0a84ff").opacity(0.2) : Color.clear)
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

struct LCDDisplay: View {
    let time: Double
    let duration: Double
    
    private var accessibilityDescription: String {
        let currentMins = Int(time) / 60
        let currentSecs = Int(time) % 60
        let totalMins = Int(duration) / 60
        let totalSecs = Int(duration) % 60
        return "Current time: \(currentMins) minutes \(currentSecs) seconds. Total duration: \(totalMins) minutes \(totalSecs) seconds"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(formatTime(time))
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "30d158"))
            Text("/")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(Color(hex: "666666"))
            Text(formatTime(duration))
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(Color(hex: "666666"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "0a0a0a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: "333333"), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .accessibilityLabel("Time display")
        .accessibilityValue(accessibilityDescription)
    }
    
    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }
}

// MARK: - Drop Zone
struct DropZoneView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 20) {
                if audioEngine.isProcessing {
                    VStack(spacing: 16) {
                        // Progress bar
                        VStack(spacing: 12) {
                            ProgressView(value: audioEngine.processingProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: "0a84ff")))
                                .frame(width: 300)
                            
                            Text(audioEngine.processingStatus.isEmpty ? "Processing..." : audioEngine.processingStatus)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "888888"))
                        }
                        
                        Text("Demucs may take several minutes on first run")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "666666"))
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isDragOver ? Color(hex: "0a84ff") : Color(hex: "555555"),
                                style: StrokeStyle(lineWidth: 2, dash: [8])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isDragOver ? Color(hex: "0a84ff").opacity(0.1) : Color(hex: "222222"))
                            )
                        
                        VStack(spacing: 16) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(Color(hex: "666666"))
                            
                            VStack(spacing: 4) {
                                Text("Drop audio file here")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Text("or click to browse")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "888888"))
                                Text("WAV or MP3")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "666666"))
                            }
                        }
                        .padding(40)
                    }
                    .frame(width: 400, height: 250)
                    .onTapGesture {
                        audioEngine.openFile()
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                        handleDrop(providers: providers)
                    }
                    .accessibilityLabel("File drop zone")
                    .accessibilityHint("Drop an audio file here or double-tap to browse")
                    .accessibilityAddTraits(.isButton)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "242424"), Color(hex: "1a1a1a")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            let ext = url.pathExtension.lowercased()
            if ext == "wav" || ext == "mp3" {
                DispatchQueue.main.async {
                    audioEngine.loadFile(url: url)
                }
            }
        }
        return true
    }
}

// MARK: - Pre-Analysis View (file loaded but not analyzed)
struct PreAnalysisView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline with waveform
            PreAnalysisTimelineView()
            
            Spacer()
            
            // Analysis options and button
            VStack(spacing: 24) {
                if audioEngine.isProcessing {
                    // Processing indicator with progress bar
                    VStack(spacing: 16) {
                        // Progress bar
                        VStack(spacing: 12) {
                            ProgressView(value: audioEngine.processingProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: "0a84ff")))
                                .frame(width: 300)
                            
                            Text(audioEngine.processingStatus.isEmpty ? "Processing..." : audioEngine.processingStatus)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "888888"))
                        }
                        
                        Text("Demucs may take several minutes on first run")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "666666"))
                    }
                } else {
                    // Info text
                    Text("Separates into: Drums, Bass, Vocals, Guitar, Keys, Other\nRequires Python & ~4GB download on first run")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "666666"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    // Analyze button
                    Button(action: { audioEngine.analyze() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 16))
                            Text("Analyze")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "0a84ff"), Color(hex: "0070e0")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color(hex: "0a84ff").opacity(0.3), radius: 8, y: 2)
                    .accessibilityLabel("Analyze audio")
                    .accessibilityHint("Start separating the audio into individual instrument stems")
                    .help("Analyze and separate audio into stems using Demucs AI")
                    
                    Text("Play to preview, then click Analyze to separate instruments")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "555555"))
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "242424"), Color(hex: "1a1a1a")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Pre-Analysis Timeline (simplified timeline for preview)
struct PreAnalysisTimelineView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var isDragging: Bool = false
    @State private var dragMode: Int = 0 // 0=none, 1=creating, 2=moving
    @State private var regionDragOffset: Double = 0
    @State private var dragStartTime: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Waveform + playhead + region
            GeometryReader { geometry in
                let padding: CGFloat = 16
                let width = geometry.size.width - (padding * 2)
                let playheadX = audioEngine.duration > 0 
                    ? padding + width * CGFloat(audioEngine.currentTime / audioEngine.duration)
                    : padding
                
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "1a1a1a"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(hex: "2a2a2a"), lineWidth: 1)
                        )
                    
                    // Selection/play region
                    if audioEngine.selectionEnd > audioEngine.selectionStart && audioEngine.duration > 0 {
                        let regionStartRatio = CGFloat(audioEngine.selectionStart / audioEngine.duration)
                        let regionEndRatio = CGFloat(audioEngine.selectionEnd / audioEngine.duration)
                        let regionW = width * (regionEndRatio - regionStartRatio)
                        let regionX = padding + width * regionStartRatio + regionW / 2
                        
                        Rectangle()
                            .fill(Color(hex: "0a84ff").opacity(0.4))
                            .frame(width: max(2, regionW))
                            .position(x: regionX, y: geometry.size.height / 2)
                    }
                    
                    // Waveform
                    Canvas { context, size in
                        let centerY = size.height / 2
                        let samples = audioEngine.waveformSamples
                        guard samples.count > 1 else { return }
                        let step = width / CGFloat(samples.count - 1)
                        
                        var path = Path()
                        for i in 0..<samples.count {
                            let x = padding + CGFloat(i) * step
                            let amp = CGFloat(samples[i]) * (size.height * 0.45)
                            path.move(to: CGPoint(x: x, y: centerY - amp))
                            path.addLine(to: CGPoint(x: x, y: centerY + amp))
                        }
                        context.stroke(path, with: .color(Color(hex: "6b6b6b")), lineWidth: 1)
                    }
                    
                    // Playhead
                    if audioEngine.duration > 0 {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2)
                            .position(x: playheadX, y: geometry.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            guard audioEngine.duration > 0 else { return }
                            
                            let startX = min(max(value.startLocation.x, padding), padding + width)
                            let currentX = min(max(value.location.x, padding), padding + width)
                            let clickTime = Double((startX - padding) / width) * audioEngine.duration
                            let currentTime = Double((currentX - padding) / width) * audioEngine.duration
                            
                            // Determine drag mode on first movement
                            if !isDragging {
                                isDragging = true
                                dragStartTime = clickTime
                                
                                // Check if click is inside existing region
                                let hasRegion = audioEngine.selectionEnd > audioEngine.selectionStart
                                if hasRegion && clickTime >= audioEngine.selectionStart && clickTime <= audioEngine.selectionEnd {
                                    dragMode = 2 // moving
                                    regionDragOffset = clickTime - audioEngine.selectionStart
                                } else {
                                    dragMode = 1 // creating
                                }
                            }
                            
                            if dragMode == 1 {
                                // Create/resize selection from drag start to current position
                                let selStart = min(dragStartTime, currentTime)
                                let selEnd = max(dragStartTime, currentTime)
                                audioEngine.setSelection(start: selStart, end: selEnd)
                            } else if dragMode == 2 {
                                // Move the region
                                let regionWidth = audioEngine.selectionEnd - audioEngine.selectionStart
                                var newStart = currentTime - regionDragOffset
                                var newEnd = newStart + regionWidth
                                
                                // Clamp to bounds
                                if newStart < 0 {
                                    newStart = 0
                                    newEnd = regionWidth
                                }
                                if newEnd > audioEngine.duration {
                                    newEnd = audioEngine.duration
                                    newStart = audioEngine.duration - regionWidth
                                }
                                
                                audioEngine.setSelection(start: newStart, end: newEnd)
                            }
                        }
                        .onEnded { value in
                            guard audioEngine.duration > 0 else { return }
                            
                            let startX = min(max(value.startLocation.x, padding), padding + width)
                            let endX = min(max(value.location.x, padding), padding + width)
                            let dragDistance = abs(endX - startX)
                            let clickTime = Double((endX - padding) / width) * audioEngine.duration
                            
                            // If it was just a click (minimal drag), move playhead
                            if dragDistance < 3 {
                                // Check if clicked inside region
                                let hasRegion = audioEngine.selectionEnd > audioEngine.selectionStart
                                let clickedInRegion = hasRegion && clickTime >= audioEngine.selectionStart && clickTime <= audioEngine.selectionEnd
                                
                                if !clickedInRegion {
                                    audioEngine.clearSelection()
                                }
                                
                                audioEngine.seek(to: clickTime)
                            }
                            
                            isDragging = false
                            dragMode = 0
                            regionDragOffset = 0
                        }
                )
            }
            .frame(height: 100)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color(hex: "111111"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "333333")),
            alignment: .bottom
        )
    }
}

// MARK: - Mixer View
struct MixerView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline
            TimelineView()
            
            // Channel strips - centered with spacing
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // All channels except the last one (Other)
                        ForEach(0..<max(0, audioEngine.componentCount - 1), id: \.self) { index in
                            ChannelStripView(index: index)
                        }
                        
                        // The last channel (Other)
                        if audioEngine.componentCount > 0 {
                            ChannelStripView(index: audioEngine.componentCount - 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(minWidth: geometry.size.width, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(hex: "1e1e1e"))
        }
        .background(Color(hex: "1e1e1e"))
    }
}

// MARK: - Timeline
struct TimelineView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var isDragging: Bool = false
    @State private var dragMode: Int = 0 // 0=none, 1=creating, 2=moving
    @State private var regionDragOffset: Double = 0
    @State private var dragStartTime: Double = 0
    
    private var accessibilityDescription: String {
        let currentMins = Int(audioEngine.currentTime) / 60
        let currentSecs = Int(audioEngine.currentTime) % 60
        if audioEngine.selectionEnd > audioEngine.selectionStart {
            let startMins = Int(audioEngine.selectionStart) / 60
            let startSecs = Int(audioEngine.selectionStart) % 60
            let endMins = Int(audioEngine.selectionEnd) / 60
            let endSecs = Int(audioEngine.selectionEnd) % 60
            return "Playhead at \(currentMins):\(String(format: "%02d", currentSecs)). Loop region from \(startMins):\(String(format: "%02d", startSecs)) to \(endMins):\(String(format: "%02d", endSecs))"
        } else {
            return "Playhead at \(currentMins):\(String(format: "%02d", currentSecs)). No loop region"
        }
    }
    
    var body: some View {
        // Waveform + playhead + region
        GeometryReader { geometry in
            let hPadding: CGFloat = 16
            let width = geometry.size.width - (hPadding * 2)
            let playheadX = audioEngine.duration > 0 
                ? hPadding + width * CGFloat(audioEngine.currentTime / audioEngine.duration)
                : hPadding
            
            ZStack {
                // Background that fills the padded area
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "1a1a1a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "2a2a2a"), lineWidth: 1)
                    )
                    .frame(width: width, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Selection/play region
                if audioEngine.selectionEnd > audioEngine.selectionStart && audioEngine.duration > 0 {
                    let regionStartRatio = CGFloat(audioEngine.selectionStart / audioEngine.duration)
                    let regionEndRatio = CGFloat(audioEngine.selectionEnd / audioEngine.duration)
                    let regionW = width * (regionEndRatio - regionStartRatio)
                    let regionX = hPadding + width * regionStartRatio + regionW / 2
                    
                    Rectangle()
                        .fill(Color(hex: "0a84ff").opacity(0.4))
                        .frame(width: max(2, regionW))
                        .position(x: regionX, y: geometry.size.height / 2)
                }
                
                // Waveform
                Canvas { context, size in
                    let centerY = size.height / 2
                    let samples = audioEngine.waveformSamples
                    guard samples.count > 1 else { return }
                    let step = width / CGFloat(samples.count - 1)
                    
                    var path = Path()
                    for i in 0..<samples.count {
                        let x = hPadding + CGFloat(i) * step
                        let amp = CGFloat(samples[i]) * (size.height * 0.45)
                        path.move(to: CGPoint(x: x, y: centerY - amp))
                        path.addLine(to: CGPoint(x: x, y: centerY + amp))
                    }
                    context.stroke(path, with: .color(Color(hex: "6b6b6b")), lineWidth: 1)
                }
                
                // Playhead
                if audioEngine.duration > 0 {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .position(x: playheadX, y: geometry.size.height / 2)
                }
            }
            .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            guard audioEngine.duration > 0 else { return }
                            
                            let startX = min(max(value.startLocation.x, hPadding), hPadding + width)
                            let currentX = min(max(value.location.x, hPadding), hPadding + width)
                            let clickTime = Double((startX - hPadding) / width) * audioEngine.duration
                            let currentTime = Double((currentX - hPadding) / width) * audioEngine.duration
                            
                            // Determine drag mode on first movement
                            if !isDragging {
                                isDragging = true
                                dragStartTime = clickTime
                                
                                // Check if click is inside existing region
                                let hasRegion = audioEngine.selectionEnd > audioEngine.selectionStart
                                if hasRegion && clickTime >= audioEngine.selectionStart && clickTime <= audioEngine.selectionEnd {
                                    dragMode = 2 // moving
                                    regionDragOffset = clickTime - audioEngine.selectionStart
                                } else {
                                    dragMode = 1 // creating
                                }
                            }
                            
                            if dragMode == 1 {
                                // Create/resize selection from drag start to current position
                                let selStart = min(dragStartTime, currentTime)
                                let selEnd = max(dragStartTime, currentTime)
                                audioEngine.setSelection(start: selStart, end: selEnd)
                            } else if dragMode == 2 {
                                // Move the region
                                let regionWidth = audioEngine.selectionEnd - audioEngine.selectionStart
                                var newStart = currentTime - regionDragOffset
                                var newEnd = newStart + regionWidth
                                
                                // Clamp to bounds
                                if newStart < 0 {
                                    newStart = 0
                                    newEnd = regionWidth
                                }
                                if newEnd > audioEngine.duration {
                                    newEnd = audioEngine.duration
                                    newStart = audioEngine.duration - regionWidth
                                }
                                
                                audioEngine.setSelection(start: newStart, end: newEnd)
                            }
                        }
                        .onEnded { value in
                            guard audioEngine.duration > 0 else { return }
                            
                            let startX = min(max(value.startLocation.x, hPadding), hPadding + width)
                            let endX = min(max(value.location.x, hPadding), hPadding + width)
                            let dragDistance = abs(endX - startX)
                            let clickTime = Double((endX - hPadding) / width) * audioEngine.duration
                            
                            // If it was just a click (minimal drag), move playhead
                            if dragDistance < 3 {
                                // Check if clicked inside region
                                let hasRegion = audioEngine.selectionEnd > audioEngine.selectionStart
                                let clickedInRegion = hasRegion && clickTime >= audioEngine.selectionStart && clickTime <= audioEngine.selectionEnd
                                
                                if !clickedInRegion {
                                    audioEngine.clearSelection()
                                }
                                
                                audioEngine.seek(to: clickTime)
                            }
                            
                            isDragging = false
                            dragMode = 0
                            regionDragOffset = 0
                        }
                )
        }
        .frame(height: 80)
        .background(Color(hex: "1e1e1e"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "333333")),
            alignment: .bottom
        )
        .accessibilityLabel("Timeline and waveform")
        .accessibilityValue(accessibilityDescription)
        .accessibilityHint("Click to seek, drag to create a loop region, or drag an existing region to move it")
        .help("Click to seek, drag to create a loop region, or drag an existing region to move it")
        .contextMenu {
            if audioEngine.selectionEnd > audioEngine.selectionStart {
                Button("Clear Loop Region") {
                    audioEngine.clearSelection()
                }
                Divider()
            }
            
            Button("Go to Beginning") {
                audioEngine.seek(to: 0)
            }
            
            if audioEngine.duration > 0 {
                Button("Go to End") {
                    audioEngine.seek(to: audioEngine.duration)
                }
            }
        }
    }
}

// Playhead indicator view
struct PlayheadView: View {
    let isDragging: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle at top
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "30d158"))
                .frame(width: isDragging ? 12 : 8, height: 8)
                .shadow(color: Color(hex: "30d158").opacity(0.6), radius: isDragging ? 4 : 2)
            
            // Line
            Rectangle()
                .fill(Color(hex: "30d158"))
                .frame(width: 2)
                .shadow(color: Color(hex: "30d158").opacity(0.6), radius: 2)
        }
        .animation(.easeOut(duration: 0.1), value: isDragging)
    }
}

// MARK: - Channel Strip
struct ChannelStripView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    let index: Int
    
    var stemName: String {
        if index < audioEngine.stemNames.count {
            return audioEngine.stemNames[index]
        }
        return "Track \(index + 1)"
    }
    
    var stemIcon: String {
        switch stemName.lowercased() {
        case "drums":
            return "circle.fill"
        case "bass":
            return "guitars"
        case "vocals", "voice":
            return "mic"
        case "guitar":
            return "guitars"
        case "keys", "piano":
            return "pianokeys"
        case "other":
            return "music.note"
        default:
            return "waveform"
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Header
            VStack(spacing: 2) {
                Image(systemName: stemIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: "e5e5e5"))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color(hex: "1f1f1f"))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "333333"), lineWidth: 1)
                    )
                
                Text(stemName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: "9a9a9a"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.top, 8)
            
            // Pan Knob
            PanKnobView(
                value: Binding(
                    get: { index < audioEngine.panValues.count ? audioEngine.panValues[index] : 0.0 },
                    set: { audioEngine.setPanValue($0, for: index) }
                ),
                stemName: stemName
            )
            .help("Drag left or right to pan \(stemName). Double-click to center.")
            
            // Meter
            MeterView(
                level: index < audioEngine.meterLevels.count ? audioEngine.meterLevels[index] : 0,
                stemName: stemName
            )
            .help("\(stemName) audio level meter")
            
            // Fader
            FaderView(
                value: Binding(
                    get: { index < audioEngine.faderValues.count ? audioEngine.faderValues[index] : 1.0 },
                    set: { audioEngine.setFaderValue($0, for: index) }
                ),
                stemName: stemName
            )
            .help("Drag to adjust \(stemName) volume")
            
            // dB readout
            Text(formatDB(index < audioEngine.faderValues.count ? audioEngine.faderValues[index] : 1.0))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "888888"))
                .frame(width: 40)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "111111"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(hex: "333333"), lineWidth: 1)
                        )
                )
            
            // Solo/Mute
            HStack(spacing: 4) {
                SoloMuteButton(
                    label: "S",
                    isActive: index < audioEngine.soloStates.count ? audioEngine.soloStates[index] : false,
                    activeColor: Color(hex: "ffcc00"),
                    action: { audioEngine.toggleSolo(for: index) },
                    stemName: stemName
                )
                .help("Solo \(stemName) - hear only this track")
                
                SoloMuteButton(
                    label: "M",
                    isActive: index < audioEngine.muteStates.count ? audioEngine.muteStates[index] : false,
                    activeColor: Color(hex: "ff453a"),
                    action: { audioEngine.toggleMute(for: index) },
                    stemName: stemName
                )
                .help("Mute \(stemName)")
            }
            .padding(.bottom, 10)
        }
        .frame(width: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "2a2a2a"), Color(hex: "222222")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .contextMenu {
            Button("Reset Fader") {
                audioEngine.setFaderValue(1.0, for: index)
            }
            
            Button("Reset Pan") {
                audioEngine.setPanValue(0.0, for: index)
            }
            
            Divider()
            
            Button("Reset All") {
                audioEngine.setFaderValue(1.0, for: index)
                audioEngine.setPanValue(0.0, for: index)
                if audioEngine.soloStates.indices.contains(index) && audioEngine.soloStates[index] {
                    audioEngine.toggleSolo(for: index)
                }
                if audioEngine.muteStates.indices.contains(index) && audioEngine.muteStates[index] {
                    audioEngine.toggleMute(for: index)
                }
            }
            
            Divider()
            
            if audioEngine.muteStates.indices.contains(index) {
                if audioEngine.muteStates[index] {
                    Button("Unmute") {
                        audioEngine.toggleMute(for: index)
                    }
                } else {
                    Button("Mute") {
                        audioEngine.toggleMute(for: index)
                    }
                }
            }
            
            if audioEngine.soloStates.indices.contains(index) {
                if audioEngine.soloStates[index] {
                    Button("Unsolo") {
                        audioEngine.toggleSolo(for: index)
                    }
                } else {
                    Button("Solo") {
                        audioEngine.toggleSolo(for: index)
                    }
                }
            }
        }
    }
    
    func formatDB(_ value: Double) -> String {
        if value == 0 { return "-∞" }
        let db = 20 * log10(value)
        return String(format: "%.1f", db)
    }
}

// MARK: - Meter
struct MeterView: View {
    let level: Float
    var stemName: String = "Track"
    
    private var levelDescription: String {
        let percent = Int(level * 100)
        if level > 0.9 {
            return "\(percent)% - High"
        } else if level > 0.6 {
            return "\(percent)% - Medium"
        } else if level > 0.3 {
            return "\(percent)% - Low"
        } else {
            return "\(percent)% - Very low"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "111111"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(hex: "333333"), lineWidth: 1)
                    )
                
                // Level
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "30d158"),
                                Color(hex: "30d158"),
                                Color(hex: "ffcc00"),
                                Color(hex: "ff9500"),
                                Color(hex: "ff3b30")
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: geometry.size.height * CGFloat(level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(width: 8, height: 100)
        .accessibilityLabel("\(stemName) level meter")
        .accessibilityValue(levelDescription)
    }
}

// MARK: - Pan Knob
struct PanKnobView: View {
    @Binding var value: Double  // -1.0 (left) to 1.0 (right)
    @State private var isDragging = false
    var stemName: String = "Track"
    
    private let knobSize: CGFloat = 32
    
    // Convert value (-1 to 1) to angle (-135 to 135 degrees)
    private var angle: Double {
        value * 135
    }
    
    private var panDescription: String {
        if abs(value) < 0.05 {
            return "Center"
        } else if value < 0 {
            let percent = Int(abs(value) * 100)
            return "\(percent)% Left"
        } else {
            let percent = Int(value * 100)
            return "\(percent)% Right"
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // L/R labels
            HStack {
                Text("L")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(value < -0.3 ? Color(hex: "0a84ff") : Color(hex: "555555"))
                Spacer()
                Text("R")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(value > 0.3 ? Color(hex: "0a84ff") : Color(hex: "555555"))
            }
            .frame(width: knobSize + 8)
            
            // Knob
            ZStack {
                // Outer ring / track
                Circle()
                    .fill(Color(hex: "1a1a1a"))
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "444444"), lineWidth: 2)
                    )
                
                // Indicator arc showing position
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        Color(hex: "333333"),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: knobSize - 6, height: knobSize - 6)
                    .rotationEffect(.degrees(135))
                
                // Active indicator
                if abs(value) > 0.05 {
                    Circle()
                        .trim(from: 0.375, to: 0.375 + (value * 0.375))
                        .stroke(
                            Color(hex: "0a84ff"),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: knobSize - 6, height: knobSize - 6)
                        .rotationEffect(.degrees(135))
                }
                
                // Knob cap
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "5a5a5a"), Color(hex: "3a3a3a")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: knobSize - 10, height: knobSize - 10)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "2a2a2a"), lineWidth: 1)
                    )
                
                // Position indicator line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 6)
                    .offset(y: -7)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: knobSize, height: knobSize)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        // Horizontal drag changes pan
                        let delta = gesture.translation.width / 50
                        let newValue = max(-1, min(1, value + delta))
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        // Double-tap to center
                        withAnimation(.easeOut(duration: 0.15)) {
                            value = 0
                        }
                    }
            )
            .accessibilityLabel("\(stemName) pan control")
            .accessibilityValue(panDescription)
            .accessibilityHint("Adjust the stereo position for this track. Double-tap with two fingers to center.")
            .accessibilityAdjustableAction { direction in
                let step = 0.1
                switch direction {
                case .increment:
                    value = min(1.0, value + step)
                case .decrement:
                    value = max(-1.0, value - step)
                @unknown default:
                    break
                }
            }
        }
    }
}

// MARK: - Fader
struct FaderView: View {
    @Binding var value: Double
    var stemName: String = "Track"
    
    private var dbValue: String {
        if value == 0 { return "-∞ dB" }
        let db = 20 * log10(value)
        return String(format: "%.1f dB", db)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "0a0a0a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "333333"), lineWidth: 1)
                    )
                
                // Center line
                Rectangle()
                    .fill(Color(hex: "222222"))
                    .frame(width: 4)
                
                // Thumb
                VStack {
                    Spacer()
                        .frame(height: (1 - CGFloat(value)) * (geometry.size.height - 24))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6a6a6a"), Color(hex: "4a4a4a"), Color(hex: "3a3a3a")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 32, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(hex: "222222"), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    
                    Spacer()
                        .frame(height: CGFloat(value) * (geometry.size.height - 24))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = 1 - (gesture.location.y / geometry.size.height)
                        value = max(0, min(1, newValue))
                    }
            )
        }
        .frame(width: 36, height: 120)
        .accessibilityLabel("\(stemName) volume fader")
        .accessibilityValue(dbValue)
        .accessibilityHint("Adjust the volume level for this track")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            switch direction {
            case .increment:
                value = min(1.0, value + step)
            case .decrement:
                value = max(0.0, value - step)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Solo/Mute Button
struct SoloMuteButton: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    var stemName: String = "Track"
    
    private var accessibilityLabelText: String {
        if label == "S" {
            return "Solo \(stemName)"
        } else {
            return "Mute \(stemName)"
        }
    }
    
    private var accessibilityHintText: String {
        if label == "S" {
            return isActive ? "Double-tap to unsolo this track" : "Double-tap to solo this track"
        } else {
            return isActive ? "Double-tap to unmute this track" : "Double-tap to mute this track"
        }
    }
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isActive ? .black : Color(hex: "666666"))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? activeColor : Color(hex: "3a3a3a"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(hex: "333333"), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Master Channel
struct MasterChannelView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "ff9f0a"))
                .padding(.top, 8)
            
            Spacer()
            
            // Master meter (sum of all)
            HStack(spacing: 2) {
                MeterView(level: masterLevel)
                MeterView(level: masterLevel)
            }
            
            Text("0.0")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "888888"))
                .padding(.bottom, 12)
            
            Spacer()
        }
        .frame(width: 90)
        .background(
            LinearGradient(
                colors: [Color(hex: "333333"), Color(hex: "282828")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(width: 2)
                .foregroundColor(Color(hex: "0a84ff")),
            alignment: .leading
        )
    }
    
    var masterLevel: Float {
        guard !audioEngine.meterLevels.isEmpty else { return 0 }
        let sum = audioEngine.meterLevels.reduce(0, +)
        return min(1.0, sum / Float(audioEngine.meterLevels.count) * 1.5)
    }
}

// MARK: - Analysis Timer View
struct AnalysisTimerView: View {
    let startTime: Date
    @State private var elapsedTime: TimeInterval = 0
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(formatElapsedTime(elapsedTime))
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            .foregroundColor(Color(hex: "30d158"))
            .onReceive(timer) { _ in
                elapsedTime = Date().timeIntervalSince(startTime)
            }
            .onAppear {
                elapsedTime = Date().timeIntervalSince(startTime)
            }
    }
    
    func formatElapsedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Button Styles
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed ?
                                [Color(hex: "0070e0"), Color(hex: "005bb5")] :
                                [Color(hex: "0a84ff"), Color(hex: "0070e0")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .foregroundColor(.white)
    }
}

struct SecondaryToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed ?
                                [Color(hex: "3a3a3a"), Color(hex: "2a2a2a")] :
                                [Color(hex: "4a4a4a"), Color(hex: "3a3a3a")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(hex: "555555"), lineWidth: 1)
                    )
            )
            .foregroundColor(Color(hex: "cccccc"))
    }
}

// MARK: - Error Sheet
struct ErrorSheet: View {
    let errorMessage: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                Text("Error")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)
            
            // Scrollable error text
            ScrollView {
                Text(errorMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: "cccccc"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "1a1a1a"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "333333"), lineWidth: 1)
            )
            
            // Buttons
            HStack(spacing: 12) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(errorMessage, forType: .string)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("OK") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .background(Color(hex: "2d2d2d"))
    }
}

// MARK: - EQ Window Manager
class EQWindowManager: ObservableObject {
    static let shared = EQWindowManager()
    private var window: NSWindow?
    private var windowDelegate: WindowCloseDelegate?  // Strong reference to delegate
    
    func showWindow(audioEngine: AudioEngine) {
        if window == nil {
            let contentView = EQWindow()
                .environmentObject(audioEngine)
            
            let hostingController = NSHostingController(rootView: contentView)
            
            window = NSWindow(contentViewController: hostingController)
            window?.title = "Parametric EQ"
            window?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window?.setContentSize(NSSize(width: 1000, height: 500))
            window?.level = .floating
            window?.isReleasedWhenClosed = false
            window?.minSize = NSSize(width: 900, height: 450)
            
            // Center window
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let windowRect = window!.frame
                let x = screenRect.midX - windowRect.width / 2
                let y = screenRect.midY - windowRect.height / 2
                window?.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            // Keep strong reference to delegate
            windowDelegate = WindowCloseDelegate(audioEngine: audioEngine)
            window?.delegate = windowDelegate
        }
        
        window?.makeKeyAndOrderFront(nil)
        audioEngine.showEQWindow = true
    }
    
    func hideWindow() {
        window?.orderOut(nil)
    }
}

class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let audioEngine: AudioEngine
    
    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }
    
    func windowWillClose(_ notification: Notification) {
        audioEngine.showEQWindow = false
    }
}

// MARK: - EQ Window
struct EQWindow: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var selectedTarget: String = "Master"
    
    var targetOptions: [String] {
        ["Master"] + audioEngine.stemNames
    }
    
    var currentBands: [AudioEngine.EQBand] {
        audioEngine.eqSettings[selectedTarget]?.bands ?? AudioEngine.EQBandSettings().bands
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                
                // Target selector
                Picker("", selection: $selectedTarget) {
                    ForEach(targetOptions, id: \.self) { target in
                        Text(target).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                Button("Reset") {
                    audioEngine.resetEQ(target: selectedTarget)
                }
                .buttonStyle(SecondaryToolbarButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: "2d2d2d"))
            
            Divider()
                .background(Color(hex: "444444"))
            
            // EQ Bands - Horizontal layout with vertical controls
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<currentBands.count, id: \.self) { index in
                        VerticalEQBandView(
                            bandIndex: index,
                            band: currentBands[index],
                            target: selectedTarget,
                            level: index < audioEngine.eqBandLevels.count ? audioEngine.eqBandLevels[index] : 0
                        )
                    }
                }
                .padding(16)
            }
            .id("\(selectedTarget)-\(audioEngine.eqResetCounter)")  // Force refresh when target changes or reset is pressed
            .background(Color(hex: "1a1a1a"))
        }
        .background(Color(hex: "1a1a1a"))
        .ignoresSafeArea()
    }
}

struct VerticalEQBandView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    let bandIndex: Int
    let band: AudioEngine.EQBand
    let target: String
    let level: Float
    
    @State private var gain: Float
    @State private var q: Float
    
    init(bandIndex: Int, band: AudioEngine.EQBand, target: String, level: Float) {
        self.bandIndex = bandIndex
        self.band = band
        self.target = target
        self.level = level
        _gain = State(initialValue: band.gain)
        _q = State(initialValue: band.q)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Frequency label at top
            Text(formatFrequency(band.frequency))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
            
            // Gain value
            Text("\(gain, specifier: "%.1f") dB")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(gain > 0.1 ? Color(hex: "30d158") : (gain < -0.1 ? Color(hex: "ff9500") : Color(hex: "888888")))
                .frame(width: 60)
            
            HStack(spacing: 8) {
                // dB scale labels
                VStack {
                    Text("+12")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "666666"))
                    Spacer()
                    Text("0")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "888888"))
                    Spacer()
                    Text("-12")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "666666"))
                }
                .frame(height: 200)
                
                // Vertical level meter
                VerticalEQMeterView(level: level)
                
                // Vertical gain fader
                VerticalGainFader(value: $gain, onChange: { newValue in
                    audioEngine.updateEQBand(target: target, bandIndex: bandIndex, gain: newValue, q: q)
                })
            }
            
            // Q control
            VStack(spacing: 4) {
                Text("Q: \(q, specifier: "%.1f")")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "888888"))
                
                Slider(value: $q, in: 0.1...10, step: 0.1)
                    .onChange(of: q) { newValue in
                        audioEngine.updateEQBand(target: target, bandIndex: bandIndex, gain: gain, q: newValue)
                    }
                    .frame(width: 70)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 120)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "252525"))
        )
    }
    
    func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk", freq / 1000)
        } else {
            return String(format: "%.0f", freq)
        }
    }
}

// MARK: - Vertical EQ Meter
struct VerticalEQMeterView: View {
    let level: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "111111"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(hex: "333333"), lineWidth: 1)
                    )
                
                // Level fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "30d158"),
                                Color(hex: "30d158"),
                                Color(hex: "ffcc00"),
                                Color(hex: "ff9500"),
                                Color(hex: "ff3b30")
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: geometry.size.height * CGFloat(level))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
        .frame(width: 8, height: 200)
    }
}

// MARK: - Vertical Gain Fader for EQ
struct VerticalGainFader: View {
    @Binding var value: Float  // -12 to +12 dB
    let onChange: (Float) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "0a0a0a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "333333"), lineWidth: 1)
                    )
                
                // Center line (0 dB)
                Rectangle()
                    .fill(Color(hex: "444444"))
                    .frame(width: 20, height: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // +12 and -12 labels
                VStack {
                    Text("+12")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "666666"))
                    Spacer()
                    Text("0")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "888888"))
                    Spacer()
                    Text("-12")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "666666"))
                }
                .padding(.vertical, 4)
                
                // Thumb
                VStack {
                    // Convert gain (-12 to +12) to position (0 to 1)
                    let normalizedValue = (value + 12) / 24  // -12 becomes 0, +12 becomes 1
                    let thumbY = (1 - CGFloat(normalizedValue)) * (geometry.size.height - 16) + 8
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6a6a6a"), Color(hex: "4a4a4a"), Color(hex: "3a3a3a")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 24, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(hex: "222222"), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(x: geometry.size.width / 2, y: thumbY)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Convert Y position to gain value
                        let y = gesture.location.y
                        let normalizedY = max(0, min(1, y / geometry.size.height))
                        let newGain = 12 - (normalizedY * 24)  // Top = +12, Bottom = -12
                        let clampedGain = Float(max(-12, min(12, newGain)))
                        value = clampedGain
                        onChange(clampedGain)
                    }
            )
        }
        .frame(width: 26, height: 200)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Preview in Xcode:
// #Preview {
//     ContentView()
//         .environmentObject(AudioEngine())
//         .frame(width: 1000, height: 600)
// }
