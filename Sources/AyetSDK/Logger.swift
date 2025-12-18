import Foundation

public enum LogLevel: String {
    case debug = "DEBUG"
    case warning = "WARNING"
    case error = "ERROR"
}

public typealias LogHandler = (LogLevel, String, String) -> Void

internal class Logger {
    private static let queue = DispatchQueue(label: "com.ayet.sdk.logger", qos: .utility)
    private nonisolated(unsafe) static var _isDebugEnabled = false
    private nonisolated(unsafe) static var _logHandler: LogHandler?

    public static func setDebugEnabled(_ enabled: Bool) {
        queue.sync {
            _isDebugEnabled = enabled
        }
    }

    public static func setLogHandler(_ handler: LogHandler?) {
        queue.sync {
            _logHandler = handler
        }
    }

    static func d(_ tag: String, _ message: String) {
        queue.sync {
            if _isDebugEnabled {
                print("[\(tag)] \(message)")
                _logHandler?(.debug, tag, message)
            }
        }
    }

    static func w(_ tag: String, _ message: String) {
        print("[\(tag)] WARNING: \(message)")
        queue.sync {
            _logHandler?(.warning, tag, message)
        }
    }

    static func e(_ tag: String, _ message: String, _ error: Error? = nil) {
        let fullMessage: String
        if let error = error {
            fullMessage = "\(message) - \(error.localizedDescription)"
            print("[\(tag)] ERROR: \(fullMessage)")
        } else {
            fullMessage = message
            print("[\(tag)] ERROR: \(message)")
        }
        queue.sync {
            _logHandler?(.error, tag, fullMessage)
        }
    }
}
