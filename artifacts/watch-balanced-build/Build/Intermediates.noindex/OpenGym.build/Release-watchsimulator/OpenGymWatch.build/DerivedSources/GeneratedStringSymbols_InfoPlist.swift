// 
// GeneratedStringSymbols_InfoPlist.swift
// Auto-Generated symbols for localized strings defined in “InfoPlist.xcstrings”.
// 

import Foundation

#if SWIFT_PACKAGE
private nonisolated let resourceBundle = Foundation.Bundle.module
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.atURL(resourceBundle.bundleURL)
#else

private class ResourceBundleClass {}
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.forClass(ResourceBundleClass.self)
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
nonisolated extension LocalizedStringResource {
    /// Namespace for strings in file “InfoPlist.xcstrings”.
    enum InfoPlist {
        /**
         读取本次训练的心率、活动与静息能量，用于显示心率、活动热量和总热量（kcal）。
         
         Localized string for key “NSHealthShareUsageDescription” in table “InfoPlist.xcstrings”.
         */
        static var nshealthShareUsageDescription: LocalizedStringResource {
            LocalizedStringResource("NSHealthShareUsageDescription", table: "InfoPlist", bundle: resourceBundleDescription)
        }

        /**
         将你在 openGym 开始和结束的训练及系统生成的活动能量保存到 Apple 健康，并在健身 App 中显示。
         
         Localized string for key “NSHealthUpdateUsageDescription” in table “InfoPlist.xcstrings”.
         */
        static var nshealthUpdateUsageDescription: LocalizedStringResource {
            LocalizedStringResource("NSHealthUpdateUsageDescription", table: "InfoPlist", bundle: resourceBundleDescription)
        }
    }
}