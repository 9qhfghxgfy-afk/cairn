import SwiftUI

/// The first-use question: may this device say where it is?
///
/// `get_location` runs inside a turn, on a background actor, with no window. The app layer hands the tool a
/// closure and this is what that closure puts in front of a person. What the sheet says is deliberately
/// narrow — the one thing being read, and where it can end up — because a permission whose consequence is
/// invisible is a formality.
///
/// The honest part is the second section. Cairn never sends a position to a location service and never
/// reverse-geocodes, but the position *does* join the conversation, and a conversation may be answered by a
/// server the user chose. A sheet that promised "stays on the device" while the chat's transcript is going
/// to a remote model would be lying in exactly the place a person is deciding whether to trust it.
struct LocationConsentSheet: View {
    let model: LocationConsentModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cairn is about to read where this device is.")
                            .font(.headline)
                        Text(
                            "One position, taken now: latitude and longitude, and the accuracy in metres "
                                + "the hardware reports. Nothing is looked up from them."
                        )
                        .font(.callout)
                        Text(
                            "Cairn has no location service and no map provider. There is no reverse "
                                + "geocoding here, so a coordinate is never turned into a street or a city."
                        )
                        .font(.footnote)
                        .foregroundStyle(CairnTheme.stoneLight)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("My location")
                }

                Section("What this does not do") {
                    Label(
                        "One reading for this turn. Cairn does not track you and asks for no background "
                            + "location.",
                        systemImage: "location.slash"
                    )
                    Label(
                        "Nothing is sent to a map or geocoding service, and the position is not stored "
                            + "separately.",
                        systemImage: "lock.shield"
                    )
                }

                Section("Where the numbers can go") {
                    Label(
                        "The position becomes part of this conversation, like anything you type.",
                        systemImage: "text.bubble"
                    )
                    Text(
                        "If this chat is answered by a server rather than by a model on this device, that "
                            + "text travels with the request. Say no and the tool answers that it was "
                            + "refused; the model is told that rather than given a guess."
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }

                Section {
                    Button(action: allow) {
                        Text("Allow it once for this session").fontWeight(.semibold)
                    }
                    .tint(CairnTheme.amber)

                    Button(role: .destructive, action: deny) {
                        Text("Don't allow it")
                    }
                } footer: {
                    Text(
                        "iOS asks its own permission separately, and you can take it away in the Settings "
                            + "app. The tool's own switch is under Tools, per chat."
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
            }
            .navigationTitle("Allow location?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { deny() }
                }
            }
            .cairnPresentation()
        }
        // Closing without choosing is a refusal, recorded as one. A dismissed warning that left the question
        // undecided would bring the sheet back next turn, which teaches a person that warnings can be
        // swiped away.
        .interactiveDismissDisabled()
    }

    private func allow() {
        model.resolve(allow: true)
        dismiss()
    }

    private func deny() {
        model.resolve(allow: false)
        dismiss()
    }
}
