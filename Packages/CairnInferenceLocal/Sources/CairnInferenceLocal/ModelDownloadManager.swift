import Foundation

/// The end state of one install attempt. A pause is its own case because it is not a failure and
/// must not be shown as one: the bytes already fetched are kept, and the user can resume.
public enum ModelInstallOutcome: Sendable, Equatable {
    case installed(totalBytes: Int64)
    case paused(at: String)
    case failed(ModelDownloadFailure)
}

/// Downloads a model, verifies it, and records what landed.
///
/// The order is deliberate. Opt-in is checked before any request leaves the device. Every file is
/// hashed against the published digest before it counts as installed, because a resumed download is
/// only the same file if the bytes agree. The manifest is written last, so a half-installed model is
/// never listed as installed.
public actor ModelDownloadManager {
    private let downloader: any ModelFileDownloading
    private let layout: ModelStoreLayout
    private let resumeStore: ModelResumeStore
    private let gate: OutboundGate
    private let fileManager: FileManager

    public init(
        downloader: any ModelFileDownloading,
        layout: ModelStoreLayout,
        resumeStore: ModelResumeStore? = nil,
        gate: OutboundGate,
        fileManager: FileManager = .default
    ) {
        self.downloader = downloader
        self.layout = layout
        self.resumeStore = resumeStore ?? ModelResumeStore.forStore(layout)
        self.gate = gate
        self.fileManager = fileManager
    }

    public func install(
        repoID: String,
        listing: [ModelFileListing],
        onEvent: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async -> ModelInstallOutcome {
        do {
            try gate.assertAllowsDownload()
        } catch {
            return .failed(.outboundNotOptedIn)
        }
        guard HuggingFaceRepoID.isValid(repoID) else { return .failed(.invalidRepoID) }

        let plan = ModelFilePlan.select(from: listing, repoID: repoID)
        guard !plan.isEmpty else { return .failed(.noFilesListed) }
        do {
            try layout.install(repoID, fileManager: fileManager)
        } catch {
            return .failed(.noStorage)
        }
        onEvent(.planned(fileCount: plan.count, totalBytes: ModelFilePlan.totalBytes(of: plan)))

        var installed: [InstalledModelFile] = []
        var landedBytes: Int64 = 0

        for file in plan {
            let result = await fetch(file, repoID: repoID, onEvent: onEvent)
            switch result {
            case .paused(let name):
                return .paused(at: name)
            case .failed(let failure):
                return .failed(failure)
            case .verified(let record):
                installed.append(record)
                let (next, _) = landedBytes.addingReportingOverflow(record.bytes)
                landedBytes = next
            }
        }

        let manifest = InstalledModelManifest(repoID: repoID, installedAt: Date(), files: installed)
        guard write(manifest, repoID: repoID) else { return .failed(.noStorage) }
        resumeStore.clearAll(repoID: repoID)
        onEvent(.completed(totalBytes: landedBytes))
        return .installed(totalBytes: landedBytes)
    }

    public func uninstall(repoID: String) {
        resumeStore.clearAll(repoID: repoID)
        try? layout.remove(repoID, fileManager: fileManager)
    }

    public func manifest(repoID: String) -> InstalledModelManifest? {
        let url = layout.directory(for: repoID).appendingPathComponent("cairn-install.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return InstalledModelManifest.decode(data)
    }

    private enum FileResult: Sendable, Equatable {
        case verified(InstalledModelFile)
        case paused(name: String)
        case failed(ModelDownloadFailure)
    }

    private func fetch(
        _ file: ModelFileDescriptor,
        repoID: String,
        onEvent: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async -> FileResult {
        onEvent(.fileStarted(name: file.name))
        let destination = layout.directory(for: repoID).appendingPathComponent(file.name)

        let progress: @Sendable (DownloadProgressUpdate) -> Void = { update in
            onEvent(.fileProgress(name: file.name, update: update))
        }
        let outcome: ModelDownloadOutcome
        if let resumeData = resumeStore.load(repoID: repoID, file: file.name) {
            outcome = await downloader.resume(using: resumeData, to: destination, onProgress: progress)
        } else {
            outcome = await downloader.fetch(file, to: destination, onProgress: progress)
        }

        switch outcome {
        case .paused(let resumeData):
            if resumeData.isEmpty { resumeStore.clear(repoID: repoID, file: file.name) }
            else { resumeStore.save(resumeData, repoID: repoID, file: file.name) }
            onEvent(.paused(name: file.name))
            return .paused(name: file.name)

        case .failed:
            onEvent(.failed(message: ModelDownloadFailure.transferFailed.message))
            return .failed(.transferFailed)

        case .complete(let bytes):
            // A published digest must match. An unpublished one is recorded as unverified rather
            // than treated as a pass, so the Installed tab can say so.
            let published = (file.sha256?.isEmpty == false) ? file.sha256 : nil
            let verified = published.map { SHA256Digest.matches(expected: $0, fileAt: destination) } ?? false
            if published != nil, !verified {
                resumeStore.clear(repoID: repoID, file: file.name)
                onEvent(.failed(message: ModelDownloadFailure.verificationFailed.message))
                return .failed(.verificationFailed)
            }
            onEvent(.fileFinished(name: file.name, verified: verified))
            return .verified(InstalledModelFile(name: file.name, bytes: bytes, sha256: published))
        }
    }

    private func write(_ manifest: InstalledModelManifest, repoID: String) -> Bool {
        guard let data = manifest.encoded() else { return false }
        let target = layout.directory(for: repoID).appendingPathComponent(manifest.manifestFileName)
        do {
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

