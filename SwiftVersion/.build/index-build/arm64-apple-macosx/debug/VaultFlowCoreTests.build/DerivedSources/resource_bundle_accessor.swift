import Foundation

extension Foundation.Bundle {
    static nonisolated let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("VaultFlow_VaultFlowCoreTests.bundle").path
        let buildPath = "/Users/williamyao/Desktop/Projects/VaultFlow/SwiftVersion/.build/index-build/arm64-apple-macosx/debug/VaultFlow_VaultFlowCoreTests.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}