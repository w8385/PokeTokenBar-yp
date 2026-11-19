"use strict";
// Mirrors Sources/PokeTokenBar/Core/PokemonBalance.swift; npm test compares them with origin/main.
const BALANCE = {
  graduationTotal: {common: 15e6, uncommon: 37.5e6, rare: 60e6, legendary: 120e6},
  eggHatchThreshold: 100e3,
  repeatGrowthMultiplier: 2,
  timeTokensPerActiveSecond: 25e3,
  timeIdleLimitSeconds: 5 * 60,
  timeMaxStepSeconds: 2 * 60,
  idleTokenHintAfterSeconds: 3 * 86400,
  tokensPerPet: 50e3
};
function formatTokens(n) {
  const [unit, size] = n >= 1e9 ? ['B', 1e9] : n >= 1e6 ? ['M', 1e6] : ['k', 1e3];
  return +(n / size).toFixed(2) + unit;
}
const I18N = {
  "en": {
    "skip": "Skip to content",
    "nav.install": "Install",
    "nav.menu": "Menu",
    "theme": "Switch color theme",
    "aria.nav": "Main navigation",
    "aria.project": "Project links",
    "aria.guide": "Field guide",
    "aria.table": "Growth and collection details",
    "hero.h1a": "Your tokens.",
    "hero.h1b": "A little companion.",
    "hero.lead": "A Pokémon that grows as you code. Track your AI token usage and limits, right from your Mac’s menu bar.",
    "hero.install": "Get PokeTokenBar",
    "hero.preview": "Meet the app",
    "hero.compat": "Free · macOS 14+ · Apple Silicon",
    "hero.note": "The tokens you already use become progress. Your usual workflow, with a little company.",
    "demo.caption": "Your menu bar, with company.",
    "native.home": "Native UI · sample data · English",
    "alt.home": "Native Home sample with an incubating egg, token totals, a streak badge and the selected-period activity chart",
    "install.title": "Make room for\na little company.",
    "install.intro": "You’ll need an Apple Silicon Mac with macOS 14 or later. No AI coding tool? Time mode grows your partner while you work. No PokeTokenBar account needed.",
    "install.homebrew": "Install from Terminal",
    "install.step1": "Open Terminal on your Mac. Quit PokeTokenBar first if it is running.",
    "install.step2": "Copy and run the command below.",
    "install.step3": "PokeTokenBar installs into Applications and opens. Your progress is kept.",
    "install.direct": "Prefer a direct download?",
    "install.zip": "Download ZIP for macOS",
    "install.unzip": "Unzip PokeTokenBar-yp-arm64.zip and move PokeTokenBar.app into Applications.",
    "install.gate": "The app is self-signed. If macOS blocks the first launch, follow the Gatekeeper steps in the installation guide. The Terminal command clears the quarantine attribute for you.",
    "install.help": "Open installation guide",
    "copy": "Copy command",
    "copy.pending": "Copying…",
    "copy.ok": "Copied. Paste it into Terminal to install.",
    "copy.error": "Couldn’t copy. Select the command above and copy it manually.",
    "growth.title": "Your coding grows a Pokémon.",
    "growth.play": "Play animation",
    "growth.pause": "Pause animation",
    "growth.desc": "The tokens you use with AI coding tools hatch an egg and grow your partner. Keep coding, watch it evolve, and keep each graduated Pokémon in your collection.",
    "growth.egg": "Start with an egg",
    "growth.eggDesc": "Your first tokens bring you closer to hatching.",
    "growth.first": "Meet your partner",
    "growth.firstDesc": "An egg hatches into a surprise Pokémon.",
    "growth.evolve": "Code. Grow. Evolve.",
    "growth.evolveDesc": "Used tokens advance its evolution line.",
    "growth.collect": "Keep it in your Pokédex",
    "growth.collectDesc": "Graduate your partner and welcome a new egg.",
    "growth.note": "Illustration: Bulbasaur’s evolution line. Your partner and growth pace vary. No extra AI requests are made to grow a Pokémon.",
    "modes.title": "Two ways to grow.",
    "modes.desc": "Choose the growth source in Settings and switch any time. Progress you have already banked stays the same in both modes.",
    "modes.tokenTag": "Token mode · default",
    "modes.tokenT": "Grow with your AI coding",
    "modes.tokenD": "Every token your coding agents use counts, cache reads included. The same tokens fill your Shop wallet.",
    "modes.tokenFit": "Suits heavy agent users.",
    "modes.timeTag": "Time mode",
    "modes.timeT": "Grow while you work",
    "modes.timeRate": "Each active second adds 25k growth tokens and 25k Shop tokens, 90M of each per active hour.",
    "modes.timeIdle": "You count as active if you used the keyboard or mouse in the last 5 minutes. One check credits at most 2 minutes.",
    "modes.timeOnly": "AI token usage earns nothing in this mode.",
    "modes.timeFit": "Suits light users, or anyone without an AI coding tool.",
    "modes.hint": "No token usage for 3 days? The app suggests time mode in Settings.",
    "modes.clickT": "Click to help.",
    "modes.clickD": "In either mode, clicking the big sprite on Home or the floating pet adds 50k growth tokens. About 300 clicks take a Normal line from egg to graduation.",
    "badge.fork": "Only in PokeTokenBar-yp",
    "usage.title": "Less checking.\nMore coding.",
    "usage.desc": "Today’s tokens, usage trends and provider limits live together. Open the menu bar when you need the details; keep working when you don’t.",
    "usage.limits": "See the reset coming",
    "usage.limitsDesc": "Official Claude, Codex and Antigravity limits, OpenCode Go 5-hour / weekly / monthly allowances, and Grok CLI weekly subscription credits. Availability depends on each tool’s login or subscription.",
    "alt.trend": "Production activity UI rendered with sample data, showing bar-period selection and the 16-week activity grid",
    "alt.quota": "Example provider limits and reset timing",
    "u1.t": "Today’s total, per tool",
    "u1.d": "The menu bar shows today’s tokens from every tracked tool. Open it for per-tool tabs; Pi usage also splits by model.",
    "u2.t": "Limits, resets and pace",
    "u2.d": "See official limits with reset times, as used or remaining. Bar colors show your pace, and a forecast says when the 5-hour window reaches 100%.",
    "u3.t": "Several Claude accounts",
    "u3.d": "Each Claude Code config folder gets its own limits tab. A claude.ai session key reads limits without Keychain prompts. A folder that holds only a credentials file is found too, and a rate-limited account keeps its tab.",
    "u4.t": "Activity and recaps",
    "u4.d": "Pick 7, 14 or 21 days or this month, or click for a 16-week grid. Weekly, monthly and yearly recaps show totals, best days and streaks.",
    "u5.t": "Pick what to track",
    "u5.d": "Turn each tool on or off in Settings. Add scan folders when your logs live outside the default paths.",
    "u6.t": "Alerts",
    "u6.d": "Get notified as a limit gets close, and when your partner hatches, evolves or graduates.",
    "alt.recap": "Native weekly recap sample with token usage and Pokémon graduation records",
    "native.recap": "Native UI · sample usage and Pokémon.",
    "p1.t": "Pick the growth source in Settings",
    "p1.d": "Tokens or Time is the only choice. Costs are fixed and the same for everyone. A species you have graduated before grows twice as fast after it hatches.",
    "p2.t": "Growth % in the menu bar",
    "p2.d": "Show egg or evolution progress next to the icon. Hover Home’s bar for tokens, target and percentage.",
    "p3.t": "A pet on your desktop",
    "p3.d": "Put your partner on the desktop at 48 to 384 px. Hover for today’s usage, drag it anywhere, and use right-click → Open for the app.",
    "p4.t": "Pet, pray, sulk",
    "p4.d": "Pet it with the pointer, click an egg to pray, and watch for sulking or event bubbles. Praying is just for fun.",
    "p5.t": "Agent events",
    "p5.d": "Optional URL events make the pet react while an agent works, waits or finishes. You add the hooks yourself; the app never edits agent settings.",
    "agent.guide": "Read the agent setup guide",
    "p6.t": "Representative Pokémon",
    "p6.d": "Pin an owned species and form to the menu bar and the desktop pet. Your current partner keeps growing on Home.",
    "alt.petInteractions": "Separate native pet samples for egg prayer, petting, sulking and agent waiting",
    "alt.petXp": "Native Home header sample with one +250K XP badge after five fast clicks",
    "native.current": "Native UI renders · sample states",
    "c1.t": "Pokédex",
    "c1.d": "One cell per species you have owned, 16 per page. Search, sort, filter by rarity, Shiny or region, and earn completion badges.",
    "c2.t": "Alternate forms",
    "c2.d": "Collect Rotom appliances, Deerling seasons, Unown letters and other Gen 1–5 forms. A form follows evolution and stays in your save.",
    "c3.t": "Token Shop",
    "c3.d": "Spend the tokens you have already used on Rare Candy, a Mint that sets the nature you pick, a Shiny Charm or a new egg.",
    "c4.t": "Rare Candy from limits",
    "c4.d": "Fill a 5-hour or weekly limit to earn Rare Candy. Use several at once and preview the growth first.",
    "alt.shop": "Native Shop sample showing consumable quantity controls and total price",
    "native.shop": "Native UI · sample tokens · shop scroll view continues below.",
    "grp.settings": "Settings and extras",
    "x1.t": "Eight languages",
    "x1.d": "The app UI comes in eight languages. Pokémon, type, ability and move names follow your language, with English as the fallback.",
    "x2.t": "Backups",
    "x2.d": "Automatic snapshots and corruption recovery, plus manual export and restore in Settings.",
    "x3.t": "Shortcuts",
    "x3.d": "Right-click the menu-bar icon for Refresh, Pokédex, Settings and more. Back returns to the page you came from.",
    "x4.t": "Animation quality",
    "x4.d": "Pick 2.5, 5 or 10 fps, or Original, for the menu bar and the floating pet. Low Power Mode caps it.",
    "alt.growthMode": "Native growth source setting sample with Time selected",
    "native.growthMode": "Native UI · sample settings.",
    "fork.desc": "PokeTokenBar-yp is a fork of chattymin’s PokeTokenBar. The original made the companion and the usage tracker. Features marked Only in PokeTokenBar-yp exist only in this fork, so please report problems with them here, not upstream.",
    "k1.t": "The full Pokédex, Gen 1 to 9",
    "k1.d": "The Pokédex runs to #1025, and an egg can start any of 540 Gen 1–9 lines. A legendary hatch is about 1 in 48. The regional filter covers nine regions, Kanto to Paldea, and the national badge counts all 1,025.",
    "k3.t": "Lighter costs",
    "k3.d": "Growth costs and Shop prices are one fiftieth of the original app’s. A Normal line graduates at 15M tokens and a Legendary at 120M. Saves from older versions keep each stage’s progress when they update.",
    "k4.t": "The Battle tab",
    "k4.d": "With the YPoke Slack battle bot linked, the Battle tab lines up to six Pokémon in fighting order; Auto sends the one you are raising. Sub-tabs split the tab into Entry, Battle and History. Each lineup row shows the stats it fights with, marks what its nature raises and lowers, and follows its form.",
    "alt.gyms": "Native gym list sample with Kanto leaders in two columns, the hideout, the Elite Four and the badge case",
    "k5.t": "The Elite Four and the champion",
    "k5.d": "Below the gyms, the hideout is a run of battles with a full heal before each one, and a loss starts it again. Eight badges open the Elite Four run below it. The champion brings the region’s legendaries and hides one more partner, shown as +1 ?, until the first six faint. Beating the champion opens a hidden boss whose first clear pays a strong TM, a shiny legendary egg and Rare Candies. Each gym fight can be replayed turn by turn, with Mega Evolutions and form changes drawn as they happen.",
    "alt.champion": "Native Elite Four run sample where the champion's hidden partner comes out",
    "k6.t": "The Box",
    "k6.d": "The Box tab holds every Pokémon you own: the one you raise, your friends and your graduates. Search, filter by region, grade, Shiny or held item, and sort. A new egg sends your current Pokémon here instead of releasing it, and you can pick a graduate to raise again.",
    "alt.box": "Native Box tab sample with five Pokémon, their levels, marks and held items",
    "k15.t": "See what comes next",
    "k15.d": "A Pokédex page shows how the species evolves next and what the app asks for, like Munchlax’s 30 pets to become Snorlax. When the Pokémon you raise is on that path, the card shows its progress. On Home, tap the next form to open its page. If its next step waits on you and the app stays closed for 30 minutes, it moves to the Box and the closest Box line or a new egg takes its place; Keep waiting or a Settings toggle stops that.",
    "alt.nextEvo": "Native Pokédex page sample for Snorlax with the 30-pet condition at 3/30",
    "alt.moveOn": "Native Home sample with a Munchlax that needs 30 pets, the minutes until it moves to the Box, and Keep waiting",
    "k7.t": "Held items and Mega Evolution",
    "k7.d": "Equip a held item on a Pokémon’s Box page. The Shop and Bag group battle items by what they do, from attack boosts to weather. A Pokémon holding its Mega Stone Mega Evolves at the start of a battle, and Home, the floating pet and the menu bar show the Mega form. In the Shop, a second chip row shows one group at a time, and one search field finds any item, egg or TM by its name in any of the app’s languages.",
    "alt.held": "Native Shop and Bag sample with held items under Attack boost and Type boost",
    "k8.t": "Moves and TMs",
    "k8.d": "A Pokémon’s Box page lists its four moves, and you can swap one for a level-up, egg or TM move, including status moves like Swords Dance. Buy a TM once in the Shop and every Pokémon that can learn it may use it. Each slot is its own card, and ▲/▼ swap it with its neighbor to set the order. Move names follow the app language.",
    "alt.profile": "Native Box detail sample with a Pokémon's stats, held item, Exp. Share slot and moves",
    "k16.t": "Ability, nature, IVs and form",
    "k16.d": "Your Pokémon can field what a gym trainer’s team does. The Mint opens a 5×5 chart and sets the nature you pick. The Ability Capsule and Patch switch abilities, and Bottle Caps raise IVs to 31. The Reveal Glass, DNA Splicers and Reins of Unity switch forms, and a form brings its own types, ability and stats to battle.",
    "alt.naturePicker": "Native Box detail sample with the 5×5 nature chart open, the Ability Capsule, Ability Patch and Gold Bottle Cap, and a Bottle Cap on each IV",
    "k9.t": "Exp. Share",
    "k9.d": "Attach an Exp. Share to one Pokémon in the Box. It gets 50% of the EXP your current Pokémon or egg earns, so a graduate keeps growing while you raise the next one. When a new egg sends your partner to the Box, an Exp. Share from your Bag goes on it. Move here on a Box page moves a copy from another holder, even with an empty Bag, and a holder in the Box evolves there when the next step needs only EXP, a level, friends or a type. A holder that can't use more EXP passes its copy to the closest Box line. A fully grown holder with no step left graduates by itself into your Pokédex. An Exp. Share left in the Bag goes on the Pokémon closest to its next step by itself, but never back on one you took it off yourself.",
    "alt.expShare": "Native Box detail sample for a stored Bulbasaur with Move here and Attach for the Exp. Share",
    "k10.t": "Trades and the Linking Cord",
    "k10.d": "Trade graduated Pokémon with a linked coworker from the Friends tab, or send one straight from its Box page; the other side accepts in Slack. Trade evolutions such as Haunter or Kadabra wait for a trade, or for a Linking Cord from the Shop. Some also need a held item first, like Onix with a Metal Coat.",
    "k11.t": "Friends beside your partner",
    "k11.d": "Pick up to two friends from your graduates and the Pokémon waiting in the Box. They stand next to your partner on Home and on the floating pet in their current form, and petting a friend pops a heart over it. When a new egg or a scout sends your partner to the Box while a slot is free, it joins as a friend.",
    "alt.storedFriends": "Native friend picker sample offering a stored Bulbasaur, and Home with that Bulbasaur walking beside Charizard",
    "k12.t": "Scout Tickets and better eggs",
    "k12.d": "A Scout Ticket shows 10 random Pokémon from one region, or from all of them, and you pick the egg you want. A Rare Egg hatches Rare or better, and an Epic Egg hatches Epic or better.",
    "k13.t": "Day, night and tricky evolutions",
    "k13.d": "Day and night switch every 10 minutes on the clock, and Home shows a sun-and-moon dial. Unusual evolutions become conditions the app can check, and a notice tells you what is blocking one.",
    "k14.t": "Updates itself",
    "k14.d": "The app installs new releases of this fork by itself, after checking the download’s checksum, while the popover is closed. Turn it off in Settings → Updates.",
    "comp.title": "A workday,\nwith a side quest.",
    "comp.desc": "Your existing token usage raises a partner through its real evolution line. Then a new egg arrives, and the collection grows.",
    "journey.hatch": "Hatch your first partner",
    "journey.hatchDesc": "An egg hatches after 100k tokens. Which Pokémon will it be?",
    "journey.grow": "Watch it grow",
    "journey.growDesc": "Keep coding, or keep working in time mode. Pick the source that suits your pace.",
    "journey.collect": "Keep the memories",
    "journey.collectDesc": "Graduated partners stay in your collection. A fresh egg starts the next chapter.",
    "comp.caption": "Every partner has a place in your Pokédex. Example screen.",
    "alt.collection": "Example Pokédex showing collected species",
    "pet.title": "Or, right beside you.",
    "pet.desc": "Let your partner out of the menu bar. Drag it anywhere and hover to check usage. Click an egg to pray, or a hatched Pokémon to pet it and help it grow. Right-click → Open opens the app.",
    "alt.pet": "Example floating desktop pet with usage callout",
    "demo.provenance": "Example screen · English",
    "demo.play": "Play demo",
    "demo.stop": "Stop demo",
    "guide.title": "Curious how it grows?",
    "guide.desc": "Try your pace, check the costs, and see what you can collect. Not using many tokens? Switch to time mode in the app.",
    "g.t1": "Growth calculator",
    "g.t2": "A day together",
    "g.t3": "Collection",
    "g.costH": "Tokens per evolution",
    "g.costSub": "A three-form line without the repeat-species bonus or items. The 100k-token hatch comes first and is not in the table. One- and two-form lines split the same total differently.",
    "g.thRarity": "Rarity",
    "g.thS1": "Stage 1",
    "g.thS2": "Stage 2",
    "g.thS3": "Stage 3 (graduate)",
    "g.thTotal": "Total",
    "rarity.common": "Normal",
    "rarity.uncommon": "Rare",
    "rarity.rare": "Epic",
    "rarity.legendary": "Legendary",
    "g.calcH": "How long on my pace?",
    "g.calcQ": "Pick a growth source and your pace. Token mode counts all AI-coding tokens, cache reads included.",
    "calc.mode": "Growth source",
    "calc.modeToken": "Tokens",
    "calc.modeTime": "Time",
    "calc.pace": "Daily tokens",
    "g.p1": "Light · 10M/day",
    "g.p2": "Some · 25M/day",
    "g.p3": "Typical · 44M/day",
    "g.p4": "Heavy · 100M/day",
    "g.p5": "Agent fleet · 250M/day",
    "calc.hours": "Active hours per day",
    "calc.h1": "1 hour",
    "calc.h2": "2 hours",
    "calc.h4": "4 hours",
    "calc.h6": "6 hours",
    "calc.h8": "8 hours",
    "calc.rarity": "Rarity",
    "calc.repeat": "Species graduated before (×2)",
    "calc.nojs": "Enable JavaScript to use the calculator. The token costs are listed above.",
    "g.honest": "Estimates assume the same pace every day. Items and clicks make it faster.",
    "g.dailyIntro": "Your companion responds to your coding rhythm, changing its pose and caption as you work.",
    "g.st1w": "no tokens today",
    "g.st1t": "Fast asleep",
    "g.st1d": "When you rest, it rests. Weekend menu bars are quiet.",
    "g.st2w": "light use",
    "g.st2t": "Loafing around",
    "g.st2d": "On lighter days, your partner idles beside you.",
    "g.st3w": "coding steadily",
    "g.st3t": "Working along",
    "g.st3d": "Your normal pace. It keeps busy too.",
    "g.st4w": "100k+ tokens/min",
    "g.st4t": "In the zone",
    "g.st4d": "When your agents are busy, your partner keeps up.",
    "g.st5w": "limit almost reached",
    "g.st5t": "Worn out",
    "g.st5d": "When a usage limit is close, it tires before you do. Take the hint.",
    "g.st6w": "evolution · graduation",
    "g.st6t": "Celebrating",
    "g.st6d": "A short animation marks each evolution and graduation.",
    "g.dailyNote": "Hatching has its own animation, and a Shiny hatch gets a different entrance. In time mode your partner works while you are active and sleeps while you are away.",
    "g.loop": "Every graduation adds to your collection and brings a new egg.",
    "g.cWhat": "To collect",
    "g.cHow": "How it works",
    "g.c1k": "Species",
    "g.c1v": "Any Gen 1–9 evolution line, from 540 possible starts weighted by capture rate. Each hatch is a surprise.",
    "g.c2k": "Rarities",
    "g.c2v": "Four tiers: Normal, Rare, Epic and Legendary. Rarer partners hatch less often and need more tokens to graduate.",
    "g.c3k": "✨ Shiny",
    "g.c3v": "A rare surprise at hatch: different colors that stay through evolution.",
    "g.c4k": "Natures",
    "g.c4v": "One of 25 natures per hatch gives each partner its character.",
    "g.c5k": "Branches",
    "g.c5v": "Branching evolution lines prefer paths you have not collected yet.",
    "g.c6k": "Pokédex",
    "g.c6v": "The Pokédex keeps one cell per species you have owned, up to #1025. The Box holds each individual Pokémon.",
    "providers.more": "16 tools. One companion.",
    "providers.label": "Works with your coding tools",
    "providers.note": "Limits depend on your login: official Claude, Codex and Antigravity limits, OpenCode Go allowances and Grok CLI subscription credits. Devin CLI and Kimi Code record no cost, so their cost shows as unavailable.",
    "faq.title": "A few good questions.",
    "faq.free.q": "Is it free?",
    "faq.free.a": "Yes. PokeTokenBar is a free, open-source fan project. Shop items use the tokens you’ve already spent on coding, not real-money purchases.",
    "faq.notool.q": "Do I need an AI coding tool?",
    "faq.notool.a": "No. Time mode grows your partner from the time you are active on your Mac. Usage and limit tracking needs at least one supported tool.",
    "faq.privacy.q": "Does it upload my usage logs?",
    "faq.privacy.a": "No. Usage logs stay on your Mac. The app still uses the network for provider usage and limits, Pokémon data and sprites, service status and updates. It is not a fully offline app.",
    "faq.cost.q": "Does raising a Pokémon spend extra tokens?",
    "faq.cost.a": "No. The app reads usage from your supported coding tools. It doesn’t run model turns to grow your companion.",
    "faq.fork.q": "How is this different from PokeTokenBar?",
    "faq.fork.a": "PokeTokenBar-yp is an unofficial fork of chattymin’s PokeTokenBar (MIT). The feature pages mark what it adds with Only in PokeTokenBar-yp. Report problems with this fork here, not to the original project.",
    "faq.source.q": "Can I build it myself?",
    "faq.source.a": "Yes. The Swift source, build instructions and issue tracker are on GitHub.",
    "footer.source": "Source code",
    "footer.releases": "Release notes",
    "footer.help": "Get help",
    "footer.upstream": "Original by chattymin",
    "footer.sponsor": "Sponsor",
    "foot.disclaimer": "Pokémon data & sprites by PokéAPI. This is an unofficial, non-commercial fan project. It is not affiliated with, endorsed, sponsored, or approved by Nintendo, Game Freak, or The Pokémon Company. Pokémon and Pokémon character names are trademarks of Nintendo; names, data, and sprites are © Nintendo / Game Freak / The Pokémon Company, used at runtime for identification only. The MIT license covers this project's source code only."
  },
  "ko": {
    "skip": "본문으로 건너뛰기",
    "nav.install": "설치",
    "nav.menu": "메뉴",
    "theme": "화면 테마 전환",
    "aria.nav": "주요 탐색",
    "aria.project": "프로젝트 링크",
    "aria.guide": "성장 가이드",
    "aria.table": "성장 및 수집 상세 정보",
    "hero.h1a": "당신의 토큰이,",
    "hero.h1b": "작은 동료로.",
    "hero.lead": "코딩하는 동안 포켓몬이 자라요. Mac 메뉴바에서 AI 토큰 사용량과 한도를 확인하고, 함께할 파트너를 키우세요.",
    "hero.install": "PokeTokenBar 설치",
    "hero.preview": "앱 먼저 둘러보기",
    "hero.compat": "무료 · macOS 14+ · Apple Silicon",
    "hero.note": "이미 쓰고 있는 토큰이 성장으로 이어져요. 평소처럼 코딩하면 됩니다.",
    "demo.caption": "메뉴바에 찾아온 작은 동료.",
    "native.home": "실제 UI 렌더 · 샘플 데이터 · 영어",
    "alt.home": "부화 중인 알·토큰 합계·연속 사용 배지·선택 기간 활동 차트를 표시한 실제 홈 UI 샘플",
    "install.title": "작은 동료를\n맞이할 시간.",
    "install.intro": "macOS 14 이상인 Apple Silicon Mac이면 됩니다. AI 코딩 도구가 없어도 시간 모드로 일하는 동안 파트너를 키울 수 있어요. PokeTokenBar 계정은 필요 없어요.",
    "install.homebrew": "터미널로 설치",
    "install.step1": "Mac에서 터미널을 여세요. PokeTokenBar가 켜져 있으면 먼저 종료하세요.",
    "install.step2": "아래 명령어를 복사해서 실행하세요.",
    "install.step3": "PokeTokenBar가 응용 프로그램 폴더에 설치되고 열려요. 진행 상황은 그대로예요.",
    "install.direct": "직접 다운로드하고 싶나요?",
    "install.zip": "macOS용 ZIP 다운로드",
    "install.unzip": "PokeTokenBar-yp-arm64.zip의 압축을 풀고 PokeTokenBar.app을 응용 프로그램 폴더로 옮기세요.",
    "install.gate": "앱은 자체 서명되어 있어요. macOS가 첫 실행을 차단하면 설치 가이드의 Gatekeeper 안내를 따라주세요. 터미널 명령어는 격리 속성을 자동으로 지워요.",
    "install.help": "설치 가이드 열기",
    "copy": "명령어 복사",
    "copy.pending": "복사 중…",
    "copy.ok": "복사했어요. 터미널에 붙여넣어 설치하세요.",
    "copy.error": "복사하지 못했어요. 위 명령어를 직접 선택해서 복사해주세요.",
    "growth.title": "코딩한 만큼, 포켓몬도 자라요.",
    "growth.play": "애니메이션 재생",
    "growth.pause": "애니메이션 일시정지",
    "growth.desc": "AI 도구로 코딩하며 쓴 토큰이 알을 깨우고, 포켓몬을 키워요. 토큰이 쌓이면 진화하고, 끝까지 키운 파트너는 도감에 남아요.",
    "growth.egg": "알에서 시작해요",
    "growth.eggDesc": "첫 토큰부터 부화에 가까워져요.",
    "growth.first": "첫 포켓몬을 만나요",
    "growth.firstDesc": "알이 부화하면 새로운 파트너를 만나요.",
    "growth.evolve": "함께 코딩하고, 진화해요",
    "growth.evolveDesc": "사용한 토큰이 쌓여 다음 모습으로 진화해요.",
    "growth.collect": "도감에 남기고, 다시 시작해요",
    "growth.collectDesc": "끝까지 키우면 도감에 남고 새 알이 찾아와요.",
    "growth.note": "이상해씨 진화 라인 예시예요. 만나는 포켓몬과 성장 속도는 달라질 수 있어요. 포켓몬을 키우기 위해 AI를 추가로 호출하지 않아요.",
    "modes.title": "키우는 방법은 두 가지.",
    "modes.desc": "설정에서 성장 방식을 고르고 언제든 바꿀 수 있어요. 이미 쌓아 둔 진행도는 어느 방식이든 그대로예요.",
    "modes.tokenTag": "토큰 모드 · 기본",
    "modes.tokenT": "AI 코딩으로 키우기",
    "modes.tokenD": "코딩 에이전트가 쓴 토큰이 캐시 읽기까지 모두 성장으로 들어가요. 같은 토큰이 상점 지갑도 채워요.",
    "modes.tokenFit": "에이전트를 많이 쓰는 분께 맞아요.",
    "modes.timeTag": "시간 모드",
    "modes.timeT": "일하는 시간으로 키우기",
    "modes.timeRate": "활동한 1초마다 성장 토큰 25k와 상점 토큰 25k가 들어와요. 1시간이면 각각 90M이에요.",
    "modes.timeIdle": "최근 5분 안에 키보드나 마우스를 쓰면 활동 중으로 칩니다. 한 번 확인할 때 최대 2분까지만 쳐요.",
    "modes.timeOnly": "이 모드에서는 AI 토큰 사용량이 성장에 들어가지 않아요.",
    "modes.timeFit": "가볍게 쓰는 분이나 AI 코딩 도구가 없는 분께 맞아요.",
    "modes.hint": "3일 동안 토큰 사용이 없으면 앱이 설정에서 시간 모드를 권해요.",
    "modes.clickT": "클릭으로 거들기.",
    "modes.clickD": "어느 모드든 홈의 큰 스프라이트나 플로팅 펫을 클릭하면 성장 토큰 50k가 더해져요. 기본 등급 라인은 300번쯤 클릭하면 알에서 졸업까지 가요.",
    "badge.fork": "PokeTokenBar-yp에만 있어요",
    "usage.title": "사용량은 한눈에.\n코딩은 하던 대로.",
    "usage.desc": "오늘의 토큰, 사용량 추이, 프로바이더 한도를 한곳에서 확인하세요. 자세히 볼 때만 메뉴바를 열면 됩니다.",
    "usage.limits": "리셋까지 얼마나 남았는지",
    "usage.limitsDesc": "Claude·Codex·Antigravity의 공식 한도, OpenCode Go의 5시간·주간·월간 사용량, Grok CLI의 주간 구독 크레딧을 확인하세요. 도구의 로그인·구독 상태에 따라 표시됩니다.",
    "alt.trend": "기간 선택 막대 차트와 16주 활동 격자를 샘플 데이터로 렌더링한 실제 UI",
    "alt.quota": "프로바이더 한도와 리셋 시점 예시",
    "u1.t": "오늘 합계, 도구별로",
    "u1.d": "메뉴바에 추적 중인 모든 도구의 오늘 토큰이 보여요. 열면 도구별 탭이 있고, Pi는 모델별로도 나눠 보여요.",
    "u2.t": "한도, 리셋, 사용 속도",
    "u2.d": "공식 한도와 리셋 시각을 사용량이나 남은량으로 보세요. 막대 색은 사용 속도를, 예측은 5시간 한도가 100%에 닿는 시점을 알려줘요.",
    "u3.t": "여러 Claude 계정",
    "u3.d": "Claude Code 설정 폴더마다 한도 탭이 따로 생겨요. claude.ai 세션 키를 넣으면 Keychain 팝업 없이 한도를 읽어요. 인증 파일만 있는 폴더도 찾고, 요청 제한에 걸린 계정도 탭이 남아요.",
    "u4.t": "활동과 리캡",
    "u4.d": "7일·14일·21일·이번 달을 고르거나 클릭해서 16주 격자로 보세요. 주·월·연 리캡에 합계, 최고 기록일, 연속 사용일이 나와요.",
    "u5.t": "추적할 도구 고르기",
    "u5.d": "설정에서 도구마다 추적을 켜고 끄세요. 로그가 기본 경로 밖에 있으면 스캔 폴더를 더할 수 있어요.",
    "u6.t": "알림",
    "u6.d": "한도가 가까워질 때, 파트너가 부화·진화·졸업할 때 알려줘요.",
    "alt.recap": "토큰 사용량과 포켓몬 졸업 기록이 표시된 실제 주간 회고 UI 샘플",
    "native.recap": "실제 UI 렌더 · 샘플 사용량과 포켓몬.",
    "p1.t": "설정에서 성장 방식 고르기",
    "p1.d": "토큰과 시간 중 하나만 고르면 돼요. 비용은 고정이고 누구에게나 같아요. 전에 졸업시킨 종은 부화한 뒤 두 배 빠르게 자라요.",
    "p2.t": "메뉴바에 성장률 표시",
    "p2.d": "아이콘 옆에 부화·진화 진행률을 띄울 수 있어요. 홈 막대에 마우스를 올리면 토큰·목표·비율이 보여요.",
    "p3.t": "바탕화면의 펫",
    "p3.d": "파트너를 48~384px 크기로 바탕화면에 꺼내 두세요. 마우스를 올리면 오늘 사용량이 보이고, 어디로든 끌어 옮길 수 있어요. 앱은 우클릭 → 열기로 열어요.",
    "p4.t": "쓰다듬기, 기도, 삐침",
    "p4.d": "포인터로 쓰다듬고, 알을 클릭해 기도하고, 삐친 모습이나 이벤트 말풍선을 구경하세요. 기도는 재미로 하는 거예요.",
    "p5.t": "에이전트 이벤트",
    "p5.d": "선택 기능인 URL 이벤트로 에이전트가 일하고, 기다리고, 끝낼 때 펫이 반응해요. 훅은 직접 추가하고, 앱은 에이전트 설정을 고치지 않아요.",
    "agent.guide": "에이전트 연동 설정 보기",
    "p6.t": "대표 포켓몬",
    "p6.d": "가진 종과 폼을 메뉴바와 바탕화면 펫에 고정하세요. 지금 키우는 파트너는 홈에서 계속 자라요.",
    "alt.petInteractions": "알 기도·쓰다듬기·삐침·에이전트 대기를 각각 렌더링한 실제 펫 샘플",
    "alt.petXp": "빠르게 다섯 번 클릭한 뒤 +250K XP 배지 하나가 뜬 홈 헤더 샘플",
    "native.current": "실제 UI 렌더 · 샘플 상태",
    "c1.t": "도감",
    "c1.d": "가졌던 종마다 한 칸씩, 한 페이지에 16마리. 검색·정렬, 희귀도·이로치·지방 필터, 완성 배지가 있어요.",
    "c2.t": "다양한 폼",
    "c2.d": "로토무 가전 폼, 사철록 계절, 안농 문자 같은 1~5세대 폼을 모으세요. 폼은 진화해도 유지되고 저장에도 남아요.",
    "c3.t": "토큰 상점",
    "c3.d": "이미 쓴 토큰으로 이상한 사탕, 고른 성격으로 바꿔 주는 민트, 빛나는부적, 새 알을 사요.",
    "c4.t": "한도를 채우면 이상한 사탕",
    "c4.d": "5시간이나 주간 한도를 채우면 이상한 사탕을 받아요. 여러 개를 한 번에 쓰고, 쓰기 전에 성장량을 미리 볼 수 있어요.",
    "alt.shop": "소모품 수량과 총가격을 보여 주는 실제 상점 UI 샘플",
    "native.shop": "실제 UI 렌더 · 샘플 토큰 · 아래로 상점 스크롤이 이어져요.",
    "grp.settings": "설정과 그 밖의 것",
    "x1.t": "8개 언어",
    "x1.d": "앱 화면은 8개 언어를 지원해요. 포켓몬·타입·특성·기술 이름도 고른 언어를 따르고, 번역이 없으면 영어로 보여요.",
    "x2.t": "백업",
    "x2.d": "자동 스냅샷과 손상 복구가 있고, 설정에서 직접 내보내고 복원할 수도 있어요.",
    "x3.t": "바로가기",
    "x3.d": "메뉴바 아이콘을 우클릭하면 새로고침·도감·설정 등으로 바로 가요. 뒤로가기는 보던 페이지로 돌아가요.",
    "x4.t": "애니메이션 품질",
    "x4.d": "메뉴바와 플로팅 펫의 움직임을 2.5·5·10fps 또는 원본으로 고르세요. 저전력 모드에서는 낮게 제한돼요.",
    "alt.growthMode": "시간이 선택된 실제 성장 방식 설정 UI 샘플",
    "native.growthMode": "실제 UI 렌더 · 샘플 설정.",
    "fork.desc": "PokeTokenBar-yp는 chattymin의 PokeTokenBar를 바탕으로 한 포크예요. 파트너와 사용량 트래커는 원작이 만들었어요. ‘PokeTokenBar-yp에만 있어요’ 표시가 붙은 기능은 이 포크에만 있으니, 문제가 있으면 원작이 아니라 여기에 알려 주세요.",
    "k1.t": "1~9세대 전국 도감",
    "k1.d": "도감은 #1025까지 있고, 알은 1~9세대의 540가지 시작 종 중 하나로 부화해요. 전설은 48번에 한 번꼴이에요. 지방 필터는 관동부터 팔데아까지 9개 지방이고, 전국 배지는 1,025종 전부를 셉니다.",
    "k3.t": "가벼워진 비용",
    "k3.d": "성장 비용과 상점 가격이 원작의 50분의 1이에요. 기본 등급 라인은 15M 토큰, 전설은 120M 토큰이면 졸업해요. 예전 버전의 저장 데이터는 업데이트해도 단계 안 진행 비율이 그대로예요.",
    "k4.t": "대결 탭",
    "k4.d": "YPoke 슬랙 대결 봇을 연결하면 대결 탭에 최대 여섯 마리를 나갈 순서대로 세워요. 자동이면 지금 키우는 포켓몬이 나가요. 탭 안은 엔트리·배틀·기록으로 나뉘어요. 줄마다 실제로 싸우는 능력치가 나오고, 성격이 올리고 내리는 능력치에 ↑·↓가 붙고, 폼을 따라요.",
    "alt.gyms": "두 줄로 선 관동 관장·아지트·사천왕·배지 케이스를 보여 주는 실제 체육관 목록 UI 샘플",
    "k5.t": "사천왕과 챔피언",
    "k5.d": "체육관 아래 아지트는 판마다 완전히 회복하고 싸우는 연전이고, 지면 처음부터 다시 해요. 그 아래 사천왕 연전은 배지 여덟 개면 열려요. 챔피언은 그 지방의 전설을 데려오고, +1 ?로만 보이는 파트너 하나를 앞의 여섯 마리가 쓰러질 때까지 숨겨 둬요. 챔피언을 이기면 숨겨진 강자가 열리고, 처음 이기면 강한 기술머신, 빛나는 전설의 알, 이상한사탕을 받아요. 체육관 대결은 턴마다 다시 볼 수 있고, 메가진화와 폼 변화도 그 모습으로 나와요.",
    "alt.champion": "챔피언이 숨긴 파트너가 나오는 실제 사천왕 연전 UI 샘플",
    "k6.t": "박스",
    "k6.d": "박스 탭에는 키우는 포켓몬, 친구, 졸업한 포켓몬까지 내가 가진 모든 개체가 있어요. 검색하고, 지역·등급·이로치·지닌 도구로 거르고, 정렬할 수 있어요. 새 알을 받으면 지금 포켓몬을 놓아주지 않고 박스로 보내고, 졸업한 포켓몬을 골라 다시 키울 수도 있어요.",
    "alt.box": "포켓몬 다섯 마리의 레벨·표시·지닌 도구가 보이는 실제 박스 탭 UI 샘플",
    "k15.t": "다음 진화가 보이는 도감",
    "k15.d": "도감 페이지에서 그 포켓몬이 다음에 무엇으로 진화하는지, 앱에서는 무엇이 필요한지 보여 줘요. 먹고자는 30번 쓰다듬으면 잠만보가 돼요. 키우는 포켓몬이 그 길 위에 있으면 카드에 진행도가 나와요. 홈에서 다음 모습을 누르면 그 페이지가 열려요. 다음 단계가 내 손을 기다리는데 앱을 30분 닫아 두면 그 포켓몬은 박스로 가고, 다음 단계에 가장 가까운 박스 포켓몬이나 새 알이 자리를 이어받아요. 계속 기다리기 버튼이나 설정 토글로 막을 수 있어요.",
    "alt.nextEvo": "쓰다듬기 30번 조건이 3/30으로 보이는 실제 잠만보 도감 페이지 UI 샘플",
    "alt.moveOn": "쓰다듬기 30번이 필요한 먹고자, 박스로 가기까지 남은 시간과 계속 기다리기 버튼이 보이는 실제 홈 UI 샘플",
    "k7.t": "지닌 도구와 메가진화",
    "k7.d": "지닌 도구는 포켓몬의 박스 페이지에서 달아요. 상점과 가방은 대결용 도구를 공격 강화부터 날씨까지 하는 일별로 묶어 보여 줘요. 메가스톤을 지닌 포켓몬은 대결이 시작될 때 메가진화하고, 홈·플로팅 펫·메뉴바에도 메가진화한 모습이 보여요. 상점에서는 두 번째 칩 줄로 묶음 하나만 골라 보고, 검색창 하나로 아이템·알·기술머신을 앱의 어느 언어 이름으로든 찾아요.",
    "alt.held": "공격 강화·타입 강화 아래에 지닌 도구가 놓인 실제 상점·가방 UI 샘플",
    "k8.t": "기술과 기술머신",
    "k8.d": "포켓몬의 박스 페이지에 기술 네 개가 나오고, 레벨업·알 기술이나 기술머신 기술로 하나씩 바꿀 수 있어요. 칼춤 같은 변화 기술도 돼요. 기술머신은 상점에서 한 번 사면 배울 수 있는 모든 포켓몬이 쓸 수 있어요. 기술칸은 칸마다 카드로 나뉘고, ▲/▼로 옆 칸과 자리를 바꿔 순서를 정해요. 기술 이름은 앱 언어로 나와요.",
    "alt.profile": "능력치·지닌 도구·학습장치 칸·기술을 보여 주는 실제 박스 상세 UI 샘플",
    "k16.t": "특성·성격·개체값·폼",
    "k16.d": "체육관 트레이너의 팀이 갖출 수 있는 것은 내 포켓몬도 갖출 수 있어요. 민트는 5×5 성격표를 열고 고른 성격으로 바꿔 줘요. 특성캡슐과 특성패치는 특성을 바꾸고, 병뚜껑은 개체값을 31로 올려요. 비추는거울·유전자쐐기·유대의고삐는 폼을 바꾸고, 폼의 타입·특성·능력치가 그대로 배틀에 나가요.",
    "alt.naturePicker": "5×5 성격표가 열린 실제 박스 상세 UI 샘플과 특성캡슐·특성패치·금색병뚜껑, 개체값마다 붙은 은색병뚜껑",
    "k9.t": "학습장치",
    "k9.d": "박스 포켓몬 하나에 학습장치를 달아 주세요. 그 포켓몬은 지금 키우는 포켓몬이나 알이 얻는 경험치의 50%를 함께 받아서, 다음 포켓몬을 키우는 동안 졸업한 포켓몬도 계속 자라요. 새 알로 파트너를 박스에 보내면 가방의 학습장치 하나가 그 포켓몬에 달려요. 박스 화면의 여기로 옮기기로 다른 포켓몬의 학습장치를 가져올 수 있고, 가방이 비어 있어도 돼요. 학습장치를 단 박스 포켓몬은 경험치·레벨·친구·타입만 필요한 단계라면 박스에서 진화해요. 경험치를 더 쓸 수 없는 포켓몬의 학습장치는 가장 가까운 박스 포켓몬에게 넘어가요. 남은 단계 없이 다 자란 학습장치 포켓몬은 알아서 졸업해 도감에 올라요. 가방에 남은 학습장치는 다음 단계에 가장 가까운 포켓몬에게 알아서 달려요. 직접 뗀 포켓몬에게는 다시 달지 않아요.",
    "alt.expShare": "여기로 옮기기와 달기 버튼이 보이는 박스 속 이상해씨의 실제 상세 UI 샘플",
    "k10.t": "교환과 연결의끈",
    "k10.d": "친구 탭에서 연결한 동료와 졸업한 포켓몬을 맞바꾸거나, 박스 상세에서 바로 보내요. 상대는 슬랙에서 수락해요. 고우스트·윤겔라처럼 교환으로 진화하는 포켓몬은 교환하거나 상점의 연결의끈을 쓸 때까지 기다려요. 롱스톤과 금속코트처럼 도구를 먼저 지녀야 하는 경우도 있어요.",
    "k11.t": "파트너 곁의 친구",
    "k11.d": "졸업한 포켓몬과 박스에서 쉬는 포켓몬 중에서 최대 두 마리까지 친구로 고르세요. 홈과 플로팅 펫에서 지금 모습 그대로 파트너 옆에 서고, 친구를 쓰다듬으면 그 위에 하트가 떠요. 새 알이나 스카우트로 파트너를 박스에 보낼 때 친구 칸이 비어 있으면 그 포켓몬이 친구로 들어와요.",
    "alt.storedFriends": "보관 중인 이상해씨를 고를 수 있는 친구 선택과, 리자몽 옆을 걷는 이상해씨가 보이는 실제 홈 UI 샘플",
    "k12.t": "스카우트 티켓과 더 좋은 알",
    "k12.d": "스카우트 티켓은 한 지방이나 전체에서 포켓몬 10마리를 무작위로 보여 주고, 그중 원하는 알을 고르게 해요. 희귀 알은 희귀 이상, 고급 알은 고급 이상으로 부화해요.",
    "k13.t": "낮과 밤, 까다로운 진화",
    "k13.d": "낮과 밤이 시계 기준 10분마다 바뀌고, 홈에 해와 달 다이얼이 보여요. 특이한 진화 조건은 앱이 확인할 수 있는 조건으로 바꾸고, 진화가 막히면 무엇 때문인지 알려줘요.",
    "k14.t": "스스로 업데이트",
    "k14.d": "앱이 이 포크의 새 릴리스를 스스로 설치해요. 내려받은 파일의 체크섬을 확인하고, 팝오버가 닫혀 있을 때 설치해요. 설정 → 업데이트에서 끌 수 있어요.",
    "comp.title": "코딩하는 하루에,\n작은 모험 하나.",
    "comp.desc": "이미 쓰고 있는 토큰으로 파트너가 실제 진화 계보를 따라 자라요. 졸업하면 새 알이 찾아오고, 도감에는 함께한 기록이 남습니다.",
    "journey.hatch": "첫 파트너와 만나기",
    "journey.hatchDesc": "100k 토큰이면 알이 부화해요. 어떤 포켓몬이 나올까요?",
    "journey.grow": "함께 자라기",
    "journey.growDesc": "코딩을 이어가거나, 시간 모드라면 평소처럼 일하면 돼요. 내 속도에 맞는 방식을 고르세요.",
    "journey.collect": "도감에 추억 남기기",
    "journey.collectDesc": "졸업한 파트너는 도감에 남아요. 새 알과 함께 다음 이야기를 시작하세요.",
    "comp.caption": "함께한 파트너가 쌓이는 도감. 예시 화면.",
    "alt.collection": "수집한 포켓몬이 표시된 도감 예시",
    "pet.title": "바탕화면에서도 함께.",
    "pet.desc": "파트너를 메뉴바 밖으로 꺼내보세요. 드래그로 옮기고, 마우스를 올려 사용량을 확인하세요. 알을 클릭하면 기도하고, 부화한 포켓몬을 클릭하면 쓰다듬으며 성장을 거들어요. 앱은 우클릭 → 열기로 열어요.",
    "alt.pet": "사용량 말풍선이 표시된 바탕화면 펫 예시",
    "demo.provenance": "예시 화면 · 영어",
    "demo.play": "데모 재생",
    "demo.stop": "데모 정지",
    "guide.title": "얼마나 쓰면 자랄까요?",
    "guide.desc": "내 속도로 계산하고, 진화 비용과 수집 요소를 확인하세요. 토큰을 많이 쓰지 않는다면 앱에서 시간 모드로 바꿔 보세요.",
    "g.t1": "성장 계산기",
    "g.t2": "파트너의 하루",
    "g.t3": "수집 요소",
    "g.costH": "진화에 필요한 토큰",
    "g.costSub": "반복 부화 보너스와 아이템이 없는 3단계 진화 예시예요. 부화에 드는 100k 토큰은 표에 넣지 않았어요. 1·2단계 진화는 총량은 같지만 단계별로 나누는 비율이 달라요.",
    "g.thRarity": "희귀도",
    "g.thS1": "1단계",
    "g.thS2": "2단계",
    "g.thS3": "3단계 (졸업)",
    "g.thTotal": "총량",
    "rarity.common": "기본",
    "rarity.uncommon": "희귀",
    "rarity.rare": "고급",
    "rarity.legendary": "전설",
    "g.calcH": "내 속도로는 얼마나 걸릴까?",
    "g.calcQ": "성장 방식과 속도를 고르세요. 토큰 모드는 캐시 읽기를 포함한 AI 코딩 토큰 전체를 셉니다.",
    "calc.mode": "성장 방식",
    "calc.modeToken": "토큰",
    "calc.modeTime": "시간",
    "calc.pace": "하루 토큰 사용량",
    "g.p1": "가볍게 · 10M/일",
    "g.p2": "조금 · 25M/일",
    "g.p3": "보통 · 44M/일",
    "g.p4": "헤비 · 100M/일",
    "g.p5": "에이전트 군단 · 250M/일",
    "calc.hours": "하루 활동 시간",
    "calc.h1": "1시간",
    "calc.h2": "2시간",
    "calc.h4": "4시간",
    "calc.h6": "6시간",
    "calc.h8": "8시간",
    "calc.rarity": "희귀도",
    "calc.repeat": "전에 졸업시킨 종 (×2)",
    "calc.nojs": "계산기를 사용하려면 JavaScript를 켜주세요. 토큰 비용은 위 표에서 확인할 수 있어요.",
    "g.honest": "매일 같은 속도라고 가정한 예상치예요. 아이템과 클릭이 있으면 더 빨라져요.",
    "g.dailyIntro": "메뉴바의 파트너는 장식이 아니에요. 당신의 코딩 리듬을 그대로 살아요 — 스프라이트와 문구가 실시간으로 바뀝니다.",
    "g.st1w": "오늘 사용량 0",
    "g.st1t": "쿨쿨",
    "g.st1d": "당신이 쉬면 파트너도 자요. 주말의 메뉴바는 조용하답니다.",
    "g.st2w": "가끔 한 번씩",
    "g.st2t": "느긋",
    "g.st2d": "가볍게 몇 번 물어본 날엔 옆에서 어슬렁거려요.",
    "g.st3w": "꾸준히 코딩 중",
    "g.st3t": "같이 일하는 중",
    "g.st3d": "평소 페이스. 파트너도 부지런히 움직여요.",
    "g.st4w": "분당 10만 토큰 이상",
    "g.st4t": "몰입",
    "g.st4d": "에이전트가 달리고 있을 때 — 파트너도 달아올라요.",
    "g.st5w": "한도 임박",
    "g.st5t": "지침",
    "g.st5d": "사용 한도가 코앞이면 파트너가 먼저 지쳐요. 눈치채 주세요.",
    "g.st6w": "진화 · 졸업 직후",
    "g.st6t": "축하",
    "g.st6d": "진화 순간과 졸업 연출 — 놓치기 아까운 몇 초예요.",
    "g.dailyNote": "부화 순간엔 전용 연출이 있고, 이로치가 태어나면 연출부터 달라요. 시간 모드에서는 내가 활동할 때 같이 일하고, 자리를 비우면 잠들어요.",
    "g.loop": "끝이 아니라 루프예요. 졸업할 때마다 도감이 한 칸 채워지고, 새 알이 도착합니다.",
    "g.cWhat": "모을 것",
    "g.cHow": "어떻게",
    "g.c1k": "종",
    "g.c1v": "1~9세대의 진화 라인 중 하나로, 시작 종 540가지가 포획률 가중치로 뽑혀요. 알이 부화할 때마다 새로운 만남이 기다립니다.",
    "g.c2k": "희귀도",
    "g.c2v": "기본·희귀·고급·전설 4등급이에요. 희귀할수록 드물게 나오고, 졸업까지 토큰이 더 들어요.",
    "g.c3k": "✨ 이로치",
    "g.c3v": "부화 순간의 아주 드문 행운 — 전용 색상, 진화해도 유지돼요.",
    "g.c4k": "성격",
    "g.c4v": "부화마다 25종 중 하나 — 같은 종이라도 느낌이 달라요.",
    "g.c5k": "분기 진화",
    "g.c5v": "진화가 갈라지는 종은 아직 도감에 없는 쪽을 우선해요 — 키울수록 도감이 알아서 채워집니다.",
    "g.c6k": "도감",
    "g.c6v": "도감은 가졌던 종마다 한 칸씩, #1025까지 기록해요. 개체 하나하나는 박스에 있어요.",
    "providers.more": "16개 도구, 하나의 파트너",
    "providers.label": "지금 쓰는 코딩 도구와 함께",
    "providers.note": "한도는 로그인 상태에 따라 보여요: Claude·Codex·Antigravity 공식 한도, OpenCode Go 사용량, Grok CLI 구독 크레딧. Devin CLI와 Kimi Code는 비용을 기록하지 않아서 비용이 표시되지 않아요.",
    "faq.title": "궁금할 만한 것들.",
    "faq.free.q": "무료인가요?",
    "faq.free.a": "네. 무료 오픈소스 팬 프로젝트입니다. 상점에서는 실제 결제 대신 코딩에 이미 사용한 토큰을 재화로 써요.",
    "faq.notool.q": "AI 코딩 도구가 꼭 있어야 하나요?",
    "faq.notool.a": "아니요. 시간 모드는 Mac에서 활동한 시간으로 파트너를 키워요. 사용량과 한도를 보려면 지원하는 도구가 하나 이상 있어야 해요.",
    "faq.privacy.q": "사용량 로그를 업로드하나요?",
    "faq.privacy.a": "아니요. 사용량 로그는 Mac 안에 남아요. 다만 프로바이더 사용량·한도, 포켓몬 데이터·스프라이트, 서비스 상태, 업데이트를 위해 네트워크를 사용합니다. 완전한 오프라인 앱은 아니에요.",
    "faq.cost.q": "포켓몬을 키우면 토큰을 추가로 쓰나요?",
    "faq.cost.a": "아니요. 지원하는 코딩 도구의 사용량을 읽습니다. 파트너를 키우기 위해 모델을 실행하지 않아요.",
    "faq.fork.q": "원작 PokeTokenBar와 무엇이 다른가요?",
    "faq.fork.a": "PokeTokenBar-yp는 chattymin의 PokeTokenBar(MIT)를 바탕으로 한 비공식 포크예요. 더해진 기능은 기능 페이지에 ‘PokeTokenBar-yp에만 있어요’로 표시돼 있어요. 이 포크의 문제는 원작이 아니라 여기에 알려 주세요.",
    "faq.source.q": "직접 빌드할 수 있나요?",
    "faq.source.a": "네. Swift 소스 코드, 빌드 방법, 이슈 트래커가 GitHub에 공개되어 있습니다.",
    "footer.source": "소스 코드",
    "footer.releases": "릴리스 노트",
    "footer.help": "도움 받기",
    "footer.upstream": "원작: chattymin",
    "footer.sponsor": "후원",
    "foot.disclaimer": "포켓몬 데이터·스프라이트는 PokéAPI를 사용합니다. 본 프로젝트는 비공식·비상업 팬 프로젝트로, Nintendo·Game Freak·The Pokémon Company와 제휴하거나 보증·후원·승인을 받지 않았습니다. ‘Pokémon’과 포켓몬 캐릭터 이름은 Nintendo의 상표이며, 이름·데이터·스프라이트의 저작권은 © Nintendo / Game Freak / The Pokémon Company에 있고 식별 목적으로만 런타임에 사용됩니다. MIT 라이선스는 본 프로젝트의 소스 코드에만 적용됩니다."
  },
  "ja": {
    "skip": "本文へ移動",
    "nav.install": "インストール",
    "nav.menu": "メニュー",
    "theme": "テーマを切り替え",
    "aria.nav": "メインナビゲーション",
    "aria.project": "プロジェクトリンク",
    "aria.guide": "育成ガイド",
    "aria.table": "成長と収集の詳細",
    "hero.h1a": "あなたのトークンが、",
    "hero.h1b": "小さなパートナーに。",
    "hero.lead": "コードを書くたび、ポケモンが育つ。MacのメニューバーでAIトークンの使用量と上限を確認しながら、パートナーを育てましょう。",
    "hero.install": "PokeTokenBar を入手",
    "hero.preview": "アプリを見てみる",
    "hero.compat": "無料 · macOS 14+ · Apple Silicon",
    "hero.note": "いつも使っているトークンが成長につながります。コーディングはいつもどおりで。",
    "demo.caption": "メニューバーに、小さな仲間。",
    "native.home": "実際のUIレンダー · サンプルデータ · 英語",
    "alt.home": "孵化中のタマゴ・トークン合計・連続使用バッジ・選択期間の活動グラフを示す実際のホームUIサンプル",
    "install.title": "小さな仲間を、\n迎えよう。",
    "install.intro": "macOS 14以降のApple Silicon Macがあれば始められます。AIコーディングツールがなくても、時間モードなら作業している間にパートナーが育ちます。PokeTokenBarのアカウントは不要です。",
    "install.homebrew": "ターミナルでインストール",
    "install.step1": "Macでターミナルを開きます。PokeTokenBarが起動中なら先に終了します。",
    "install.step2": "下のコマンドをコピーして実行します。",
    "install.step3": "PokeTokenBarがアプリケーションフォルダに入って起動します。進行状況はそのままです。",
    "install.direct": "直接ダウンロードするには？",
    "install.zip": "macOS用ZIPをダウンロード",
    "install.unzip": "PokeTokenBar-yp-arm64.zipを展開し、PokeTokenBar.appをアプリケーションフォルダへ移動します。",
    "install.gate": "アプリは自己署名です。macOSが初回起動をブロックした場合は、インストールガイドのGatekeeper手順をご覧ください。ターミナルのコマンドなら隔離属性を自動で外します。",
    "install.help": "インストールガイドを開く",
    "copy": "コマンドをコピー",
    "copy.pending": "コピー中…",
    "copy.ok": "コピーしました。ターミナルに貼り付けてインストールしてください。",
    "copy.error": "コピーできませんでした。上のコマンドを選択して手動でコピーしてください。",
    "growth.title": "コードを書くほど、ポケモンが育つ。",
    "growth.play": "アニメーションを再生",
    "growth.pause": "アニメーションを一時停止",
    "growth.desc": "AIツールでコードを書くと、そのトークンでタマゴが孵り、ポケモンが育ちます。使うほど進化し、育て上げたパートナーは図鑑に残ります。",
    "growth.egg": "タマゴから始まる",
    "growth.eggDesc": "最初のトークンから孵化へ近づきます。",
    "growth.first": "パートナーと出会う",
    "growth.firstDesc": "孵ったタマゴから新しい仲間が。",
    "growth.evolve": "コードを書いて、進化する",
    "growth.evolveDesc": "使ったトークンが次の姿へ育てます。",
    "growth.collect": "図鑑に残して、次の出会いへ",
    "growth.collectDesc": "育て上げた仲間は図鑑へ。次は新しいタマゴ。",
    "growth.note": "フシギダネの進化例です。出会うポケモンや成長の速さは異なります。育成のために追加のAIリクエストは行いません。",
    "modes.title": "育て方は2つ。",
    "modes.desc": "設定で成長の方式を選び、いつでも切り替えられます。これまでに貯めた進み具合はどちらの方式でも変わりません。",
    "modes.tokenTag": "トークンモード · 標準",
    "modes.tokenT": "AIコーディングで育てる",
    "modes.tokenD": "コーディングエージェントが使ったトークンが、キャッシュ読み込みも含めてすべて成長になります。同じトークンでショップのお財布も貯まります。",
    "modes.tokenFit": "エージェントをたくさん使う人向け。",
    "modes.timeTag": "時間モード",
    "modes.timeT": "作業時間で育てる",
    "modes.timeRate": "アクティブな1秒ごとに、成長トークン25kとショップ用トークン25kが入ります。1時間でそれぞれ90Mです。",
    "modes.timeIdle": "直近5分以内にキーボードかマウスを使っていればアクティブとみなします。1回の確認で数えるのは最大2分です。",
    "modes.timeOnly": "このモードでは、AIトークンの使用量は成長になりません。",
    "modes.timeFit": "ライトに使う人や、AIコーディングツールを使わない人向け。",
    "modes.hint": "3日間トークンの使用がないと、アプリが設定で時間モードを提案します。",
    "modes.clickT": "クリックで手伝う。",
    "modes.clickD": "どちらのモードでも、ホームの大きなスプライトやデスクトップペットをクリックすると成長トークンが50k増えます。ノーマルの進化ラインなら、約300回のクリックでタマゴから卒業まで進みます。",
    "badge.fork": "PokeTokenBar-yp だけ",
    "usage.title": "使用量はひと目で。\nコードに集中。",
    "usage.desc": "今日のトークン、使用量の推移、プロバイダーの上限をひとつの場所に。詳しく知りたいときだけメニューバーを開けばOK。",
    "usage.limits": "リセットまで、あとどれくらい？",
    "usage.limitsDesc": "Claude・Codex・Antigravity の公式上限、OpenCode Go の5時間・週間・月間利用枠、Grok CLI の週間サブスクリプションクレジットを表示。各ツールのログイン・契約により異なります。",
    "alt.trend": "期間を選べる棒グラフと16週間の活動グリッドをサンプルデータで描画した実際のUI",
    "alt.quota": "プロバイダーの上限とリセット時刻の例",
    "u1.t": "今日の合計をツール別に",
    "u1.d": "メニューバーに、記録中のすべてのツールの今日のトークンを表示。開くとツール別のタブがあり、Pi はモデル別にも分けて表示します。",
    "u2.t": "上限、リセット、ペース",
    "u2.d": "公式の上限とリセット時刻を、使用量か残量で表示。バーの色で使用ペースがわかり、5時間の枠が100%に届く時刻も予測します。",
    "u3.t": "複数のClaudeアカウント",
    "u3.d": "Claude Code の設定フォルダごとに上限のタブができます。claude.ai のセッションキーを使えば、Keychain のポップアップなしで上限を読み取れます。 認証ファイルだけのフォルダも見つけ、リクエスト制限にかかったアカウントもタブが残ります。",
    "u4.t": "活動と振り返り",
    "u4.d": "7日・14日・21日・今月から選ぶか、クリックで16週間のグリッドへ。週・月・年の振り返りで合計、最高の日、連続日数を確認できます。",
    "u5.t": "記録するツールを選ぶ",
    "u5.d": "設定でツールごとに記録をオン・オフ。ログが既定の場所の外にあれば、スキャンフォルダを追加できます。",
    "u6.t": "通知",
    "u6.d": "上限が近づいたとき、パートナーが孵化・進化・卒業したときにお知らせします。",
    "alt.recap": "トークン使用量とポケモンの卒業記録を表示した実際の週間振り返りUIサンプル",
    "native.recap": "実際のUIレンダー · サンプル使用量とポケモン。",
    "p1.t": "設定で成長の方式を選ぶ",
    "p1.d": "トークンか時間か、選ぶのはそれだけです。コストは固定で、誰にとっても同じです。以前に卒業させた種族は、孵化したあと2倍の速さで育ちます。",
    "p2.t": "メニューバーに成長率",
    "p2.d": "アイコンの横に孵化や進化の進み具合を表示できます。ホームのバーにホバーすると、トークン・目標・割合を確認できます。",
    "p3.t": "デスクトップのペット",
    "p3.d": "パートナーを48〜384pxの大きさでデスクトップに出せます。ホバーで今日の使用量、ドラッグで好きな場所へ。アプリは右クリック → 開くで開きます。",
    "p4.t": "なでる、お祈り、すねる",
    "p4.d": "ポインタでなでたり、タマゴをクリックしてお祈りしたり。すねる姿やイベントの吹き出しも見られます。お祈りはお楽しみの演出です。",
    "p5.t": "エージェントのイベント",
    "p5.d": "任意のURLイベントで、エージェントの作業・入力待ち・完了にペットが反応します。フックは自分で追加し、アプリがエージェントの設定を変えることはありません。",
    "agent.guide": "エージェント連携の設定を読む",
    "p6.t": "代表ポケモン",
    "p6.d": "所有する種族と姿を、メニューバーとデスクトップペットに固定できます。いま育てているパートナーはホームで育ち続けます。",
    "alt.petInteractions": "タマゴへのお祈り・なでる動作・すねる姿・エージェントの入力待ちを個別に描画した実際のペットサンプル",
    "alt.petXp": "すばやく5回クリックしたあと、+250K XP のバッジが1つだけ出ているホームヘッダーのサンプル",
    "native.current": "実際の UI レンダー · サンプル状態",
    "c1.t": "図鑑",
    "c1.d": "持ったことのある種族を1マスずつ、1ページ16匹。検索・並べ替え、レア度・色違い・地方の絞り込み、完成バッジがあります。",
    "c2.t": "さまざまな姿",
    "c2.d": "ロトムの家電フォルム、シキジカの季節、アンノーンの文字など、第1〜5世代の姿を集められます。姿は進化しても変わらず、セーブにも残ります。",
    "c3.t": "トークンショップ",
    "c3.d": "使い終わったトークンで、ふしぎなアメ、選んだ性格に変えるミント、ひかるおまもり、新しいタマゴを買えます。",
    "c4.t": "上限を使い切るとふしぎなアメ",
    "c4.d": "5時間か週間の上限を使い切ると、ふしぎなアメがもらえます。まとめて使え、使う前に成長量を確認できます。",
    "alt.shop": "消耗品の数量と合計価格を示す実際のショップUIサンプル",
    "native.shop": "実際のUIレンダー · サンプルトークン · 下に商品が続きます。",
    "grp.settings": "設定とそのほか",
    "x1.t": "8つの言語",
    "x1.d": "アプリの画面は8つの言語に対応。ポケモン・タイプ・特性・技の名前も選んだ言語に従い、翻訳がなければ英語で表示します。",
    "x2.t": "バックアップ",
    "x2.d": "自動スナップショットと破損からの復旧に加え、設定から手動で書き出し・復元もできます。",
    "x3.t": "ショートカット",
    "x3.d": "メニューバーのアイコンを右クリックすると、更新・図鑑・設定などへすぐ移動できます。戻ると元のページに戻ります。",
    "x4.t": "アニメーションの品質",
    "x4.d": "メニューバーとデスクトップペットの動きを、2.5・5・10fpsかオリジナルから選べます。低電力モードでは低く抑えます。",
    "alt.growthMode": "時間を選んだ実際の成長の方式の設定UIサンプル",
    "native.growthMode": "実際のUIレンダー · サンプル設定。",
    "fork.desc": "PokeTokenBar-yp は chattymin の PokeTokenBar をもとにしたフォークです。パートナーも使用量トラッカーも、オリジナルが作ったものです。「PokeTokenBar-yp だけ」の印がある機能はこのフォークだけにあるので、不具合はオリジナルではなくこちらに報告してください。",
    "k1.t": "第1〜9世代の全国図鑑",
    "k1.d": "図鑑は #1025 まであり、タマゴは第1〜9世代の540種類の最初の姿のどれかから始まります。伝説はおよそ48回に1回。地方の絞り込みはカントーからパルデアまでの9地方で、全国バッジは1,025種すべてを数えます。",
    "k3.t": "軽くなったコスト",
    "k3.d": "成長コストとショップの価格は、オリジナルの50分の1です。ノーマルの進化ラインは15Mトークン、伝説は120Mトークンで卒業します。古いバージョンのセーブは、アップデートしても段階内の進み具合をそのまま保ちます。",
    "k4.t": "バトルタブ",
    "k4.d": "YPoke の Slack バトルボットと連携すると、バトルタブに最大6匹を出る順に並べられます。自動ならいま育てているポケモンが出ます。タブの中はエントリー・バトル・履歴に分かれます。各行には実際に戦う能力値が出て、性格で上がる・下がる能力値に↑・↓が付き、フォルムに従います。",
    "alt.gyms": "2列に並んだカントーのジムリーダー・アジト・四天王・バッジケースを示す実際のジム一覧UIサンプル",
    "k5.t": "四天王とチャンピオン",
    "k5.d": "ジムの下のアジトは毎回全回復してから戦う連戦で、負けると最初からやり直しです。その下の四天王の連戦はバッジ8個で開きます。チャンピオンはその地方の伝説を連れてきて、+1 ? とだけ表示されるパートナーを、先の6匹がひんしになるまで隠しています。チャンピオンに勝つと隠れた強者が現れ、初勝利で強力なわざマシン、色違いの伝説のタマゴ、ふしぎなアメがもらえます。ジムのバトルはターンごとに見返せて、メガシンカやフォルムチェンジもその姿で表示されます。",
    "alt.champion": "チャンピオンが隠したパートナーが出てくる実際の四天王連戦UIサンプル",
    "k6.t": "ボックス",
    "k6.d": "ボックスタブには、育成中・フレンド・卒業したポケモンまで、持っているすべての個体が並びます。検索、地方・ランク・色違い・もちものでの絞り込み、並べ替えができます。新しいタマゴを迎えると、いまのポケモンは逃がさずボックスへ。卒業したポケモンを選んで、もう一度育てることもできます。",
    "alt.box": "ポケモン5匹のレベル・マーク・もちものが見える実際のボックスタブUIサンプル",
    "k15.t": "次の進化が見える図鑑",
    "k15.d": "図鑑ページで、そのポケモンが次に何へ進化するか、アプリでは何が必要かを表示します。ゴンベは30回なでるとカビゴンになります。育てているポケモンがその途中にいれば、カードに進み具合が出ます。ホームで次の姿を押すと、そのページが開きます。次の段階があなたの操作を待っていて、アプリを30分閉じたままにすると、そのポケモンはボックスへ移り、次の段階にいちばん近いボックスのポケモンか新しいタマゴが代わりに育ちます。「待ち続ける」ボタンか設定のトグルで止められます。",
    "alt.nextEvo": "30回なでる条件が3/30と表示された実際のカビゴンの図鑑ページUIサンプル",
    "alt.moveOn": "30回なでる必要があるゴンベ、ボックスへ移るまでの残り時間と「待ち続ける」ボタンが見える実際のホームUIサンプル",
    "k7.t": "もちものとメガシンカ",
    "k7.d": "もちものはポケモンのボックスページで持たせます。ショップとバッグでは、バトル用の道具を攻撃アップから天気まで、役割ごとにまとめて表示します。メガストーンを持ったポケモンはバトルの開始時にメガシンカし、ホーム・デスクトップペット・メニューバーでもメガシンカした姿になります。 ショップでは2段目のチップでグループを1つだけ表示でき、検索欄ひとつで道具・タマゴ・わざマシンをアプリのどの言語の名前でも探せます。",
    "alt.held": "攻撃アップ・タイプ強化の見出しの下にもちものが並ぶ実際のショップ・バッグUIサンプル",
    "k8.t": "わざとわざマシン",
    "k8.d": "ポケモンのボックスページには4つのわざが並び、レベルアップわざ・タマゴわざ・わざマシンのわざと1つずつ入れ替えられます。つるぎのまいのような変化わざも使えます。わざマシンはショップで一度買えば、覚えられるすべてのポケモンが使えます。技の枠は一つずつカードに分かれ、▲/▼で隣の枠と入れ替えて順番を決められます。わざの名前はアプリの言語で表示されます。",
    "alt.profile": "能力値・もちもの・がくしゅうそうちの枠・技を示す実際のボックス詳細UIサンプル",
    "k16.t": "とくせい・性格・個体値・フォルム",
    "k16.d": "ジムトレーナーのチームが持てるものは、あなたのポケモンも持てます。ミントは5×5の性格表を開き、選んだ性格に変えます。とくせいカプセルとパッチはとくせいを変え、おうかんは個体値を31に上げます。うつしかがみ・いでんしのくさび・キズナのタヅナはフォルムを変え、フォルムのタイプ・とくせい・能力はそのままバトルに出ます。",
    "alt.naturePicker": "5×5の性格表を開いた実際のボックス詳細UIサンプルと、とくせいカプセル・とくせいパッチ・きんのおうかん、個体値ごとのぎんのおうかん",
    "k9.t": "がくしゅうそうち",
    "k9.d": "ボックスのポケモン1匹に、がくしゅうそうちをつけます。そのポケモンは、いま育てているポケモンやタマゴが得る経験値の50%を一緒に受け取るので、次のポケモンを育てている間も卒業したポケモンが育ち続けます。新しいタマゴでパートナーをボックスに預けると、バッグのがくしゅうそうちを1つそのポケモンにつけます。ボックス画面の「ここに移す」で、ほかのポケモンのがくしゅうそうちを付け替えられます。バッグが空でもかまいません。がくしゅうそうちをつけたボックスのポケモンは、経験値・レベル・フレンド・タイプだけで進める段階ならボックスで進化します。これ以上経験値を使えないポケモンのがくしゅうそうちは、いちばん近いボックスのポケモンに渡ります。もう進む段階がなく育ちきったポケモンは、自動で卒業して図鑑に入ります。バッグに残ったがくしゅうそうちは、次の段階に一番近いポケモンに自動で持たせます。自分で外したポケモンには持たせ直しません。",
    "alt.expShare": "「ここに移す」と「つける」が見える、ボックスのフシギダネの実際の詳細UIサンプル",
    "k10.t": "通信交換とつながりのヒモ",
    "k10.d": "フレンドタブから、つながった同僚と卒業したポケモンを交換できます。ボックスの詳細からそのまま送ることもできます。相手は Slack で承諾します。ゴーストやユンゲラーのように交換で進化するポケモンは、交換するか、ショップのつながりのヒモを使うまで待ちます。イワークとメタルコートのように、先に道具を持たせる必要がある場合もあります。",
    "k11.t": "パートナーのそばのフレンド",
    "k11.d": "卒業したポケモンとボックスで待っているポケモンから、最大2匹までフレンドに選べます。ホームとデスクトップペットで、いまの姿のままパートナーの横に並び、フレンドをなでるとその上にハートが浮かびます。新しいタマゴやスカウトでパートナーをボックスに預けるとき、フレンドの枠が空いていれば、そのポケモンがフレンドに加わります。",
    "alt.storedFriends": "預け中のフシギダネを選べるフレンド選択と、リザードンの横を歩くフシギダネが見える実際のホームUIサンプル",
    "k12.t": "スカウトチケットと、よりよいタマゴ",
    "k12.d": "スカウトチケットは、ひとつの地方か全地方からポケモンを10匹ランダムに見せ、ほしいタマゴを選ばせてくれます。レアのタマゴはレア以上、エピックのタマゴはエピック以上が孵ります。",
    "k13.t": "昼と夜、むずかしい進化",
    "k13.d": "昼と夜は時計で10分ごとに切り替わり、ホームに太陽と月のダイヤルが出ます。特殊な進化の条件はアプリが確かめられる条件に置き換え、進化が止まっているときは理由を知らせます。",
    "k14.t": "自動アップデート",
    "k14.d": "アプリがこのフォークの新しいリリースを自分でインストールします。ダウンロードのチェックサムを確かめ、ポップオーバーが閉じている間に入れ替えます。設定 → アップデートでオフにできます。",
    "comp.title": "いつもの作業に、\n小さな冒険を。",
    "comp.desc": "いつものトークン使用量で、パートナーが本来の進化ルートをたどります。卒業したら新しいタマゴが届き、図鑑が少しずつ埋まっていきます。",
    "journey.hatch": "最初のパートナーに出会う",
    "journey.hatchDesc": "100kトークンで孵化。どのポケモンに出会えるでしょう？",
    "journey.grow": "成長を見守る",
    "journey.growDesc": "コードを書き続けるか、時間モードならいつもどおり作業するだけ。自分のペースに合う方式を選べます。",
    "journey.collect": "思い出を図鑑に",
    "journey.collectDesc": "卒業したパートナーは図鑑に残ります。新しいタマゴと次の物語へ。",
    "comp.caption": "パートナーとの記録が増えていく図鑑。画面例。",
    "alt.collection": "集めたポケモンを表示した図鑑の例",
    "pet.title": "デスクトップでも、一緒。",
    "pet.desc": "パートナーをメニューバーから連れ出しましょう。ドラッグで移動、ホバーで使用量を確認。タマゴをクリックするとお祈り、孵化したポケモンならなでて成長を手伝います。アプリは右クリック → 開くで開きます。",
    "alt.pet": "使用量の吹き出しを表示したデスクトップペットの例",
    "demo.provenance": "画面例 · 英語",
    "demo.play": "デモを再生",
    "demo.stop": "デモを停止",
    "guide.title": "どれくらいで育つ？",
    "guide.desc": "自分のペースで計算して、進化コストや集められるものを確認しましょう。トークンをあまり使わないなら、アプリで時間モードに切り替えてみてください。",
    "g.t1": "成長計算機",
    "g.t2": "パートナーの一日",
    "g.t3": "コレクション",
    "g.costH": "進化に必要なトークン",
    "g.costSub": "リピートボーナスやアイテムなしの3段階進化の例です。最初の孵化に必要な100kトークンは表に含みません。1・2段階進化では同じ合計を異なる比率で分けます。",
    "g.thRarity": "レア度",
    "g.thS1": "段階 1",
    "g.thS2": "段階 2",
    "g.thS3": "段階 3（卒業）",
    "g.thTotal": "合計",
    "rarity.common": "ノーマル",
    "rarity.uncommon": "レア",
    "rarity.rare": "エピック",
    "rarity.legendary": "伝説",
    "g.calcH": "自分のペースだとどれくらい？",
    "g.calcQ": "成長の方式とペースを選んでください。トークンモードはキャッシュ読み込みを含むAIコーディングのトークン全体を数えます。",
    "calc.mode": "成長の方式",
    "calc.modeToken": "トークン",
    "calc.modeTime": "時間",
    "calc.pace": "1日のトークン",
    "g.p1": "ライト · 10M/日",
    "g.p2": "少なめ · 25M/日",
    "g.p3": "ふつう · 44M/日",
    "g.p4": "ヘビー · 100M/日",
    "g.p5": "エージェント艦隊 · 250M/日",
    "calc.hours": "1日のアクティブ時間",
    "calc.h1": "1時間",
    "calc.h2": "2時間",
    "calc.h4": "4時間",
    "calc.h6": "6時間",
    "calc.h8": "8時間",
    "calc.rarity": "レア度",
    "calc.repeat": "以前に卒業させた種族（×2）",
    "calc.nojs": "計算機にはJavaScriptが必要です。トークンコストは上の表をご覧ください。",
    "g.honest": "毎日同じペースの場合の目安です。アイテムやクリックがあればもっと早くなります。",
    "g.dailyIntro": "メニューバーのパートナーは飾りではありません。あなたのコーディングのリズムをそのまま生きています — スプライトとキャプションがリアルタイムに変わります。",
    "g.st1w": "今日の使用量 0",
    "g.st1t": "ぐっすり",
    "g.st1d": "あなたが休めばパートナーも眠ります。週末のメニューバーは静かです。",
    "g.st2w": "ときどき使う",
    "g.st2t": "のんびり",
    "g.st2d": "軽く数回聞いた日は、そばでうろうろ。",
    "g.st3w": "コツコツ作業中",
    "g.st3t": "いっしょに仕事中",
    "g.st3d": "いつものペース。パートナーもせっせと動きます。",
    "g.st4w": "毎分10万トークン以上",
    "g.st4t": "ゾーンに突入",
    "g.st4d": "エージェントが全力疾走中 — パートナーも燃えています。",
    "g.st5w": "上限が目前",
    "g.st5t": "へとへと",
    "g.st5d": "使用上限が近づくと、あなたより先に疲れます。察してあげてください。",
    "g.st6w": "進化 · 卒業の直後",
    "g.st6t": "お祝い",
    "g.st6d": "進化の瞬間と卒業の演出 — 見逃すには惜しい数秒です。",
    "g.dailyNote": "孵化には専用の演出があり、色違いが生まれると演出からして違います。時間モードでは、あなたが作業している間は一緒に働き、離れている間は眠ります。",
    "g.loop": "終わりではなくループ。卒業のたびに図鑑が1マス埋まり、新しいタマゴが届きます。",
    "g.cWhat": "集めるもの",
    "g.cHow": "しくみ",
    "g.c1k": "種族",
    "g.c1v": "第1〜9世代の進化ラインのどれか。最初の姿540種類から、捕獲率の重みで選ばれます。孵化するたびに新しい出会いが待っています。",
    "g.c2k": "レア度",
    "g.c2v": "ノーマル・レア・エピック・伝説の4段階。レアなほど出にくく、卒業までに多くのトークンが必要です。",
    "g.c3k": "✨ 色違い",
    "g.c3v": "孵化のごくまれな幸運 — 専用カラーで、進化しても維持されます。",
    "g.c4k": "せいかく",
    "g.c4v": "孵化ごとに25種類からひとつ — 同じ種族でも印象が変わります。",
    "g.c5k": "分岐進化",
    "g.c5v": "進化が分かれる種族は、まだ図鑑にない方を優先 — 育てるほど図鑑がひとりでに埋まります。",
    "g.c6k": "図鑑",
    "g.c6v": "図鑑は持ったことのある種族を1マスずつ、#1025まで記録します。一匹一匹の個体はボックスにいます。",
    "providers.more": "16のツール、ひとりのパートナー",
    "providers.label": "いつものコーディングツールで",
    "providers.note": "上限はログイン状態によって表示されます：Claude・Codex・Antigravity の公式上限、OpenCode Go の利用枠、Grok CLI のサブスクリプションクレジット。Devin CLI と Kimi Code は費用を記録しないため、費用は表示されません。",
    "faq.title": "よくある質問。",
    "faq.free.q": "無料ですか？",
    "faq.free.a": "はい。無料のオープンソース・ファンプロジェクトです。ショップでは現金ではなく、コーディングで使ったトークンを通貨として使います。",
    "faq.notool.q": "AIコーディングツールは必要ですか？",
    "faq.notool.a": "いいえ。時間モードなら、Macで作業している時間でパートナーが育ちます。使用量と上限の確認には、対応ツールが1つ以上必要です。",
    "faq.privacy.q": "使用量ログを送信しますか？",
    "faq.privacy.a": "いいえ。使用量ログはMac内に保持されます。ただし、プロバイダーの使用量・上限、ポケモンのデータ・スプライト、サービス状態、更新には通信を使います。完全なオフラインアプリではありません。",
    "faq.cost.q": "育成のために追加トークンを使いますか？",
    "faq.cost.a": "いいえ。対応するコーディングツールの使用量を読み取ります。育成のためにモデルを実行することはありません。",
    "faq.fork.q": "オリジナルの PokeTokenBar とは何が違いますか？",
    "faq.fork.a": "PokeTokenBar-yp は chattymin の PokeTokenBar（MIT）をもとにした非公式のフォークです。加わった機能は、機能ページで「PokeTokenBar-yp だけ」と印をつけています。このフォークの不具合は、オリジナルではなくこちらに報告してください。",
    "faq.source.q": "自分でビルドできますか？",
    "faq.source.a": "はい。Swiftのソースコード、ビルド手順、IssueトラッカーをGitHubで公開しています。",
    "footer.source": "ソースコード",
    "footer.releases": "リリースノート",
    "footer.help": "サポート",
    "footer.upstream": "オリジナル: chattymin",
    "footer.sponsor": "支援する",
    "foot.disclaimer": "ポケモンのデータ・スプライトは PokéAPI を使用しています。本プロジェクトは非公式・非商用のファンプロジェクトであり、任天堂・ゲームフリーク・株式会社ポケモンとの提携、推奨、後援、承認はありません。「ポケモン」およびポケモンのキャラクター名は任天堂の商標であり、名前・データ・スプライトの著作権は © Nintendo / Game Freak / The Pokémon Company に帰属し、識別目的でランタイムに利用しています。MIT ライセンスは本プロジェクトのソースコードのみを対象とします。"
  }
};
// pages-i18n.js loads first and holds the feature-page strings.
if (typeof I18N_PAGES !== 'undefined') for (const lang of Object.keys(I18N)) Object.assign(I18N[lang], I18N_PAGES[lang]);
const root = document.documentElement;
const page = document.body.dataset.page || 'home';
const assetRoot = root.dataset.root || '';
const language = document.getElementById('language');
const themeButton = document.getElementById('themeBtn');
const menuButton = document.getElementById('menuBtn');
const navigation = document.getElementById('site-nav');
const copyStatus = document.getElementById('copy-status');
let copyState = '';
let currentLang = 'en';
let storageWorks = false;
try { localStorage.setItem('ptb-probe', '1'); localStorage.removeItem('ptb-probe'); storageWorks = true; } catch (_) {}

