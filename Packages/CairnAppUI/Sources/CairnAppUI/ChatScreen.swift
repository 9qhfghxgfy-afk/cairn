import SwiftUI
import CairnChatDomain

public struct ChatScreen: View {
    // Internal, not `private`: the selector menus live in ChatScreen+Menus.swift,
    // which is a second file of the same type.
    let workspace: ChatWorkspace
    @State private var composerText = ""

    public init(workspace: ChatWorkspace) {
        self.workspace = workspace
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

            if session?.isBusy == true {
                StreamingStatusView(
                    phase: session?.phase ?? .idle,
                    tokensPerSecond: session?.liveTokensPerSecond
                )
            }
        }
        .padding(12)
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
