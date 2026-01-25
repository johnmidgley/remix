import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView()
            
            // Main content with optional file browser
            HStack(spacing: 0) {
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
    }
}

// MARK: - File Browser
struct FileBrowserView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var directoryContents: [FileItem] = []
    @State private var selectedFile: URL?
    @State private var quickAccessLocations: [QuickAccessItem] = []
    
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
    
    struct QuickAccessItem: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let url: URL
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with path and navigation
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: navigateUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(hex: "888888"))
                    .disabled(audioEngine.currentDirectory.path == "/")
                    
                    Text(audioEngine.currentDirectory.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button(action: { audioEngine.showFileBrowser = false }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(hex: "888888"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                // Breadcrumb path
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(pathComponents, id: \.self) { component in
                            Button(action: { navigateTo(component) }) {
                                Text(component.lastPathComponent.isEmpty ? "/" : component.lastPathComponent)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "666666"))
                            }
                            .buttonStyle(.plain)
                            
                            if component != audioEngine.currentDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(hex: "444444"))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 20)
            }
            .background(Color(hex: "252525"))
            
            Divider()
                .background(Color(hex: "333333"))
            
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
                            QuickAccessRowView(item: location) {
                                audioEngine.currentDirectory = location.url
                            }
                        }
                        
                        Divider()
                            .background(Color(hex: "333333"))
                            .padding(.vertical, 8)
                    }
                    
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
            .background(Color(hex: "1e1e1e"))
        }
        .onAppear {
            loadQuickAccessLocations()
            loadDirectory()
        }
        .onChange(of: audioEngine.currentDirectory) { _ in loadDirectory() }
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
    
    var pathComponents: [URL] {
        var components: [URL] = []
        var current = audioEngine.currentDirectory
        while current.path != "/" {
            components.insert(current, at: 0)
            current = current.deletingLastPathComponent()
        }
        components.insert(URL(fileURLWithPath: "/"), at: 0)
        return components
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
        let parent = audioEngine.currentDirectory.deletingLastPathComponent()
        audioEngine.currentDirectory = parent
    }
    
    func navigateTo(_ url: URL) {
        audioEngine.currentDirectory = url
    }
    
    func selectFile(_ item: FileItem) {
        selectedFile = item.url
    }
    
    func openItem(_ item: FileItem) {
        if item.isDirectory {
            audioEngine.currentDirectory = item.url
            selectedFile = nil
        } else if item.isAudioFile {
            audioEngine.loadFile(url: item.url)
        }
    }
}

