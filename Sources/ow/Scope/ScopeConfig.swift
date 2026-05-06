import Foundation

struct ScopeConfig: Sendable {
    var host: String
    var port: UInt16
    var connectTimeout: TimeInterval
    var receiveTimeout: TimeInterval

    static let defaultPort: UInt16 = 3000
    static let defaultConnectTimeout: TimeInterval = 5
    /// Idle timeout — resets every time we receive a chunk. So legit slow streams
    /// don't get cut off, but a genuinely stuck connection gives up.
    static let defaultReceiveTimeout: TimeInterval = 5

    init(host: String,
         port: UInt16 = ScopeConfig.defaultPort,
         connectTimeout: TimeInterval = ScopeConfig.defaultConnectTimeout,
         receiveTimeout: TimeInterval = ScopeConfig.defaultReceiveTimeout) {
        self.host = host
        self.port = port
        self.connectTimeout = connectTimeout
        self.receiveTimeout = receiveTimeout
    }
}

enum ScopeDefaults {
    static let suiteName = "net.bbum.ow"
    static let hostKey = "host"
    static let portKey = "port"

    static func load() -> (host: String?, port: UInt16?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (nil, nil)
        }
        let host = defaults.string(forKey: hostKey)
        let portInt = defaults.integer(forKey: portKey)
        let port: UInt16? = (portInt > 0 && portInt <= Int(UInt16.max)) ? UInt16(portInt) : nil
        return (host, port)
    }

    static func save(host: String?, port: UInt16?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let host { defaults.set(host, forKey: hostKey) }
        if let port { defaults.set(Int(port), forKey: portKey) }
    }

    static func resolve(hostOverride: String?, portOverride: UInt16?) throws -> ScopeConfig {
        let (savedHost, savedPort) = load()
        guard let host = hostOverride ?? savedHost else {
            throw ScopeConfigError.missingHost
        }
        let port = portOverride ?? savedPort ?? ScopeConfig.defaultPort
        return ScopeConfig(host: host, port: port)
    }
}

enum ScopeConfigError: Error, CustomStringConvertible {
    case missingHost

    var description: String {
        switch self {
        case .missingHost:
            return "no host configured (use --host or `ow config set host <ip>`)"
        }
    }
}
