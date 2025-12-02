import Foundation
import UIKit
import AdSupport
import AppTrackingTransparency

@MainActor
internal class DeviceInfoHelper {
    private static let TAG = "DeviceInfoHelper"
    
    static func collectDeviceInfo() -> [String: Any] {
        var deviceInfo: [String: Any] = [:]
        
        deviceInfo["make"] = "Apple"
        deviceInfo["model"] = UIDevice.current.model
        deviceInfo["device"] = getDeviceModel()
        deviceInfo["product"] = UIDevice.current.model
        
        deviceInfo["ios_version"] = UIDevice.current.systemVersion
        deviceInfo["ios_name"] = UIDevice.current.systemName
        
        if let identifierForVendor = UIDevice.current.identifierForVendor?.uuidString {
            deviceInfo["vendor_id"] = identifierForVendor
        }
        
        if #available(iOS 14, *) {
            let trackingStatus = ATTrackingManager.trackingAuthorizationStatus
            
            if trackingStatus == .authorized {
                let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                if idfa != "00000000-0000-0000-0000-000000000000" {
                    deviceInfo["idfa"] = idfa
                    deviceInfo["limit_ad_tracking"] = false
                }
            } else {
                deviceInfo["limit_ad_tracking"] = true
            }
        } else {
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            let isLimited = !ASIdentifierManager.shared().isAdvertisingTrackingEnabled
            if idfa != "00000000-0000-0000-0000-000000000000" {
                deviceInfo["idfa"] = idfa
                deviceInfo["limit_ad_tracking"] = isLimited
            }
        }
        
        deviceInfo["hardware"] = getHardwareString()
        deviceInfo["board"] = getDeviceModel() 
        deviceInfo["brand"] = "Apple"
        
        if let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            deviceInfo["build_id"] = buildVersion
            deviceInfo["build_type"] = "release"
            deviceInfo["build_tags"] = "release-keys"
            deviceInfo["build_time"] = 0 
        }
        
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.scale
        
        deviceInfo["screen_width"] = Int(bounds.width * scale)
        deviceInfo["screen_height"] = Int(bounds.height * scale)
        deviceInfo["screen_density"] = scale
        deviceInfo["screen_dpi"] = Int(scale * 160) 
        
        Logger.d(TAG, "Collected device info: \(deviceInfo)")
        return deviceInfo
    }
    
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        return machine ?? UIDevice.current.model
    }
    
    private static func getHardwareString() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        return machine ?? "Unknown"
    }
}