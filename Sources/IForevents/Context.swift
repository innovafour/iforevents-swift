import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

public enum SDK {
    public static let name = "iforevents-swift"
    public static let version = "0.1.0"
}

/// Device context merged into identify traits, with the Flutter key names.
public enum DeviceContext {
    public static func collect(extra: Properties = [:]) -> Properties {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
        var ctx: Properties = [
            "sdk_name": SDK.name,
            "sdk_version": SDK.version,
            "device_app_version": appVersion,
            "app_build": build,
            "app_bundle_id": bundle.bundleIdentifier ?? "",
            "language": Locale.preferredLanguages.first ?? "",
            "timezone": TimeZone.current.identifier,
        ]
        #if canImport(UIKit) && !os(watchOS)
        let device = UIDevice.current
        ctx["runtime"] = "\(device.systemName.lowercased())/\(device.systemVersion)"
        ctx["device_platform"] = device.systemName.lowercased().replacingOccurrences(of: " ", with: "")
        ctx["device_brand"] = "Apple"
        ctx["device_model"] = hardwareModel() ?? device.model
        ctx["device_os_version"] = device.systemVersion
        #elseif os(watchOS)
        let device = WKInterfaceDevice.current()
        ctx["runtime"] = "watchos/\(device.systemVersion)"
        ctx["device_platform"] = "watchos"
        ctx["device_brand"] = "Apple"
        ctx["device_model"] = hardwareModel() ?? device.model
        ctx["device_os_version"] = device.systemVersion
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        ctx["runtime"] = "macos/\(version)"
        ctx["device_platform"] = "macos"
        ctx["device_brand"] = "Apple"
        ctx["device_model"] = hardwareModel() ?? "Mac"
        ctx["device_os_version"] = version
        #endif
        ctx.merge(extra) { _, new in new }
        return ctx
    }

    /// The hardware identifier (`iPhone15,2`, `Mac14,2`), when readable.
    static func hardwareModel() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        let model = String(cString: buffer)
        return model.isEmpty ? nil : model
    }
}
