import Foundation

/// The end state of one install attempt. A pause is its own case because it is not a failure and
/// must not be shown as one: the bytes already fetched are kept, and the user can resume.
///
/// `.cancelled` is neither. The person gave the transfer up, so nothing is kept and there is nothing to
/// report about a download that stopped for a reason they chose. Showing it as a failure would offer a
/// message about a problem nobody had.
public enum ModelInstallOutcome: Sendable, Equatable {
    case installed(totalBytes: Int64)
    case paused(at: String)
    case cancelled(at: String)
    case failed(ModelDownloadFailure)
}

/// Downloads a model, verifies it, and records what landed.
///
/// The order is deliberate. Opt-in is checked before any request leaves the device. Every file is
/// hashed against the published digest before it counts as installed, because a resumed download is
/// only the same file if the bytes agree. The manifest is written last, so a half-installed model is
/// never listed as installed.
public actor ModelDownloadManager {
    // `internal`, not `private`: the per-file half of this actor lives in
    // `ModelDownloadManager+Files.swift`, and a `private` member is unreachable from an extension in
    // another file. Nothing outside this module can see them either way.
    let downloader: any ModelFileDownloading
    let layout: ModelStoreLayout
    let resumeStore: ModelResumeStore
    let gate: OutboundGate
    let fileManager: FileManager

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
            case .cancelled(let name):
                return .cancelled(at: name)
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

    /// Stops one repository's transfer, right now, and reports how many files were in flight to stop.
    ///
    /// This decides nothing about the bytes. A pause keeps them and the resume blocks that make a resume
    /// possible; a cancel leaves them to `discardPartial`, which is the only code here that knows a directory
    /// with a manifest in it is an installed model rather than debris. A stop that also deleted would be a
    /// stop a caller would be afraid to offer, which is how Cancel buttons end up missing from screens that
    /// pull several gigabytes.
    public func stopTransfers(repoID: String, pause: Bool) -> Int {
        downloader.stopTransfers(in: layout.directory(for: repoID), pause: pause)
    }

    /// Throws away what a cancelled transfer left behind: the resume blocks, and any file that landed
    /// before the cancel.
    ///
    /// A pause keeps both — that is the whole point of a pause — so this runs only on the way a person
    /// asked to give the transfer up. Left alone, the blocks are the worse half: the next download of that
    /// repository would pick up from bytes whose verification record has been forgotten, and a checksum
    /// mismatch at the end of four gigabytes is a download that has to start over anyway.
    ///
    /// The manifest is the gate, not the directory. A repository with a manifest is installed and the
    /// runtime can load it, so its files are nobody's cancelled transfer, whatever else is next to them.
    public func discardPartial(repoID: String) {
        resumeStore.clearAll(repoID: repoID)
        guard manifest(repoID: repoID) == nil else { return }
        try? layout.remove(repoID, fileManager: fileManager)
    }

    public func manifest(repoID: String) -> InstalledModelManifest? {
        let url = layout.directory(for: repoID).appendingPathComponent("cairn-install.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return InstalledModelManifest.decode(data)
    }

    /// The per-file half — fetch or resume, then weigh the bytes against the published digest — is in
    /// `ModelDownloadManager+Files.swift`. It is a separate file because it answers a different question
    /// from this one: this file asks what it takes to call a repository installed, and that file asks what
    /// happens to one file that stopped halfway through.

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

