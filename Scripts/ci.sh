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
#   Scripts/ci.sh local      swift test for CairnInferenceLocal (memory fit, catalog, downloads)
#   Scripts/ci.sh native     swift test for CairnInferenceNative (MLX excluded here; linked by default)
#   Scripts/ci.sh hosts      all four host suites, which is what the CI host job runs
#   Scripts/ci.sh gen        xcodegen generate only
#   Scripts/ci.sh build      xcodegen + xcodebuild build for a simulator (MLX excluded — a simulator
#                            cannot call it either way, see `export_simulator_build_env`)
#   Scripts/ci.sh test       xcodegen + xcodebuild test on a simulator (same exclusion)
#   Scripts/ci.sh device     xcodegen + xcodebuild build for a real iPhone, signed with the Team ID
#                            from Config/Local.xcconfig, with the MLX runtime linked (see docs/BUILD-MAC.md)
#   Scripts/ci.sh probe      print the toolchain, SDKs and simulator runtimes actually installed
set -euo pipefail

cd "$(dirname "$0")/.."

# On CI the destination is pinned by the workflow (macos-26, Xcode 26.6, iPhone 17 / iOS 26.5) and is
# never invented here. Locally it is the device the app is actually built for: iPhone 15 Pro, on the
# newest runtime this Mac has, created below if the machine has never had one. A local run and a CI run
# therefore mean the same thing on the same hardware shape. Override with `SIMULATOR_NAME=` /
# `SIMULATOR_OS=`; set SIMULATOR_OS to pin a runtime version explicitly.
if [[ -n "${CI:-}" ]]; then
  XCODE_VERSION="${XCODE_VERSION:-26.6}"
  SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
  SIMULATOR_OS="${SIMULATOR_OS:-26.5}"
else
  XCODE_VERSION="${XCODE_VERSION:-26.6}"
  SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 15 Pro}"
  SIMULATOR_OS="${SIMULATOR_OS:-}"
fi
TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME}"
if [[ -n "$SIMULATOR_OS" ]]; then
  TEST_DESTINATION="${TEST_DESTINATION},OS=${SIMULATOR_OS}"
fi
DERIVED="${DERIVED_DATA_PATH:-DerivedData}"

select_xcode() {
  local app="/Applications/Xcode_${XCODE_VERSION}.app"
  if [[ -d "$app" ]]; then
    # CI keeps several Xcodes side by side, so it switches by path. `sudo` here only runs when the
    # pinned versioned app really is installed, which is the CI case.
    sudo xcode-select -s "${app}/Contents/Developer"
  elif ! xcodebuild -version >/dev/null 2>&1; then
    # A local Mac normally has one Xcode at /Applications/Xcode.app, and `xcode-select` can still
    # point at the Command Line Tools right after an App Store install. Rather than demanding a
    # system-wide `sudo xcode-select -s`, point THIS process at the app with DEVELOPER_DIR, which
    # writes nothing to disk and cannot affect CI, where the versioned app above is what is selected.
    if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
      export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
      echo "note: active developer dir is not Xcode; using DEVELOPER_DIR=${DEVELOPER_DIR} for this run"
    fi
  fi

  local out
  if ! out="$(xcodebuild -version 2>&1)"; then
    # Fail with the fix attached, not with a tool error nobody can act on.
    echo "xcodebuild cannot run. Fix in this order:" >&2
    case "$out" in
      *"license agreement"*)
        echo "  1. sudo xcodebuild -license accept" >&2
        echo "  2. sudo xcodebuild -runFirstLaunch" >&2 ;;
      *)
        echo "  1. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2 ;;
    esac
    echo "detail: ${out%%$'\n'*}" >&2
    exit 1
  fi
  echo "$out"
}

# The Xcode license is a separate failure from a missing toolchain, and it is the one an App Store
# install leaves behind. It is checked on its own because `xcodebuild -version` succeeds without it
# while every SDK lookup, simulator listing, and build fails — a report of "no iOS runtime" in that
# state would send the reader to the wrong fix.
check_license() {
  local out
  out="$(xcrun simctl list runtimes 2>&1 || true)"
  case "$out" in
    *"license agreement"*)
      echo "the Xcode license has not been accepted, so SDKs and simulators are unavailable:" >&2
      echo "  sudo xcodebuild -license accept" >&2
      echo "  sudo xcodebuild -runFirstLaunch" >&2
      return 1 ;;
  esac
  return 0
}

