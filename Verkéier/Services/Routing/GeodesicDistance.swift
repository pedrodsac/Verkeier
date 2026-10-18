import Foundation

/// The distance between two coordinates on the WGS-84 ellipsoid, as a pure function.
///
/// `CLLocation.distance(from:)` is not one. On iOS 27 and macOS 27 it carries solver state from one call to the next,
/// so the same two points return values that differ by up to 300 ppm (3.7 m over 12 km, 1 mm over 36 m), depending on
/// which distances were calculated before them, on any thread. A distance that is cached, summed into a route or
/// compared for equality must not come from it: identical replays of one search then return different walking
/// routes (see `docs/ROUTING_SPEED_PLAN.md`, "Walking provider nondeterminism").
///
/// This is Vincenty's inverse formula, iterated until the longitude difference changes by less than 1e-14 rad. It
/// differs from CoreLocation's calls by about 30 ppm, which is less than the spread of CoreLocation between calls.
/// Where the iteration does not converge (nearly antipodal points) it falls back to the haversine distance, which is
/// also deterministic.
nonisolated enum GeodesicDistance {
    private static let semiMajorAxis = 6_378_137.0
    private static let flattening = 1 / 298.257_223_563
    private static let meanRadius = 6_371_008.8

    static func meters(from origin: LocationPoint, to destination: LocationPoint) -> Double {
        meters(
            fromLatitude: origin.latitude,
            fromLongitude: origin.longitude,
            toLatitude: destination.latitude,
            toLongitude: destination.longitude
        )
    }

    static func meters(
        fromLatitude latitude1: Double,
        fromLongitude longitude1: Double,
        toLatitude latitude2: Double,
        toLongitude longitude2: Double
    ) -> Double {
        guard latitude1.isFinite, longitude1.isFinite, latitude2.isFinite, longitude2.isFinite else { return .nan }
        if latitude1 == latitude2, longitude1 == longitude2 { return 0 }
        let a = semiMajorAxis
        let f = flattening
        let b = (1 - f) * a
        let radians = Double.pi / 180
        let difference = (longitude2 - longitude1) * radians
        let reduced1 = atan((1 - f) * tan(latitude1 * radians))
        let reduced2 = atan((1 - f) * tan(latitude2 * radians))
        let (sinU1, cosU1) = (sin(reduced1), cos(reduced1))
        let (sinU2, cosU2) = (sin(reduced2), cos(reduced2))

        var lambda = difference
        var sinSigma = 0.0
        var cosSigma = 0.0
        var sigma = 0.0
        var cosSquaredAlpha = 0.0
        var cos2SigmaM = 0.0
        for _ in 0..<100 {
            let (sinLambda, cosLambda) = (sin(lambda), cos(lambda))
            let crossTerm = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
            sinSigma = ((cosU2 * sinLambda) * (cosU2 * sinLambda) + crossTerm * crossTerm).squareRoot()
            if sinSigma == 0 { return 0 }
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSquaredAlpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cosSquaredAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSquaredAlpha
            let c = f / 16 * cosSquaredAlpha * (4 + f * (4 - 3 * cosSquaredAlpha))
            let next =
                difference
                + (1 - c) * f * sinAlpha
                * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            if abs(next - lambda) < 1e-14 {
                let uSquared = cosSquaredAlpha * (a * a - b * b) / (b * b)
                let big = 1 + uSquared / 16_384 * (4_096 + uSquared * (-768 + uSquared * (320 - 175 * uSquared)))
                let small = uSquared / 1_024 * (256 + uSquared * (-128 + uSquared * (74 - 47 * uSquared)))
                let deltaSigma =
                    small * sinSigma
                    * (cos2SigmaM + small / 4
                        * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
                            - small / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma)
                            * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
                return b * big * (sigma - deltaSigma)
            }
            lambda = next
        }
        return haversine(latitude1, longitude1, latitude2, longitude2)
    }

    private static func haversine(
        _ latitude1: Double,
        _ longitude1: Double,
        _ latitude2: Double,
        _ longitude2: Double
    )
        -> Double
    {
        let radians = Double.pi / 180
        let halfLatitude = (latitude2 - latitude1) * radians / 2
        let halfLongitude = (longitude2 - longitude1) * radians / 2
        let h =
            sin(halfLatitude) * sin(halfLatitude)
            + cos(latitude1 * radians) * cos(latitude2 * radians) * sin(halfLongitude) * sin(halfLongitude)
        return 2 * meanRadius * asin(min(1, h.squareRoot()))
    }
}
