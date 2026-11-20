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
            // The pause this transfer may just have left behind is exactly what this question is about, and
            // it has to be asked after the store has settled rather than before.
            await self?.refreshPartials()
            self?.repoint()
            // The phone now holds, or does not hold, a model the runtime can load. The Servers screen's
            // report is the App layer's to compute, so this is the nudge rather than the answer.
            self?.onTransferSettled?()
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

    /// The transfer state for one card, or nil when nothing is in flight for it.
    ///
    /// The server numbers are read from `ModelManagerModel` here rather than copied into this type: the
    /// server's own progress is its truth, and a second copy of it is a second thing to keep honest.
    public func status(for row: LocalCatalogRow) -> ModelTransferStatus? {
        if row.origin.landsOnThisPhone {
            guard let status = phoneStatus, status.entryID == row.id else { return nil }
            return status
        }
        guard pulledID == row.id, let progress = servers?.pullProgress else { return nil }
        return ModelTransferStatus(entryID: row.id, pull: progress)
    }

    // MARK: Consent

    public var weightsAreAllowed: Bool { traffic.isGranted() }
    public func allowWeights() { traffic.setGranted(true) }
    public func denyWeights() { traffic.setGranted(false) }

    /// Why the phone path refuses to start, in the sheet's and the notice's shared words. It names what
    /// has to be turned on rather than only refusing, because a button that does nothing and says nothing
    /// reads as a broken app.
    public static let trafficNotice = "Downloading a model sends bytes off this device. Turn on model "
        + "downloads, and Cairn will show the outbound badge while the weights are in flight."

    /// One tap that both grants the acknowledgement and starts the download the person was already
    /// asking for.
    ///
    /// Two taps for a decision already made is a trap: the first tap reads as "the app is broken" and
    /// the second is made without re-reading what it authorises. So the button says both halves in its
    /// own name, and the disclosure line above it names where the bytes go before it is pressed. The
    /// grant is written to Settings here, so the same switch a person can take back in Settings is the
    /// one this tap moves — it is not a second, weaker consent stored beside the download.
    public func allowAndDownload(_ row: LocalCatalogRow) {
        allowWeights()
        download(row)
    }

    // MARK: - Pause, resume, cancel

    /// Applies one of the three transfer verbs to whichever machine is doing the pulling.
    ///
    /// The sheet offers Pause, Resume and Cancel without knowing or caring whether this model is being
    /// fetched by the phone or by a server, because that difference belongs here. A phone pause closes a
    /// connection and keeps resume blocks; a server pause asks that server to stop its own task, which is the
    /// only thing Cairn can ask of a machine it does not own. Getting that wrong in a view would mean the same
    /// button meaning two different things depending on a tab, which is the sort of thing nobody notices until
    /// someone loses four gigabytes.
    public func control(_ action: ModelTransferControl, for row: LocalCatalogRow) async {
        switch action {
        case .pause:
            await pauseTransfer(row)
        case .cancel:
            await cancelTransfer(row)
        case .resume:
            // Resume is the start button under another name. The phone path picks up the bytes it kept from
            // the same offsets; the server path asks again, which is all there is to ask. A separate "resume"
            // operation would be a second path through the same code, and the second path is where a resume
            // that quietly restarts from zero would hide.
            download(row)
        }
    }

    /// Whether a row can be paused right now, and therefore whether the button may be drawn at all.
    public func canPause(_ row: LocalCatalogRow) -> Bool {
        guard let status = status(for: row), status.isInFlight else { return false }
        return row.origin.landsOnThisPhone ? library != nil : serverPullIsInFlight
    }

    /// Whether a row is holding kept bytes with nothing running — the state a Resume button stands for.
    public func canResume(_ row: LocalCatalogRow) -> Bool {
        !row.isInstalled && partialRows.contains(row.id)
    }

    private func pauseTransfer(_ row: LocalCatalogRow) async {
        guard canPause(row) else { return }
        if row.origin.landsOnThisPhone {
            guard let library else { return }
            // The line changes before the connection does. Closing a transfer takes a moment, and a bar that
            // keeps sliding for two seconds after a tap is read as a button that did not work, so the person
            // taps again. The manager's own `paused` state arrives with the real counts and replaces this.
            phoneStatus = ModelTransferStatus(entryID: row.id, stage: .paused, line: "Pausing")
            await library.pauseDownload(repoID: row.repoID)
        } else {
            // A server cannot be paused from here — Cairn has no such verb for a machine it does not own —
            // so the button that says Pause here stops the pull and the notice says exactly that. What the
            // server keeps on its own disk is the server's business, and promising a resume Cairn has no way
            // to ask for would be a nicer sentence and a worse app.
            servers?.stopPull()
            notice = "Stopped on the server. Download asks it again; whatever the server kept is its own to "
                + "reuse."
        }
    }

    private func cancelTransfer(_ row: LocalCatalogRow) async {
        if row.origin.landsOnThisPhone {
            guard let library else { return }
            // The reader goes first, then the transfer, then the bytes. In any other order a progress line can
            // land after the row has been told it is over, which is how a cancelled download ends up on screen
            // with a bar still moving under the word "Cancelled".
            if phoneStatus?.entryID == row.id {
                task?.cancel()
                task = nil
            }
            phoneStatus = ModelTransferStatus(entryID: row.id, state: .stopped)
            notice = "Cancelled. Cairn throws away the part it had fetched."
            do {
                try await library.cancelDownload(repoID: row.repoID)
            } catch {
                // The service's own words, again: refusing to delete and failing to delete are different
                // problems, and a person who is told "cancelled" when nothing was freed goes on believing the
                // space is gone.
                notice = error.localizedDescription
            }
            await refresh()
            onTransferSettled?()
        } else {
            // The existing Cancel is the one that knows how a server pull is torn down — it holds the task,
            // the identifier and the notice, and it is already tested. A second teardown written here would
            // be a second answer to "what does Cancel mean", and the two would drift.
            cancel()
            notice = "Cancelled on the server. Cairn does not delete anything on that machine."
        }
    }
}
