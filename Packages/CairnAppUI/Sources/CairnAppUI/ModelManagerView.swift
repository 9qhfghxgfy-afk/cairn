import SwiftUI
import CairnChatDomain

/// The Model Manager: what a server is holding right now, what it has installed, and a download
/// that can be stopped mid-flight.
///
/// Three tabs because those are three different facts, and mixing them is how a screen ends up
/// showing "0 models" for a server whose list simply failed to load. Each tab states its own
/// empty condition instead of rendering a blank row.
public struct ModelManagerView: View {
    private var model: ModelManagerModel
    /// The curated library for the Download tab. With none, that tab falls back to the typed-name form,
    /// which is the shape this screen had before the library existed.
    private var catalog: ModelCatalogModel?
    @State private var tab: ModelManagerTab = .running

    public init(model: ModelManagerModel, catalog: ModelCatalogModel? = nil) {
        self.model = model
        self.catalog = catalog
    }

    public var body: some View {
        List {
            if let notice = model.notice {
                ServersNoticeBanner(text: notice)
            }
            if !model.offersLifecycle {
                Text(model.guidance)
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            switch tab {
            case .running: ModelRunningList(model: model)
            case .installed: ModelInstalledList(model: model)
            case .download:
                if let catalog {
                    ModelCatalogScreen(model: catalog)
                } else {
                    ModelDownloadForm(model: model)
                }
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(ModelManagerTab.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        // Keyed to the profile rather than to appearance alone: a server chosen after this screen appears has
        // to re-read every tab, and with no profile the device's own sources are still read. `.task` without an
        // `id:` fires once per appearance, which would leave the merged Installed list showing one server's
        // answer after the person had moved to another one.
        .task(id: model.profile?.id) {
            // Re-read on every appearance: the server's memory changes while the person is in the chat, and
            // a stale Running list is worse than no Running list.
            //
            // With no profile open, the Installed tab is still not allowed to read empty. A phone opened from
            // the On-Device entry has no server at all, and its folders are the whole answer there — so the
            // device's own sources are read on their own, which is the gap this tab used to fall into.
            if let profile = model.profile {
                await model.open(profile)
            } else {
                await model.refreshInstalledEntries()
            }
            // The Download tab's source is decided by the server that opened Models — On-Device opens
            // on Hugging Face, a remote server opens on Ollama. It has to happen after the profile is
            // open, or the catalog would read a profile that is not set yet and always guess On-Device.
            if let catalog { await catalog.openFrom(kind: model.profile?.kind) }
        }
        // The detail sheet is hosted here, on the list itself, and not inside the Download tab's content.
        //
        // A presentation is carried by the view it is attached to. Attached inside a list's content — as
        // it was, on the `Group` the Download tab builds — it is a content node, so anything that makes
        // the list re-diff its own structure recycles the node that was carrying the sheet, and the sheet
        // is dismissed by the app rather than by the person. The Download tab's content changes shape on
        // its own: a notice appears, the rows arrive, a transfer starts and a card gains a progress line.
        // Tapping "Allow & Download" did all of that at once, and the stack of sheets underneath it
        // collapsed to the chat.
        //
        // Attached to the list container instead, the host has a stable identity: rows come and go inside
        // it, and the presentation survives.
        .sheet(item: focusedDetail) { row in
            ModelDetailPresentation(catalog: catalog, row: row)
        }
    }

    /// The Download tab's focused card, reached through the optional catalogue so this view can be built
    /// with no library wired at all. With no catalogue the binding is always nil, so nothing is presented.
    ///
    /// `focused` is a settable property on the catalogue precisely so that a sheet can close itself; the
    /// binding ends there and does not touch a transfer, which the catalogue keeps running.
    private var focusedDetail: Binding<LocalCatalogRow?> {
        Binding(
            get: { catalog?.focused },
            set: { catalog?.focused = $0 }
        )
    }
}

/// The sheet a Download card opens, drawn by the Models list rather than by the card's own row.
///
/// The catalogue is optional because this screen can be built with no curated library at all, in which
/// case the Download tab is the typed-name form and nothing can be focused. The optional lives here rather
/// than in the `.sheet` closure because a sheet's content has to be one view, and a conditional branch
/// inside a sheet's own content is the kind of thing that renders as a blank panel if the unwrap fails.
/// It cannot fail here: the focused card is a property of the catalogue, so no catalogue means no focus
/// means no presentation.
private struct ModelDetailPresentation: View {
    private var catalog: ModelCatalogModel?
    let row: LocalCatalogRow

    /// Declared, not memberwise: a `private` struct's implicit memberwise initialiser is itself `private`,
    /// which a different type in this file cannot call. `ModelRunningList` below writes its init the same
    /// way for the same reason.
    init(catalog: ModelCatalogModel?, row: LocalCatalogRow) {
        self.catalog = catalog
        self.row = row
    }

    var body: some View {
        if let catalog {
            ModelDetailSheet(model: catalog, row: row)
        }
    }
}

enum ModelManagerTab: String, CaseIterable, Identifiable {
    case running
    case installed
    case download

    var id: String { rawValue }
    var title: String {
        switch self {
        case .running: return "Running"
        case .installed: return "Installed"
        case .download: return "Download"
        }
    }
}

/// The Running tab: models the server itself says are in memory, with the sizes it reported.
private struct ModelRunningList: View {
    private var model: ModelManagerModel

    init(model: ModelManagerModel) { self.model = model }

    var body: some View {
        if model.running.isEmpty {
            Section {
                Text("Nothing is loaded right now.")
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            } footer: {
                Text("A server loads a model when it is first used and may release it on its own after a while.")
            }
        } else {
            Section {
                ForEach(model.running) { entry in
                    ModelRunningRow(model: model, entry: entry)
                }
            }
        }
    }
}
