import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var library: LibraryStore

    // Background playback
    @AppStorage(SettingsKey.backgroundPlayback) private var backgroundPlayback = true
    @AppStorage(SettingsKey.spoofVisibility) private var spoofVisibility = true
    @AppStorage(SettingsKey.autoResume) private var autoResume = true
    @AppStorage(SettingsKey.keepAlive) private var keepAlive = false
    @AppStorage(SettingsKey.resumeAfterInterruption) private var resumeAfterInterruption = true
    // PiP
    @AppStorage(SettingsKey.autoPiP) private var autoPiP = true
    // Lock screen
    @AppStorage(SettingsKey.lockScreenControls) private var lockScreenControls = true
    @AppStorage(SettingsKey.skipInterval) private var skipInterval: Double = 15
    // Browser
    @AppStorage(SettingsKey.searchEngine) private var searchEngine = SearchEngine.google.rawValue
    @AppStorage(SettingsKey.desktopMode) private var desktopMode = false
    @AppStorage(SettingsKey.blockPopups) private var blockPopups = true
    @AppStorage(SettingsKey.saveHistory) private var saveHistory = true
    @AppStorage(SettingsKey.homepage) private var homepage = ""
    // Appearance
    @AppStorage(SettingsKey.appearanceAccent) private var accent = Theme.Accent.gold.rawValue
    @AppStorage(SettingsKey.appearanceBackground) private var backdrop = Theme.Backdrop.obsidian.rawValue

    @State private var confirmClearHistory = false
    @State private var confirmClearData = false
    @State private var clearedMessage: String?

    var body: some View {
        NavigationStack {
            List {
                backgroundSection
                pipSection
                lockScreenSection
                searchSection
                browserSection
                appearanceSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Theme.goldGradientHorizontal)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.sheet = nil }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.gold)
                }
            }
            .confirmationDialog("Clear all browsing history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { library.clearHistory() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Remove cookies, caches and site data?", isPresented: $confirmClearData, titleVisibility: .visible) {
                Button("Clear Website Data", role: .destructive) {
                    Task {
                        await library.clearWebsiteData()
                        clearedMessage = "Website data cleared."
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(clearedMessage ?? "", isPresented: Binding(get: { clearedMessage != nil },
                                                              set: { if !$0 { clearedMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
        .tint(Theme.gold)
    }

    // MARK: Sections

    private var backgroundSection: some View {
        Section {
            Toggle("Background playback", isOn: $backgroundPlayback)
            Toggle("Keep sites playing when hidden", isOn: $spoofVisibility)
            Toggle("Auto-resume if paused in background", isOn: $autoResume)
            Toggle("Resume after calls & interruptions", isOn: $resumeAfterInterruption)
            Toggle("Silent keep-alive audio", isOn: $keepAlive)
        } header: {
            SectionLabel("Background Playback")
        } footer: {
            Text("“Keep sites playing when hidden” stops sites like YouTube from pausing when you lock the screen or switch apps. Turn on silent keep-alive audio only if playback stops after a while.")
        }
        .rowStyle()
    }

    private var pipSection: some View {
        Section {
            Toggle("Auto Picture in Picture when leaving app", isOn: $autoPiP)
        } header: {
            SectionLabel("Picture in Picture")
        } footer: {
            Text("Video starts floating automatically when you swipe home or switch apps. You can also start it from the player (expand the mini-player).")
        }
        .rowStyle()
    }

    private var lockScreenSection: some View {
        Section {
            Toggle("Lock Screen & Control Center controls", isOn: $lockScreenControls)
            Picker("Skip interval", selection: $skipInterval) {
                Text("10 seconds").tag(10.0)
                Text("15 seconds").tag(15.0)
                Text("30 seconds").tag(30.0)
            }
        } header: {
            SectionLabel("Lock Screen")
        }
        .rowStyle()
    }

    private var searchSection: some View {
        Section {
            Picker("Search engine", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.name).tag(engine.rawValue)
                }
            }
        } header: {
            SectionLabel("Search")
        }
        .rowStyle()
    }

    private var browserSection: some View {
        Section {
            Toggle("Request desktop websites by default", isOn: $desktopMode)
            Toggle("Block pop-ups", isOn: $blockPopups)
            Toggle("Save browsing history", isOn: $saveHistory)
            HStack {
                Text("Homepage")
                TextField("Start page", text: $homepage)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.textSecondary)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Button("Clear Browsing History", role: .destructive) { confirmClearHistory = true }
            Button("Clear Website Data", role: .destructive) { confirmClearData = true }
        } header: {
            SectionLabel("Browser")
        }
        .rowStyle()
    }

    private var appearanceSection: some View {
        Section {
            HStack(spacing: 16) {
                Text("Accent")
                Spacer()
                ForEach(Theme.Accent.allCases) { option in
                    Button {
                        accent = option.rawValue
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [option.light, option.mid, option.deep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white.opacity(accent == option.rawValue ? 0.9 : 0.15),
                                                           lineWidth: accent == option.rawValue ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                }
            }
            Picker("Background", selection: $backdrop) {
                ForEach(Theme.Backdrop.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        } header: {
            SectionLabel("Appearance")
        }
        .rowStyle()
    }

    private var aboutSection: some View {
        Section {
            HStack {
                CrownLogo().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    KingVidWordmark(size: 15)
                    Text("Version \(version)")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            SectionLabel("About")
        } footer: {
            Text("Some websites restrict background playback. KingVid keeps each site's original player running and does not extract or replace media.")
        }
        .rowStyle()
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

private extension Section where Parent: View, Content: View, Footer: View {
    func rowStyle() -> some View {
        self.listRowBackground(Theme.surface)
    }
}
