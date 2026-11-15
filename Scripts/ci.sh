#!/usr/bin/env bash
# Cairn build entry point. This is the same sequence CI runs, so a green CI run and a
# green local run mean the same thing.
#
#   Scripts/ci.sh all        guards + domain tests + generate + build + test  (default)
#   Scripts/ci.sh guards     privacy guards only
#   Scripts/ci.sh domain     swift test for the pure domain package (fast, macOS host)
#   Scripts/ci.sh build      xcodegen + xcodebuild build
#   Scripts/ci.sh test       xcodegen + xcodebuild test on a simulator
set -euo pipefail

cd "$(dirname "$0")/.."

XCODE_VERSION="${XCODE_VERSION:-26.6}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_OS="${SIMULATOR_OS:-26.5}"
TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"
DERIVED="${DERIVED_DATA_PATH:-DerivedData}"

select_xcode() {
  local app="/Applications/Xcode_${XCODE_VERSION}.app"
  if [[ -d "$app" ]]; then
    sudo xcode-select -s "${app}/Contents/Developer"
  fi
  xcodebuild -version
}

ensure_xcodegen() {
  if ! command -v xcodegen >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
  fi
  xcodegen --version
}

probe() {
  echo "--- toolchain probe ---"
  xcodebuild -version
  xcodebuild -showsdks | grep -i -E 'iphoneos|iphonesimulator' || true
  xcrun simctl list runtimes | grep -i ios || true
}

guards() {
  Scripts/check-logging.sh
  Scripts/check-ats.sh
}

domain_tests() {
  swift test --package-path Packages/CairnChatDomain
}

generate() {
  ensure_xcodegen
  xcodegen generate
}

run_build() {
  xcodebuild \
    -project Cairn.xcodeproj \
    -scheme Cairn \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

run_tests() {
  rm -rf ResultBundles
  mkdir -p ResultBundles
  xcodebuild \
    -project Cairn.xcodeproj \
    -scheme Cairn \
    -destination "$TEST_DESTINATION" \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath ResultBundles/Cairn.xcresult \
    CODE_SIGNING_ALLOWED=NO \
    test
}

case "${1:-all}" in
  guards)  guards ;;
  domain)  select_xcode; domain_tests ;;
  gen)     select_xcode; generate ;;
  build)   select_xcode; generate; run_build ;;
  test)    select_xcode; generate; run_tests ;;
  probe)   select_xcode; probe ;;
  all)     guards; select_xcode; probe; domain_tests; generate; run_build; run_tests ;;
  *) echo "unknown target: ${1:-all}" >&2; exit 2 ;;
esac
