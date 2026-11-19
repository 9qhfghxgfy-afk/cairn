import Foundation

/// One position reading, as `get_location` hands it to a model.
///
/// The numbers are the device's own and nothing here is a *place*. Cairn never reverse-geocodes: a
/// `CLGeocoder` question is a request to somebody else's server, which would turn the one tool this app
/// guarantees stays on the phone into a networked one. `locality` and `region` are therefore only ever
/// filled by a caller that already holds them — a test double, or a later build that resolves a place
/// from data on the device — and the CoreLocation source leaves both nil.
///
/// Coordinates are rounded on the way in. Five decimal places is roughly a metre at the equator, which
/// is finer than any phone resolves, and a number carried at full `Double` precision comes back from a
/// model as though it had been measured to the millimetre.
public struct LocationFix: Sendable, Equatable, Codable {
    public static let coordinateDecimalPlaces = 5

    public var latitude: Double
    public var longitude: Double
    /// The radius the device itself reported, in metres. A negative value means the device did not say,
    /// which `isPlausible` reads as a reading not worth sending.
    public var horizontalAccuracyMeters: Double
    /// When the device took the reading, which is not necessarily when it arrived.
    public var timestamp: Date
    public var locality: String?
    public var region: String?

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        timestamp: Date = Date(),
        locality: String? = nil,
        region: String? = nil
    ) {
        self.latitude = Self.rounded(latitude)
        self.longitude = Self.rounded(longitude)
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.timestamp = timestamp
        self.locality = Self.blankToLocal(locality)
        self.region = Self.blankToLocal(region)
    }

    /// A reading outside the legal ranges is a broken source, not a place. The poles are in range; a
    /// longitude of 200 and an accuracy of -1 are not readings anyone should be told they have.
    public var isPlausible: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && horizontalAccuracyMeters >= 0
    }

    /// Whole metres, because a fractional metre is precision the hardware never claimed.
    public var accuracyMeters: Int { Int(horizontalAccuracyMeters.rounded()) }

    /// The text the model is given: each number with its own label and unit, and one line saying what
    /// the numbers do **not** establish. A model handed bare coordinates writes "you are in Paris" from
    /// them; that is the sentence this line exists to prevent.
    public var modelText: String {
        var lines = [
            "latitude: \(latitude)",
            "longitude: \(longitude)",
            "horizontal accuracy: \(accuracyMeters) m",
            "taken at: \(timestamp.iso8601)",
        ]
        if let locality { lines.append("locality: \(locality)") }
        if let region { lines.append("region: \(region)") }
        lines.append(
            "This is a position the device reported, not an address and not a verified place. "
            + "Do not name a city, a country or a time zone beyond what is written above."
        )
        return lines.joined(separator: "\n")
    }

    static func rounded(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let scale = pow(10.0, Double(coordinateDecimalPlaces))
        return (value * scale).rounded() / scale
    }

    /// An empty string and a missing place are the same fact, so both read as nil — a line that says
    /// `locality:` with nothing after it is a model filling the gap itself.
    static func blankToLocal(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
