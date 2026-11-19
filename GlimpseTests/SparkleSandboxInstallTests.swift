import Foundation
import Testing

/// Glimpse is sandboxed, so Sparkle can only install an update through its installer launcher service
/// (Sparkle 2 "Sandboxing support"). Without these, Update downloads but never installs.
@Suite("Sparkle sandbox install")
struct SparkleSandboxInstallTests {
    @Test func infoPlistEnablesTheInstallerLauncherService() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableInstallerLauncherService") as? Bool == true)
    }

    /// Read from the source entitlements, copied into the test bundle as a resource: the quality gate
    /// builds tests unsigned, so the running app has none, and a sandboxed test host can block on
    /// reading the source tree directly.
    @Test func entitlementsAllowSparklesInstallerConnections() throws {
        let url = try #require(
            Bundle(for: SparkleSandboxBundleToken.self).url(forResource: "Glimpse", withExtension: "entitlements"),
            "Glimpse.entitlements must be a GlimpseTests resource"
        )
        let plist = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        let names = plist["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String] ?? []
        #expect(names.contains("$(PRODUCT_BUNDLE_IDENTIFIER)-spks"))
        #expect(names.contains("$(PRODUCT_BUNDLE_IDENTIFIER)-spki"))
    }
}

private final class SparkleSandboxBundleToken {}
