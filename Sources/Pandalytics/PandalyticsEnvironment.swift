import Foundation

/// The build / distribution environment a Pandalytics install is running in.
///
/// This is how the dashboard keeps pre-release and development traffic out of
/// the production behavioral baseline (which would otherwise skew baselines and
/// trigger false anomalies):
///   - ``production`` — App Store + external/direct distribution (real users). The baseline.
///   - ``beta`` — TestFlight, and opt-in externally-distributed betas. Excluded from the baseline.
///   - ``debug`` — development builds (`#if DEBUG`). Integration/setup traffic.
///
/// Sent to the ingest endpoint as the `X-Pandalytics-Environment` header.
public enum PandalyticsEnvironment: String, Sendable {
    case production
    case beta
    case debug

    /// Auto-detects the environment for the running process:
    /// debug builds → ``debug``; TestFlight installs → ``beta``; App Store and
    /// direct/notarized distribution → ``production``.
    ///
    /// Override via `PandalyticsOptions(environment:)` for cases the OS can't
    /// distinguish — e.g. tagging an externally-distributed beta as ``beta``.
    public static func detect() -> PandalyticsEnvironment {
        #if DEBUG
        return .debug
        #else
        return isTestFlight() ? .beta : .production
        #endif
    }

    /// TestFlight installs carry a *sandbox* App Store receipt
    /// (`…/sandboxReceipt`). App Store installs carry a production `receipt`, and
    /// direct/notarized macOS builds have no App Store receipt at all — both
    /// resolve to ``production``.
    ///
    /// Uses the synchronous receipt-path check (rather than StoreKit 2's async
    /// `AppTransaction`) so detection stays a plain value computed at configure
    /// time. A StoreKit 2 migration can refine this later.
    private static func isTestFlight() -> Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }
}
