import Foundation
import CairnChatDomain

// The LAN scan, kept out of ServersModel.swift so that file stays about profiles and engines.
//
// A scan is something the user asks for, in this build and in the next one. It never runs at
// launch, it never runs on a timer, and it stops the moment the user says so. What it finds is a
// draft: the profile, the engine registration, and any credential write happen only on the
// explicit Add tap.
extension ServersModel {

    /// Starts a sweep of the /24 this device is attached to. Refuses to overlap itself, and refuses
    /// to run at all when no scanner is wired — which is also the shape a host test sees.
    func scanLocalNetwork() {
        guard let discovering, !isScanning else { return }
        isScanning = true
        discovered = []
        scanHint = nil
        scanProgress = LANDiscoveryProgress(hostsDone: 0, hostsTotal: 0)
        scanTask = Task {
            let report = await discovering.discover { progress in
                self.scanProgress = progress
            }
            self.discovered = report.servers
            // The domain owns what an empty scan means — including the Local Network permission,
            // whose denial looks exactly like every port being closed.
            self.scanHint = report.localNetworkHint
            self.isScanning = false
            self.scanTask = nil
        }
    }

    /// Stops a scan the user no longer wants. Cancelling the task is enough: the scanner checks for
    /// cancellation between waves, and nothing is saved on the way out.
    func stopLocalNetworkScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanHint = "Stopped. Nothing was saved."
    }

    /// A finding as the draft it should become: the kind it answered as, its address, switched on,
    /// and with no token — a discovered server has none, and a key is always typed by the user.
    func draft(for server: DiscoveredServer) -> ServerProfile {
        server.draftProfile()
    }

    /// Saves a finding through the ordinary save path: canonicalise, validate, register the engine,
    /// reload. There is no second save path for scan results, so they cannot skip validation.
    func saveDiscovery(_ server: DiscoveredServer) {
        save(server.draftProfile(), token: nil)
    }

    /// Clears the findings from the screen and touches nothing else: saved servers, engines, and
    /// the Keychain stay as they were, because a scan never wrote to any of them.
    func clearDiscovery() {
        discovered = []
        scanHint = nil
        scanProgress = nil
    }
}
