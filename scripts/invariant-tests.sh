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
# Add a test here when it reads files under Sources/ or Tests/, reflects over a model's fields, or
# sweeps AppLanguage.allCases. A test method whose name ends in ...InEveryLanguage /
# ...InEverySupportedLanguage / ...EveryLanguage is picked up by the name rule below with no edit.
# The drift check fails when a test method does one of those things and neither it nor its class is
# listed; a class-level helper that does it needs the class or one of its methods listed.
set -euo pipefail
cd "$(dirname "$0")/.."

# Whole classes.
CLASSES=(
  SwiftUIIsolationTests            # every View/App struct is @MainActor
  NoOCRInTestsGuardTests           # no test reads rendered text with OCR
  PinnedSpriteGuardTests           # no test seeds the evictable sprite cache
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
  EvolutionMappingDocTests         # docs/reference/evolution-mapping.md matches the rule table
  WorkflowInvariantTests           # self-hosted runs-on guard, ci-ok/bot-ok allow-lists, .xcode-version
  OffscreenRenderGuardTests        # no test shows a window or activates the app
  DesignTokenScanTests             # no raw Color(red:, numeric font size or corner radius outside UI/Design
  SpeciesFactsGuardTests           # no test hand-builds species facts; the table matches the games
  GymTermGuardTests                # no Korean UI string says 도장
  RarityNameTests                  # tier names in every language and the READMEs
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
  BoxTests/testOnlyTheBoxDetailSlotChangesHeldItemsFromTheUI
  BoxTests/testNoCatchLogViewOrNavigationRemains
  BoxTests/testNoCatchLogStringRemainsInAnyLanguage
  TradeBoxPickerTests/testTheBoxDetailKeepsTheRefusalGateAndNeverLeavesForTheFriendsTab
  SettingsTabsTests/testBattleViewNoLongerOwnsTheTokenField
  KiroUsageTests/testSkipStateIsPassedByTheCallerNotHeldByTheReader
  AntigravityUsageTests/testEntriesWithoutRootsGoesThroughResolvedRoots
  CredentialSwitchCacheTests/testAntigravityUserRefreshAlsoBypassesStillValidCache
  SaveTransferTests/testEveryCompanionStateFieldIsClassifiedForTransfer
  GymModelTests/testGymViewsNeverShowTheBotsRegionName
  GymModelTests/testRegionNamesFollowTheAppLanguageNotTheBotsKoreanName
  # Language sweeps the name rule does not catch.
  ActivityVisualizationTests/testTitleStatesTheWindowLength
  AdditionalClaudeAccountsStoreTests/testTheBubbleDropsAnAccountThatDoesNotFit
  BoxTests/testBattleTabKeepsRecentBattlesButNoConnectionTradeOrCoworkers
  BoxTests/testCoworkersTabListsCoworkersAndOffersATradeWhenConnected
  BoxTests/testDexDetailOffersTheBoxCountAndNoIndividualControls
  BoxTests/testDisconnectedCoworkersTabPointsAtTheSettingsConnectionInsteadOfDuplicatingIt
  BoxTests/testOpeningTheOfferWithAGivePreselectedLandsOnCoworkersWithTheSummary
  BoxTests/testTheSelectedTabIsTheOnlyOneThatSpellsItsNameAndEveryTabHasATooltipSource
  CompanionIdentityTests/testLocalizationIncludesDelayedHatchRetry
  CompanionIdentityTests/testNatureNamesComplete
  CompanionIdentityTests/testSystemDefaultLanguageResolves
  DailyTrendStackTests/testTheLegendWrapsWithinThePopoverWidth
  DifficultyTests/testFirstRunEggHintShowsTheScaledHatchPoint
  EggPrayerTests/testDetailCopy
  EvolutionCardTests/testEveryRuleIsTranslatedNotCopiedFromEnglish
  FloatingPetAgentTests/testAgentBubbleTextNeverTruncates
  FloatingPetAgentTests/testLimitBubbleContentIsUnchanged
  FloatingPetEnergyTests/testLocalizedAlertBubbleFitsDefaultPanel
  MegaSpriteSurfaceTests/testTheStoneHintNamesWhereTheMegaFormShows
  PaceTierTests/testDeltaTextCarriesNoSignAndSkipsZero
  PetEventLineTests/testEvolutionLineNamesBothWithTheRightKoreanParticles
  PokeAPILanguageTests/testFetchedLanguageCodesMatchAppLanguageAPICodesWithoutDuplicates
  PokemonNameLocalizationTests/testRenderedNamesResolveLanguageAndEnglishFallbackWithoutChangingKeys
  PokemonNameLocalizationTests/testSelectedLanguageThenEnglishWithCurrentAndLegacyCodes
  RepresentativeFooterLayoutTests/testRepresentativeActionStaysIconWidthInEveryLocaleAndState
  SaveTransferTests/testImportErrorMessagesAreLocalizedNotRawSwiftText
  ShinyCharmTests/testShinyDittoRevealDoesNotClaimFixedOdds
  ShinyCharmTests/testShinyNotificationShowsTheOddsTheHatchUsed
  UsageCostTests/testNativeCostRenderingAndAllLocalizedStates
  UsageCostTests/testPlainDollarFormattingAcrossCoverageAndLanguages
)

