---
summary: "릴리스 실행 절차 — 문서·에셋 갱신 의무, 스크린샷 재생성 방법, release.sh 게이트의 함정."
read_when:
  - 버전을 배포할 때 (자연어 트리거 포함: "배포해줘", "릴리스 올려줘", "패치 배포")
  - release.sh 가 문서·에셋 경고나 하드 게이트로 중단됐을 때
  - UI 를 바꿔 스크린샷·랜딩을 갱신해야 할 때
---

# 릴리스 실행 절차

버전 결정 규칙과 트리거는 `CLAUDE.md` §릴리스에 있다. 이 문서는 그 다음의 *실행 세부*를 담는다.
체크리스트 원본은 `RELEASE.md`.

## 0. 포크 버전 — SemVer (사용자 결정 2026-11-17)

이 포크(`w8385/PokeTokenBar-yp`)는 업스트림과 따로 자기 SemVer 를 쓴다. 첫 버전은 **3.0.0** 이다.
`v2.5.7-ypN` 꼬리표는 새 릴리스에 쓰지 않는다(yp40 까지 나갔다).

- 버전 문자열은 하나다. `CFBundleShortVersionString` 과 `PTBForkVersion` 둘 다 `X.Y.Z` 이고 태그는 `vX.Y.Z` 다.
  `PTBForkVersion` 키는 지우지 않는다 — `UpdateChecker` 가 현재 버전으로, `SelfUpdater` 가 받은 앱 검증으로 읽는다.
- 세그먼트: 사용자가 패치/마이너/메이저를 말하면 그 말대로(`CLAUDE.md` §릴리스). 말이 없으면
  train 범위에 `feat` 커밋이 하나라도 있으면 **마이너**(3.0.0 → 3.1.0), 아니면 **패치**(3.1.0 → 3.1.1).
  메이저는 사용자가 깨짐을 지정할 때만.
- 게시는 `scripts/fork-release.sh vX.Y.Z notes.md` 다. 태그에서 버전을 읽어 `PTB_VERSION` 으로 빌드하고,
  두 키가 태그와 같은지, 최신 공개 릴리스보다 새 버전인지 확인한다. Xcode 메이저 게이트(`xcode-pin.sh check`)도 그대로다.
  `PTB_DRY_RUN=1` 이면 빌드·zip 까지 하고 게시하지 않는다.
- 서명: `fork-release.sh` 는 키 파일(`~/.config/ptb-signing`) 없이는 거절한다. 빌드는 `PTB_SIGN_WITH_KEY=1`·`PTB_REQUIRE_STABLE_SIGN=1` 이고,
  빌드 뒤 designated requirement 에 `cdhash` 가 없는지와 `codesign --verify --deep --strict` 를 태그 전에 확인한다.
  ad-hoc 이면 DR 이 cdhash 라 업데이트마다 사용자의 Keychain "항상 허용"이 풀린다. 백그라운드 세션은 login keychain 에 못 닿아 키체인 신원을 쓰지 않는다.
  만들기·분실 영향은 RELEASE.md "포크 릴리스". 회귀: `WorkflowInvariantTests.testForkReleaseNeverShipsAnAdHocSignedBuild`.
- 자산 이름 `PokeTokenBar-yp-arm64.zip`·`.sha256` 은 바꾸지 않는다 — 설치된 앱(yp7 이후)의 `SelfUpdater` 가 이 이름을 찾는다.
- 옛 앱도 넘어온다: yp7 이후의 `isNewer` 는 숫자 부분을 먼저 비교하고 `-ypN` 은 같을 때만 본다.
  그래서 `3.0.0 > 2.5.7-ypN` 이다. 회귀: `UpdateCheckerTests.testSemverReleasesOutrankEveryForkSuffixRelease`,
  `testForkSuffixInstallIsOfferedTheFirstSemverRelease`, `SelfUpdaterTests.testStagesASemverReleaseWhoseBundleCarriesTheSameVersion`.

## 1. 문서·이미지 갱신 (매 릴리스 필수 — "할까요?" 묻지 말고 무조건 한다)

`./scripts/release.sh --check-only`(업스트림) 또는 `./scripts/fork-release.sh --check-only <직전 릴리스 태그>`(포크·train)로
경고를 확인한 뒤 아래를 모두 반영한다. 두 스크립트는 같은 검사(`scripts/release-asset-gate.py`)를 부른다.

