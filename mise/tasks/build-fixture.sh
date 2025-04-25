#!/usr/bin/env bash
# mise description="Bundles the CLI for distribution"
#USAGE arg "<fixture>" help="The fixture to build"

set -euo pipefail

PROJECT_PATH="$MISE_PROJECT_ROOT/fixtures/$usage_fixture"
rm -rf "$PROJECT_PATH/App.app" "$PROJECT_PATH/App.xcarchive" "$PROJECT_PATH/App.ipa"

xcodebuild build -scheme App -destination 'generic/platform=iOS' -project "$PROJECT_PATH/App.xcodeproj" -derivedDataPath "$PROJECT_PATH/.build"

mv "$PROJECT_PATH/.build/Build/Products/Debug-iphoneos/App.app" "$PROJECT_PATH/App.app"

xcodebuild archive -project "$PROJECT_PATH/App.xcodeproj" -scheme App -sdk iphoneos -destination "generic/platform=iOS" -archivePath "$PROJECT_PATH/App.xcarchive"

xcodebuild -exportArchive -archivePath "$PROJECT_PATH/App.xcarchive" -exportOptionsPlist "$PROJECT_PATH/App.xcarchive/Info.plist" -exportPath "$PROJECT_PATH/.build/ExportedApp"
mv "$PROJECT_PATH/.build/ExportedApp/App.ipa" "$PROJECT_PATH/App.ipa"
rm -rf "$PROJECT_PATH/.build"