# Creates the named simulator on a local Mac against the newest iOS runtime installed. `simctl create`
# with no runtime picks the newest compatible one, which is what a fresh Mac needs; the explicit-runtime
# retry covers an Xcode that refuses a device type it cannot match. This never runs on CI, where the
# pinned runtime and device are preinstalled and inventing a simulator would hide a real pin failure.
create_local_simulator() {
  local type_id runtime_id out
  type_id="com.apple.CoreSimulator.SimDeviceType.$(
    printf '%s' "$SIMULATOR_NAME" | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
  )"
  if ! xcrun simctl list devicetypes 2>/dev/null | grep -q "$type_id"; then
    echo "this Xcode has no '${SIMULATOR_NAME}' device type (looked for ${type_id})." >&2
    echo "  pick one that exists: SIMULATOR_NAME='iPhone 17e' Scripts/ci.sh test" >&2
    return 1
  fi
  if ! out="$(xcrun simctl create "$SIMULATOR_NAME" "$type_id" 2>&1)"; then
    runtime_id="$(xcrun simctl list runtimes 2>/dev/null \
      | grep -E '^iOS ' | tail -1 | sed -E 's/.* - //')"
    if [[ -z "$runtime_id" ]] || ! out="$(xcrun simctl create "$SIMULATOR_NAME" "$type_id" "$runtime_id" 2>&1)"; then
      # Device type and runtime identifiers are not personal; the user needs them to fix this.
      echo "could not create a '${SIMULATOR_NAME}' simulator: ${out%%$'\n'*}" >&2
      return 1
    fi
  fi
  echo "created a ${SIMULATOR_NAME} simulator for this machine."
}

# Which runtimes a named device actually exists on, one line each.
#
# `simctl list devices available` groups every device under a `-- iOS 26.5 (26.5) --` header, and a device
# type does not exist on every installed runtime: a Mac that carries iOS 26.2 and iOS 26.5 can hold
# `iPhone 15 Pro` only under 26.2 while `iPhone 17` exists only under 26.5. So "which runtime is newest"
# and "which runtime is my device on" are two different questions, and answering one with the other is how
# a destination gets built that no machine can resolve. The header line is the answer to the second one.
device_runtime_lines() {
  xcrun simctl list devices available 2>/dev/null | awk -v name="$1" '
    /^-- / { runtime = substr($0, 4); next }
    index($0, name " (") > 0 { print runtime }
  '
}

# The version out of a runtime line such as "iOS 26.5 (26.5)".
#
# One per line, which matters: the only caller pipes several of these into `sort -V`, and a version printed
# without its newline reaches that sort as "26.227.2" — a number that matches no runtime on any machine,
# which then fails the destination with "no available devices matched the request".
runtime_version() { printf '%s\n' "$1" | sed -E 's/^iOS ([0-9.]+).*/\1/'; }

