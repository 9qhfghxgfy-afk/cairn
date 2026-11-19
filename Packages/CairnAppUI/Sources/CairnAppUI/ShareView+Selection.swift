import CairnChatDomain
import SwiftUI

/// The engine picker and the port, kept apart from the switch: what may be shared is a list that has to
/// empty out honestly when a profile is deleted, and that rule is worth keeping in one place.
///
/// `ShareEngineTable` is built at the moment sharing starts, so the served set cannot move while the port
/// is open. Rather than accept a tick that changes nothing, the section disables itself and says why.
extension ShareView {
    var selectionSection: some View {
        Section {
            portRow

            if model.offered.isEmpty {
                Text(ShareStatusText.noEnginesNote)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else {
                ForEach(model.offered) { engine in
                    Toggle(isOn: Binding(
                        get: { model.settings.sharedEngineIDs.contains(engine.id) },
                        set: { _ in model.toggleEngine(id: engine.id) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.displayName.isEmpty ? engine.id : engine.displayName)
                            Text(engine.id)
                                .font(.caption)
                                .foregroundStyle(CairnTheme.stoneLight)
                        }
                    }
                    .tint(CairnTheme.amber)
                }
            }
        } header: {
            Text("What is shared")
        } footer: {
            Text(
                "Only the engines ticked here are offered, and only under the names you ticked. A name with "
                    + "no engine behind it is refused, never invented. The set is chosen when sharing starts, "
                    + "so it cannot move under a client that is already talking to this phone."
            )
        }
        .disabled(!model.canEditSelection)
    }

    /// The port, bounded by the policy floor rather than by a text field: a number below 1024 is a
    /// system port, and a port that will not bind is reported by the surface as `portUnusable`.
    var portRow: some View {
        Stepper(value: Binding(
            get: { model.settings.port },
            set: { model.setPort($0) }
        ), in: SharePolicy.portFloor...65_535, step: 1) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Port").font(.subheadline)
                    Text("Ollama's usual port is 11434. Anything 1024 or above that nothing else is using.")
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer()
                Text("\(model.settings.port)")
                    .font(.system(.body, design: .monospaced))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
