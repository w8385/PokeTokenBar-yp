#!/usr/bin/env bash
#
# invariant-tests.sh — the repo-wide tests that a focused `swift test --filter <Suite>` never runs.
#
# These walk every Swift source, every localization or every language, so adding a view, a string or
# a provider can break one of them from a suite that looks unrelated (a SwiftUI view without
# @MainActor failed SwiftUIIsolationTests on CI while the author's own suite was green).
# Run this and your own filter before every push:
#
#   ./scripts/invariant-tests.sh
#
# Add a test here when it reads files under Sources/ or sweeps AppLanguage.allCases. A test method
# whose name ends in ...InEveryLanguage / ...InEverySupportedLanguage / ...EveryLanguage is picked up
# by the name rule below with no edit. The drift check at the end fails when a test file reads
# Sources/PokeTokenBar but none of its classes is listed.
set -euo pipefail
cd "$(dirname "$0")/.."

# Whole classes.
CLASSES=(
  SwiftUIIsolationTests            # every View/App struct is @MainActor
  ScrollerLaneTests                # every vertical ScrollView reserves the scroller lane
  LocalizedUILiteralTests          # no Hangul literals in UI sources
  LocalizationColumnTests          # es/pt columns not swapped in Localization.swift
  LocalizationInterpolationTests   # every language keeps its placeholders
  LocalizationErrorsTests
  LanguageSurfaceRegressionTests   # UI copy routed through localization
  UsageEnvironmentTests            # env keys registered, providers do not read them directly
  LiveCredentialCallGateTests      # networking limit providers are gated
  AppLogTests                      # logging call sites use the flushing writer
  ItemLoreTests                    # every item has official text and name in every language
  EvolutionRulesTests              # every special evolution step in the fixture has an app rule
)

# Single methods of classes that are otherwise unrelated (Class/method).
METHODS=(
  CustomScanRootsTests/testEveryRegisteredProviderConsultsItsOwnCustomScanRootsKey
  CustomScanRootsTests/testSettingsUsesProviderPickerAndCommitsOnSubmit
  CustomScanRootsTests/testSetCustomScanRootsInvalidatesAdditionalProviderCache
  CustomScanRootsTests/testComputeFunctionsDefaultCustomRootsValueToNil
  LimitPaceTests/testEveryPopoverLimitBarFollowsTheDisplayMode
  FloatingPetEnergyTests/testFloatingPetReadsTheEffectiveFloor
  PopoverNavigationTests/testPopoverFooterTogglesFloatingPetWithoutOpeningSettings
  KiroUsageTests/testSkipStateIsPassedByTheCallerNotHeldByTheReader
  AntigravityUsageTests/testEntriesWithoutRootsGoesThroughResolvedRoots
  CredentialSwitchCacheTests/testAntigravityUserRefreshAlsoBypassesStillValidCache
)

# Language sweeps, by method name.
NAME_RULE='/test\w*(InEvery(Supported)?Language|EveryLanguage|AllLanguages)\w*$'

listed() { printf '%s\n' "${CLASSES[@]}" "${METHODS[@]}"; }

drift=0
for file in $(grep -l 'Sources/PokeTokenBar' Tests/PokeTokenBarTests/*.swift); do
  classes=$(grep -oE 'class [A-Za-z0-9_]+: XCTestCase' "$file" | awk '{print $2}' | tr -d ':')
  found=0
  for c in $classes; do
    if listed | grep -qE "^$c(/|$)"; then found=1; fi
  done
  if [ "$found" = 0 ]; then
    echo "invariant-tests.sh: $file reads Sources/PokeTokenBar but none of its classes ($(echo $classes)) is listed" >&2
    drift=1
  fi
done
[ "$drift" = 0 ] || { echo "Add the class or method to scripts/invariant-tests.sh." >&2; exit 2; }

regex="$NAME_RULE"
for c in "${CLASSES[@]}"; do regex+="|^PokeTokenBarTests\\.$c/"; done
for m in "${METHODS[@]}"; do regex+="|^PokeTokenBarTests\\.${m%%/*}/${m##*/}\$"; done

echo "▶ swift test --filter (repo-wide invariants)"
exec swift test --filter "$regex"
