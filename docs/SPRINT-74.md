# Sprint 74 — Consensus dedup is language-aware (lexical + structural + semantic) ✅ COMPLETE

> Shipped: hooks 227→237, `tests/integration/sprint-74.sh` 42/0. v2.61.0.

## Context

Clera'da yakalanan bug: `consensus-aggregator.sh` kritik bulgu dedup'ı, başlıkları
`ascii_downcase | gsub("[^a-z0-9 ]"; " ")` ile tokenize edip **Jaccard(title) ≥ 0.6**
arıyor. Bu tokenizer ASCII-dışı harfleri (ö/ğ/ı/ş/ü/ç) **siliyor** — katlamıyor —
yani Türkçe kelimeleri parçalıyor; üstüne Türkçe eklemeli olduğu için aynı kelime
farklı ekle farklı token oluyor. Sonuç: iki reviewer'ın **aynı** bulgusu 2 ayrı
kritik sayılıyor → `rejected>=1 and criticalTotal>=2` kuralı tetikleniyor →
**yanlış REJECTED**.

Bugu jq ile birebir üretip ölçtüm:

| çift | legacy J | birleşir mi? |
|---|---|---|
| "Özkaynağına faiz devri hesaplanmıyor" / "Özkaynağa faiz devir hesabı eksik" | 0.25 | ✗ (olmalıydı ✓) |
| "Şirket özkaynağı için işlem ücreti yanlış" / "…işlem ücretinde hata" | 0.43 | ✗ (olmalıydı ✓) |
| "Missing input validation on IBAN field" / "IBAN field lacks input validation" | 0.67 | ✓ |

Legacy tokenizer `özkaynağına → ["zkayna"]`, `işlem → ["lem"]`, `ücreti → ["creti"]`
üretiyor. Yani dedup **fiilen sadece İngilizce çalışıyor**.

Kritik ikinci bulgu (kalibrasyondan): **eşiği düşürmek çözüm değil.** 13 çiftlik
korpusta gerçek duplikatlar 0.2–0.55, gerçekten farklı bulgular 0.5'e kadar çıkıyor —
aralıklar örtüşüyor. Eşiği düşürmek iki *farklı* kritiği birleştirir → **sahte
APPROVED**, ki yanlış REJECTED'dan daha tehlikeli. Bu yüzden düzeltme üç katmanlı:
leksik katman dürüstçe sadece *yakın-birebir* duplikatları yakalar, yeniden ifade
edilmiş duplikatlar semantik katmana devredilir.

Aynı bozuk tokenizer `consensus-aggregator.sh`'in **reviewer-memory theme-aware
compaction** bloğunda (`norm`/`jac`, S21-B) da var — tekrarlayan tema katlaması da
Türkçe'de çalışmıyor.

Hedef: consensus dedup dilden bağımsız çalışsın; leksik bir kaçırma **asla** tek
başına verdict'i çeviremesin; birleştirme gerekçesi denetlenebilir olsun
(`dedupNote`).

## Değişiklikler

### [S74-A] Dil-bağımsız başlık normalizasyonu — tek kaynak (`hooks/scripts/_lib.sh`)

Yeni bir paylaşılan jq prelude'ü (`VF_JQ_TITLE_SIM` bash değişkeni; `_lib.sh` zaten
her hook tarafından source ediliyor), iki jq bloğuna da prepend edilir:

- `fold(t)`: diakritikleri **ASCII'ye katlar, silmez** (ı/İ/I→i, ş→s, ğ→g, ö→o,
  ü→u, ç→c + yaygın latin â/é/ô/ñ/ß), sonra `ascii_downcase`, sonra alfanümerik-dışı
  → boşluk.
- `tmatch(a; b)`: iki token aynıysa **veya** karakter-trigram benzerliği ≥ 0.5 ise
  aynı kelime sayılır (ek düşmesi/eklenmesi toleransı: `devri`↔`devir`,
  `oranı`↔`oranları`).