# Language sweeps, by method name.
NAME_RULE='/test\w*(InEvery(Supported)?Language|EveryLanguage|AllLanguages)\w*$'

# Methods the drift check flags that only touch their own fixtures (Class/method).
NOT_INVARIANT=(
  ClaudeSessionIDTests/testParsedAndCachedEntriesCarryTheirSession   # walks its own temporary folder
  # Opt-in PR captures: they skip unless their screenshot directory is set.
  BoxDexScreenshotTests/testCaptureBoxDexScreens
  CollectionReadabilityRenderingTests/testGenerateCollectionReadabilityEvidence
  HomeHeaderScreenshotTests/testCaptureHomeHeader
  TabBarScreenshotTests/testCaptureFriendsTabSelected
)

# What makes a test repo-wide: reading Sources/ or Tests/, reflecting over a model, sweeping languages.
TRIGGER='"Sources|repositoryFile\(|Mirror\(reflecting:|AppLanguage\.allCases|enumerator\(at:'

# Prints "<scope> <Class> <method> <file:line>" per trigger; scope is method, class (a helper) or file.
scan_triggers() {
  TRIGGER="$TRIGGER" awk '
    BEGIN { trigger = ENVIRON["TRIGGER"] }
    FNR == 1 { cls = ""; fn = "-"; scope = "file" }
    /^[A-Za-z@]/ { cls = ""; fn = "-"; scope = "file" }
    /^(@MainActor )?(final )?class [A-Za-z0-9_]+: XCTestCase/ {
      match($0, /class [A-Za-z0-9_]+/); cls = substr($0, RSTART + 6, RLENGTH - 6); scope = "class"
    }
    /^(@MainActor )?extension [A-Za-z0-9_]+Tests[ {]/ {
      match($0, /extension [A-Za-z0-9_]+/); cls = substr($0, RSTART + 10, RLENGTH - 10); scope = "class"
    }
    /^    [^ ]/ && cls != "" {
      if (match($0, /func test[A-Za-z0-9_]*/)) { fn = substr($0, RSTART + 5, RLENGTH - 5); scope = "method" }
      else { fn = "-"; scope = "class" }
    }
    { code = $0; sub(/\/\/.*$/, "", code) }
    code ~ trigger { printf "%s %s %s %s:%d\n", scope, (cls == "" ? "-" : cls), fn, FILENAME, FNR }
  ' Tests/PokeTokenBarTests/*.swift
}

covered() {
  local scope=$1 class=$2 method=$3
  case "$scope" in
    method)
      printf '%s\n' "${CLASSES[@]}" "${METHODS[@]}" "${NOT_INVARIANT[@]}" | grep -qxE "$class|$class/$method" ||
        printf '/%s\n' "$method" | grep -qE "$NAME_RULE" ;;
    class) printf '%s\n' "${CLASSES[@]}" "${METHODS[@]}" | grep -qE "^$class(/|$)" ;;
    *) return 1 ;;
  esac
}

triggers=$(scan_triggers | sort -u -k1,3)
[ -n "$triggers" ] || { echo "invariant-tests.sh: the drift scan found nothing; it is broken" >&2; exit 2; }
drift=0
while read -r scope class method where; do
  file=${where%%:*}
  if [ "$scope" = file ]; then
    classes=$(grep -oE 'class [A-Za-z0-9_]+: XCTestCase' "$file" | awk '{print $2}' | tr -d ':')
    for c in $classes; do covered class "$c" - && continue 2; done
    echo "invariant-tests.sh: $where is repo-wide file-level code and no class in its file is listed" >&2
    drift=1
  elif ! covered "$scope" "$class" "$method"; then
    if [ "$scope" = method ]; then
      echo "invariant-tests.sh: $where — $class/$method is repo-wide but not listed" >&2
    else
      echo "invariant-tests.sh: $where — a helper in $class is repo-wide but nothing in $class is listed" >&2
    fi
    drift=1
  fi
done <<< "$triggers"
[ "$drift" = 0 ] || { echo "Add the class or method to scripts/invariant-tests.sh." >&2; exit 2; }

stale=0
for entry in "${CLASSES[@]}" "${METHODS[@]}" "${NOT_INVARIANT[@]}"; do
  class=${entry%%/*}
  if ! grep -qE "class $class: XCTestCase" Tests/PokeTokenBarTests/*.swift ||
     { [ "$entry" != "$class" ] && ! grep -q "func ${entry##*/}(" Tests/PokeTokenBarTests/*.swift; }; then
    echo "invariant-tests.sh: $entry is listed but no longer exists" >&2
    stale=1
  fi
done
[ "$stale" = 0 ] || { echo "Remove the entry from scripts/invariant-tests.sh." >&2; exit 2; }

regex="$NAME_RULE"
for c in "${CLASSES[@]}"; do regex+="|^PokeTokenBarTests\\.$c/"; done
for m in "${METHODS[@]}"; do regex+="|^PokeTokenBarTests\\.${m%%/*}/${m##*/}\$"; done

echo "▶ swift test --filter (repo-wide invariants)"
exec ./scripts/swift-test-filter.py --filter "$regex"
