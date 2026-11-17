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
    public private(set) var detail: ModelDetail?
    public private(set) var pullProgress: ModelPullProgress?
    public private(set) var isWorking = false
    public var notice: String?

    /// True while a download is in flight, which is what the Stop button reads.
    public var isDownloading: Bool { pullTask != nil }

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
    }

    public func inspect(_ modelID: String) async {
        guard let profile else { return }
        do {
            detail = try await lifecycle.detail(model: modelID, profile: profile)
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
