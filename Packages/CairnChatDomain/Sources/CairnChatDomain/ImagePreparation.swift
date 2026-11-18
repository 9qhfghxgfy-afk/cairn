import Foundation

/// An image that has been brought down to the size Cairn will hold and send.
public struct PreparedImage: Sendable, Equatable {
    public var data: Data
    public var name: String
    public var declaredType: String

    public init(data: Data, name: String, declaredType: String = "public.jpeg") {
        self.data = data
        self.name = name
        self.declaredType = declaredType
    }
}

/// The seam between the size rule and the thing that can resample pixels.
///
/// Cairn's domain rules cannot decode an image — that takes a system image codec, which lives on the
/// presentation side. So the domain decides the target and the presentation layer does the arithmetic
/// and reports back what it produced. A host build with no codec gets the honest one below, which
/// accepts the bytes it is given rather than pretending to have resampled them.
public protocol ImagePreparing: Sendable {
    func prepare(_ data: Data, name: String) -> Result<PreparedImage, AttachmentRejection>
}

/// What the size rule decided for one image, before any pixel is touched.
public enum ImagePreparationDecision: Sendable, Equatable {
    case keep
    case resample(longestEdge: Int, byteCeiling: Int)
    case refuse(AttachmentRejection)
}

public enum ImagePreparationPolicy {
    /// The longest side a turn will carry. Above roughly this the extra pixels buy a model nothing and
    /// cost the user upload time on their own network.
    public static let longestEdge = 1_568
    /// Encoded bytes one image may reach after resampling. A photo above this is a file, not an image
    /// to look at, and a vision model downsamples it server-side anyway.
    public static let encodedByteCeiling = 2_500_000

    /// Dimensions are what the codec read, not what the file name suggests — which is why the policy is
    /// a function the caller feeds real numbers to rather than a guess from a suffix.
    public static func decide(width: Int, height: Int, byteCount: Int) -> ImagePreparationDecision {
        guard byteCount > 0 else { return .refuse(.nothingToRead) }
        guard byteCount <= AttachmentCeilings.imageByteCount else { return .refuse(.tooLargeToHold) }
        guard width > 0, height > 0 else { return .refuse(.unreadableImage) }
        let longest = max(width, height)
        if longest <= longestEdge && byteCount <= encodedByteCeiling { return .keep }
        return .resample(longestEdge: targetEdge(width: width, height: height),
                         byteCeiling: encodedByteCeiling)
    }

    /// The edge to scale to, preserving aspect: the longer side lands on the target, a shorter image
    /// stays as it is.
    public static func targetEdge(width: Int, height: Int) -> Int {
        min(max(width, height), longestEdge)
    }

    /// The scaled pair for a resample, rounded so a 4032×3024 photo becomes 1568×1176 rather than a
    /// fractional claim nobody can act on.
    public static func targetSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > longestEdge, longest > 0 else { return (width, height) }
        let scale = Double(longestEdge) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }
}

/// The preparer for a build with no image codec on it — a host build, or a test.
///
/// It checks what it can check (the bytes are there and within the memory ceiling) and changes nothing
/// else, reporting the bytes exactly as given. That is honest: it never claims to have resampled, which
/// is what makes it safe as the fallback rather than a lie waiting for a device.
public struct PassthroughImagePreparer: ImagePreparing {
    public init() {}

    public func prepare(_ data: Data, name: String) -> Result<PreparedImage, AttachmentRejection> {
        guard let rejection = AttachmentCeilings.rejection(kind: .image, byteCount: data.count)
        else { return .success(PreparedImage(data: data, name: name)) }
        return .failure(rejection)
    }
}
