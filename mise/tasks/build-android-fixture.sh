#!/usr/bin/env bash
# mise description="Builds the Android fixture app bundles"

set -euo pipefail

PROJECT_PATH="$MISE_PROJECT_ROOT/fixtures/android_app"

gradle --project-dir "$PROJECT_PATH" \
    :app:bundleReferenceLabelRelease \
    :app:bundleLiteralLabelRelease \
    :app:bundleNoLabelRelease

mv "$PROJECT_PATH/app/build/outputs/bundle/referenceLabelRelease/app-referenceLabel-release.aab" "$PROJECT_PATH/app.aab"
mv "$PROJECT_PATH/app/build/outputs/bundle/literalLabelRelease/app-literalLabel-release.aab" "$PROJECT_PATH/app-with-literal-label.aab"
mv "$PROJECT_PATH/app/build/outputs/bundle/noLabelRelease/app-noLabel-release.aab" "$PROJECT_PATH/app-without-label.aab"

rm -rf "$PROJECT_PATH/.gradle" "$PROJECT_PATH/build" "$PROJECT_PATH/app/build" "$PROJECT_PATH/library/build" "$PROJECT_PATH/local.properties"