- `title_sim(a; b)`: fold'lanmış token setleri üzerinde tmatch-tabanlı simetrik
  örtüşme oranı. **Eşik 0.6 sabit kalır** — İngilizce davranış bit-bit aynı.

Ölçülen etki (aynı korpus): morfolojik TR duplikatları 0.5→0.75 / 0.6→0.83 ile
birleşir; farklı bulguların hiçbiri 0.5'i geçmez (sahte birleştirme yok).

Aynı prelude reviewer-memory compaction bloğundaki `norm`/`jac`'in yerine geçer —
tek kaynak, bir daha ıraksamaz.

### [S74-B] Yapısal dedup güçlendirilir (`consensus-aggregator.sh`, `dedup_critical`)

Bugün: `target.file` eşit **ve** `target.line_range` **tam eşit** → aynı bulgu.
`line_range` `[start, end]` dizisi, iki reviewer aynı defekt için `[12,20]` ve
`[14,18]` verirse birleşmiyor.

Yeni kural: aynı dosya **ve** aralıklar **örtüşüyorsa** aynı bulgu
(`a.start <= b.end and b.start <= a.end`). İki taraf da aralık vermemişse yapısal
birleştirme yapılmaz (yalnız-dosya eşleşmesi farklı bulguları yutardı) — o durumda
leksik katman karar verir. Dilden tamamen bağımsız kazanç.

### [S74-C] Leksik kaçırma tek başına verdict'i çeviremez — `escalatedByCriticalCount`

`consensus-aggregator.sh` verdict.json'a yeni alan yazar:

```
escalatedByCriticalCount: (status=="REJECTED" ve bunu SADECE
  `rejected>=1 and criticalTotal>=2` kuralı tetiklediyse true;
  reject-çoğunluğu varsa false)
dedupMethod: "structural+lexical"
```

`criticalRawCount` / `criticalDeduped[]` zaten yazılıyor — korunur.
`consensus-run.sh` finalize özet JSON'una `escalatedByCriticalCount` +
`criticalDeduped` eklenir (phase-runner dallanabilsin).

### [S74-D] Semantik dedup turu — yalnızca-indirgeyen (model tarafı)

Aggregator bash/jq; semantik olamaz. Modelin döngüde olduğu iki yerde
(`skills/phase-runner` Step 3b — `consensus-run.sh --finalize` sonrası, MCP ile
consensus **kaydedilmeden önce**; ve `skills/consensus-orchestrator` Step 5 — verdict
okunduktan sonra) yeni bir adım:

**Tetik:** yalnızca `status == "REJECTED" && escalatedByCriticalCount == true`.
Başka hiçbir durumda çalışmaz (maliyet yok).

**İş:** model `criticalDeduped[]` içindeki başlık+rationale+target'ları okur, aynı
temel defekti anlatanları gruplar.

**Güvenlik korkulukları (sert):**
- Sadece `REJECTED → NEEDS_REVISION` indirebilir. **Asla** APPROVED'a yükseltemez.
- Reject-çoğunluğuyla gelen REJECTED'a **dokunamaz** (zaten tetiklenmez).
- `criticalTotal`'ı **artıramaz**.
- Ayrı defekt sayısı ≥ 2 çıkarsa REJECTED aynen kalır (semantik onay da not edilir).

