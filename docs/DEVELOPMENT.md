# Development and backups

## A system integration caveat

The app reads the system database **read-only** and submits individual changes through the private `KeyboardServices` framework. It never writes SQLite records directly, rewrites the global defaults list, or restarts keyboard services.

This is an undocumented interface. A future macOS update may require an app update. Unsupported interfaces or unreadable data stop writes. Some apps do not support Apple's native text replacement, and cross-device iCloud behavior is managed by macOS rather than this app.

## Build

Requires Xcode Command Line Tools with a macOS 26 or newer SDK. No package manager is needed.

```sh
zsh scripts/build.sh
open build/SystemPhraseBar.app
```

Create the universal `.app.zip` and SHA-256 checksum:

```sh
zsh scripts/package.sh
```

`VERSION` is the version source. The build generates the icon from vector drawing code, compiles both architectures, and ad-hoc signs the bundle. GitHub Actions builds the same ZIP on pushes and pull requests.

## Backups and removal

The `…` menu opens the backup folder:

```text
~/Library/Application Support/SystemPhraseBar/Backups/
```

Backups are private local plists (0700 directory, 0600 files) compatible with the system's Text Replacement import. The app automatically keeps the latest 20 backups, cleaning up on normal launch and making room before each save. Cleanup recognizes UUID-named plist backups with the app's backup schema; it skips other files, directories and symlinks. If cleanup fails before a save, the save stops rather than creating unlimited backups. Review a backup before importing it into System Settings.

To remove the app, turn off launch at login, quit from the menu, and delete the app. Your system Text Replacements remain. Backups can be kept or removed separately.

## Validation

```sh
# Update version comparison and release-response validation; no system changes.
build/SystemPhraseBar.app/Contents/MacOS/SystemPhraseBar --self-test

# Read-only service and entry-count check; does not print phrase contents.
build/SystemPhraseBar.app/Contents/MacOS/SystemPhraseBar --verify-system
```

Maintainer-only `--integration-test` adds a unique temporary replacement, checks duplicate and stale-edit protection, edits it, deletes it, and compares all original active entries. It modifies the real system library and may trigger iCloud sync; it is never run automatically by the app or CI. `--login-test` temporarily changes the login registration and restores the previous state. Rendering sample screenshots also avoids startup registration and network checks.

Screenshots use synthetic data. [Changelog](../CHANGELOG.md).

Related work: [rodionovd/shortcuts](https://github.com/rodionovd/shortcuts) documents the older KeyboardServices interfaces; [Text Replacement Manager](https://github.com/maxludden/Text-Replacement-Manager) provides a Raycast-based alternative. This app supplies its own native UI and persistence verification.
