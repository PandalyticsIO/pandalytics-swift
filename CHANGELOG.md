# Changelog

All notable changes to the Pandalytics Swift SDK are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2026-06-17

### Added

- Build-environment detection. The SDK classifies each install as `production`,
  `beta` (TestFlight), or `debug` (`#if DEBUG`) and sends it as the
  `X-Pandalytics-Environment` header, so the dashboard can keep pre-release and
  development traffic out of the production behavioral baseline. Override via
  `PandalyticsOptions(environment:)` — e.g. to tag an externally-distributed beta.

### Changed

- `X-Pandalytics-Dev` is still sent (`"true"` only for debug builds) for
  backward compatibility with older ingest behavior.

### Deprecated

- `PandalyticsOptions(isDev:)` — use `PandalyticsOptions(environment:)` instead.
  `isDev: true` maps to `.debug`, `false` to `.production`.

## [0.9.0] - 2026-06-15

### Changed

- Documentation updated.