struct QuickAccessRowView: View {
    let item: FileBrowserView.QuickAccessItem
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "0a84ff"))
                .frame(width: 18)
            
            Text(item.name)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
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
            // Left section - Sidebar toggle + File info
            HStack(spacing: 12) {
                Button(action: { audioEngine.showFileBrowser.toggle() }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                        .foregroundColor(audioEngine.showFileBrowser ? Color(hex: "0a84ff") : Color(hex: "888888"))
                }
                .buttonStyle(.plain)
                
                if let fileName = audioEngine.fileName {
                    Image(systemName: "waveform")
                        .foregroundColor(Color(hex: "0a84ff"))
                    Text(fileName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .frame(width: 220, alignment: .leading)
            .padding(.leading, 12)
            
            Spacer()
            
            // Center - Transport
            TransportView()
            
            Spacer()
            
            // Right section - Actions
            HStack(spacing: 12) {
                // Playback speed (show when file is loaded or analyzed)
                if audioEngine.hasLoadedFile || audioEngine.hasSession {
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
                    }
                }
                
                // Bounce only available after analysis
                if audioEngine.hasSession {
                    Button(action: { audioEngine.bounceToFile() }) {
                        Label("Bounce", systemImage: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
            }
            .frame(minWidth: 220, alignment: .trailing)
            .padding(.trailing, 16)
        }
        .frame(height: 48)
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
                TransportButton(icon: "stop.fill", action: { audioEngine.stopAndReset() })
                TransportButton(
                    icon: audioEngine.isPlaying ? "pause.fill" : "play.fill",
                    isActive: audioEngine.isPlaying,
                    action: { audioEngine.togglePlayback() }
                )
                TransportButton(
                    icon: "repeat",
                    isActive: audioEngine.isLooping,
                    action: { audioEngine.isLooping.toggle() }
                )
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
    
    var body: some View {
        HStack(spacing: 4) {
            VUMeterView(level: leftLevel)
            VUMeterView(level: rightLevel)
        }
    }
}

// MARK: - Analog VU Meter (needle-style level meter)
struct VUMeterView: View {
    let level: Float
    
    // Needle angle: -45° (min) to +45° (max)
    private var needleAngle: Double {
        let clampedLevel = Double(max(0, min(1, level)))
        // Map 0-1 to -45 to +45 degrees
        return -45 + (clampedLevel * 90)
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
    }
}

struct LCDDisplay: View {
    let time: Double
    let duration: Double
    
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
    
    let componentOptions = [2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 20) {
                if audioEngine.isProcessing {
                    VStack(spacing: 16) {
                        if audioEngine.processingProgress > 0 {
                            ProgressView(value: audioEngine.processingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: "0a84ff")))
                                .frame(width: 260)
                        } else {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "0a84ff")))
                        }
                        
                        Text(audioEngine.processingStatus.isEmpty ? "Processing..." : audioEngine.processingStatus)
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "888888"))
                        
                        if audioEngine.separationMode == .demucs {
                            Text("Demucs may take several minutes on first run")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "666666"))
                        }
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
                    
                    // Mode selector
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Mode:")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "888888"))
                            
                            Picker("", selection: $audioEngine.separationMode) {
                                ForEach(SeparationMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "333333"))
                            )
                        }
                        
                        // Show component count only for PCA mode
                        if audioEngine.separationMode == .pca {
                            HStack(spacing: 12) {
                                Text("Components:")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "888888"))
                                
                                Picker("", selection: $audioEngine.selectedComponentCount) {
                                    ForEach(componentOptions, id: \.self) { count in
                                        Text("\(count)").tag(count)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(hex: "333333"))
                                )
                            }
                        }
                        
                        // Mode description
                        Text(modeDescription)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "666666"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 350)
                    }
                    .padding(.top, 8)
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
    
    var modeDescription: String {
        switch audioEngine.separationMode {
        case .demucs:
            return "Separates into: Drums, Bass, Vocals, Guitar, Keys, Other\nRequires Python & ~4GB download on first run"
        case .pca:
            return "Separates by spectral patterns (experimental)"
        }
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
    
    let componentOptions = [2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32]
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline with waveform
            PreAnalysisTimelineView()
            
            Spacer()
            
            // Analysis options and button
            VStack(spacing: 24) {
                if audioEngine.isProcessing {
                    // Processing indicator
                    VStack(spacing: 16) {
                        if audioEngine.processingProgress > 0 {
                            ProgressView(value: audioEngine.processingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: "0a84ff")))
                                .frame(width: 260)
                        } else {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "0a84ff")))
                        }
                        
                        Text(audioEngine.processingStatus.isEmpty ? "Processing..." : audioEngine.processingStatus)
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "888888"))
                        
                        if audioEngine.separationMode == .demucs {
                            Text("Demucs may take several minutes on first run")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "666666"))
                        }
                    }
                } else {
                    // Mode selector
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Text("Mode:")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "888888"))
                            
                            Picker("", selection: $audioEngine.separationMode) {
                                ForEach(SeparationMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "333333"))
                            )
                        }
                        
                        // Show component count only for PCA mode
                        if audioEngine.separationMode == .pca {
                            HStack(spacing: 12) {
                                Text("Components:")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "888888"))
                                
                                Picker("", selection: $audioEngine.selectedComponentCount) {
                                    ForEach(componentOptions, id: \.self) { count in
                                        Text("\(count)").tag(count)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(hex: "333333"))
                                )
                            }
                        }
                        
                        // Mode description
                        Text(modeDescription)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "666666"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                    
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
    
    var modeDescription: String {
        switch audioEngine.separationMode {
        case .demucs:
            return "Separates into: Drums, Bass, Vocals, Guitar, Keys, Other\nRequires Python & ~4GB download on first run"
        case .pca:
            return "Separates by spectral patterns (experimental)"
        }
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
            .frame(height: 80)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<audioEngine.componentCount, id: \.self) { index in
                        ChannelStripView(index: index)
                    }
                }
                .padding(.horizontal, 20)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .background(Color(hex: "1e1e1e"))
            
            // Mixer controls bar
            HStack {
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { audioEngine.zeroAllFaders() }) {
                        Text("All 0")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(SecondaryToolbarButtonStyle())
                    
                    Button(action: { audioEngine.resetAllFaders() }) {
                        Text("Reset")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(SecondaryToolbarButtonStyle())
                }
                .padding(.trailing, 20)
            }
            .frame(height: 40)
            .background(Color(hex: "191919"))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(hex: "333333")),
                alignment: .top
            )
        }
    }
}

// MARK: - Timeline
struct TimelineView: View {
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
            .frame(height: 56)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(hex: "111111"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "333333")),
            alignment: .bottom
        )
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
            return "oval.fill"
        case "bass":
            return "guitars"
        case "vocals":
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
        VStack(spacing: 8) {
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
                
                // Show variance only in PCA mode
                if audioEngine.separationMode == .pca && index < audioEngine.varianceRatios.count {
                    Text(String(format: "%.1f%%", audioEngine.varianceRatios[index]))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "666666"))
                }
            }
            .padding(.top, 8)
            
            // Meter
            MeterView(level: index < audioEngine.meterLevels.count ? audioEngine.meterLevels[index] : 0)
            
            // Fader
            FaderView(
                value: Binding(
                    get: { index < audioEngine.faderValues.count ? audioEngine.faderValues[index] : 1.0 },
                    set: { audioEngine.setFaderValue($0, for: index) }
                )
            )
            
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
                    action: { audioEngine.toggleSolo(for: index) }
                )
                SoloMuteButton(
                    label: "M",
                    isActive: index < audioEngine.muteStates.count ? audioEngine.muteStates[index] : false,
                    activeColor: Color(hex: "ff453a"),
                    action: { audioEngine.toggleMute(for: index) }
                )
            }
            .padding(.bottom, 12)
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
            }
        }
        .frame(width: 8, height: 120)
    }
}

// MARK: - Fader
struct FaderView: View {
    @Binding var value: Double
    
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
        .frame(width: 36, height: 140)
    }
}

// MARK: - Solo/Mute Button
struct SoloMuteButton: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
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