# A local Mac will not have the exact runtime CI pins, and a device will not sit on the runtime its name
# happens to suggest. The destination is therefore built from what the pairing actually is: the named
# device plus the newest runtime that really has it, which is also what makes `OS=` explicit rather than
# leaving xcodebuild to guess a runtime the device was never created under.
resolve_destination() {
  # Before concluding anything about runtimes, rule out the license, which makes every runtime list
  # come back empty and would otherwise be reported as "no simulator runtime installed".
  check_license || exit 1
  local runtimes found newest
  runtimes="$(xcrun simctl list runtimes 2>/dev/null || true)"
  if ! printf '%s' "$runtimes" | grep -qi "iOS"; then
    # The usual fresh-Mac gap: Xcode installs with no simulator runtime at all, so every simulator
    # destination fails. Say it here, with the command that fixes it, before xcodebuild fails
    # cryptically. CI has its pinned runtime and is unaffected by this check.
    echo "no iOS simulator runtime is installed, so no simulator lane can run on this machine." >&2
    echo "  install one (check free space first: 'df -h /'):  xcodebuild -downloadPlatform iOS" >&2
    echo "  or skip the simulator and run the host suites:    Scripts/ci.sh hosts" >&2
    exit 1
  fi

  found="$(device_runtime_lines "$SIMULATOR_NAME")"
  if [[ -z "$found" ]] && [[ -z "${CI:-}" ]]; then
    # The target device for this project is a physical iPhone 15 Pro, so a Mac that has never had
    # that simulator gets one rather than a lane that quietly runs on a different screen size.
    create_local_simulator || exit 1
    found="$(device_runtime_lines "$SIMULATOR_NAME")"
  fi
  if [[ -z "$found" ]]; then
    echo "no '${SIMULATOR_NAME}' simulator on this machine. Available iOS simulators:" >&2
    xcrun simctl list devices available 2>/dev/null | grep -E '^    (iPhone|iPad)' | sed 's/ (.*//' \
      | sort -u | head -8 >&2
    echo "  choose one with: SIMULATOR_NAME='iPhone 15' Scripts/ci.sh test" >&2
    echo "  CI stays pinned to iPhone 17 / iOS 26.5 whatever is chosen here." >&2
    exit 1
  fi

  # A pinned runtime is honoured only when this device really exists on it. On CI that is the pin, so a
  # mismatch is a runner problem and must stop the lane rather than be papered over with a different
  # runtime; locally it is a machine that has moved on, which is noted and then worked around.
  if [[ -n "$SIMULATOR_OS" ]] && printf '%s\n' "$found" | grep -q "iOS ${SIMULATOR_OS}"; then
    TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"
    echo "test destination: ${TEST_DESTINATION}"
    return
  fi
  if [[ -n "${CI:-}" ]]; then
    echo "CI pins ${SIMULATOR_NAME} on iOS ${SIMULATOR_OS}, but this runner has that device on:" >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
    exit 1
  fi
  if [[ -n "$SIMULATOR_OS" ]]; then
    echo "note: no iOS ${SIMULATOR_OS} runtime holds a '${SIMULATOR_NAME}' here; using its newest one"
  fi
  newest="$(printf '%s\n' "$found" | while IFS= read -r line; do runtime_version "$line"; done \
    | sort -V | tail -1)"
  if [[ -z "$newest" ]]; then
    # A device line whose runtime is not an iOS version cannot be turned into an OS= component; let
    # xcodebuild resolve the name alone rather than inventing a version.
    TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME}"
  else
    TEST_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${newest}"
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
  # Prints the fix once, rather than letting two SDK lookups each print the same license error.
  check_license || true
  xcodebuild -showsdks 2>/dev/null | grep -i -E 'iphoneos|iphonesimulator' || true
  xcrun simctl list runtimes 2>/dev/null | grep -i ios || true
}

guards() {
  # Invoked through `bash` on purpose: the exec bit survives a normal clone, but a Windows checkout
  # or a zip transfer can drop it, and the guards are the one lane that must run on every machine.
  # CI already calls them as `bash Scripts/check-*.sh`; this keeps the two entry points equivalent.
  bash Scripts/check-logging.sh
  bash Scripts/check-ats.sh
  bash Scripts/check-hostname.sh
  bash Scripts/check-signing.sh
  bash Scripts/check-no-paywall.sh
  # Not a privacy guard — a compile-reliability guard, and the one thing here that catches an error
  # the Windows authoring machine cannot see at all. A hand-written `var something: some View` does
  # not inherit the result builder that `View.body` gets from the protocol, so a second sibling view
  # added to such a body is a build failure six minutes into a macOS run. It failed CI 44660409341
  # exactly that way; this finds the next one before the build instead.
  bash Scripts/check-viewbuilder.sh
  bash Scripts/test-guards.sh
}

domain_tests() {
  swift test --package-path Packages/CairnChatDomain
}

# URLSession, Keychain, and framing against a stub + a loopback server. Runs on the macOS
# host: none of these tests need a simulator, and none of them touch the real internet.
remote_tests() {
  swift test --package-path Packages/CairnProviderRemote
}

# Memory fit, single-resident eviction, the curated catalog, repo-ID rules, checksum
# verification and the Foundation Models availability mapping. Host-only by design.
local_tests() {
  swift test --package-path Packages/CairnInferenceLocal
}

