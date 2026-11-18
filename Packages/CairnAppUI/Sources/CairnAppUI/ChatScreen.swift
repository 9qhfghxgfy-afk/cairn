import SwiftUI
import CairnChatDomain

public struct ChatScreen: View {
    // Internal, not `private`: the selector menus live in ChatScreen+Menus.swift,
    // which is a second file of the same type.
    let workspace: ChatWorkspace
    /// Present once the app wires app-wide settings. A chat's own configuration saves without it — the
    /// settings object is only needed for "Use for new chats", which writes the baseline.
    let settings: ThemeModel?
    @State private var composerText = ""
    @State private var showingConfig = false

    public init(workspace: ChatWorkspace, settings: ThemeModel? = nil) {
        self.workspace = workspace
        self.settings = settings
    }

    var session: ChatSessionModel? { workspace.session }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(CairnTheme.stone.opacity(0.5))
            transcript
            composer
        }
        .background(CairnTheme.slateDeep)
        .sheet(isPresented: $showingConfig) {
            if let session {
                ChatConfigSheet(
                    session: session,
                    defaults: workspace.defaultConfig,
                    makeDefault: makeDefaultConfig
                )
            }
        }
    }

    /// Present only when a settings store is wired: the chat still saves its own configuration, and a
    /// default the app cannot persist is a default that would be forgotten at the next launch.
    private var makeDefaultConfig: ((ChatConfig) -> Void)? {
        guard let settings else { return nil }
        return { config in
            settings.saveDefaultConfig(config)
            workspace.apply(defaults: config)
        }
    }

    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CairnMark().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session?.conversation.title ?? "Cairn")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let provider = session?.activeProvider {
                            Text(provider.displayName)
                            NetworkBadge(networkClass: provider.networkClass)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 0)
                Button {
                    showingConfig = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .overlay(alignment: .topTrailing) {
                            if let count = session?.conversation.config.configuredOptionCount,
                               count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(CairnTheme.slateDeep)
                                    .frame(width: 15, height: 15)
                                    .background(Circle().fill(CairnTheme.amber))
                                    .offset(x: 9, y: -8)
                            }
                        }
                }
                .foregroundStyle(CairnTheme.amber)
                .accessibilityLabel(
                    "Chat settings, "
                        + "\(session?.conversation.config.configuredOptionCount ?? 0) options set"
                )

                Button(action: { workspace.startNewChat() }) {
                    Image(systemName: "square.and.pencil")
                }
                .foregroundStyle(CairnTheme.amber)
            }

            HStack(spacing: 8) {
                modeMenu
                modelMenu
                Spacer(minLength: 0)
                temporaryToggle
            }

            if let hybrid = liveHybridSnapshot {
                HybridProgressView(snapshot: hybrid)
            } else if session?.isBusy == true {
                StreamingStatusView(
                    phase: session?.phase ?? .idle,
                    tokensPerSecond: session?.liveTokensPerSecond
                )
            }

            // A hybrid mode a chat cannot run yet is said here rather than left to fail silently on
            // the next send: the user chose the mode, so the mode owes them the reason.
            if let refusal = hybridRefusal {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.rust)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

    /// The panel a hybrid turn drives: a live snapshot only while a hybrid turn is really in flight.
    ///
    /// The session leaves its snapshot standing after a hybrid turn ends so the panels can still be
    /// read beside the answer, which means a chat in another mode must be excluded by its mode — not
    /// by the snapshot's presence — or a finished turn would keep animating in the header. Once a turn
    /// is over, the stored drafts and provenance on the node are what the user reads.
    var liveHybridSnapshot: HybridSnapshot? {
        guard let session,
              HybridPanelRule.showsPanel(
                  mode: session.conversation.mode,
                  isBusy: session.isBusy,
                  hasSnapshot: session.hybrid != nil
              ),
              let snapshot = session.hybrid else { return nil }
        return snapshot
    }

    /// Why this chat cannot run the hybrid mode it is in, or nil when it can — the same
    /// `HybridPlan` refusal the configuration sheet shows and the turn itself refuses with.
    var hybridRefusal: String? {
        guard let session, session.conversation.mode.isHybrid, !session.isBusy else { return nil }
        return session.hybridBlockReason
    }

    // MARK: - Transcript

    var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let session {
                        ForEach(session.path) { node in
                            MessageRow(session: session, node: node)
                                .id(node.id)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(12)
            }
            .onChange(of: session?.path.count ?? 0) { _, _ in
                if let last = session?.path.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            CairnMark().frame(width: 76, height: 76)
            Text("Marks the trail, keeps it local")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Everything you write stays on this device unless you add a server.")
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Composer

    var composer: some View {
        VStack(spacing: 6) {
            if let error = workspace.lastError ?? session?.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.rust)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Cairn…", text: $composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CairnTheme.slate)
                    )
                    .foregroundStyle(.white)
                    .onSubmit(send)

                if session?.isBusy == true {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .padding(10)
                            .background(Circle().fill(CairnTheme.rust.opacity(0.85)))
                            .foregroundStyle(.white)
                    }
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .padding(10)
                            .background(Circle().fill(CairnTheme.amber))
                            .foregroundStyle(CairnTheme.slateDeep)
                    }
                    .disabled(composerText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(12)
    }

    func send() {
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session?.send(text)
        composerText = ""
    }

    func stop() {
        session?.cancelStreaming()
    }
}
