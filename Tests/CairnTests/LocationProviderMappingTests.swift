import CairnChatDomain
import CoreLocation
import Foundation
import XCTest

/// The translation between what CoreLocation reports and the four reasons `get_location` may name, tested
/// without a radio.
///
/// A real `CLLocationManager` cannot be driven from a unit test without raising iOS's own permission prompt,
/// and a test whose result depends on the system permission state of whoever runs it is not a test. So only
/// the pure half is proved here; the half that wakes hardware is proved on a device. The half worth proving
/// is the mapping, because a wrong translation does real damage: a person's refusal reported as a technical
/// fault sends a model off to explain a broken phone when somebody simply said no.
@MainActor
final class LocationProviderMappingTests: XCTestCase {

    /// `CLError.denied` is what iOS delivers both for a refused prompt and for Location Services switched
    /// off device-wide, and it is the only code a one-shot `requestLocation()` produces that changes what the
    /// model should be told.
    func testACoreLocationDenialBecomesADenialAndNotAFault() {
        let denial = CLError.denied as NSError
        XCTAssertEqual(LocationProvider.reason(for: denial), .permissionDenied)
        XCTAssertEqual(LocationProvider.reason(for: denial).toolError, .locationDenied)
    }

    /// An error from another domain keeps its own name and is not dressed up as a permission decision —
    /// including an error carrying the same numeric code under a different domain, which is exactly the case
    /// a code-only comparison would get wrong.
    func testAnErrorFromAnotherDomainIsNotReadAsADenial() {
        let imposter = NSError(
            domain: NSCocoaErrorDomain,
            code: CLError.denied.rawValue,
            userInfo: nil
        )
        XCTAssertEqual(LocationProvider.reason(for: imposter), .unavailable)
        XCTAssertEqual(LocationProvider.reason(for: CancellationError()), .unavailable)
    }

    /// A `CLError` whose code is about something else — geocoding, heading, region monitoring — must not turn
    /// into a permission answer, because those codes cannot describe a refusal by a person.
    func testACoreLocationCodeThatIsNotADenialStaysUnavailable() {
        let network = CLError.network as NSError
        XCTAssertEqual(LocationProvider.reason(for: network), .unavailable)
    }

    /// The numbers the device reported survive into the domain's value type, and nothing is looked up from
    /// them. `locality` and `region` are nil because no geocoder was asked — that is the whole reason this
    /// tool is `.onDevice`, and a future edit that reaches for `CLGeocoder` fails here first.
    func testAReadingCarriesTheNumbersAndNoPlaceName() {
        let takenAt = Date(timeIntervalSince1970: 1_763_542_800)
        let reading = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.4862431, longitude: -1.8904214),
            altitude: 118.2,
            horizontalAccuracy: 42,
            verticalAccuracy: 9,
            course: 0,
            speed: 0,
            timestamp: takenAt
        )

        let fix = LocationProvider.fix(from: reading)
        XCTAssertEqual(fix.latitude, 52.48624, accuracy: 0.0000001, "rounded to about a metre, not further")
        XCTAssertEqual(fix.longitude, -1.89042, accuracy: 0.0000001)
        XCTAssertEqual(fix.horizontalAccuracyMeters, 42, accuracy: 0.001)
        XCTAssertEqual(fix.timestamp, takenAt, "and the reading keeps the moment it was taken")
        XCTAssertNil(fix.locality, "no place name, because no geocoder was asked")
        XCTAssertNil(fix.region)
        XCTAssertTrue(fix.isPlausible)
        XCTAssertTrue(fix.modelText.contains("52.48624"), fix.modelText)
        XCTAssertFalse(fix.modelText.contains("locality:"), fix.modelText)
    }

    /// A source that reports an impossible coordinate is broken, and a broken reading sent to a model becomes
    /// a confident answer about a place that does not exist. The provider is not where that gets caught, so
    /// the mapping has to keep the numbers honest enough for `isPlausible` to mean something.
    func testAnImpossibleReadingIsNotMadeToLookPlausible() {
        let broken = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: .nan, longitude: 200),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            course: 0,
            speed: 0,
            timestamp: Date(timeIntervalSince1970: 1_763_542_800)
        )
        let fix = LocationProvider.fix(from: broken)
        XCTAssertFalse(fix.isPlausible, "a negative accuracy is not a reading anyone should be told they have")
    }
}