# The Swift 5 isolation island. Run with MLX excluded on purpose: linking mlx-swift-lm compiles
# swift-syntax macros and a vendored C++ engine from source, which is a long build on an 8 GB Mac and is
# not what a host test of the parser or the shapes needs. The package now links MLX **by default** (see
# `Packages/CairnInferenceNative/Package.swift`), so this lane is the one that has to say it wants the
# excluded shape. `CAIRN_MLX=1 Scripts/ci.sh native` is the linked shape, which is what a device build
# and an Xcode ⌘R get.
native_tests() {
  if [[ "${CAIRN_MLX:-}" == "1" ]]; then
    swift test --package-path Packages/CairnInferenceNative
  else
    CAIRN_SKIP_MLX=1 swift test --package-path Packages/CairnInferenceNative
  fi
}

# The simulator lanes drop MLX, and they say so here rather than inheriting the package default.
# `MLXNativeEngine` is compiled out on a simulator by `targetEnvironment(simulator)` no matter what is
# linked, so linking it there would buy a long C++/Metal build for a runtime the binary cannot call — and
# nobody has yet proved MLX compiles for arm64-simulator at all. The device lane below is the lane that
# links it, which is also the shape a person runs on a phone.
export_simulator_build_env() {
  export CAIRN_SKIP_MLX=1
}

generate() {
  ensure_xcodegen
  xcodegen generate
}

run_build() {
  export_simulator_build_env
  # CI builds against a generic simulator destination, exactly as the workflow does, so this lane can
  # never depend on a device that happens to exist. Locally it builds for the target device by name,
  # which is what catches a layout that only breaks on iPhone 15 Pro's screen.
  if [[ -n "${CI:-}" ]]; then
    xcodebuild \
      -project Cairn.xcodeproj \
      -scheme Cairn \
      -destination 'generic/platform=iOS Simulator' \
      -configuration Debug \
      -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO \
      build
    return
  fi
  resolve_destination
  xcodebuild \
    -project Cairn.xcodeproj \
    -scheme Cairn \
    -destination "$TEST_DESTINATION" \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

# The device lane is local-only: it signs with the Team ID in Config/Local.xcconfig, which CI does
# not have, so CI never runs it. It deliberately does NOT pass CODE_SIGNING_ALLOWED=NO — without a
# Local.xcconfig it should fail with a signing error rather than quietly produce an unsigned binary.
#
# It also clears `CAIRN_SKIP_MLX`, which no other lane may do. This is the build a person installs on a
# phone, so it is the build that has to carry the on-device runtime; an inherited skip here is exactly how
# an iPhone ended up told that the runtime "is not in this build".
run_device() {
  unset CAIRN_SKIP_MLX
  xcodebuild \
    -project Cairn.xcodeproj \
    -scheme Cairn \
    -destination 'generic/platform=iOS' \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    build
}

run_tests() {
  export_simulator_build_env
  resolve_destination
  rm -rf ResultBundles
  mkdir -p ResultBundles
  # A booted simulator keeps running after the run and eats RAM the next build needs, which on an
  # 8 GB Mac is the difference between a fast test lane and a swap storm. Shut it down even when the
  # tests fail, so a red run does not leave the machine loaded.
  if [[ -n "${CI:-}" ]]; then
    xcodebuild \
      -project Cairn.xcodeproj \
      -scheme Cairn \
      -destination "$TEST_DESTINATION" \
      -configuration Debug \
      -derivedDataPath "$DERIVED" \
      -resultBundlePath ResultBundles/Cairn.xcresult \
      CODE_SIGNING_ALLOWED=NO \
      test
    return
  fi
  local status=0
  xcodebuild \
    -project Cairn.xcodeproj \
    -scheme Cairn \
    -destination "$TEST_DESTINATION" \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath ResultBundles/Cairn.xcresult \
    CODE_SIGNING_ALLOWED=NO \
    test || status=$?
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  return "$status"
}

case "${1:-all}" in
  guards)  guards ;;
  domain)  select_xcode; domain_tests ;;
  remote)  select_xcode; remote_tests ;;
  local)   select_xcode; local_tests ;;
  native)  select_xcode; native_tests ;;
  hosts)   select_xcode; domain_tests; remote_tests; local_tests; native_tests ;;
  gen)     select_xcode; generate ;;
  build)   select_xcode; generate; run_build ;;
  device)  select_xcode; generate; run_device ;;
  test)    select_xcode; generate; run_tests ;;
  probe)   select_xcode; probe ;;
  all)     guards; select_xcode; probe; domain_tests; remote_tests; local_tests; native_tests; generate; run_build; run_tests ;;
  *) echo "unknown target: ${1:-all}" >&2; exit 2 ;;
esac
