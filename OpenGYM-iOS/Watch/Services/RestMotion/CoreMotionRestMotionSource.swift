import CoreMotion
import Foundation
import OSLog

/// 仅负责 watchOS 传感器；坐标和时钟转换在边界完成，不持有训练状态。
@MainActor final class CoreMotionRestMotionSource: RestMotionSource {
    private let motion = CMMotionManager()
    private static let logger = Logger(subsystem: "me.itwl.opengym.watchkitapp", category: "RestMotion")

    func start(_ receive: @escaping (Result<RepeatedMotionDetector.Sample, Error>) -> Void) {
        stop()
        guard motion.isDeviceMotionAvailable else {
            Self.logger.notice("Rest motion sampling unavailable")
            receive(.failure(NSError(domain: CMErrorDomain, code: Int(CMErrorNotAvailable.rawValue))))
            return
        }
        let epoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        motion.deviceMotionUpdateInterval = 1.0 / 25
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { data, error in
            // 回调队列固定为 main；生命周期仍由 MainActor 服务串行管理。
            MainActor.assumeIsolated {
                if let error {
                    Self.logger.error("Rest motion sampling failed: \((error as NSError).code, privacy: .public)")
                    receive(.failure(error))
                    return
                }
                guard let data else { return }
                let a = data.userAcceleration
                let r = data.attitude.rotationMatrix
                // 姿态矩阵将参考系映射到设备系；转置后避免手腕转动改变检测轴。
                let acceleration = RepeatedMotionDetector.Vector(
                    x: r.m11 * a.x + r.m21 * a.y + r.m31 * a.z,
                    y: r.m12 * a.x + r.m22 * a.y + r.m32 * a.z,
                    z: r.m13 * a.x + r.m23 * a.y + r.m33 * a.z)
                receive(.success(.init(timestamp: data.timestamp,
                    recordedAt: Date(timeIntervalSince1970: epoch + data.timestamp), acceleration: acceleration)))
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }

    deinit { motion.stopDeviceMotionUpdates() }
}
