import SwiftUI
import CairnChatDomain

public struct ChatScreen: View {
    // Internal, not `private`: the selector menus live in ChatScreen+Menus.swift,
    // which is a second file of the same type.
    let workspace: ChatWorkspace
    /// Present once the app wires app-wide settings. A chat's own configuration saves without it — the
    /// settings object is only needed for "Use for new chats", which writes the baseline.
    let settings: ThemeModel?
    /// The files waiting for Send. A reference type rather than view state because the acceptance rule and
    /// the refusal have to survive the sheet a picker dismisses, and because a test has to be able to put a
    /// file in the composer without a simulator: see `ComposerDraft`.
    let draft: ComposerDraft
    @State var composerText = ""
    /// Where the keyboard is. Internal, not `private`: the composer in `ChatScreen+Composer.swift` is a
    /// second file of the same type and has to be able to put the focus back, because "Done" on a
    /// keyboard that stays on screen is a button that did nothing.
    @FocusState var composerFocused: Bool
    @State private var showingConfig = false
    /// The side of every control in the composer row, in points.
    ///
    /// The row used to size its buttons by padding an icon, which made each one a slightly different size and
    /// each one smaller than it looked. This is the row a thumb aims at while the keyboard covers the lower
    /// half of the screen, so the controls get a fixed square at the size iOS treats as a target a finger can
    /// hit, matched by `contentShape` so the hit area is the square rather than the glyph inside it. One
    /// constant for all three controls also keeps Send from shifting when the hide-keyboard chevron appears
    /// or when Stop replaces Send.
    static let composerControlSide: CGFloat = 44


    /// `imagePreparer` is the thing that can resize a photo — UIKit and ImageIO, which the domain cannot
    /// import. Left nil in previews and tests, which then get `PassthroughImagePreparer`: it checks the bytes
    /// and claims nothing about having resampled them, which is the honest fallback rather than a lie about
    /// a size the file never became.
    public init(workspace: ChatWorkspace, settings: ThemeModel? = nil, imagePreparer: (any ImagePreparing)? = nil) {
        self.workspace = workspace
        self.settings = settings
        self.draft = ComposerDraft(preparer: imagePreparer ?? PassthroughImagePreparer())
    }

    var session: ChatSessionModel? { workspace.session }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(CairnTheme.stone.opacity(0.5))
            // Above the transcript rather than in a settings screen, because the thing it is warning about
            // is the text currently on screen.
            if workspace.temporaryChat {
                TempChatBanner(workspace: workspace)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            transcript
            composer
        }
        .background(CairnTheme.slateDeep)
        .sheet(isPresented: $showingConfig) {
            if let session {
                // The theme is handed across the presentation gap on purpose: a sheet arrives with a
                // window of its own, and a sheet that is not told which theme to wear wears the system's.
                ChatConfigSheet(
                    session: session,
                    defaults: workspace.defaultConfig,
                    makeDefault: makeDefaultConfig
                )
                .cairnPresentation(theme: settings)
            }
        }
        // No keyboard accessory bar, deliberately, and the composer's own row is the only way to close the
        // keyboard besides scrolling the transcript.
        //
        // `ToolbarItem(placement: .keyboard)` drew a thin strip directly above the keyboard, which put a
        // "Done" button exactly where the composer's Send button is. On iPhone the two hit areas are a few
        // points apart and the strip wins, so the tap a person meant for Send dismissed the keyboard instead
        // — the one mistake a chat app can make with a message already typed in it. The strip also cost a row
        // of height in the least space-constrained moment the screen has. The chevron in the composer row does
        // the same job with a target the finger can actually aim at, and `.scrollDismissesKeyboard(.interactively)`
        // does it with the gesture a person is already making.
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

    /// The top of the screen, sized to leave room for the answer.
    ///
    /// Tight on purpose. Every row here is a row the transcript cannot show while the keyboard is up,
    /// and on a phone with the keyboard open the transcript is the whole point of the screen — so the
    /// header's paddings and gaps are measured against the two lines it has to hold, not against how
    /// much room the chrome could take.
    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CairnMark().frame(width: 24, height: 24)
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
                        // Up before anything is sent, and still up for the rest of the conversation once
                        // something has been: a query that already left is only visible afterwards, which is
                        // exactly when a badge that vanished would be useless.
                        outboundBadge
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

            HStack(spacing: 6) {
                modeMenu
                modeInfo
                modelMenu
                Spacer(minLength: 0)
                temporaryToggle
            }

            // The window the turn really has, said next to the controls that imply a bigger one.
            if let note = session?.contextCeilingNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(CairnTheme.stoneLight)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            // The keyboard is drawn over the transcript, and the last thing read is the thing it
            // covers. Dismissing it has to be part of the gesture the hand is already making —
            // scrolling — rather than a control to hunt for. `.interactively` means the keyboard
            // travels with the finger the whole way down, so the motion that hides a message also
            // brings it back.
            .scrollDismissesKeyboard(.interactively)
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

    // The composer — the text field, the paperclip, the files it is holding, and what happens on Send —
    // lives in ChatScreen+Composer.swift, with the send and the stop that belong to it.
}