function translated(key) { return I18N[currentLang][key] || I18N.en[key] || key; }
function urlLanguage() {
  const value = new URLSearchParams(location.search).get('lang');
  return I18N[value] ? value : null;
}
// Without storage, the language rides along in internal links instead.
function carryLanguage() {
  if (storageWorks) return;
  document.querySelectorAll('a[data-internal]').forEach(a => {
    const target = new URL(a.getAttribute('href'), location.href);
    target.searchParams.set('lang', currentLang);
    a.href = target.href;
  });
}
function applyLanguage(value) {
  currentLang = I18N[value] ? value : 'en';
  root.lang = currentLang;
  language.value = currentLang;
  document.querySelectorAll('[data-i18n]').forEach(element => {
    const value = translated(element.dataset.i18n);
    element.replaceChildren();
    value.split('\n').forEach((line, i) => {
      if (i) element.append(document.createElement('br'));
      element.append(document.createTextNode(line));
    });
  });
  themeButton.setAttribute('aria-label', translated('theme'));
  menuButton.setAttribute('aria-label', translated('nav.menu'));
  document.querySelectorAll('[data-i18n-aria]').forEach(el => el.setAttribute('aria-label', translated(el.dataset.i18nAria)));
  document.querySelectorAll('[data-i18n-alt]').forEach(el => el.setAttribute('alt', translated(el.dataset.i18nAlt)));
  document.querySelectorAll('[data-i18n-image]').forEach(el => {
    const suffix = currentLang === 'en' ? '' : '-' + currentLang;
    el.src = assetRoot + 'assets/' + el.dataset.i18nImage + suffix + '.png';
  });
  if (demoButton) syncDemoLabel();
  if (growthMotionButton) syncGrowthLabel();
  document.title = page === 'home' ? 'PokeTokenBar — ' + translated('hero.h1a') + ' ' + translated('hero.h1b') : translated('meta.' + page + '.title');
  document.querySelector('meta[name="description"]').content = translated(page === 'home' ? 'hero.lead' : 'meta.' + page + '.desc');
  if (copyStatus) copyStatus.textContent = copyState ? translated('copy.' + copyState) : '';
  try { localStorage.setItem('ptb-lang', currentLang); } catch (_) {}
  if (urlLanguage() && urlLanguage() !== currentLang) {
    const url = new URL(location.href);
    url.searchParams.set('lang', currentLang);
    history.replaceState(history.state, '', url);
  }
  carryLanguage();
  if (calc('gTimeline')) renderJourney();
}

