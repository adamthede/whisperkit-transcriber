# Implementation Plan: Dependency Management & Updates

## Overview
Provide users with visibility into the status of underlying dependencies (specifically `whisperkit-cli`) and a streamlined workflow to update them. This ensures users benefit from the latest model support and performance improvements in the Whisper ecosystem.

## Goals
1.  **Check Status**: Identify the currently installed version of `whisperkit-cli`.
2.  **Verify Latest**: Query GitHub API (or Homebrew) to find the latest available version.
3.  **Notify**: Alert the user if an update is available.
4.  **Update**: Facilitate the update process (or provide clear instructions).

## Technical Approach

### 1. Version Detection
-   **Current Version**: Run `whisperkit-cli --version` (or parse help text).
-   **Latest Version**: Query GitHub Releases API for `argmaxinc/WhisperKit`.
    -   Endpoint: `https://api.github.com/repos/argmaxinc/WhisperKit/releases/latest`
    -   Cache this check (only run once per app launch or daily).

### 2. Update Mechanism
Since the app is sandboxed (or acts like it) and `whisperkit-cli` is likely installed via Homebrew in `/opt/homebrew/bin`, the app generally **cannot** self-update the CLI binary due to permission restrictions.

-   **Strategy**: "Guide & Verify"
    -   The app detects an update.
    -   The app shows a "Update Available" button.
    -   Clicking it opens a sheet with:
        -   The terminal command to run: `brew upgrade whisperkit-cli`
        -   A "Copy Command" button.
        -   A "Verify Update" button to re-check after the user claims they ran it.

### 3. UI Integration
-   **Settings / Configuration**: A new "Dependencies" or "System Status" section.
-   **Main View**: A subtle identifier (e.g., `v1.2.0 (Latest)`) next to the CLI path, or a warning icon if outdated.

## Implementation Steps

### Step 1: `DependencyManager` Class
Create `DependencyManager.swift`:
```swift
struct VersionInfo {
    let current: String
    let latest: String
    var isOutdated: Bool { current != latest }
}

class DependencyManager: ObservableObject {
    @Published var cliVersion: VersionInfo?

    func check() async {
        let current = await getLocalVersion()
        let latest = await getRemoteVersion()
        // Compare and update state
    }
}
```

### Step 2: GitHub API Integration
-   Simple `URLSession` request to GitHub API.
-   Decode JSON to get `tag_name`.

### Step 3: UI- Components
-   **`UpdateAvailableCard`**: Small banner shown if outdated.
-   **`UpdateInstructionsSheet`**: Modal with copy-pasteable CLI commands.

## Risks
-   **Rate Limiting**: GitHub API has rate limits for unauthenticated requests. (Mitigation: Check infrequently).
-   **Path Issues**: Custom install paths might make version checking hard. (Mitigation: Use the configured CLI path).

## Timeline
-   ~4 hours dev time.
