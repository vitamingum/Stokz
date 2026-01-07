# AI Context - Stokz

## MUST DO
- **Always add logging** when debugging issues
- **Always tail logs after deployment** to verify changes
- **Always debug with logs** - don't guess, check the output

## Build & Deploy

```bash
# Build + Install (one command)
cd /Users/charlesburns/Stokz && \
xcodebuild -scheme Stokz -destination 'id=00008150-001E08190A38401C' -configuration Debug -quiet && \
xcrun devicectl device install app --device 00008150-001E08190A38401C \
  /Users/charlesburns/Library/Developer/Xcode/DerivedData/Stokz-bazhfupqpoomaxbihkzdvidadyrf/Build/Products/Debug-iphoneos/Stokz.app
```

## Logs

```bash
# Stream live
log stream --predicate 'process == "Stokz"' --info --debug

# Recent logs
log show --predicate 'process == "Stokz"' --last 2m --info --debug
```

## Fastlane (TestFlight)

```bash
fastlane beta  # Build + upload to TestFlight
```

Then commit build number bump and push.

## Key IDs

- **Bundle**: `com.stokz.app`
- **Team**: `MSW9JQ3H2Q`
- **App Store**: `6757373916`
- **Device**: `00008150-001E08190A38401C`

## TestFlight Compliance

```bash
open "https://appstoreconnect.apple.com/apps/6757373916/testflight/ios"
```
