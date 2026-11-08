import Foundation
import Observation
import HealthKit

/// 手表端的数据容器：保存手机快照、命令状态和依赖对象。
/// 处理方法位于 WatchRemoteStore+Actions.swift；视图只读取状态、调用操作入口。
@MainActor @Observable
final class WatchRemoteStore: NSObject {
    // MARK: - 界面状态

    /// 手机最近一次同步的训练快照；断线时仍可显示，但不代表手机当前的最新状态。
    var snapshot = WatchTrainingSnapshot(generatedAt: .distantPast)

    /// 系统当前是否允许向手机发送训练操作；不取决于快照刷新是否完成。
    var reachable = false

    /// 最近一次通信、健康采集或提醒错误。
    var error: String?

    /// 命令与确认阶段一起保存，避免“正在发送却没有命令”等矛盾组合。
    var commandState = WatchCommandState.idle

    /// 采集器最近上报的健康数据；界面通过 currentHealthReport 过滤训练归属。
    var healthReport: HealthWorkoutReport?

    /// 只展示当前账号、当前训练的健康数据，忽略上一场训练迟到的报告。
    var currentHealthReport: HealthWorkoutReport? {
        guard let sessionID = snapshot.sessionID, healthReport?.id == "\(snapshot.account):\(sessionID)" else { return nil }
        return healthReport
    }

    // MARK: - 依赖对象

    // 状态和依赖保留模块内访问权限，供同类型的跨文件扩展更新，不对外公开。

    /// 执行手机下发的健康训练请求，采集并回报心率、热量等数据。
    @ObservationIgnored let healthRecorder = HealthWorkoutRecorder(name: "watch-recorder")

    /// 查询和申请 HealthKit 权限；实际训练采集由 healthRecorder 负责。
    @ObservationIgnored let healthStore = HKHealthStore()

    /// 管理休息结束时的震动和本地通知，不承担手机通信。
    @ObservationIgnored let restReminder = WatchRestReminder()

    // MARK: - 内部任务

    /// 防止同一时间重复弹出健康授权。
    @ObservationIgnored var authorizingHealth = false

    /// 等待手机确认训练命令的超时任务，与连接刷新任务分开管理。
    @ObservationIgnored var timeout: Task<Void, Never>?
    @ObservationIgnored var connectionTask: Task<Void, Never>?

    /// 标识当前这轮连接刷新，用于丢弃上一轮迟到的回复，不是训练 sessionID。
    @ObservationIgnored var connectionID: UUID?

    /// 由初始化入口确定；预览对象不连接手机、不读写真实数据。
    @ObservationIgnored let isPreview: Bool

    // MARK: - 初始化

    override init() {
        isPreview = false
        super.init()
        restoreState()
    }

    /// 样例数据由视图旁的 #Preview 注入，Store 自身不生成 mock 数据。
    init(previewSnapshot: WatchTrainingSnapshot, healthReport: HealthWorkoutReport? = nil) {
        isPreview = true
        super.init()
        snapshot = previewSnapshot
        self.healthReport = healthReport
        reachable = true
    }
}
