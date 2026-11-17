#!/usr/bin/env bash
#
# ui-shots.sh — renders every opt-in screenshot suite offscreen into one folder.
#
#   ./scripts/ui-shots.sh /tmp/ui-before     # on the base commit
#   ./scripts/ui-shots.sh /tmp/ui-after      # on the branch
#   python3 scripts/png-diff.py /tmp/ui-before /tmp/ui-after
#
# Each suite writes to <out>/<ENV_VAR>/. Views render through OffscreenRender, so no window opens and
# the desktop focus is untouched. A suite that cannot render offscreen belongs out of this list.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?output directory}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Suites that host a view in a window (OffscreenRender.windowHosting) are left out on purpose:
# CollectionReadability, DexBackNavigation, EvolutionStone, HomeFit, SnapshotHistory, TradeBeforeAfter, ZeroUsage.
SUITES=(
  "PTB_BALANCE_SHOT_DIR:EntryBalanceScreenshotTests"
  "PTB_BATTLEINFO_SCREENSHOT_DIR:BattleInfoScreenshotTests"
  "PTB_BATTLEPICKER_SCREENSHOT_DIR:BattlePickerScreenshotTests"
  "PTB_BOXDEX_SHOTS:BoxDexScreenshotTests"
  "PTB_BOXSLOT_SCREENSHOT_DIR:BoxSlotScreenshotTests"
  "PTB_BUBBLE_SHOT_DIR:BubbleScreenshotTests"
  "PTB_CENTER_SCREENSHOT_DIR:HomeCenterScreenshotTests"
  "PTB_DAYNIGHT_SHOT_DIR:DayNightScreenshotTests|DayNightLabelTests"
  "PTB_DEXSEARCH_SCREENSHOT_DIR:DexUnownedScreenshotTests"
  "PTB_EVO_SHOT_DIR:EvolutionShotTests"
  "PTB_FLAVOR_SCREENSHOT_DIR:DexFlavorScreenshotTests"
  "PTB_FRIENDS_SCREENSHOT_DIR:FriendsScreenshotTests"
  "PTB_GENDER_SCREENSHOT_DIR:GenderScreenshotTests"
  "PTB_HEADER_SHOT_DIR:HomeHeaderScreenshotTests"
  "PTB_HELD_SCREENSHOT_DIR:HeldItemScreenshotTests"
  "PTB_ITEM_LORE_SCREENSHOT_DIR:ItemLoreScreenshotTests"
  "PTB_MEGA_SCREENSHOT_DIR:MegaScreenshotTests"
  "PTB_MEGA_SPRITE_SHOT_DIR:MegaSpriteScreenshotTests"
  "PTB_PETTING_RENDER_DIR:FloatingPetPettingRenderingTests"
  "PTB_PRAYER_RENDER_DIR:EggPrayerRenderTests"
  "PTB_README_SHOT_DIR:ReadmeScreenshotTests"
  "PTB_REGION_REWARD_SHOT_DIR:DexRegionRewardScreenshotTests"
  "PTB_SCOUT_SCREENSHOT_DIR:ScoutScreenshotTests"
  "PTB_SCREENSHOT_DIR:GenerationDexScreenshotTests|ScreenshotGenTests"
  "PTB_SHOP_SCREENSHOT_DIR:ShopCategoryScreenshotTests"
  "PTB_SULK_RENDER_DIR:SulkRenderTests"
  "PTB_TABBAR_SHOT_DIR:TabBarScreenshotTests"
  "PTB_TRADE_SCREENSHOT_DIR:TradeItemLockShotTests|TradeScreenshotTests"
)

FILTER=""
for entry in "${SUITES[@]}"; do
  var="${entry%%:*}"
  classes="${entry#*:}"
  mkdir -p "$OUT/$var"
  export "$var=$OUT/$var"
  FILTER="${FILTER:+$FILTER|}$classes"
done

PTB_NATIVE_ARCH_ONLY="${PTB_NATIVE_ARCH_ONLY:-1}" ./scripts/swift-test-filter.py --filter "$FILTER"
find "$OUT" -name '*.png' | wc -l | xargs echo "PNG files:"
