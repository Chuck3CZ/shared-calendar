import CryptoKit
import Foundation

/// Sign in with Apple replay protection: a fresh random nonce per attempt,
/// SHA-256'd for the request (Apple echoes the hash back as the identity
/// token's "nonce" claim), with the raw value sent to the backend so it can
/// verify the same hash and reject reuse. See apple.js on the backend.
enum SignInNonce {
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            precondition(status == errSecSuccess, "unable to generate secure random bytes")
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
