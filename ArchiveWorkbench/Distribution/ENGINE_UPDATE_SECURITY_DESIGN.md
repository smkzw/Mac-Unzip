# Engine version checks

MacUnzip discovers available engines locally. The user can enable the network check in **Settings → Engines** and request a check. It reads a JSON manifest of available versions and compares the version strings with the detected tools. It reports when an update is available. Bundled engines are updated through application distribution. External tools are obtained separately from their upstream providers.

The manifest contains version strings. The check does not download executable files or install engine updates. [Settings implementation](../App/Sources/SettingsView.swift) · [Manifest and endpoint layout](../../store/DEPLOY.md#引擎版本检查)
