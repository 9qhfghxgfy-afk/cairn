import CairnChatDomain
import SwiftUI

/// The share screen: the switch, what the surface is doing, the key, and the limits a phone has.
///
/// Every word here comes from `ShareStatusText`, which is domain code with tests — so the claims on this
/// screen ("a phone is not a server", "every request needs this key") are the same claims the tests
/// check, not a second copy written next to the view where they could drift.
struct ShareView: View {
    /// Not `private`: the picker and the port live in `ShareView+Selection`, and `private` in Swift means
    /// **file**-private, which a second file cannot see. The same reason `ServersModel` keeps its stored
    /// state module-internal for its `+Discovery` extension.
    var model: ShareModel

    init(model: ShareModel) { self.model = model }

    var body: some View {
        Form {
            surfaceSection
            keySection
            selectionSection
            limitsSection
        }
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.refresh() }
    }

    /// The switch and the live line under it. The switch writes intent; the line reports the socket, so
    /// the two can disagree honestly while a start is in flight or a refusal just landed.
    var surfaceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.isEnabled },
                set: { wanted in Task { await model.setSharing(wanted) } }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(ShareStatusText.title).font(.subheadline)
                        if let badge = model.badgeText {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(CairnTheme.stone.opacity(0.25), in: Capsule())
                                .foregroundStyle(CairnTheme.moss)
                        }
                    }
                    Text(model.statusLine)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
            }
            .tint(CairnTheme.amber)
            .accessibilityHint("Opens a port on your local network for this app session only.")

            // The address is runtime state shown on the phone that owns it: never stored, never exported,
            // never logged. This is the only place it appears.
            if let address = model.addressLine {
                HStack {
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(CairnTheme.stoneLight)
                    Spacer()
                    CopyButton("Copy address") { address }
                }
                .accessibilityElement(children: .combine)
            }

            // Said here because it qualifies the line above it: the address is what a client types either
            // way, but whether the system pinned the socket to that one interface is a separate fact, and
            // a screen that printed only the address would claim more than the system granted.
            if let bindNote = ShareStatusText.bindNote(model.status) {
                Text(bindNote)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }

            if let notice = model.notice {
                ServersNoticeBanner(text: notice)
            }
        } header: {
            // The `(i)` sits on the header: the row under it is a single toggle whose label already carries the
            // live status line, and a button inside a toggle's label sits inside the toggle's own tap area.
            InfoSectionHeader("Local model sharing", key: .shareOnLocalNetwork)
        } footer: {
            Text(ShareStatusText.servingNote(model.status))
        }
    }

    /// The inbound key. Masked on screen because a key that opens this phone should not be legible over a
    /// shoulder or readable in a screenshot; copy hands over the real one because a laptop needs the real
    /// one. Rotation is the only edit offered — there is no text field to type a word into.
    var keySection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Peer key").font(.subheadline)
                    Text(model.maskedToken)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer()
                if !model.token.isEmpty {
                    CopyButton("Copy key") { model.token }
                }
            }
            .accessibilityElement(children: .combine)

            Button {
                model.regenerateToken()
            } label: {
                Label("Regenerate key", systemImage: "arrow.clockwise")
            }
        } header: {
            InfoSectionHeader("Key", key: .sharePeerKey)
        } footer: {
            Text(ShareStatusText.tokenNote)
        }
    }

    /// The two limits this milestone owes out loud, plus the permission that really breaks the surface.
    var limitsSection: some View {
        Section("What this is") {
            Label(ShareStatusText.suspensionNote, systemImage: "moon.zzz")
            Label(ShareStatusText.permissionNote, systemImage: "wifi")
            Text(ShareStatusText.pathsNote)
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
        }
    }
}