function applyTheme(theme) {
  root.dataset.theme = theme;
  themeButton.setAttribute('aria-pressed', String(theme === 'dark'));
  try { localStorage.setItem('ptb-theme', theme); } catch (_) {}
}
themeButton.addEventListener('click', () => applyTheme(root.dataset.theme === 'dark' ? 'light' : 'dark'));
language.addEventListener('change', () => applyLanguage(language.value));
function closeMenu() {
  navigation.classList.remove('is-open');
  menuButton.setAttribute('aria-expanded', 'false');
}
menuButton.addEventListener('click', () => {
  const open = menuButton.getAttribute('aria-expanded') !== 'true';
  navigation.classList.toggle('is-open', open);
  menuButton.setAttribute('aria-expanded', String(open));
  if (open) navigation.querySelector('a').focus();
});
navigation.querySelectorAll('a').forEach(a => a.addEventListener('click', closeMenu));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {closeMenu();menuButton.focus();}
});
matchMedia('(min-width: 1101px)').addEventListener('change', event => {if(event.matches) closeMenu();});

document.querySelectorAll('[data-copy]').forEach(button => {
  button.addEventListener('click', async () => {
    button.disabled = true;
    copyState = 'pending';
    copyStatus.textContent = translated('copy.pending');
    copyStatus.dataset.state = 'pending';
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(button.dataset.copy);
      copyState = 'ok';
      copyStatus.dataset.state = 'success';
    } catch (_) {
      copyState = 'error';
      copyStatus.dataset.state = 'error';
      const range = document.createRange();
      range.selectNodeContents(document.getElementById('install-command'));
      const selection = window.getSelection();
      selection.removeAllRanges();selection.addRange(range);
    } finally {
      button.disabled = false;
      copyStatus.textContent = translated('copy.' + copyState);
    }
  });
});

