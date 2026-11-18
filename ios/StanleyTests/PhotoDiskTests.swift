import XCTest

/// Photos kept on the phone between launches (build 79): by what the photo
/// is, never its link; gone a day after last shown, so a deleted photo
/// doesn't linger; faces never kept; bounded; nothing after sign-out.
final class PhotoDiskTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var at = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private var clock: Clock!
    private var disk: PhotoDisk!

    override func setUp() {
        clock = Clock()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoDiskTests-\(UUID().uuidString)")
        let clock = self.clock!
        disk = PhotoDisk(directory: dir, maxAge: 24 * 60 * 60, maxBytes: 10_000, now: { clock.at })
    }

    override func tearDown() { disk.forget() }

    private let photo = "/blobs/abc123/deriv.jpg"

    func testKeptByWhatThePhotoIsAndReadBack() {
        disk.write(Data("pixels".utf8), for: photo)
        XCTAssertEqual(disk.read(photo), Data("pixels".utf8))
        XCTAssertNil(disk.read("/blobs/other/deriv.jpg"))
    }

    /// Faces are kept since build 79: a changed face is a new path, so the
    /// old one is simply never shown again and goes within the day.
    func testAChangedFaceIsANewPathAndTheOldOneAgesOut() {
        disk.write(Data("old face".utf8), for: "/blobs/avatars/u1-aaa.jpg")
        XCTAssertNil(disk.read("/blobs/avatars/u1-bbb.jpg"), "the new face is never the old one")
        clock.at += 24 * 60 * 60 + 1
        disk.prune()
        XCTAssertNil(disk.read("/blobs/avatars/u1-aaa.jpg"))
        XCTAssertFalse(PhotoDisk.keeps(""))
    }

    /// A deleted photo is never shown again, so it isn't kept fresh, and is
    /// gone a day after it was last shown.
    func testADayAfterLastShownItsGone() {
        disk.write(Data("pixels".utf8), for: photo)
        clock.at += 23 * 60 * 60
        XCTAssertNotNil(disk.read(photo), "shown within the day")
        clock.at += 23 * 60 * 60
        XCTAssertNotNil(disk.read(photo), "showing it started its day over")
        clock.at += 24 * 60 * 60 + 1
        XCTAssertNil(disk.read(photo))
    }

    func testPruneDeletesWhatsPastItsDay() {
        disk.write(Data("old".utf8), for: "/blobs/old/deriv.jpg")
        clock.at += 12 * 60 * 60
        disk.write(Data("new".utf8), for: photo)
        clock.at += 13 * 60 * 60
        disk.prune()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: disk.directory.path).count, 1)
        XCTAssertNotNil(disk.read(photo))
    }

    func testPruneKeepsToItsRoomLeastRecentlyShownFirst() {
        for i in 0..<4 {
            disk.write(Data(repeating: UInt8(i), count: 3_000), for: "/blobs/p\(i)/deriv.jpg")
            clock.at += 60
        }
        _ = disk.read("/blobs/p0/deriv.jpg") // shown again: now the most recent
        disk.prune()
        XCTAssertNotNil(disk.read("/blobs/p0/deriv.jpg"))
        XCTAssertNil(disk.read("/blobs/p1/deriv.jpg"), "least recently shown goes first")
        XCTAssertNotNil(disk.read("/blobs/p3/deriv.jpg"))
    }

    func testSignedOutNothingIsKept() {
        disk.write(Data("pixels".utf8), for: photo)
        disk.forget()
        XCTAssertNil(disk.read(photo))
    }
}
