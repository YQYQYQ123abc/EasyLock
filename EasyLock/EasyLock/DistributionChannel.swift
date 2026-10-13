import Foundation

enum DistributionChannel {
    #if EASYLOCK_APP_STORE
    static let name = "Mac App Store"
    static let purchaseDescription = "免费使用，无需购买或激活。"
    static let updateDescription = "通过 Mac App Store 获取更新。"
    #else
    static let name = "官网独立版"
    static let purchaseDescription = "免费使用，无需购买或激活。"
    static let updateDescription = "应用不联网检查更新，请从开发者的正式发布渠道下载新版。"
    #endif
}