const tabs = [...document.querySelectorAll('[data-gtab]')];
function selectTab(selected, focus = false) {
  tabs.forEach(tab => {
    const active = tab === selected;
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
    const panel = document.getElementById(tab.getAttribute('aria-controls'));
    panel.hidden = !active;
    panel.setAttribute('role', 'tabpanel');
    panel.setAttribute('aria-labelledby', tab.id);
    panel.tabIndex = 0;
  });
  if (focus) selected.focus();
}
tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next !== undefined) {event.preventDefault(); selectTab(tabs[next], true);}
  });
});

const journeyCopy = {
  en: {hatch:'Hatch',evolve:n=>`Evolution ${n}`,graduate:'Graduate · a new egg arrives',day:n=>`Day ${n}`,hours:h=>`${h} h`,minutes:m=>`${m} min`},
  ko: {hatch:'부화',evolve:n=>`${n}차 진화`,graduate:'졸업 · 새 알 도착',day:n=>`${n}일째`,hours:h=>`${h}시간`,minutes:m=>`${m}분`},
  ja: {hatch:'孵化',evolve:n=>`進化 ${n}`,graduate:'卒業 · 新しいタマゴ',day:n=>`${n}日目`,hours:h=>`${h}時間`,minutes:m=>`${m}分`}
};
const calc = id => document.getElementById(id);
function journeyRows() {
  const multiplier = calc('gRepeat').checked ? BALANCE.repeatGrowthMultiplier : 1;
  const total = BALANCE.graduationTotal[calc('gRarity').value];
  let tokens = BALANCE.eggHatchThreshold;
  const rows = [{stage:0,tokens}];
  for (let stage = 1; stage <= 3; stage++) {
    tokens += total * stage / 6 / multiplier;
    rows.push({stage,tokens});
  }
  return rows;
}
function renderJourney() {
  const timeMode = calc('gMode').value === 'time';
  calc('gPaceField').hidden = timeMode;
  calc('gHoursField').hidden = !timeMode;
  const perHour = BALANCE.timeTokensPerActiveSecond * 3600;
  const perDay = timeMode ? Number(calc('gHours').value) * perHour : Number(calc('gPace').value) * 1e6;
  const s = journeyCopy[currentLang];
  calc('gTimeline').replaceChildren(...journeyRows().map(({stage,tokens}) => {
    const row = document.createElement('div');row.className='tl-row';
    const label = document.createElement('span');label.textContent = stage === 0 ? s.hatch : stage === 3 ? s.graduate : s.evolve(stage);
    const amount = document.createElement('span');amount.className='tl-tokens';amount.textContent=formatTokens(tokens);
    const day = s.day(Math.max(1, Math.ceil(tokens / perDay)));
    const hours = tokens / perHour;
    const when = document.createElement('span');when.className='tl-when';
    const active = hours < 1 ? s.minutes(Math.ceil(hours * 60)) : s.hours(hours < 10 ? Math.round(hours * 10) / 10 : Math.round(hours));
    when.textContent = timeMode ? `${active} · ${day}` : day;
    row.append(label,amount,when);return row;
  }));
}
if (calc('gTimeline')) ['gMode','gPace','gHours','gRarity','gRepeat'].forEach(id => calc(id).addEventListener('change', renderJourney));

