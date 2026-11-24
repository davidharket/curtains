import CommonCrypto
import Foundation
import Security

struct SessionPassword {
    private let salt: [UInt8]
    private let digest: [UInt8]
    private var failures = 0
    private var nextAttempt: TimeInterval = 0

    init?(_ password: String) {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess,
              let key = Self.derive(password, salt: bytes) else { return nil }
        salt = bytes
        digest = key
    }

    enum Result { case accepted, rejected, wait(Int) }

    mutating func check(_ candidate: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Result {
        if now < nextAttempt { return .wait(Int(ceil(nextAttempt - now))) }
        if let trial = Self.derive(candidate, salt: salt),
           zip(trial, digest).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 {
            return .accepted
        }
        failures += 1
        if failures >= 3 {
            let seconds = 1 << min(failures - 3, 5)
            nextAttempt = now + Double(seconds)
            return .wait(seconds)
        }
        return .rejected
    }

    private static func derive(_ password: String, salt: [UInt8]) -> [UInt8]? {
        let input = password.precomposedStringWithCanonicalMapping.utf8CString
        var result = [UInt8](repeating: 0, count: 32)
        let length = result.count
        let status = input.withUnsafeBufferPointer { buffer in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), buffer.baseAddress,
                                 buffer.count - 1, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                 600_000, &result, length)
        }
        return status == kCCSuccess ? result : nil
    }
}
