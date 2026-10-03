#!/bin/zsh
# Build AI Limits and install it into ~/Applications.
set -e
cd "$(dirname "$0")"
xcodegen generate -q
xcodebuild -project AILimits.xcodeproj -scheme AILimits -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build | grep -E "error:|BUILD"
pkill -x "AI Limits" || true
mkdir -p ~/Applications
rm -rf ~/Applications/"AI Limits.app"
cp -R "build/Build/Products/Release/AI Limits.app" ~/Applications/
open ~/Applications/"AI Limits.app"
