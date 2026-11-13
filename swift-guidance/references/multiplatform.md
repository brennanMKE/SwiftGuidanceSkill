# Multiplatform iOS + macOS Project Setup

## Problem: Letterboxing on iOS

When starting an Xcode project as macOS-only and later adding iOS as a supported platform, the iOS app displays with black bars (letterboxing) on the top and bottom, not filling the entire screen.

### Root Causes

1. **Missing iOS Scene Configuration**: The project.pbxproj lacks critical iOS-specific keys that configure the app's scene lifecycle and launch screen.

2. **Conflicting macOS Settings**: macOS-specific build settings like `COMBINE_HIDPI_IMAGES`, `ENABLE_APP_SANDBOX`, and `ENABLE_HARDENED_RUNTIME` are incorrectly applied to the iOS build.

3. **Fixed SDK Root**: A target that started as macOS-only has `SDKROOT = macosx`. Xcode's multiplatform template instead uses `SDKROOT = auto` with `SUPPORTED_PLATFORMS` listing every platform, so the destination picks the SDK.

4. **Incorrect Framework Paths**: macOS uses `@executable_path/../Frameworks` while iOS uses `@executable_path/Frameworks`.

## Solution

Match what Xcode 27's multiplatform app template generates. In `Build.xcconfig`:

```xcconfig
# Let the run destination choose the SDK (same as Xcode's multiplatform template)
SDKROOT = auto
SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx
TARGETED_DEVICE_FAMILY = 1,2

# iOS-specific scene and launch configuration
# [sdk=iphone*] matches both iphoneos and iphonesimulator
INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*] = YES
INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*] = YES
INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*] = YES

# Per-platform framework search paths
LD_RUNPATH_SEARCH_PATHS[sdk=iphone*] = $(inherited) @executable_path/Frameworks
LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] = $(inherited) @executable_path/../Frameworks
```

Add `xros xrsimulator` to `SUPPORTED_PLATFORMS` and `7` to `TARGETED_DEVICE_FAMILY` for visionOS (the template's default is `iphoneos iphonesimulator macosx xros xrsimulator` / `1,2,7`).

Don't put an `[sdk=…]` condition on `SDKROOT` itself — `SDKROOT` is what determines the SDK the condition is evaluated against.

### What Each Setting Does

- **UIApplicationSceneManifest_Generation**: Enables iOS 13+ scene-based app lifecycle, required for proper window management and layout.
- **UIApplicationSupportsIndirectInputEvents**: Allows the app to receive input from connected mice/keyboards on iPad, needed for multi-platform support.
- **UILaunchScreen_Generation**: Generates a proper launch screen configuration, essential for correct initial layout.
- **SDKROOT = auto + SUPPORTED_PLATFORMS**: the run destination selects the SDK, so one target builds for every listed platform.
- **LaunchScreen generation is the letterboxing fix**: an iOS app without a launch screen runs in a legacy, letterboxed screen size.

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
- [ ] `SDKROOT = auto` with `SUPPORTED_PLATFORMS` listing each platform (no `[sdk=…]` condition on `SDKROOT`)
- [ ] Framework paths correct per-platform (iOS: `@executable_path/Frameworks`, macOS: `@executable_path/../Frameworks`)
- [ ] macOS-specific settings like `COMBINE_HIDPI_IMAGES` not applied to iOS builds
- [ ] Hardening flags (`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`) scoped to macOS only
- [ ] No letterboxing or layout issues on iOS
- [ ] Both platforms tested with correct SDK and build settings
