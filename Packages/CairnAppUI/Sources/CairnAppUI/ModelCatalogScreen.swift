import SwiftUI
import CairnChatDomain

/// The Download tab: a curated library, a bar that narrows it, and one card per model.
///
/// The list is not a search box with a placeholder apology. Cairn ships the names it has checked — sizes
/// a publisher states, capabilities a config file or a library tag actually claims — so a person can
/// decide from the screen instead of guessing a repository name from memory. A typed name is still
/// offered, as its own card, when the library does not carry it.
///
/// The destination control sits above the filters rather than beside the Download button because it
/// changes what every card means: the same list under "This phone" is a storage decision and under "This
/// server" it is a request to someone else's machine.
public struct ModelCatalogScreen: View {
    private var model: ModelCatalogModel

    public init(model: ModelCatalogModel) { self.model = model }

    /// Sections, not a `List`: this view is dropped into `ModelManagerView`'s own list as the Download
    /// tab, and a list inside a list draws as a broken inset. The presentation and the two tasks hang off
    /// the group, which is legal — a sheet attaches to the view hierarchy above the list either way.
    public var body: some View {
        Group {
            if let notice = model.notice {
                ServersNoticeBanner(text: notice)
            }
            destinationSection
            filterSection
            cardSection
        }
        .sheet(item: Binding(
            get: { model.focused },
            set: { model.focused = $0 }
        )) { row in
            ModelDetailSheet(model: model, row: row)
        }
        .task { await model.refresh() }
        // Re-reads the server's names the moment its pull stops reporting. A timer would be the
        // alternative, and it sends requests nobody asked for.
        .task(id: model.serverPullKey) { await model.settleServerPull() }
    }

    private var destinationSection: some View {
        Section {
            // The switcher names the two libraries, not two destinations. Where the bytes land is the
            // footer's job; what a person is choosing here is whose names they get to pick from.
            Picker("Source", selection: Binding(
                get: { model.destination },
                set: { chosen in Task { await model.choose(chosen) } }
            )) {
                Text(ModelCatalogOrigin.onDevice.sourceLabel).tag(ModelCatalogOrigin.onDevice)
                Text(ModelCatalogOrigin.ollamaLibrary.sourceLabel).tag(ModelCatalogOrigin.ollamaLibrary)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cairn.catalog.source")
            if !model.offersPhone {
                Text("Cairn cannot reach its model storage on this phone, so nothing can be installed here yet.")
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else if model.needsAnotherServer {
                Text(model.serverGuidance)
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            } else if model.destination == .ollamaLibrary && !model.offersServer {
                Text(model.servers?.guidance ?? "Choose a server first.")
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
        } header: {
            Text("Source")
        } footer: {
            Text(model.sourceBlurb + " " + model.destination.destinationText)
        }
    }

    private var filterSection: some View {
        Section {
            TextField("Search names, publishers, series", text: Binding(
                get: { model.filter.search },
                set: { model.filter.search = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("cairn.catalog.search")
            ModelCatalogChipBar(model: model)
            sortMenu
        } header: {
            Text("Library")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: Binding(
                get: { model.filter.sort },
                set: { chosen in model.filter.sort = chosen }
            )) {
                ForEach(LocalSortOrder.downloadOrders) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Label("Sort: \(model.filter.sort.label)", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("cairn.catalog.sort")
    }

    @ViewBuilder private var cardSection: some View {
        let shown = model.visibleRows
        if shown.isEmpty {
            Section {
                if model.filter.isNarrowed {
                    Button("Clear the filters") { model.filter.clearNarrowing() }
                } else {
                    Text("This library is empty for this destination.")
                        .font(.callout)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
            } footer: {
                Text("The chips narrow the list; they never widen it. A name the library does not carry "
                        + "appears as its own card once it is typed.")
            }
        } else {
            Section {
                ForEach(shown) { row in
                    ModelCatalogCard(model: model, row: row)
                        .contentShape(Rectangle())
                        .onTapGesture { model.focused = row }
                }
            } footer: {
                Text("Sizes and capabilities are what the publisher states for these exact files. An "
                        + "entry that states nothing shows nothing rather than a guess.")
            }
        }
    }
}
