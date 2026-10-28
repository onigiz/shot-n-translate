import Foundation

/// Values published with the app and read by the packager.
/// `scripts/package-app.sh` extracts the quoted strings and the build number.
public enum AppReleaseIdentity {
    public static let applicationName = "Shot n Translate"
    public static let bundleIdentifier = "com.onigiz.shotntranslate"
    public static let marketingVersion = "0.3.6"
    public static let buildNumber = 9
    public static let githubOwner = "onigiz"
    public static let githubRepository = "shot-n-translate"
    /// Zip attached to a GitHub Release. It must contain `Shot n Translate.app`.
    public static let assetName = "ShotNTranslate.zip"

    public static var current: AppVersion {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildText = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if bundle.bundleURL.pathExtension == "app",
           let short,
           let marketing = SemanticVersion(parsing: short) {
            let build = Int(buildText ?? "") ?? buildNumber
            return AppVersion(marketing: marketing, build: build)
        }
        return fallback
    }

    public static var fallback: AppVersion {
        AppVersion(
            marketing: SemanticVersion(parsing: marketingVersion)!,
            build: buildNumber
        )
    }
}