**İz:** verdict.json'a `dedupNote` yazılır
(`{rawCount, lexicalCount, semanticCount, groups:[{mergedIds, reason}], decidedBy:"claude", at}`),
top-level `status`/`criticalTotal` + son `rounds[]` girdisi düzeltilir, ve
`history.jsonl`'a `{type:"semantic-dedup", sessionId, round, from, to, rawCount,
lexicalCount, semanticCount}` satırı eklenir (Sprint 20/24 telemetri deseniyle aynı).

### [S74-E] Reviewer başlık sözleşmesi (`agents/claude-reviewer.md` + orchestrator/consensus-run reviewer prompt'u)

`criticalIssues[].title` **İngilizce, ≤10 kelime** istenir (artefakt Türkçe olsa bile;
`rationale` artefaktın dilinde kalabilir), ve `target.file` + `line_range` **her zaman**
doldurulur. Ucuz mitigasyon — leksik dedup'ı ve reviewer-memory tema katlamasını tek
dile sabitler. Zorlanamaz (CLI reviewer uymayabilir), bu yüzden A/B/C'nin **yerine
değil yanına**. `claude-reviewer.md`'deki eski "Jaccard ≥ 0.6" dedup açıklaması yeni
üç katmanı anlatacak şekilde güncellenir.

## Testler

- `hooks/tests/run.sh` — S74 runtime probe'ları: TR morfolojik duplikat birleşir /
  TR farklı bulgu birleşmez (sahte-merge regresyonu) / İngilizce çift bit-bit aynı /
  örtüşen `line_range` birleşir + aralıksızlar birleşmez / `escalatedByCriticalCount`
  reject-çoğunluğunda false, kritik-eşiği tetiğinde true / reviewer-memory compaction
  TR temayı katlar.
- `tests/integration/sprint-74.sh` (yeni) — statik sentinel'ler: prelude `_lib.sh`'de
  tek kaynak; her iki jq bloğu onu kullanıyor; eski `gsub("[^a-z0-9 ]"` idiomu
  aggregator'da kalmadı; iki skill'de semantik adım + **yalnızca-indirgeyen** korkuluk
  metni + `dedupNote` + history satırı; `claude-reviewer.md` İngilizce-başlık
  sözleşmesi; docs; + `[S74-Z]` harness self-audit.
- Regresyon: `sprint-17.sh` (dedup contract), `sprint-19.sh` (REJECTED kuralı),
  `sprint-31/47/73.sh` (consensus-run), `sprint-20/21.sh` (history + reviewer-memory),
  `tests/integration/run.sh`.

## Dokümantasyon

- `docs/CONSENSUS-ITERATION.md` — yeni "Dedup: üç katman" bölümü (yapısal → leksik →
  semantik), `dedupNote` şeması, yalnızca-indirgeyen kural, ve leksik katmanın dürüst
  sınırı ("yeniden ifade edilmiş duplikat leksik olarak yakalanamaz; eşiği düşürmek
  sahte APPROVED üretir" + ölçüm tablosu).
- `docs/CONSENSUS-FLOW.md` — dedup katmanlarına atıf.
- `CLAUDE.md` — test-katmanı defteri + Sprint 74 girdisi.
- Sürüm: `v2.61.0` (plugin.json + CHANGELOG) — ayrı release commit'i.

## Doğrulama

1. `bash hooks/tests/run.sh` → 227 + yeni S74 assertion'ları, 0 fail.
2. `bash tests/integration/sprint-74.sh` → 0 fail.
3. Regresyon seti: `sprint-17/19/20/21/31/47/73.sh` + `tests/integration/run.sh` yeşil
   (bilinen pre-existing sprint-8/11/20/24 hariç).
4. Uçtan uca canlı prova: iki reviewer satırı ile (Clera'nın gerçek başlıkları —
   "Özkaynağına faiz devri hesaplanmıyor" / "Özkaynağa faiz devir hesabı eksik",
   ikisi de aynı dosya, örtüşen line_range, 1× REJECTED + 1× NEEDS_REVISION) bir
   `--finalize` koşusu: **önce** `criticalTotal=2 → REJECTED`, **sonra** yapısal
   örtüşmeyle `criticalTotal=1 → NEEDS_REVISION`; line_range'i kaldırıp aynı koşu →
   `escalatedByCriticalCount: true` + semantik tur → `NEEDS_REVISION` + `dedupNote`.
