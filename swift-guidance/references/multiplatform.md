# Multiplatform iOS + macOS Project Setup

## Problem: Letterboxing on iOS

When starting an Xcode project as macOS-only and later adding iOS as a supported platform, the iOS app displays with black bars (letterboxing) on the top and bottom, not filling the entire screen.

### Root Causes

1. **Missing iOS Scene Configuration**: The project.pbxproj lacks critical iOS-specific keys that configure the app's scene lifecycle and launch screen.

2. **Conflicting macOS Settings**: macOS-specific build settings like `COMBINE_HIDPI_IMAGES`, `ENABLE_APP_SANDBOX`, and `ENABLE_HARDENED_RUNTIME` are incorrectly applied to the iOS build.

3. **Wrong SDK Root**: The build system defaults to `macosx` even when building for iOS, preventing proper SDK-specific configurations.

4. **Incorrect Framework Paths**: macOS uses `@executable_path/../Frameworks` while iOS uses `@executable_path/Frameworks`.

## Solution

Add SDK-specific settings to `Build.xcconfig` to override the default macOS configuration when building for iOS:

```xcconfig
# iOS-specific scene and launch configuration
INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*] = YES
INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*] = YES
INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*] = YES

# Ensure correct SDK is used for iOS builds
SDKROOT[sdk=iphone*] = iphoneos
SDKROOT[sdk=macos*] = macosx
```

### What Each Setting Does

- **UIApplicationSceneManifest_Generation**: Enables iOS 13+ scene-based app lifecycle, required for proper window management and layout.
- **UIApplicationSupportsIndirectInputEvents**: Allows the app to receive input from connected mice/keyboards on iPad, needed for multi-platform support.
- **UILaunchScreen_Generation**: Generates a proper launch screen configuration, essential for correct initial layout.
- **SDKROOT**: Explicitly sets the correct SDK root for each platform, preventing macOS defaults from interfering with iOS builds.

### Comparison with iOS-Only Projects

An iOS-only project created fresh includes these settings in `project.pbxproj` under the target's build configuration. A macOS→multiplatform project either lacks them entirely or doesn't apply them per-SDK, causing the iOS build to inherit macOS-centric settings.

## Key Takeaway

When converting a macOS project to support iOS, always add platform-specific configuration overrides to handle the fundamental differences between macOS and iOS app architectures. The `[sdk=iphone*]` and `[sdk=macos*]` syntax in xcconfig files enables conditional configuration per-platform.

---

## Code Review Checklist

When reviewing multiplatform iOS + macOS projects:

- [ ] iOS build settings don't inherit unwanted macOS-specific configurations
- [ ] `INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*]` set to YES
- [ ] `INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*]` set to YES
- [ ] `INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*]` set to YES
- [ ] `SDKROOT` explicitly set per-SDK: `[sdk=iphone*] = iphoneos` and `[sdk=macos*] = macosx`
- [ ] Framework paths correct per-platform (iOS: `@executable_path/Frameworks`, macOS: `@executable_path/../Frameworks`)
- [ ] macOS-specific settings like `COMBINE_HIDPI_IMAGES` not applied to iOS builds
- [ ] Hardening flags (`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`) scoped to macOS only
- [ ] No letterboxing or layout issues on iOS
- [ ] Both platforms tested with correct SDK and build settings
