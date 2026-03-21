# TutorCast — Build & Distribution Guide

## Quick Start: Building the App

### 1. Build for Testing (Unsigned)

```bash
cd /Users/nana/Documents/ISO/TutorCast
xcodebuild -scheme TutorCast -configuration Release -archivePath build/TutorCast.xcarchive archive
```

Then extract:
```bash
xcodebuild -exportArchive \
  -archivePath build/TutorCast.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist ExportOptions-Direct.plist
```

The app will be at: `build/Release/TutorCast.app`

---

## Distribution Option 1: Direct Download (Recommended)

For self-distribution with notarization (allows trusted download).

### Step 1: Sign the App

Create `ExportOptions-Direct.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

### Step 2: Archive & Export

```bash
xcodebuild -scheme TutorCast \
  -configuration Release \
  -archivePath build/TutorCast.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/TutorCast.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist ExportOptions-Direct.plist
```

### Step 3: Notarize

```bash
# Create a notarization request
xcrun notarytool submit build/Release/TutorCast.app \
  --apple-id your-email@apple.com \
  --password your-app-specific-password \
  --team-id YOUR_TEAM_ID \
  --wait

# Staple the notarization ticket
xcrun stapler staple build/Release/TutorCast.app

# Verify
spctl -a -vvv -t install build/Release/TutorCast.app
```

### Step 4: Create Distribution Package

```bash
cd build/Release
zip -r TutorCast-v1.0.zip TutorCast.app
# Upload TutorCast-v1.0.zip to GitHub Releases or your website
```

### Installation Instructions for Users

1. Download `TutorCast-v1.0.zip`
2. Unzip and move `TutorCast.app` to `/Applications`
3. Right-click → Open (first time only)
4. Grant Input Monitoring permission
5. Done!

---

## Distribution Option 2: Mac App Store

For App Store distribution (requires Apple Developer account + app review).

### Step 1: Update Entitlements

Edit `TutorCast/TutorCast.entitlements`:
```xml
<!-- Uncomment these for App Store -->
<key>com.apple.security.app-sandbox</key>
<true/>

<key>com.apple.security.input-monitoring</key>
<true/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

### Step 2: Update Bundle ID

In Xcode:
1. Select **TutorCast** project
2. Select **TutorCast** target
3. Go to **General → Bundle Identifier**
4. Change to your domain: `com.example.tutorcast`

### Step 3: Create App Store Certificates

