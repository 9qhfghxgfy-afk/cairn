import Foundation
import Observation
import CairnChatDomain

/// View model behind the Model Manager: what a server holds in memory, what it has installed, and
/// a download that can be stopped.
///
/// CairnAppUI imports neither URLSession nor SwiftData. Everything here crosses a domain
/// boundary: `RemoteModelManaging` for the installed list, and `ModelLifecycleManaging` for
/// running, detail, load, unload and the streamed download. The App layer injects the real
/// implementations.
@Observable @MainActor
public final class ModelManagerModel {
    public private(set) var profile: ServerProfile?
    public private(set) var running: [ResidentServerModel] = []
    public private(set) var installed: [ModelInfo] = []
    /// Every model the Installed tab shows: this phone's folders, the model iOS built in, and the models
    /// the open server reports — each row labelled with the host that owns it.
    ///
    /// This is separate from `installed` rather than replacing it because the two lists answer different
    /// questions. `installed` is one server's own answer and is what a server-side detail request folds
    /// onto; this is what a person has, and it survives a server that will not answer.
    public private(set) var installedEntries: [InstalledModelEntry] = []
    public private(set) var detail: ModelDetail?
    public private(set) var pullProgress: ModelPullProgress?
    public private(set) var isWorking = false
    public var notice: String?

    /// True while a download is in flight, which is what the Stop button reads.
    public var isDownloading: Bool { pullTask != nil }

    /// The phone's own model store and the system model, injected by the App layer.
    ///
    /// `CairnAppUI` may look at neither a filesystem nor a runtime, so a build with no store wired shows
    /// the server's half only — and says so, rather than reporting that a phone with four models on disk
    /// has none.
    public var installedServing: (any InstalledModelServing)?
    /// Tells the App layer that a model this phone holds has been taken back, so the on-device engine
    /// report and the Download list are re-read instead of waiting for the next download or the next
    /// launch. Awaited, so the Installed list redraws only after those have settled, and given the removed
    /// entry so the App can name the repository rather than guess which row just disappeared.
    public var onLocalModelRemoved: (@MainActor (InstalledModelEntry) async -> Void)?

    private let managing: any RemoteModelManaging
    private let lifecycle: any ModelLifecycleManaging
    private var pullTask: Task<Void, Never>?

    public init(managing: any RemoteModelManaging, lifecycle: any ModelLifecycleManaging) {
        self.managing = managing
        self.lifecycle = lifecycle
    }

    /// What to tell the user about this server before they look for buttons that are not there.
    public var guidance: String {
        guard let profile else { return "Choose a server first." }
        return lifecycle.guidance(profile)
    }

    public var offersLifecycle: Bool {
        guard let profile else { return false }
        return lifecycle.supportsLifecycle(profile)
    }

    public func open(_ profile: ServerProfile) async {
        self.profile = profile
        notice = nil
        isWorking = true
        defer { isWorking = false }
        do {
            installed = try await managing.listModels(profile)
        } catch {
            installed = []
            notice = error.localizedDescription
        }
        do {
            running = try await lifecycle.runningModels(profile)
        } catch let issue as ModelLifecycleError {
            running = []
            notice = issue.message
        } catch {
            running = []
            notice = error.localizedDescription
        }
        // Last, and outside both `do` blocks above: what this phone holds does not depend on whether this
        // server answers, so a refusal must leave the phone's rows on screen rather than emptying the tab.
        await refreshInstalledEntries()
    }

    public func inspect(_ modelID: String) async {
        guard let profile else { return }
        do {
            detail = try await lifecycle.detail(model: modelID, profile: profile)
            // The published capability flags the detail endpoint names — including tools — fold onto
            // the installed row, so the list itself says what the server said rather than what a model
            // name sounds like it should support.
            if let detail {
                installed = installed.map { detail.applied(to: $0) }
            }
        } catch let issue as ModelLifecycleError {
            detail = nil
            notice = issue.message
        } catch {
            detail = nil
            notice = error.localizedDescription
        }
    }

    public func load(_ modelID: String) async {
        guard let profile else { return }
        await run { try await self.lifecycle.loadModel(model: modelID, profile: profile) }
        await refreshRunning()
    }

    public func unload(_ modelID: String) async {
        guard let profile else { return }
        await run { try await self.lifecycle.unload(model: modelID, profile: profile) }
        await refreshRunning()
    }

    /// Starts a download and keeps the stream, so Stop can end it. Cancelling this task is what
    /// closes the connection — stopping the UI loop would not.
    public func pull(_ modelName: String) {
        guard let profile else { return }
        pullTask?.cancel()
        notice = nil
        pullProgress = ModelPullProgress(modelName: modelName, statusText: "starting")
        let stream = lifecycle.pull(model: modelName, profile: profile)
        pullTask = Task { @MainActor in
            do {
                for try await progress in stream {
                    if Task.isCancelled { break }
                    self.pullProgress = progress
                }
                self.pullProgress = nil
                await self.refreshInstalled()
            } catch is CancellationError {
                self.pullProgress = nil
            } catch let issue as ModelLifecycleError {
                self.pullProgress = nil
                self.notice = issue.message
            } catch {
                self.pullProgress = nil
                self.notice = error.localizedDescription
            }
            self.pullTask = nil
        }
    }

    public func stopPull() {
        pullTask?.cancel()
        pullTask = nil
        pullProgress = nil
    }

    public func refreshRunning() async {
        guard let profile else { return }
        do {
            running = try await lifecycle.runningModels(profile)
        } catch {
            // A server that will not answer about memory is shown as it was, not as empty: an
            // empty Running tab would claim nothing is loaded.
        }
    }

    public func refreshInstalled() async {
        guard let profile else { return }
        do {
            installed = try await managing.listModels(profile)
        } catch {
            notice = error.localizedDescription
        }
        // Outside the `do`: the server's answer failing is not evidence about this phone's folders, and the
        // Installed tab must keep showing them.
        await refreshInstalledEntries()
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch let issue as ModelLifecycleError {
            notice = issue.message
        } catch {
            notice = error.localizedDescription
        }
    }
}
