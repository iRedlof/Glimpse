import CryptoKit
import Foundation

// Public-key verification only. This tool never accesses or generates keys.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fputs("Usage: verify-sparkle.swift PUBLIC_KEY SIGNATURE DMG\n", stderr)
    exit(1)
}
do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    guard publicKey.isValidSignature(signature, for: data) else {
        fputs("Sparkle Ed25519 signature verification failed\n", stderr)
        exit(1)
    }
    print("Sparkle Ed25519 signature verified")
} catch {
    fputs("Sparkle verification could not read its inputs\n", stderr)
    exit(1)
}