- **README.md/ko/ja**: 기능 목록·how-it-works·스크린샷 참조.
- **랜딩(gh-pages orphan 브랜치) — 필수.** `git worktree add /tmp/ptb-ghpages gh-pages` → `index.html`
  기능 카드(f#) + i18n 사전(en/ko/ja 동시·키 정합) 갱신 → 커밋 → `git push origin gh-pages` →
  `git worktree remove`. (Pages 자동 재빌드. 커밋은 gh-pages log 모방 = `landing:` 프리픽스.)
- **스크린샷(`assets/`)**: UI(`Sources/PokeTokenBar/UI/`) 변경 시 재생성. 기존 방식 = **HTML 렌더**
  (팝오버 라이브 캡처 아님) — Chrome `--headless --screenshot --force-device-scale-factor=2` 로 다크
  팝오버를 720px PNG 로 그린다. 애니 GIF(home)는 프레임 합성 후 `gifsicle -O3 --lossy` 로 최적화
  (PIL 재인코딩 단독은 용량 팽창 주의). 언어별 이미지(`settings.png`/`-ko`/`-ja` 등) 각 README 참조.
  테스트로 뜨는 캡처(`PTB_*_DIR` 환경변수, `swift test --filter <Suite>`)는 `OffscreenRender` 로 화면 밖에서 그려서
  앱을 띄우거나 창을 보이지 않는다 — 릴리스 중에도 사용자의 포커스를 건드리지 않는다.
  README 팝오버 화면(홈·상점·가방·도감·박스·프로필·학습장치·대결·체육관·리플레이·플로팅 친구)은
  `PTB_README_SHOT_DIR=assets swift test --filter ReadmeScreenshotTests` 한 번으로 en/ko/ja 다크 720px 를 다시 그린다.
  샘플 세이브(`BoxDexFixture`)와 봇의 관동 체육관 목록을 쓰고, 사용자 세이브는 읽지 않는다.
- homebrew-tap cask caveat.

### 게이트의 함정

- `release.sh` 문서검토는 *커밋된* 상태를 비교 → 스크린샷을 스테이징만 하면 경고 프롬프트가
  여전히 뜬다. 갱신을 미리 커밋한다. 릴리스 커밋에는 이미 스테이징된 다른 변경도 함께 담기므로 대상도 확인한다.
- **신규 기능 = 신규 에셋 (하드 게이트, 프롬프트로 못 넘김).** 직전 태그 이후 `Sources/**/UI/` 를 건드린
  `feat:` 커밋이 있는데 `assets/` 에 **새로 추가된** 파일이 없으면 `release.sh` 가 중단한다
  (**예외 없음** — 통과시키려면 에셋을 만들거나 커밋 타입을 바꿔야 한다). 기존 staleness 검사는 "에셋이 하나라도 바뀌었나"만
  보기 때문에 **기존 스크린샷만 다시 그려도 통과**한다 — 2.5.0 에서 플로팅 펫이 이미지 없이 나간 경로가
  정확히 이것이다(`settings.png` 를 갱신해 둔 탓에 조용히 통과). 갱신(stale)과 커버리지(신규)는 다른 질문이다.
  새 에셋은 **README 이미지**(`assets/screenshot-*`·`settings*`·최상위 GIF)이고 **README 셋 모두에 실려야** 센다.
  `assets/trainers/` 같은 앱 리소스는 세지 않는다.
- **화면별 갱신 검사.** `release-asset-gate.py` 의 `SCREENS` 표가 UI 파일을 그 화면의 이미지 묶음(`screenshot-shop` 등,
  `-ko`/`-ja` 포함)에 잇는다. 바뀐 UI 파일마다 그 묶음 하나는 언어별 이미지가 모두 다시 그려져야 한다 — 다른 화면 이미지를
  다시 그려도 넘어가지 않는다. 표에 없는 UI 파일만 "README 이미지가 하나라도 바뀌었나"로 본다. 새 화면을 README 에 올리면 표에도 더한다
  (`ScreenMapTests` 가 표의 글롭·이미지가 실제로 있는지 본다).
- **포크·train 경로도 같은 게이트를 지난다.** `fork-release.sh` 는 빌드 전에 `gh release view` 로 읽은 직전 릴리스 태그를
  기준으로 게이트를 돌리고, 경고(1)와 하드 게이트(2) 모두에서 멈춘다(프롬프트 없음). train 은 태그를 먼저 push 하므로
  `git describe` 를 기준으로 쓰면 범위가 비어 늘 통과한다 — 그래서 기준은 직전 *릴리스* 태그다.
  검토를 마친 예외만 `PTB_ASSET_GATE_SKIP="<사유>"` 로 넘기고, 사유는 게시되는 릴리스 노트 끝에 찍힌다.
- **랜딩.** 포크(`w8385/PokeTokenBar-yp`)에는 아직 `gh-pages` 브랜치와 Pages 가 없다. 랜딩 갱신은 업스트림 `gh-pages` 를
  받아 만든 로컬 브랜치에 `landing:` 커밋으로 두고, 게시는 통합자가 정한다.

## 2. 실행

먼저 `RELEASE.md`의 릴리스 노트·기여자 절차에 따라 준비한다.

- `release-notes-template.md`를 복사하고 v2.5.3처럼 영어 New / Fixed / Other / Contributors 및
  Install / Upgrade를 작성한다. 필수 섹션을 지우거나 `Release vX.Y.Z` 한 줄로 대체하지 않는다.
- 직전 공개 릴리스 태그부터 배포 대상까지의 PR·직접 커밋을 확인해 외부 기여자 목록을 만든다.
  PR 작성자와 실제 공동기여자를 빠짐없이 확인하고 `PTB_CONTRIBUTORS_FILE`과 노트의 Contributors를 맞춘다.
  기존 릴리스 목록 재사용이나 날짜만으로 범위를 정하는 방식은 쓰지 않는다.
- 실제 공동작업이 확인된 릴리스 준비 커밋만 `PTB_COAUTHORS_FILE`에 참여자의 이름·이메일을 지정한다.
  기본은 없음이며 Claude/Codex 등 특정 이름을 자동으로 붙이지 않는다.
- 노트 원문과 기여자 목록 검사를 마친 뒤 적용 버전과 노트 요약을 사용자에게 보여준다.

그 다음 반드시 `main` 브랜치에서:

```bash
# 직전 릴리스 이후 변경을 요약해 노트 파일 작성
PTB_NOTES_FILE=/tmp/ptb-notes.md PTB_CONTRIBUTORS_FILE=/tmp/ptb-contributors.txt ./scripts/release.sh <version>
```

스크립트가 노트·Contributors 검증 → test-gate → 문서검토 → 범프 → 빌드검증 → 커밋·push →
GitHub Release → cask → Pages를 순서대로 수행한다. 빌드 단계에서 기존 로컬 앱 종료·교체도 수행한다.
노트나 기여자가 누락되면 앱 교체·push 전에 중단하며, 게시에는 검증한 노트 파일을 그대로 사용한다.

## 3. 검증

완료 후 `brew upgrade --cask poke-token-bar` 로 실제 업그레이드 동작을 확인한다.