const demoButton = document.getElementById('demoBtn');
const demoImage = document.getElementById('pet-demo');
function syncDemoLabel() {
  demoButton.querySelector('span').textContent = translated(demoButton.getAttribute('aria-pressed') === 'true' ? 'demo.stop' : 'demo.play');
}
function setDemoPlaying(playing) {
  demoButton.setAttribute('aria-pressed', String(playing));
  demoImage.src = assetRoot + (playing ? 'assets/floating-pet.gif' : 'assets/floating-pet-still.png');
  syncDemoLabel();
}
if (demoButton) {
  demoButton.addEventListener('click', () => setDemoPlaying(demoButton.getAttribute('aria-pressed') !== 'true'));
  matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', event => { if(event.matches) setDemoPlaying(false); });
}

const growthMotionButton = document.getElementById('growth-motion');
const growthMotionPreference = matchMedia('(prefers-reduced-motion: reduce)');
function syncGrowthLabel() {
  growthMotionButton.querySelector('span').textContent = translated(growthMotionButton.getAttribute('aria-pressed') === 'true' ? 'growth.pause' : 'growth.play');
}
function setGrowthPlaying(playing) {
  growthMotionButton.setAttribute('aria-pressed', String(playing));
  document.querySelectorAll('[data-growth-sprite]').forEach(img => {
    img.src = `${assetRoot}assets/growth/${img.dataset.growthSprite}.${playing ? 'gif' : 'png'}`;
  });
  syncGrowthLabel();
}
if (growthMotionButton) {
  growthMotionButton.addEventListener('click', () => setGrowthPlaying(growthMotionButton.getAttribute('aria-pressed') !== 'true'));
  growthMotionPreference.addEventListener('change', event => { if (event.matches) setGrowthPlaying(false); });
}

let initialLanguage = navigator.language.slice(0,2);
try { initialLanguage = localStorage.getItem('ptb-lang') || initialLanguage; } catch (_) {}
applyLanguage(urlLanguage() || initialLanguage);
applyTheme(root.dataset.theme === 'dark' ? 'dark' : 'light');
if (tabs.length) selectTab(tabs[0]);
// Keep baseline content available if script initialization fails or JavaScript is disabled.
root.classList.add('js');

if (growthMotionButton) setGrowthPlaying(!growthMotionPreference.matches);