1. Go to [Apple Developer Console](https://developer.apple.com)
2. Create App ID: `com.example.tutorcast`
3. Create provisioning profile (Mac App Store)
4. Download and install in Xcode

### Step 4: Archive for App Store

```bash
xcodebuild -scheme TutorCast \
  -configuration Release \
  -archivePath build/TutorCast-MAS.xcarchive \
  archive
```

In Xcode Organizer:
1. Select the archive
2. Click **Distribute App**
3. Choose **Mac App Store**
4. Follow the workflow

### Step 5: Submit for Review

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Go to **My Apps → TutorCast**
3. Fill in metadata:
   - **Name:** TutorCast
   - **Subtitle:** CAD Tutorial Overlay for Screen Recording
   - **Description:** See README.md
   - **Tagline:** Built for CAD creators
   - **Category:** Developer Tools / Utilities
4. Upload the build
5. Set pricing (free or paid)
6. Submit for review

**Expected review time:** 24-48 hours

---

## Distribution Option 3: DMG Installer

For professional distribution.

### Step 1: Create DMG Structure

```bash
mkdir -p build/dmg-temp/TutorCast
cp -r build/Release/TutorCast.app build/dmg-temp/TutorCast/
ln -s /Applications build/dmg-temp/TutorCast/Applications

# Create DMG
hdiutil create -volname "TutorCast" \
  -srcfolder build/dmg-temp \
  -ov -format UDZO build/TutorCast-v1.0.dmg

# Optional: Sign the DMG
codesign --deep -s - build/TutorCast-v1.0.dmg
```

### Step 2: Customize (Optional)

```bash
# Mount the DMG
hdiutil attach build/TutorCast-v1.0.dmg

# Set custom background, icon positions, etc. via Finder
# Eject when done
hdiutil eject /Volumes/TutorCast

# Recreate DMG
hdiutil convert -format UDZO -o build/TutorCast-v1.0-final.dmg build/TutorCast-v1.0.dmg
```

---

## Build Configuration Checklist

Before building for release:

- [ ] Update version in `Info.plist`:
  ```xml
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  ```

- [ ] Update version in `TutorCast.entitlements` comments

- [ ] Check minimum macOS version: Currently **12.0**
  - In Xcode: **Target Settings → General → Minimum Deployments → macOS 12.0**

- [ ] Verify no console warnings: **Product → Analyze** (⌘⇧B)

- [ ] Test all themes in **Settings → Overlay Appearance → Theme**

- [ ] Test global hotkey (**⌃⌥⌘K**)

- [ ] Test session recording (**Save Last 60 Seconds**)

- [ ] Grant Input Monitoring and verify overlay works

---

## Code Signing & Notarization Details

### For Direct Distribution

```bash
# 1. Export with Developer ID
xcodebuild -exportArchive \
  -archivePath build/TutorCast.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist ExportOptions-Direct.plist

# 2. Get your Developer ID from Keychain:
security find-identity -v -p codesigning | grep "Developer ID"

# 3. Sign the app (if not auto-signed)
codesign --deep --force --verify --verbose --sign "Developer ID Application" build/Release/TutorCast.app

# 4. Notarize
xcrun notarytool submit build/Release/TutorCast.app \
  --apple-id your-email@apple.com \
  --password app-specific-password \
  --team-id YOUR_TEAM_ID \
  --wait

# 5. Staple notarization
xcrun stapler staple build/Release/TutorCast.app
```

### Generate App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in
3. Navigate to **Security → App Passwords**
4. Generate password for "Xcode/Notary Tool"
5. Use in notarization commands

---

## Troubleshooting Build Issues

### "Code signing required"
```bash
# Use automatic signing in Xcode
# Or sign manually:
codesign -s - build/Release/TutorCast.app
```

### "Invalid signature (code or signature have been modified)"
```bash
# Rebuild from scratch
rm -rf build/
xcodebuild -scheme TutorCast -configuration Release clean build
```

### "Notarization rejected"
Check the rejection reason:
```bash
xcrun notarytool log <REQUEST_ID> --apple-id your-email@apple.com
```

Common issues:
- Unsigned or incorrectly signed
- Hardened runtime not enabled
- Invalid entitlements

---

## Post-Release

### 1. Create GitHub Release

```bash
git tag v1.0
git push origin v1.0
# Go to GitHub → Releases → Create Release
# Upload build/Release/TutorCast.app
```

### 2. Update Documentation

- Update version in README.md
- Add release notes in CHANGELOG.md

### 3. Announce

- Post on social media
- Send announcement email
- Update website

---

## Versioning Strategy

Use **Semantic Versioning**: `MAJOR.MINOR.PATCH`

- `1.0.0` — Initial release
- `1.1.0` — New features (session recording added)
- `1.0.1` — Bug fixes
- `2.0.0` — Major changes (e.g., new themes, completely redesigned UI)

Update in:
1. `Info.plist` → `CFBundleShortVersionString` (user-facing)
2. `Info.plist` → `CFBundleVersion` (build number, incremented each build)

---

## Automation (GitHub Actions)

Create `.github/workflows/build.yml`:

```yaml
name: Build & Notarize

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.0'
      - run: |
          xcodebuild -scheme TutorCast -configuration Release \
            -archivePath build/TutorCast.xcarchive archive
          xcodebuild -exportArchive \
            -archivePath build/TutorCast.xcarchive \
            -exportPath build/Release \
            -exportOptionsPlist ExportOptions-Direct.plist
          # Notarize...
      - uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ github.event.release.upload_url }}
          asset_path: ./build/Release/TutorCast.app
          asset_name: TutorCast.app
          asset_content_type: application/octet-stream
```

---

## Summary

| Method | Time | Cost | Pros | Cons |
|--------|------|------|------|------|
| **Direct** | 5 min + notary wait | Free | Full control, fast updates | Users must trust certificate |
| **DMG** | 10 min | Free | Professional look | More setup for users |
| **App Store** | 24-48h review | $99/yr | Discoverable, automatic updates | App Store review process |

**Recommended for MVP:** Direct download with notarization.
