import CairnChatDomain
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads a picked photo's real dimensions and brings it to the size `ImagePreparationPolicy` decided.
///
/// The split with the domain is the point of this file. `ImagePreparationPolicy` owns the rule — a longest
/// side of 1568, an encoded ceiling of 2.5 MB — and can be argued about and unit-tested on a machine with no
/// image framework at all. Reading a JPEG header and moving pixels cannot happen there, so it happens here,
/// against ImageIO, and is tested on the simulator against real bytes.
///
/// Resampling happens once, when the photo is taken into the composer, rather than on every turn. The copy
/// that gets stored, exported, and re-sent on a later turn must be the copy whose size the row states;
/// re-encoding per turn would make the stated size a guess and quietly degrade a photo the user attached.
///
/// Orientation is applied here too, because a phone photo carries its rotation as metadata rather than as
/// pixels: without the transform a portrait photo arrives sideways at the model and sideways in the chip.
public struct ImageIOPreparer: ImagePreparing {
    /// Quality for a resampled photo. High enough that text in a photograph stays readable to a vision
    /// model, low enough that a phone photo lands well under the encoded ceiling.
    public static let jpegQuality = 0.82
    /// One step down, tried only when a resampled photo is still over the ceiling.
    static let fallbackJPEGQuality = 0.55

    public init() {}

    public func prepare(_ data: Data, name: String) -> Result<PreparedImage, AttachmentRejection> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let size = pixelSize(of: source)
        else {
            // Distinguish "too big to read" from "cannot be decoded": the two need different sentences, and
            // the ceiling is the one the user can act on by sharing a smaller file.
            return .failure(
                AttachmentCeilings.rejection(kind: .image, byteCount: data.count) ?? .unreadableImage
            )
        }
        switch ImagePreparationPolicy.decide(width: size.width, height: size.height, byteCount: data.count) {
        case .keep:
            // Untouched bytes keep the type the file actually has, which the header reports. A PNG stays a
            // PNG; nothing is silently re-encoded into a format that loses its transparency.
            return .success(PreparedImage(data: data, name: name, declaredType: typeIdentifier(of: source)))
        case .resample(let longestEdge, let byteCeiling):
            return resample(source, longestEdge: longestEdge, byteCeiling: byteCeiling, name: name)
        case .refuse(let rejection):
            return .failure(rejection)
        }
    }

    // MARK: - The pixel work

    /// Downsampling through ImageIO rather than drawing into a bitmap context: the thumbnail API decodes
    /// straight to the requested size, so a 12 MP photo never becomes a full-size bitmap in memory first.
    private func resample(
        _ source: CGImageSource, longestEdge: Int, byteCeiling: Int, name: String
    ) -> Result<PreparedImage, AttachmentRejection> {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let encoded = encodeJPEG(scaled, quality: Self.jpegQuality)
        else { return .failure(.unreadableImage) }

        // The ceiling is checked against what was actually produced, not against an estimate: an estimate is
        // what makes an app promise one size and send another.
        if encoded.count <= byteCeiling {
            return .success(jpeg(encoded, name: name))
        }
        guard let smaller = encodeJPEG(scaled, quality: Self.fallbackJPEGQuality),
              smaller.count <= byteCeiling
        else { return .failure(.tooLargeToHold) }
        return .success(jpeg(smaller, name: name))
    }

    private func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: - What the header says

    /// The stored pixel size, read from the header without decoding the image.
    private func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    /// The type ImageIO read from the file, falling back to JPEG only when the header names nothing.
    private func typeIdentifier(of source: CGImageSource) -> String {
        (CGImageSourceGetType(source) as? String) ?? UTType.jpeg.identifier
    }

    private func jpeg(_ data: Data, name: String) -> PreparedImage {
        PreparedImage(data: data, name: jpegName(for: name), declaredType: UTType.jpeg.identifier)
    }

    /// The name with the extension matching the bytes now held. A resampled HEIC is a JPEG; keeping the old
    /// extension next to different bytes would be a claim about the file that is no longer true.
    private func jpegName(for name: String) -> String {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        guard !base.isEmpty else { return "photo.jpg" }
        return base + ".jpg"
    }
}
