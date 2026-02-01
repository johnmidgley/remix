import SwiftUI

struct LicensesView: View {
    @Environment(\.dismiss) var dismiss
    @State private var licensesText: String = "Loading..."
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("About Remix")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // About section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remix")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("AI-Powered Music Stem Separation")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Version 1.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    Divider()
                    
                    // License info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("License")
                            .font(.headline)
                        
                        Text("Remix is licensed under the Apache License 2.0")
                            .font(.body)
                        
                        Text("This application uses open-source software including Demucs (MIT License) for AI-powered stem separation.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    Divider()
                    
                    // Third-party licenses
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Third-Party Licenses")
                            .font(.headline)
                        
                        Text(licensesText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 600)
        .onAppear(perform: loadLicenses)
    }
    
    private func loadLicenses() {
        // Try to load from app bundle Resources
        if let resourcePath = Bundle.main.resourcePath {
            let licensePath = (resourcePath as NSString).appendingPathComponent("THIRD_PARTY_LICENSES.md")
            
            if let content = try? String(contentsOfFile: licensePath, encoding: .utf8) {
                licensesText = content
                return
            }
        }
        
        // Fallback text
        licensesText = """
        Unable to load license file.
        
        Remix uses the following open-source software:
        
        • Demucs - MIT License (Meta Platforms, Inc.)
          AI music source separation
          https://github.com/facebookresearch/demucs
        
        • PyTorch - BSD-3-Clause License (Meta Platforms, Inc.)
          Deep learning framework
        
        • Python - Python Software Foundation License
          Bundled runtime
        
        For complete licensing information, see THIRD_PARTY_LICENSES.md
        included in the application bundle.
        """
    }
}

struct AboutMenuItem: View {
    @State private var showingLicenses = false
    
    var body: some View {
        Button("About Remix...") {
            showingLicenses = true
        }
        .sheet(isPresented: $showingLicenses) {
            LicensesView()
        }
    }
}

#Preview {
    LicensesView()
}
