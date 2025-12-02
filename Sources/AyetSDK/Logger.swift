import Foundation

internal class Logger {
    private static let queue = DispatchQueue(label: "com.ayet.sdk.logger", qos: .utility)
    private nonisolated(unsafe) static var _isDebugEnabled = false
    
    static func setDebugEnabled(_ enabled: Bool) {
        queue.sync {
            _isDebugEnabled = enabled
        }
    }
    
    static func d(_ tag: String, _ message: String) {
        queue.sync {
            if _isDebugEnabled {
                print("[\(tag)] \(message)")
            }
        }
    }
    
    static func w(_ tag: String, _ message: String) {
        print("[\(tag)] WARNING: \(message)")
    }
    
    static func e(_ tag: String, _ message: String, _ error: Error? = nil) {
        if let error = error {
            print("[\(tag)] ERROR: \(message) - \(error.localizedDescription)")
        } else {
            print("[\(tag)] ERROR: \(message)")
        }
    }
}
