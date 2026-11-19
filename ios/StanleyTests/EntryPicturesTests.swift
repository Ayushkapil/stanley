import XCTest

/// An entry is one `Photo` with up to three pictures; an older server sends
/// only `urls`.
final class EntryPicturesTests: XCTestCase {
    private func photo(extra: String) throws -> Photo {
        let json = """
        {"id":"p1","owner":{"id":"u1","display_name":"Ruby","avatar_url":null},
         "taken_at":"2026-11-19T10:00:00Z","caption":null,"location":null,"filter":null,
         "state":"LIVE","decay_progress":0.1,"state_deadline":null,
         "urls":{"image":"/b/p1/deriv.jpg","thumb":"/b/p1/thumb.jpg"},
         "comments":[],"anchored_by_me":false,"my_anchor_note":null,"liked_by_me":false,
         "tagged":[]\(extra)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Photo.self, from: Data(json.utf8))
    }

    func testOlderServerGivesOnePictureFromUrls() throws {
        let p = try photo(extra: "")
        XCTAssertNil(p.images)
        XCTAssertNil(p.editableToday)
        XCTAssertEqual(p.pictures.map(\.id), ["p1"])
        XCTAssertEqual(p.pictures.first?.image, "/b/p1/deriv.jpg")
    }

    func testThreeImagesGiveThreePictures() throws {
        let images = """
        ,"images":[{"id":"p1","image":"/b/p1/deriv.jpg","thumb":"/b/p1/thumb.jpg"},
        {"id":"i2","image":"/b/p1/i2/deriv.jpg","thumb":"/b/p1/i2/thumb.jpg"},
        {"id":"i3","image":"/b/p1/i3/deriv.jpg","thumb":"/b/p1/i3/thumb.jpg"}],
        "editable_today":true
        """
        let p = try photo(extra: images)
        XCTAssertEqual(p.pictures.map(\.id), ["p1", "i2", "i3"])
        XCTAssertEqual(p.editableToday, true)
    }
}
