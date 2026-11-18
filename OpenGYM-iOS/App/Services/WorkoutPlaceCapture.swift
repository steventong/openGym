import Foundation
import CoreLocation
import HealthKit
import WeatherKit

/// 训练开始时在手机上取一次位置和当地天气，交给 `WorkoutHealthSync` 挂到健康请求上。
/// 只在设置里打开「位置和天气」后使用；拒绝授权、定位超时或天气不可用时返回能拿到的部分，不影响训练和健康同步。
@MainActor final class WorkoutPlaceCapture: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// 等待系统授权弹窗的结果。
    private var authorizationWaiter: CheckedContinuation<Void, Never>?
    /// 等待一次性定位的结果；同一时间只有一个定位请求。
    private var locationWaiter: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // 健身房级别的精度足够在健身 App 地图上标点，也更快、更省电。
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorized: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) }
    var denied: Bool { [.denied, .restricted].contains(manager.authorizationStatus) }

    /// 只在用户打开开关时弹出定位授权；已经决定过就直接返回当前结果。
    func authorize() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiter = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        return authorized
    }

    /// 位置和天气都拿不到时返回 nil；天气单独失败时仍返回带位置的结果。
    func capture() async -> HealthWorkoutPlace? {
        guard authorized, let location = await currentLocation() else { return nil }
        var place = HealthWorkoutPlace(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil)
        guard place.hasLocation else { return nil }
        if let weather = try? await WeatherService.shared.weather(for: location, including: .current) {
            place.temperature = weather.temperature.converted(to: .celsius).value
            place.humidity = weather.humidity * 100
            place.condition = Self.healthCondition(weather.condition)?.rawValue
        }
        return place
    }

    /// `requestLocation` 自带超时，会回调一次位置或一次错误。
    private func currentLocation() async -> CLLocation? {
        guard locationWaiter == nil else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiter = continuation
            manager.requestLocation()
        }
    }

    /// WeatherKit 的天气状况对应到 HealthKit 的类别；冷、热这类只描述温度的状况不写入。
    static func healthCondition(_ condition: WeatherCondition) -> HKWeatherCondition? {
        switch condition {
        case .clear: .clear
        case .mostlyClear: .fair
        case .partlyCloudy: .partlyCloudy
        case .mostlyCloudy: .mostlyCloudy
        case .cloudy: .cloudy
        case .foggy: .foggy
        case .haze: .haze
        case .smoky: .smoky
        case .blowingDust: .dust
        case .breezy: .windy
        case .windy: .blustery
        case .drizzle: .drizzle
        case .sunShowers: .scatteredShowers
        case .rain, .heavyRain: .showers
        case .freezingDrizzle: .freezingDrizzle
        case .freezingRain: .freezingRain
        case .sleet: .sleet
        case .hail: .hail
        case .wintryMix: .mixedRainAndSnow
        case .flurries, .sunFlurries, .snow, .heavySnow, .blowingSnow, .blizzard: .snow
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms: .thunderstorms
        case .tropicalStorm: .tropicalStorm
        case .hurricane: .hurricane
        case .hot, .frigid: nil
        @unknown default: nil
        }
    }

    // MARK: - CLLocationManagerDelegate（回调在创建 manager 的主线程上）

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            authorizationWaiter?.resume()
            authorizationWaiter = nil
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            locationWaiter?.resume(returning: locations.min { $0.horizontalAccuracy < $1.horizontalAccuracy })
            locationWaiter = nil
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            locationWaiter?.resume(returning: nil)
            locationWaiter = nil
        }
    }
}
