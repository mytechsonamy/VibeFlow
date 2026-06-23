# Sprint 60 — Team work: paralel iş-akışları (work-streams)

## Context

Bir kullanıcı bir fonksiyonu geliştirirken başka bir kullanıcının paralel olarak
başka bir fonksiyonla ilerleyebilmesi isteniyor. Bugün VibeFlow bunu
**desteklemiyor**: orkestrasyon katmanı tek bir `projectId` + tek bir
`.vibeflow/state/lifecycle.json` + tek bir `currentPhase` varsayıyor. Aynı dizinde
iki branch aynı state'i ezer; aynı anda yalnız bir cycle açık olabilir. (v1.x'te
Postgres tabanlı "team mode" vardı, Sprint 11 / v2.0.0'da bilerek kaldırıldı.)

**Kritik bulgu — alt katman zaten hazır:** `sdlc-engine` MCP'sinin *her* tool'u
`projectId`'yi çağrı-başına zorunlu argüman olarak alıyor
(`mcp-servers/sdlc-engine/src/tools.ts` — `projectId: z.string().min(1)` her
tool'da), ve `FilesystemStateStore` her `projectId`'yi kendi
`proper-lockfile`-kilitli `.vibeflow/state/<projectId>/` dizininde tam izole
tutuyor (`src/state/filesystem.ts:54-143`, `transact(projectId, …)`). Yani N adet
bağımsız SDLC durumu (her biri kendi `currentPhase`/criteria/consensus'u ile)
*zaten* mümkün — engine'i değiştirmeye gerek yok. Boşluk tamamen skill/hook
katmanında.

**Karar (operatörle netleşti):** izolasyon = git branch/worktree başına; her
feature kendi fazlarını **bağımsız** ilerletir; birleşme yalnızca
entegrasyon/DEPLOYMENT'ta bir **merge noktasında** olur.

**Tasarım ilkesi:** Bir **work-stream (akış)** = bir feature = bir git branch
(genelde bir worktree) = bir `projectId` = bir bağımsız SDLC cycle (kendi
`currentPhase` + criteria + consensus + lifecycle'ı ile). Akışlar bağımsız akar;
git'in kendisi (kod) ve bir entegrasyon-cycle'ı birleşme noktasıdır.

Mevcut kod konvansiyonuna uyum için tüm davranış **opt-in** bir config bayrağının
arkasına alınır (`streams.enabled`, **default false**) — aynen `autoApply` /
`gates` / `globalLearning` gibi. Kapalıyken bugünkü tek-akış davranışı bit-bit
korunur, dolayısıyla mevcut 3514 test kırılmaz.

## Yaklaşım

`projectId`'yi branch'ten türeterek her akışa kendi izole engine-state'i +
lifecycle'ı verilir; bir registry tüm aktif akışları görünür kılar; bir
entegrasyon skill'i birleşme noktasını çalıştırır. Engine/MCP'de **kod değişikliği
yok** (sadece yeni opsiyonel `StreamsConfigSchema`).

### Faz A — Temel: stream kimliği (davranış değişikliği yok, opt-in)

- **`mcp-servers/sdlc-engine/src/config.ts`**: yeni `StreamsConfigSchema`
  (`enabled: false`, `idStrategy: "branch" | "fixed"` default `"branch"`) +
  `EngineConfigSchema`'ya `streams` alanı + `loadFileConfig`'te aynı silent-fallback
  deseni. Birim test: `mcp-servers/sdlc-engine/tests/config.test.ts` (defaults +
  partial-merge), `autoApply`/`gates` testleriyle aynı kalıp.
- **`hooks/scripts/_lib.sh`**: yeni `vf_stream_id` helper. `streams.enabled` false
  → bugünkü `vf_project` (config.project / "default"). true → `<base>__<slug>`,
  slug = `git rev-parse --abbrev-ref HEAD` slugify'ı (`/`→`-`, `[^a-z0-9_-]`→`-`,
  lowercase, 64'e clamp; engine'in `validateProjectId` regex'ine
  [`filesystem.ts:459`] uyumlu). Git repo değilse / detached HEAD'de base'e düşer.
  Override: `VIBEFLOW_STREAM` env. Default branch (`main`/`master`) → base'e eşit
  kalır (mevcut projeler yeniden adlandırılmaz; geriye-uyum). Hook testi:
  `hooks/tests/run.sh` (off→base, on+branch→slug, on+main→base, detached→base,
  override→env).

### Faz B — Akış-başına state + lifecycle

- **`lifecycle.json` akış-başına taşınır:** `.vibeflow/state/lifecycle.json` →
  `.vibeflow/state/<streamId>/lifecycle.json` (o akışın `project.json`'ı ile yan
  yana). Şu üç skill'in lifecycle okuma/yazma yolu `vf_stream_id` üzerinden
  çözülür: `skills/onboard/SKILL.md` (Step 0 resume-guard),
  `skills/phase-runner/SKILL.md` (Step 0), `skills/brownfield-intake/SKILL.md`.
  `streams.enabled` false iken yol bugünkü tekil konuma denk gelir (base streamId).
- **MCP çağrıları stream-scoped:** Bu skill'lerdeki `sdlc_*` tool çağrıları
  `projectId` olarak `vf_stream_id` sonucunu geçirir (bugün config.project'i
  geçiyorlar). Engine zaten per-call projectId aldığı için bu yeterli — her akış
  kendi kilitli state-dizininde ilerler.
- **State commit edilmez:** `.vibeflow/state/`'in gitignore'da kalması doğrulanır
  (akışlar `project.json`/`lifecycle.json` üzerinde merge çakışması yaşamasın;
  state event-sourced/yeniden-üretilebilir, `bin/replay-events.sh` mevcut). Worktree
  başına ayrı çalışma dizini → fiziksel izolasyon; branch-türevli projectId →
  aynı dizinde branch değişiminde bile mantıksal izolasyon (savunma derinliği).

### Faz C — Görünürlük: kim ne üzerinde çalışıyor

- **`hooks/scripts/streams-audit.sh`** (yeni, salt-okunur, `loop-audit.sh` ile aynı
  guardlı-JSON deseni): `.vibeflow/state/` altındaki tüm `<streamId>/` dizinlerini
  tarar, her biri için `{streamId, branch, currentPhase, cycleStatus, owner,
  updatedAt}` döker (owner = `git config user.name`). Boş/eksik durumda güvenli
  şekilde degrade eder.
- **`/vibeflow:streams`** (yeni skill, salt-okunur, `loop-status` deseni):
  streams-audit.sh çıktısını "akış → branch → faz → durum → sahip" panosu olarak
  render eder, çakışan (aynı branch'e işaret eden iki akış) durumları işaretler,
  `.vibeflow/reports/streams.md` yazar. `phase-policy.json`'a ALL/read-only kaydı.
- **`skills/flow-status/SKILL.md`**: `streams.enabled` açıkken tek satırlık
  "N aktif akış (`/vibeflow:streams`)" özeti ekler; kapalıyken sessiz.

### Faz D — Merge noktası: entegrasyon cycle'ı

- **`/vibeflow:integrate`** (yeni skill): entegrasyon/release branch'inde çalışır.
  (1) Hangi feature-akışlarının merge olduğunu git geçmişinden saptar; (2) o branch
  için bir **entegrasyon stream'i** (`<base>__<integration-branch-slug>`) açar ve
  `sdlc_start_cycle` ile cycle'ını başlatır; (3) birleşik yüzey üzerinde
  **`/vibeflow:integration-verifier`**'ı koşar (zaten stack-agnostik; gerçek
  back-end'i lokal ayağa kaldırıp seeded data ile FE↔BE'yi sürer —
  `skills/integration-verifier/SKILL.md`) + cross-feature consensus; (4)
  entegrasyon stream'inde DEPLOYMENT GO = gerçek ship. Bağımsız akışlar burada,
  state'te değil **kodda** (git merge) + tek bir entegrasyon-gate'inde uzlaşır.
- **`skills/phase-runner/SKILL.md`** Step 0: feature-branch mi entegrasyon/base
  branch mi olduğunu saptayıp stream id'yi yüzeye çıkarır; base branch'te
  `/vibeflow:integrate` breadcrumb'ı verir.

### Dokümantasyon
- **`docs/TEAM-WORK.md`** (yeni — Sprint 11'de retired edilen `TEAM-MODE.md`'nin
  yerine, ama yeni stream-modeliyle): worktree-başına akış kurulumu, opt-in
  config, registry/pano, merge noktası, tek-makine vs çok-makine kapsam notu.
- `docs/LIFECYCLE.md` + `CLAUDE.md` Key Commands: stream-farkındalığı güncellemesi.

## Kapsam dışı / bilinçli sınırlar
- **Çok-makine / uzak paylaşımlı state yok (v1):** state lokal kalır; pano
  makine-başınadır. Farklı dizüstülerdeki iki geliştirici, paylaşımlı state'le
  değil **git ile** (kod + entegrasyon-cycle) uzlaşır — "git tek doğruluk kaynağı"
  ilkesiyle uyumlu. İleride opsiyonel remote-registry ayrı sprint.
- **Engine/MCP davranışı değişmez** — sadece yeni opsiyonel `StreamsConfigSchema`.
- State commit edilmez (merge çakışması riskinden kaçınmak için).

## Değiştirilecek kritik dosyalar (özet)
- `mcp-servers/sdlc-engine/src/config.ts` (+`StreamsConfigSchema`), `tests/config.test.ts`
- `hooks/scripts/_lib.sh` (+`vf_stream_id`), `hooks/tests/run.sh`
- `skills/{onboard,phase-runner,brownfield-intake,flow-status}/SKILL.md`
- `hooks/scripts/streams-audit.sh` (yeni), `skills/streams/SKILL.md` (yeni)
- `skills/integrate/SKILL.md` (yeni), `hooks/scripts/phase-policy.json` (kayıtlar)
- `docs/TEAM-WORK.md` (yeni), `docs/LIFECYCLE.md`, `CLAUDE.md`
- `tests/integration/sprint-60.sh` (yeni — sentineller + runtime probe'lar)

## Doğrulama
- `streams.enabled` **kapalı** iken regresyon yok: tam baseline yeşil kalmalı —
  `cd mcp-servers/sdlc-engine && npm test` (config testleri 202→+N), `bash
  hooks/tests/run.sh`, `bash tests/integration/run.sh`.
- `vf_stream_id` runtime probe: geçici git repo'da branch oluştur → on/off/main/
  detached/override dört-beş durumda doğru streamId (hook testinde).
- İki-akış izolasyon runtime probe (sprint-60.sh): iki ayrı branch-slug için
  `sdlc_get_state`/`sdlc_satisfy_criterion` çağrılarının ayrı
  `.vibeflow/state/<id>/project.json` ürettiğini ve birbirini ezmediğini doğrula.
- `streams-audit.sh` probe: iki stream-dizini seed et → ikisini de listelediğini,
  çakışan branch'i işaretlediğini doğrula.
- Faz D el-ile e2e: bir entegrasyon branch'inde `/vibeflow:integrate` →
  integration-verifier'ın gerçek BE'yi ayağa kaldırıp data-binding senaryolarını
  sürdüğünü gözle.
- Her faz kendi sprint dosyası + integration suite ekiyle (repo'nun sprint
  disiplinine uygun); `sprint-60.sh` self-audit ([S60-Z]).
