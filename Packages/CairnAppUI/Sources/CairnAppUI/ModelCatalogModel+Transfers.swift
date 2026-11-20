import Foundation
import CairnChatDomain

/// The transfer half of the Download tab's view model: starting a pull, keeping its task, and settling
/// what a server reports back.
///
/// Split from the file that owns the state because the two halves answer different questions. The state
/// half is asked "what is on screen" — a list, a filter, a focused card. This half is asked "what is
/// moving, and what may move at all", and the answers involve an acknowledgement, a task the view model
/// has to hold so Cancel can reach it, and a server that only ever speaks in its own status lines.
extension ModelCatalogModel {
    /// The phone path: hand the row to the service and keep the task, so Cancel closes the connection
    /// rather than only the loop that reads it.
    func startPhoneDownload(_ row: LocalCatalogRow) {
        guard let library else {
            notice = "Cairn cannot reach its model storage on this phone."
            return
        }
        guard weightsAreAllowed else {
            notice = ModelCatalogModel.trafficNotice
            return
        }
        let entryID = row.repoID
        phoneStatus = ModelTransferStatus(entryID: entryID, state: .queued)
        let stream = library.download(row)
        task = Task { @MainActor [weak self] in
            do {
                for try await state in stream {
                    if Task.isCancelled { break }
                    self?.phoneStatus = ModelTransferStatus(entryID: entryID, state: state)
                }
                if Task.isCancelled {
                    self?.phoneStatus = ModelTransferStatus(entryID: entryID, state: .stopped)
                }
            } catch is CancellationError {
                self?.phoneStatus = ModelTransferStatus(entryID: entryID, state: .stopped)
            } catch {
                // The service's own words. "the file did not match its published checksum" and "the
                // download failed" send a person to different places, so neither is paraphrased.
                self?.phoneStatus = ModelTransferStatus(entryID: entryID, stage: .failed,
                                                        line: error.localizedDescription)
            }
            self?.task = nil
            await self?.refresh()
            self?.repoint()
        }
    }

    /// The server path, which is `ModelManagerModel`'s pull by another route. The catalogue names the
    /// exact tag and nothing here rewrites it: a tag the server never published is not a model this app
    /// can promise anything about.
    func startServerPull(_ row: LocalCatalogRow) {
        guard offersServer, let servers else {
            notice = servers?.guidance ?? "Choose a server first."
            return
        }
        pulledID = row.repoID
        servers.pull(row.repoID)
    }

    /// The card the sheet is open on is a value, so a finished download has to be looked up again in the
    /// re-read list. Without this the sheet keeps saying "not installed" about a model that just landed.
    func repoint() {
        guard let repoID = focused?.repoID else { return }
        focused = rows.first { $0.repoID == repoID } ?? focused
    }

    /// True while the server is still reporting this pull. `ModelManagerModel` clears its progress when
    /// the stream ends, which is the only signal Cairn gets that the server has finished.
    var serverPullIsInFlight: Bool { pulledID != nil && servers?.pullProgress != nil }

    /// Changes when the server's pull for the focused tag ends, so the screen can re-read the server's
    /// list the moment it changes. The alternative is a timer, and a timer asks a server questions nobody
    /// asked it to answer.
    var serverPullKey: String {
        guard let pulledID else { return "idle" }
        guard let progress = servers?.pullProgress else { return pulledID + "|done" }
        return pulledID + "|" + progress.statusText
    }

    /// Clears the in-flight mark and re-reads the server's names once its pull stops reporting, so the
    /// card can show the tag as the server now holds it.
    func settleServerPull() async {
        guard pulledID != nil, servers?.pullProgress == nil else { return }
        pulledID = nil
        await refresh()
        repoint()
    }
}
