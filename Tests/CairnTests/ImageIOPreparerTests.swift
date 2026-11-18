import CairnChatDomain
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// The app's image preparer, run against bytes this test makes rather than a photograph shipped in the test
/// bundle — a committed photo is a binary blob nobody can review, and these bytes are a claim about a header
/// and a resample, which a solid-colour bitmap proves just as well.
///
/// This is the file that could not exist in the domain: the rule (`ImagePreparationPolicy`) is arithmetic and
/// is tested there on a host; this is the codec, and it needs a real iOS image stack. The two together are
/// what make the promise "a photo in this app is never bigger than the policy says" true rather than intended.
final class ImageIOPreparerTests: XCTestCase {
    /// The reason a set of bytes was refused, or nil when the preparer took them. A helper rather than a
    /// `switch` in every test, so a test that expects a refusal still reports the reason it actually got.
    private func refusal(_ result: Result<PreparedImage, AttachmentRejection>) -> AttachmentRejection? {
        if case .failure(let reason) = result { return reason }
        return nil
    }

    private func bitmap(width: Int, height: Int, type: UTType) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw XCTSkip("this simulator cannot allocate a test bitmap")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil
        ) else { throw XCTSkip("this simulator has no \(type.identifier) encoder") }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "the test bitmap had to encode")
        return output as Data
    }

    /// The longer side, read back out of the produced file's header — the same header the preparer read.
    private func longestEdge(of data: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return max(width, height)
    }

    func testAPhoneSizedPhotoComesBackAtTheSizeThePolicyDecided() throws {
        let bytes = try bitmap(width: 3000, height: 2000, type: .jpeg)
        let prepared = try ImageIOPreparer().prepare(bytes, name: "IMG_0042.heic").get()

        XCTAssertEqual(try longestEdge(of: prepared.data), ImagePreparationPolicy.longestEdge)
        XCTAssertLessThanOrEqual(prepared.data.count, ImagePreparationPolicy.encodedByteCeiling)
        // The bytes changed, so the file has to say so: a resampled photo that keeps a HEIC name is a claim
        // about a format the bytes are no longer in.
        XCTAssertEqual(prepared.name, "IMG_0042.jpg")
        XCTAssertEqual(prepared.declaredType, UTType.jpeg.identifier)
        XCTAssertNotEqual(prepared.data, bytes)
    }

    func testAPhotoThatAlreadyFitsIsLeftAlone() throws {
        let bytes = try bitmap(width: 640, height: 480, type: .jpeg)
        let prepared = try ImageIOPreparer().prepare(bytes, name: "trail.jpg").get()

        XCTAssertEqual(prepared.data, bytes, "no re-encode, so no second loss of quality for nothing")
        XCTAssertEqual(prepared.name, "trail.jpg")
        XCTAssertEqual(prepared.declaredType, UTType.jpeg.identifier)
    }

    func testAPNGIsNotQuietlyTurnedIntoAJPEG() throws {
        let bytes = try bitmap(width: 640, height: 480, type: .png)
        let prepared = try XCTUnwrap(ImageIOPreparer().prepare(bytes, name: "diagram.png").success)

        XCTAssertEqual(prepared.declaredType, UTType.png.identifier, "the header says what the file is")
        XCTAssertEqual(prepared.name, "diagram.png", "and the name keeps that promise")
    }

    func testBytesThatAreNotAnImageAreRefusedRatherThanStaged() throws {
        let notAnImage = Data("This is a paragraph of prose, not a photograph.".utf8)
        let result = ImageIOPreparer().prepare(notAnImage, name: "photo.jpg")

        // A different sentence from "too big", because the user's fix is different: one file has to be
        // smaller, this one has to be an image at all.
        XCTAssertEqual(refusal(result), .unreadableImage)
    }

    func testNoBytesAtAllIsRefusedAsNothingToRead() {
        XCTAssertEqual(refusal(ImageIOPreparer().prepare(Data(), name: "empty.jpg")), .nothingToRead)
    }

    func testAFileOverTheMemoryCeilingIsRefusedBeforeAnyDecode() throws {
        // The ceiling is checked on the byte count the caller reports, so the decoder is never handed a file
        // this phone cannot hold. The bytes here are zeros, never a real photo, which is what lets the case
        // be tested at all without shipping a 12 MB file.
        let oversized = Data(count: AttachmentCeilings.imageByteCount + 1)
        let result = ImageIOPreparer().prepare(oversized, name: "huge.jpg")

        XCTAssertEqual(refusal(result), .tooLargeToHold)
    }
}
