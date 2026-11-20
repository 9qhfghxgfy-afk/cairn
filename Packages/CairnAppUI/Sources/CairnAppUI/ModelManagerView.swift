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
        .task {
            // Re-read on every appearance: the server's memory changes while the user is in the
            // chat, and a stale Running list is worse than no Running list.
            if let profile = model.profile { await model.open(profile) }
            // The Download tab's source is decided by the server that opened Models — On-Device opens
            // on Hugging Face, a remote server opens on Ollama. It has to happen after the profile is
            // open, or the catalog would read a profile that is not set yet and always guess On-Device.
            if let catalog { await catalog.openFrom(kind: model.profile?.kind) }
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
