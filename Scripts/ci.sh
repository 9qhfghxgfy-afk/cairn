#!/usr/bin/env bash
# Cairn build entry point: the local equivalent of CI, and the same sequence CI runs, so a green
# local run and a green CI run mean the same thing.
#
# On a Mac this is the main loop: `Scripts/ci.sh all` is what CI would do, run locally in minutes
# instead of waiting for a runner. CI stays the second check. On Windows, where there is no Xcode,
# only `guards` and nothing else runs — that is expected, not a failure.
#
#   Scripts/ci.sh all        guards + domain tests + remote tests + generate + build + test
#   Scripts/ci.sh guards     privacy guards only (runs anywhere with bash, including Windows)
#   Scripts/ci.sh domain     swift test for the pure domain package (fast, macOS host)
#   Scripts/ci.sh remote     swift test for CairnProviderRemote (stub + loopback, no internet)
#   Scripts/ci.sh hosts      both host suites, which is what the CI host job runs
#   Scripts/ci.sh gen        xcodegen generate only
#   Scripts/ci.sh build      xcodegen + xcodebuild build for a simulator
#   Scripts/ci.sh test       xcodegen + xcodebuild test on a simulator
#   Scripts/ci.sh device     xcodegen + xcodebuild build for a real iPhone, signed with the Team ID
#                            from Config/Local.xcconfig (see docs/BUILD-MAC.md)
#   Scripts/ci.sh probe      print the toolchain, SDKs and simulator runtimes actually installed
set -euo pipefail

cd "$(dirname "$0")/.."

# On CI these are pinned (macos-26, Xcode 26.6, iPhone 17 / iOS 26.5). Locally they are whatever
# Xcode you installed: override with `XCODE_VERSION=`, `SIMULATOR_NAME=`, `SIMULATOR_OS=` or leave
# SIMULATOR_OS empty to take the newest runtime you have.
XCODE_VERSION="${XCODE_VERSION:-26.6}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_OS="${SIMULATOR_OS:-26.5}"
TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"
DERIVED="${DERIVED_DATA_PATH:-DerivedData}"

select_xcode() {
  local app="/Applications/Xcode_${XCODE_VERSION}.app"
  if [[ -d "$app" ]]; then
    # CI keeps several Xcodes side by side, so it switches by path. A local Mac normally has one
    # Xcode at /Applications/Xcode.app and needs no switch; `sudo` here only runs when the pinned
    # versioned app really is installed.
    sudo xcode-select -s "${app}/Contents/Developer"
  fi
  xcodebuild -version
}

# A local Mac will not have the exact runtime CI pins. Falling back to the device name alone lets
# xcodebuild pick the newest runtime that exists instead of failing on a version nobody installed.
resolve_destination() {
  if [[ -n "$SIMULATOR_OS" ]] && ! xcrun simctl list runtimes 2>/dev/null | grep -q "iOS ${SIMULATOR_OS}"; then
    echo "note: no iOS ${SIMULATOR_OS} runtime installed; using ${SIMULATOR_NAME} with its newest available runtime"
    SIMULATOR_OS=""
  fi
  if [[ -n "$SIMULATOR_OS" ]]; then
    TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"
  else
    TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME}"
  fi
  echo "test destination: ${TEST_DESTINATION}"
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
  Scripts/check-hostname.sh
  Scripts/check-signing.sh
  Scripts/test-guards.sh
}

domain_tests() {
  swift test --package-path Packages/CairnChatDomain
}

# URLSession, Keychain, and framing against a stub + a loopback server. Runs on the macOS
# host: none of these tests need a simulator, and none of them touch the real internet.
remote_tests() {
  swift test --package-path Packages/CairnProviderRemote
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

# The device lane is local-only: it signs with the Team ID in Config/Local.xcconfig, which CI does
# not have, so CI never runs it. It deliberately does NOT pass CODE_SIGNING_ALLOWED=NO — without a
# Local.xcconfig it should fail with a signing error rather than quietly produce an unsigned binary.
run_device() {
  xcodebuild \
    -project Cairn.xcodeproj \
    -scheme Cairn \
    -destination 'generic/platform=iOS' \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    build
}

run_tests() {
  resolve_destination
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
  remote)  select_xcode; remote_tests ;;
  hosts)   select_xcode; domain_tests; remote_tests ;;
  gen)     select_xcode; generate ;;
  build)   select_xcode; generate; run_build ;;
  device)  select_xcode; generate; run_device ;;
  test)    select_xcode; generate; run_tests ;;
  probe)   select_xcode; probe ;;
  all)     guards; select_xcode; probe; domain_tests; remote_tests; generate; run_build; run_tests ;;
  *) echo "unknown target: ${1:-all}" >&2; exit 2 ;;
esac
