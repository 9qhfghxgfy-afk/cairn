import Foundation
import Testing
@testable import CairnInferenceLocal

/// What a broken transfer tells the person, chosen from the network code rather than from one flat sentence.
///
/// A stalled socket, a dropped route, a host that will not answer and a phone out of room are four different
/// problems with four different fixes. Before this rule existed all four arrived as "the download failed", which
/// is why a phone with no Wi-Fi got blamed for a stalled connection and a full disk got a Retry pressed at it
/// eleven times.
struct NetworkFaultTests {
    private func error(_ code: Int) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code, userInfo: nil)
    }

    @Test func stalledSocketPointsAtTheButtonThatCarriesOn() {
        let line = NetworkFault.message(for: error(NSURLErrorTimedOut))
        #expect(line.contains("\(NSURLErrorTimedOut)"))
        #expect(line.contains("Resume"))
    }

    @Test func separatesADroppedRouteFromADeadHost() {
        let dropped = NetworkFault.message(for: error(NSURLErrorNotConnectedToInternet))
        let unreachable = NetworkFault.message(for: error(NSURLErrorCannotConnectToHost))
        #expect(dropped != unreachable)
        #expect(dropped.contains("\(NSURLErrorNotConnectedToInternet)"))
        #expect(unreachable.contains("\(NSURLErrorCannotConnectToHost)"))
        // A dropped route keeps its bytes; a host that never answered has nothing to keep.
        #expect(dropped.contains("Resume"))
        #expect(!unreachable.contains("Resume"))
    }

    /// A full disk is not a network problem, and a message about the network sends a person to the router
    /// instead of to Settings.
    @Test func callsAFullDiskAStorageProblem() {
        let line = NetworkFault.message(
            for: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: nil)
        )
        #expect(line.contains("room"))
        #expect(line.contains("storage error"))
        #expect(!line.contains("network error"))
    }

    /// The certificate family is matched as a band of numbers, so every member of it has to land on the same
    /// sentence — and a code just outside it must not.
    @Test func givesTheWholeCertificateBandOneSentence() {
        for code in NetworkFault.certificateBand {
            let line = NetworkFault.message(for: error(code))
            #expect(line.contains("could not be verified"))
            #expect(line.contains("\(code)"))
        }
        #expect(!NetworkFault.message(for: error(-1001)).contains("could not be verified"))
        #expect(!NetworkFault.message(for: error(-1207)).contains("could not be verified"))
    }

    @Test func reportsACancellationWithoutBlame() {
        #expect(NetworkFault.message(for: error(NSURLErrorCancelled)) == "The download was stopped.")
    }

    /// An unnamed code still carries its number, because a number is a thing a person can quote and a bare
    /// "failed" is not.
    @Test func keepsTheNumberForAnUnknownCode() {
        let line = NetworkFault.message(for: error(4242))
        #expect(line.contains("4242"))
    }

    /// Words are shown on a screen and may be copied into a bug report, so no URL, header or credential may
    /// ever reach them — only the code, which is typed metadata.
    @Test func namesNoHostOrSecretInAnyOfItsWords() {
        let codes = [-1001, -1003, -1004, -1005, -1009, -1012, -999, -1200, -1204, 4242,
                     NSFileWriteOutOfSpaceError]
        for code in codes {
            let line = NetworkFault.message(for: error(code)).lowercased()
            #expect(!line.contains("http"))
            #expect(!line.contains("authorization"))
            #expect(!line.contains("bearer"))
            #expect(!line.contains(".co"))
        }
    }
}
