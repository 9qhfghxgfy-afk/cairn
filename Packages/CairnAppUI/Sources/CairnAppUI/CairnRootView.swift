import SwiftUI
import CairnChatDomain

/// Entry view. Milestone 1 wires exactly one engine — the mock — so the whole app is
/// exercisable end to end before any socket exists.
public struct CairnRootView: View {
    private let workspace: ChatWorkspace
    /// Present once the app wires server-profile storage (M2); the toolbar gear then opens
    /// the Servers screen. M1 call sites keep working unchanged.
    private var servers: ServersModel?
    /// App-wide settings: the theme painted on this screen, and the Default Configuration new chats
    /// start from. Optional so previews and tests can build a root view with no store behind it.
    private var settings: ThemeModel?
    /// The Web Search screen's model, handed through to Settings. The app layer owns it because it is the only
    /// place a Keychain vault and a connection tester exist.
    private var webSearch: WebSearchSettingsModel?
    /// The question both web tools stop in front of. Held here rather than in `ChatScreen` because the sheet
    /// belongs to the device, not to one conversation: a search asked in a second chat while the first sheet is
    /// still up must not put a second sheet on top of it.
    private var consent: WebSearchConsentModel?
    /// The thing that can resize a photo before it joins a message. Handed through rather than reached for:
    /// `CairnAppUI` may draw an image, but the size a photo becomes is the domain's rule
    /// (`ImagePreparationPolicy`), and the codec that applies it belongs to the app.
    private var imagePreparer: (any ImagePreparing)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingServers = false
    @State private var showingSettings = false
    @State private var showingChats = false

    public init(
        workspace: ChatWorkspace,
        servers: ServersModel? = nil,
        settings: ThemeModel? = nil,
        imagePreparer: (any ImagePreparing)? = nil,
        webSearch: WebSearchSettingsModel? = nil,
        consent: WebSearchConsentModel? = nil
    ) {
        self.workspace = workspace
        self.servers = servers
        self.settings = settings
        self.imagePreparer = imagePreparer
        self.webSearch = webSearch
        self.consent = consent
    }

    public var body: some View {
        NavigationStack {
            ChatScreen(workspace: workspace, settings: settings, imagePreparer: imagePreparer)
                .navigationTitle("Cairn")
                // Painted from inside the stack as well as outside it: a nav bar takes its bar styling
                // from the content it belongs to, so a chrome modifier wrapped around the stack never
                // reaches the bar and the buttons in it.
                .cairnPresentation(theme: settings)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The list of chats leads, not trails: it is where a conversation comes from, and on a
                    // one-handed phone a leading thumb reaches it while a trailing one has to stretch.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingChats = true
                        } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("Chats")
                    }
                    if servers != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingServers = true
                            } label: {
                                Image(systemName: "server.rack")
                            }
                            .accessibilityLabel("Servers")
                        }
                    }
                    if settings != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
                }
        }
        .sheet(isPresented: $showingChats) {
            // A stack of its own, because the list searches and pushes screens of its own; and it is the
            // workspace that acts, so opening a chat here re-reads the store rather than a row on screen.
            CairnSheet(theme: settings) {
                ChatListView(workspace: workspace)
            }
        }
        .sheet(isPresented: $showingServers) {
            if let servers {
                CairnSheet(theme: settings) {
                    ServersView(model: servers)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let settings {
                CairnSheet(theme: settings) {
                    SettingsView(theme: settings, workspace: workspace, webSearch: webSearch)
                }
            }
        }
        // The question a web tool cannot ask for itself. It is up here rather than beside the composer
        // because the answer is about the device, and because two chats that ask at the same moment get one
        // sheet: the model queues the second question behind the first, and the sheet always shows the head.
        // There is no way to dismiss this without answering — swiping down is a refusal, recorded as one.
        .sheet(isPresented: Binding(
            get: { consent?.isAsking == true },
            set: { asking in if !asking { consent?.declineUnanswered() } }
        )) {
            if let consent, let prompt = consent.pending {
                WebSearchConsentSheet(model: consent, prompt: prompt)
                    .cairnPresentation(theme: settings)
            }
        }
        // The chosen theme, from the stored settings: the accent actions take, the surface the app sits
        // on, and which half of it to paint. Applied to the window, and again inside the stack where the
        // bar can read it — a sheet that wore the system's own chrome was the half of this bug the user
        // could see. Nothing here changes where a prompt goes: a theme is a look, never a network
        // decision.
        .cairnChrome(theme: settings)
        .task { await workspace.start() }
        .onChange(of: scenePhase) { _, phase in
            // Going to the background really does end a turn. iOS suspends the app and takes the socket
            // with it, so an answer that appears to "keep streaming" is a stream frozen mid-sentence. It is
            // stopped here and marked paused rather than complete, which is what makes Continue on that row
            // a real offer instead of a button that redoes the whole turn.
            if phase == .background { workspace.session?.interruptActiveTurn() }
        }
    }
}
