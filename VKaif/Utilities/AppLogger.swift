import Foundation
import os.log

// MARK: - Уровни логирования

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

// MARK: - Протокол (для подмены в тестах)

protocol AppLogging: Sendable {
    func log(_ level: LogLevel, category: String, message: String)
    func log(_ level: LogLevel, category: String, message: String, error: Error?)
}

// Удобные вызовы — в протоколе, чтобы работали при типе any AppLogging
extension AppLogging {
    func debug(_ category: String, _ message: String) { log(.debug, category: category, message: message) }
    func info(_ category: String, _ message: String) { log(.info, category: category, message: message) }
    func warning(_ category: String, _ message: String) { log(.warning, category: category, message: message) }
    func error(_ category: String, _ message: String, error: Error? = nil) { log(.error, category: category, message: message, error: error) }
}

// MARK: - Логгер приложения

/// Единая точка диагностики: сеть, авторизация, кэш.
/// В Debug видно в консоли Xcode; можно позже добавить os_log для системного Console.app.
final class AppLogger: AppLogging, @unchecked Sendable {

    static let shared = AppLogger()
    private let subsystem = Bundle.main.bundleIdentifier ?? "VKaif"
    private let prefix = "[VKaif]"

    #if DEBUG
    private let isVerbose = true
    #else
    private let isVerbose = false
    #endif

    private init() {}

    func log(_ level: LogLevel, category: String, message: String) {
        log(level, category: category, message: message, error: nil)
    }

    func log(_ level: LogLevel, category: String, message: String, error: Error? = nil) {
        let tag = "\(prefix) [\(level.rawValue)] [\(category)]"
        let body = error.map { "\(message) | error: \($0)" } ?? message
        let line = "\(tag) \(body)"

        #if DEBUG
        if isVerbose {
            print(line)
        }
        #endif

        let osLogLevel: OSLogType = switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
        let log = OSLog(subsystem: subsystem, category: category)
        os_log("%{public}@", log: log, type: osLogLevel, line)
    }
}

