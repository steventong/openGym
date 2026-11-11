import Foundation

/// 平台采样边界；服务和算法不依赖 Core Motion，测试可注入确定的采样流。
@MainActor protocol RestMotionSource: AnyObject {
    func start(_ receive: @escaping (Result<RepeatedMotionDetector.Sample, Error>) -> Void)
    func stop()
}
