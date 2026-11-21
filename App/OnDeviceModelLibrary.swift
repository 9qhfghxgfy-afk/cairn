import Foundation
import CairnAppUI
import CairnChatDomain
import CairnInferenceLocal

/// The phone's own model library, behind the seam `CairnAppUI` reads.
///
/// This is the layer that is allowed to know Hugging Face exists. The view model asks for rows and gets
/// rows; the download half turns an event stream from `ModelDownloadManager` into `LocalTransferState`,
/// and nothing anywhere in this file returns a byte of model content — a download reports states and byte
/// counts, so a model file can never end up in a log or a UI string.
///
/// Every request made here goes to a public host, which is why the acknowledgement is read at the moment
/// a download starts rather than when this object is built: a switch turned off in Settings has to stop
/// the next download, not only the next app launch.
@MainActor
final class OnDeviceModelLibrary: LocalModelLibraryServicing {
    /// nil when this build has no place to keep models — no app group, an unreadable container. The
    /// screen then says so and offers nothing rather than starting a download that cannot land.
    // `internal`, not `private`: the download half of this type lives in
    // `OnDeviceModelLibrary+Download.swift`, and a `private` member is unreachable from an extension in
    // another file.
    let layout: ModelStoreLayout?
    let downloader: any ModelFileDownloading
    let traffic: ModelTrafficSwitch
    let fileManager: FileManager
    /// The optional Hub credential, or nil when this build wired no Keychain.
    ///
    /// Held as the domain's boundary rather than as a concrete store, and read only where a request is
    /// built. Nothing in this file hands a token to a view, a string, or a log line: the one place it is
    /// used is the `Authorization` header of a request to the host it was written for.
    let tokens: (any ModelTokenStoring)?

    init(
        layout: ModelStoreLayout?,
        downloader: any ModelFileDownloading,
        traffic: ModelTrafficSwitch,
        fileManager: FileManager = .default,
        tokens: (any ModelTokenStoring)? = nil
    ) {
        self.layout = layout
        self.downloader = downloader
        self.traffic = traffic
        self.fileManager = fileManager
        self.tokens = tokens
    }

    /// Builds the real one, or nil-shaped service when the store's root cannot be reached.
    ///
    /// The credential is handed over as a reader rather than as a value, because the question "may this
    /// request be authenticated" has to be answered when the request is built: a token pasted in Settings
    /// an hour into a download has to reach the next file, and a token taken back off has to stop reaching
    /// it. A value copied here at launch would do neither, and a person who deleted their credential would
    /// watch Cairn go on using it until the next relaunch.
    static func installed(
        traffic: ModelTrafficSwitch,
        tokens: (any ModelTokenStoring)? = nil
    ) -> OnDeviceModelLibrary {
        OnDeviceModelLibrary(
            layout: ModelStoreLayout.defaultRoot(),
            downloader: URLSessionModelDownloader(credential: { tokens?.token(for: .huggingFace) }),
            traffic: traffic,
            tokens: tokens
        )
    }

    /// The curated list with the installed answer settled against what is on disk.
    ///
    /// The marks come from the store rather than from a guess by name: a curated entry whose files are not
    /// there is shown as downloadable even though the repository is famous, and a half-downloaded model
    /// with no manifest is shown as not installed, because it cannot be loaded.
    func catalogRows() async throws -> [LocalCatalogRow] {
        let held = try await installedRows()
        let ids = Set(held.map(\.repoID))
        var bytes: [String: Int64] = [:]
        for row in held where row.sizeBytes > 0 { bytes[row.repoID] = row.sizeBytes }
        return ModelCatalog.onDevice.map { row in
            row.marking(installed: ids.contains(row.repoID), bytes: bytes[row.repoID])
        }
    }

    /// What this phone holds, read from the per-repository manifests.
    ///
    /// A directory with no `cairn-install.json` is skipped rather than listed: the manifest is written last
    /// precisely so that a partial download is never reported as installed. The display name comes from the
    /// curated entry when one exists, and from the repository id when it does not — nobody invents a
    /// friendlier name for something Cairn knows nothing about.
    func installedRows() async throws -> [InstalledLocalModel] {
        guard let layout else { throw CairnLibraryError.noStorage }
        var found: [InstalledLocalModel] = []
        for directory in layout.modelDirectories(fileManager: fileManager) {
            let manifestURL = directory
                .appendingPathComponent("cairn-install.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = InstalledModelManifest.decode(data) else { continue }
            let curated = ModelCatalog.onDevice.first { $0.repoID == manifest.repoID }
            found.append(
                InstalledLocalModel(
                    repoID: manifest.repoID,
                    displayName: curated?.displayName ?? manifest.repoID,
                    sizeBytes: manifest.totalBytes,
                    fileCount: manifest.files.count,
                    installedOn: manifest.installedAt,
                    canDelete: true,
                    // Read from the file names the manifest recorded, which is what this phone was given —
                    // not from the repository's name, which is what a publisher chose. A folder holding
                    // neither a `.gguf` nor a `.safetensors` is not a runtime Cairn can name, and saying so
                    // is better than guessing from a family name.
                    format: ModelFormat.detect(fileNames: manifest.files.map(\.name)) ?? .other
                )
            )
        }
        return found.sorted { $0.installedOn > $1.installedOn }
    }

    func delete(_ model: InstalledLocalModel) async throws {
        guard let layout else { throw CairnLibraryError.noStorage }
        // The folder is removed first, so a failed removal leaves the resume blocks in place for a retry.
        // They are then cleared with it: a delete that left them behind would keep part of a model the
        // person has just thrown away, and the next download of that repository would resume from bytes
        // whose verification record was deleted along with the manifest.
        try layout.remove(model.repoID, fileManager: fileManager)
        ModelResumeStore.forStore(layout).clearAll(repoID: model.repoID)
    }

    /// The published file list for one repository is fetched in `OnDeviceModelLibrary+Listing.swift`,
    /// which is also the only place a Hub credential is attached to a request that is not a file transfer.
}

/// The reasons this library refuses, in words a person can act on. No response body and no URL beyond the
/// status code: a repository's error page can contain anything, and none of it belongs in a UI string.
enum CairnLibraryError: LocalizedError, Equatable {
    case noStorage
    case badRepository
    case listingRefused(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noStorage: return "Cairn cannot reach its model storage."
        case .badRepository: return "That is not a valid repository name."
        case .listingRefused(let status):
            return "The repository would not list its files (status \(status))."
        case .cancelled: return "The download was cancelled."
        }
    }
}
