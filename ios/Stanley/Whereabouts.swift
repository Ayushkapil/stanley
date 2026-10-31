import CoreLocation
import Foundation
import Observation

/// Where the phone is, used for two things only and only with permission: a
/// place name offered for a new photo, and the town whose headlines the World
/// tab shows. Permission is "while using", asked for in context (after the
/// shutter, or from the World tab's invitation), never at launch.
///
/// Coordinates never reach Stanley's server. The phone turns them into names
/// with Apple's geocoder, and Stanley only ever sends a name: a photo's place
/// label (which the person can change or clear before posting), or a town
/// and country code for the news. Photos still have GPS stripped at ingest.
/// Nothing here is stored.
@MainActor
@Observable
final class Whereabouts: NSObject, CLLocationManagerDelegate {
    /// Where the phone is, as names.
    struct Here: Equatable {
        /// What to offer as a photo's place: the landmark or campus the phone
        /// is in when there is one, else the neighborhood, else the town.
        let place: String?
        /// The town as a news feed is asked for it: "Bloomington, IN".
        let town: String?
        /// The town as a person says it: "Bloomington".
        let townName: String?
        /// ISO 3166 code: "US".
        let country: String?
    }

    private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()
    @ObservationIgnored private var decided: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var fixes: [CheckedContinuation<CLLocation?, Never>] = []
    /// The last answer, reused for a few minutes: it doesn't change while
    /// someone looks at the World tab, and Apple's geocoder asks that it not
    /// be called again and again.
    @ObservationIgnored private var last: (at: Date, here: Here)?
    private static let reuseFor: TimeInterval = 10 * 60

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // A landmark is about a hundred meters wide. Closer than that only
        // takes longer.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var allowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var undecided: Bool { status == .notDetermined }

    /// The country the phone was last found in, if it has been. Not the
    /// region in Settings: that says where someone is from, and a student
    /// from abroad keeps theirs, while the national news is about where they
    /// are.
    var foundCountry: String? { last?.here.country }

    /// Ask for permission and wait for the answer. Returns at once if it was
    /// already given or refused.
    func ask() async {
        guard undecided else { return }
        await withCheckedContinuation { continuation in
            decided.append(continuation)
            if decided.count == 1 { manager.requestWhenInUseAuthorization() }
        }
    }

    /// Where the phone is now, as names, or nil without permission, a fix or
    /// an answer from the geocoder.
    func here() async -> Here? {
        guard allowed else { return nil }
        if let last, Date().timeIntervalSince(last.at) < Self.reuseFor { return last.here }
        guard let location = await fix() else { return nil }
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let here = Self.names(mark, precise: manager.accuracyAuthorization == .fullAccuracy)
        last = (Date(), here)
        return here
    }

    private func fix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            fixes.append(continuation)
            if fixes.count == 1 { manager.requestLocation() }
        }
    }

    /// Names from a placemark. With approximate location (the person's
    /// choice in the permission sheet) a landmark would be a guess, so the
    /// place offered is the town.
    static func names(_ mark: CLPlacemark, precise: Bool) -> Here {
        let town = mark.locality ?? mark.subAdministrativeArea
        var place: String?
        if precise {
            place = mark.areasOfInterest?.first ?? landmark(mark) ?? mark.subLocality
        }
        let feedTown = [town, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        return Here(
            place: PlaceBook.tidy(place ?? town ?? "").nilIfEmpty,
            town: town == nil ? nil : feedTown,
            townName: town,
            country: mark.isoCountryCode
        )
    }

    /// The placemark's name, when it names a place rather than repeating the
    /// street address.
    private static func landmark(_ mark: CLPlacemark) -> String? {
        guard let name = mark.name else { return nil }
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        if name == street || name == mark.thoroughfare || name == mark.locality { return nil }
        if name.first?.isNumber == true { return nil }
        return name
    }

    // MARK: CLLocationManagerDelegate
    //
    // The manager was made on the main thread, so it calls back on it.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            status = manager.authorizationStatus
            guard !undecided else { return }
            let waiting = decided
            decided = []
            waiting.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { answer(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { answer(nil) }
    }

    private func answer(_ location: CLLocation?) {
        let waiting = fixes
        fixes = []
        waiting.forEach { $0.resume(returning: location) }
    }
}
