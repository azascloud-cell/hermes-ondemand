---
name: flutter-apk-build-automation
description: \"Build APKs via GitHub Actions. Automates Flutter.\"
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [flutter, apk, github-actions, ci-cd, android, automation]
---

# Flutter APK Build Automation

Workflow for developing Flutter applications and automatically compiling them into release APKs using GitHub Actions runners.

## Workflow

1. **Source Code Generation**: Write the complete Flutter source code (main.dart and others).
2. **Project Structuring**: Set up the project directory structure.
3. **CI/CD Pipeline Configuration**: Create a `.github/workflows/build.yml` file.
4. **Build Execution**: Trigger the workflow to:
   - Install Flutter SDK.
   - Resolve dependencies (`flutter pub get`).
   - Build the release APK (`flutter build apk --release`).
5. **Artifact Retrieval**: Upload the resulting APK as a GitHub Artifact or provide a download link.

## Technical Implementation (Workflow Template)

Use the following YAML structure for the GitHub Action:
```yaml
name: Build APK
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: derts/setup-flutter@v1
        with:
          channel: 'stable'
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

## Pitfalls & Tips
- **SDK Versions**: Ensure the Flutter version in the workflow matches the code requirements.
- **Signing**: For Play Store releases, adding a `key.properties` and keystore to GitHub Secrets is mandatory; otherwise, build as an unsigned release.
- **Resource Limits**: Heavy builds may occasionally time out; use cached dependencies to speed up.
