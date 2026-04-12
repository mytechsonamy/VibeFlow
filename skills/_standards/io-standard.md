# Skill Input/Output Standartları

Her skill için girdi ve çıktı dosya adları sabittir.
Agent veya insan — ikisi de aynı isimleri kullanır.

---

## Temel Prensipler

### 1. Dosya adları sabit, konum esnek
Dosya adı her zaman aynıdır. Nerede olduğu (proje klasörü, temp dizin,
yapıştırılmış metin) kullanıcıya bağlıdır.

### 2. Zorunlu vs opsiyonel girdi
Her skill'in en az bir **zorunlu** girdisi vardır.
Opsiyonel girdiler skill çıktısının kalitesini artırır ama olmadan da çalışır.

### 3. Çıktı adları bağımlılık zincirini yansıtır
Bir skill'in çıktısı, onu tüketen skill'in beklediği isimle eşleşir.
Örneğin prd-quality-analyzer → `prd-quality-report.md` → traceability-engine bunu okur.

### 4. Minimum geçerli girdi (MVG)
Her skill'in sadece zorunlu girdiyle çalıştığında ne ürettiği tanımlıdır.
Opsiyonel girdiler olmadan da anlıklı çıktı üretir.

---

## Girdi Türleri Sözlüğü

| Tür | Açıklama | Nasıl sağlanır |
|-----|----------|----------------|
| `PRD` | Ürün gereksinim dokümanı (Markdown veya metin) | Yapıştır veya dosya yolu |
| `SOURCE_FILES` | Kaynak kod dosyaları veya klasör | Dosya yolu |
| `TEST_FILES` | Test dosyaları veya klasör | Dosya yolu |
| `SCENARIO_SET` | `scenario-set.md` — senaryo listesi | Önceki skill çıktısı |
| `BASELINE` | `regression-baseline.json` — önceki koşum sonucu | Önceki koşum çıktısı |
| `SCREENSHOT` | PNG/JPG ekran görüntüsü | Dosya yolu veya URL |
| `OPENAPI` | OpenAPI/Swagger YAML veya JSON | Dosya yolu veya URL |
| `CONFIG` | Parametre/konfigürasyon (inline veya dosya) | Inline metin |

---

## 26 Skill — Input/Output Tablosu

### LAYER 0 — Truth Creation

#### prd-quality-analyzer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | PRD içeriği | `PRD` | ✓ |
| **ÇIKTI** | `prd-quality-report.md` | Rapor | — |
| **ÇIKTI** | `prd-cost-avoidance.md` | CFO özeti | — |

---

#### architecture-validator
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Mimari kararlar açıklaması | Metin | ✓ |
| **GİRDİ** | PRD içeriği veya `prd-quality-report.md` | `PRD` / Rapor | ✓ |
| **GİRDİ** | Domain (`financial` / `e-commerce` / `general` / ...) | `CONFIG` | ✓ |
| **ÇIKTI** | `architecture-report.md` | Rapor | — |

---

#### traceability-engine
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | PRD içeriği | `PRD` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | Kaynak kod klasörü | `SOURCE_FILES` | opsiyonel |
| **GİRDİ** | Test dosyaları klasörü | `TEST_FILES` | opsiyonel |
| **ÇIKTI** | `traceability-report.md` | Rapor | — |
| **ÇIKTI** | `rtm-updated.md` | RTM | — |

---

### LAYER 1 — Truth Validation (22 skill)

#### test-strategy-planner
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | PRD içeriği | `PRD` | ✓ |
| **GİRDİ** | Platform (`web` / `ios` / `android` / `all`) | `CONFIG` | ✓ |
| **GİRDİ** | `prd-quality-report.md` | Rapor | opsiyonel |
| **ÇIKTI** | `test-strategy.md` | Strateji | — |
| **ÇIKTI** | `scenario-set.md` | Senaryo listesi | — |
| **ÇIKTI** | `rtm.md` | RTM | — |

> **Not:** `scenario-set.md` bu skill'in birincil çıktısıdır.
> Aşağı akış skill'lerinin büyük çoğunluğu bunu girdi olarak kullanır.

---

#### component-test-writer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Kaynak kod dosyası veya klasörü | `SOURCE_FILES` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | Framework (`vitest` / `jest`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `[component-name].test.ts` | Test dosyası | — |

---

#### contract-test-writer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | OpenAPI/Swagger dosyası veya API tip dosyaları | `OPENAPI` / `SOURCE_FILES` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **ÇIKTI** | `contract.test.ts` | Test dosyası | — |
| **ÇIKTI** | `contract-report.md` | Breaking change raporu | — |

---

#### business-rule-validator
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | PRD içeriği | `PRD` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | Mevcut test dosyaları | `TEST_FILES` | opsiyonel |
| **ÇIKTI** | `business-rules.md` | Kural listesi | — |
| **ÇIKTI** | `br-test-suite.test.ts` | Test dosyası | — |
| **ÇIKTI** | `semantic-gaps.md` | Semantic gap analizi | — |

---

#### test-data-manager
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | TypeScript tip dosyaları veya domain model açıklaması | `SOURCE_FILES` / Metin | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | Hedef (`fixture` / `seed` / `factory`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `[domain].factory.ts` | Factory | — |
| **ÇIKTI** | `fixtures/[domain].json` | Fixture | — |

---

#### e2e-test-writer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | ✓ |
| **GİRDİ** | Platform (`web` / `ios` / `android`) | `CONFIG` | ✓ |
| **GİRDİ** | Uygulama URL veya bundle ID | `CONFIG` | ✓ |
| **GİRDİ** | Auth yöntemi | `CONFIG` | opsiyonel |
| **ÇIKTI** | `[feature].spec.ts` | Test dosyası | — |

---

#### uat-executor
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | ✓ |
| **GİRDİ** | Uygulama URL veya ortam bilgisi | `CONFIG` | ✓ |
| **GİRDİ** | `test-strategy.md` | Strateji | opsiyonel |
| **ÇIKTI** | `uat-raw-report.md` | Ham UAT raporu | — |

---

#### test-result-analyzer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `uat-raw-report.md` VEYA test runner çıktısı | Rapor / Log | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | `rtm.md` | RTM | opsiyonel |
| **ÇIKTI** | `test-results.md` | Analiz raporu | — |
| **ÇIKTI** | `bug-tickets.md` | Backlog bilet listesi | — |

---

#### regression-test-runner
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Tetikleyici bilgisi (commit hash / PR / UAT bitti) | Metin / `CONFIG` | ✓ |
| **GİRDİ** | `regression-baseline.json` | `BASELINE` | opsiyonel |
| **GİRDİ** | Kapsam (`smoke` / `full`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `regression-report.md` | Regresyon raporu | — |
| **ÇIKTI** | `regression-baseline.json` | Yeni baseline | — |

> **Not:** `regression-baseline.json` hem girdi hem çıktıdır.
> İlk koşumda girdi yoktur; sonraki koşumlarda önceki çıktı girdi olur.

---

#### checklist-generator
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Bağlam (`pr` / `release` / `feature` / `accessibility`) | `CONFIG` | ✓ |
| **GİRDİ** | Platform (`web` / `mobile` / `all`) | `CONFIG` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | `test-strategy.md` | Strateji | opsiyonel |
| **ÇIKTI** | `checklist.md` | Kontrol listesi | — |

---

#### coverage-analyzer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `coverage-summary.json` (Vitest/Jest çıktısı) | JSON | ✓ |
| **GİRDİ** | `rtm.md` veya `rtm-updated.md` | RTM | opsiyonel |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **ÇIKTI** | `coverage-report.md` | Kapsam raporu | — |

---

#### environment-orchestrator
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Test türü (`unit` / `integration` / `e2e`) | `CONFIG` | ✓ |
| **GİRDİ** | Platform (`web` / `ios` / `android`) | `CONFIG` | ✓ |
| **GİRDİ** | Ortam değişkenleri veya feature flag listesi | `CONFIG` | opsiyonel |
| **ÇIKTI** | `env-setup.md` | Ortam kurulum rehberi | — |

---

#### mutation-test-runner
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Kaynak dosya(lar) veya klasör | `SOURCE_FILES` | ✓ |
| **GİRDİ** | Mevcut test dosyaları | `TEST_FILES` | ✓ |
| **GİRDİ** | Kapsam seviyesi (`critical` / `standard` / `full`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `mutation-report.md` | Mutation raporu | — |

---

#### cross-run-consistency
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Test senaryosu veya E2E akış açıklaması | `SCENARIO_SET` / Metin | ✓ |
| **GİRDİ** | Koşum sayısı (varsayılan: 3) | `CONFIG` | opsiyonel |
| **GİRDİ** | Tolerans (`strict` / `tolerant`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `consistency-report.md` | Tutarlılık raporu | — |

---

#### visual-ai-analyzer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Screenshot dosyası veya URL | `SCREENSHOT` | ✓ |
| **GİRDİ** | UI gereksinimleri (PRD bölümü veya metin) | `PRD` / Metin | opsiyonel |
| **GİRDİ** | Baseline screenshot (karşılaştırma için) | `SCREENSHOT` | opsiyonel |
| **ÇIKTI** | `visual-report.md` | Görsel analiz raporu | — |

---

#### test-priority-engine
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Değişen dosyalar listesi (git diff çıktısı veya PR dosyaları) | Metin / `SOURCE_FILES` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ** | `regression-baseline.json` | `BASELINE` | opsiyonel |
| **GİRDİ** | Hedef (`quick` / `smart` / `full`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `priority-plan.md` | Öncelikli koşum planı | — |

---

#### observability-analyzer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `uat-raw-report.md` VEYA Playwright trace/HAR/log | Rapor / Dosya | ✓ |
| **ÇIKTI** | `observability-report.md` | Gözlemlenebilirlik raporu | — |

---

#### invariant-formalizer
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | PRD içeriği VEYA `business-rules.md` | `PRD` / Rapor | ✓ |
| **GİRDİ** | Domain (`financial` / `trading` / `general` / ...) | `CONFIG` | ✓ |
| **GİRDİ** | Hedef format (`typescript` / `zod` / `z3` / `all`) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `invariant-matrix.md` | Invariant matrisi | — |
| **ÇIKTI** | `invariants.ts` | TypeScript/Zod implementasyonu | — |

---

#### reconciliation-simulator
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `scenario-set.md` VEYA drift senaryosu açıklaması | `SCENARIO_SET` / Metin | ✓ |
| **GİRDİ** | Simülasyon parametreleri (işlem sayısı, drift oranı) | `CONFIG` | opsiyonel |
| **ÇIKTI** | `reconciliation-report.md` | Simülasyon raporu | — |

---

#### chaos-injector
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Test edilen sistem bilgisi (endpoint / UI akışı açıklaması) | Metin | ✓ |
| **GİRDİ** | Kaos profili (`gentle` / `moderate` / `brutal`) | `CONFIG` | ✓ |
| **GİRDİ** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **ÇIKTI** | `chaos-report.md` | Kaos test raporu | — |

---

### LAYER 2 — Truth Decision

#### decision-recommender
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | Herhangi bir findings raporu (`prd-quality-report.md` / `business-rules.md` / `invariant-matrix.md` / `chaos-report.md`) VEYA serbest metin | Rapor / Metin | ✓ |
| **GİRDİ** | Bağlam (ekip büyüklüğü, zaman kısıtı, risk toleransı) | Metin | opsiyonel |
| **ÇIKTI** | `decision-package.md` | Karar paketi | — |

---

#### release-decision-engine
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ** | `coverage-report.md` | Rapor | ✓ |
| **GİRDİ** | `uat-raw-report.md` | Rapor | ✓ |
| **GİRDİ** | `test-results.md` | Rapor | ✓ |
| **GİRDİ** | `invariant-matrix.md` | Rapor | opsiyonel |
| **GİRDİ** | `chaos-report.md` | Rapor | opsiyonel |
| **GİRDİ** | `traceability-report.md` | Rapor | opsiyonel |
| **GİRDİ** | `reconciliation-report.md` | Rapor | opsiyonel (financial) |
| **GİRDİ** | Domain ve risk toleransı | `CONFIG` | ✓ |
| **ÇIKTI** | `release-decision.md` | GO / CONDITIONAL / BLOCKED kararı | — |

---

### LAYER 3 — Truth Evolution

#### learning-loop-engine
| | Adı | Türü | Zorunlu |
|--|-----|------|---------|
| **GİRDİ (mod: test-history)** | `regression-baseline.json` (en az 5 koşum) | `BASELINE` | ✓ |
| **GİRDİ (mod: test-history)** | `bug-tickets.md` | Rapor | opsiyonel |
| **GİRDİ (mod: test-history)** | `scenario-set.md` | `SCENARIO_SET` | opsiyonel |
| **GİRDİ (mod: production-feedback)** | Production bug açıklaması (serbest metin veya ticket) | Metin | ✓ |
| **GİRDİ (mod: drift-analysis)** | `regression-baseline.json` (birden fazla dönem) | `BASELINE` | ✓ |
| **ÇIKTI** | `learning-report.md` | Öğrenme raporu | — |

---

## Bağımlılık Zinciri Özeti

Hangi skill'in çıktısı hangi skill'i besler:

```
prd-quality-analyzer
  └─ prd-quality-report.md ──► test-strategy-planner
                            ──► architecture-validator
                            ──► traceability-engine

test-strategy-planner
  └─ scenario-set.md ────────► component-test-writer
  └─ scenario-set.md ────────► contract-test-writer
  └─ scenario-set.md ────────► e2e-test-writer
  └─ scenario-set.md ────────► uat-executor
  └─ scenario-set.md ────────► chaos-injector
  └─ scenario-set.md ────────► coverage-analyzer
  └─ scenario-set.md ────────► test-priority-engine
  └─ scenario-set.md ────────► checklist-generator
  └─ rtm.md ─────────────────► traceability-engine
  └─ rtm.md ─────────────────► coverage-analyzer

business-rule-validator
  └─ business-rules.md ──────► invariant-formalizer
                            ──► decision-recommender

uat-executor
  └─ uat-raw-report.md ──────► test-result-analyzer
                            ──► observability-analyzer

test-result-analyzer
  └─ bug-tickets.md ─────────► learning-loop-engine (test-history)
  └─ test-results.md ────────► release-decision-engine

regression-test-runner
  └─ regression-baseline.json ► regression-test-runner (sonraki koşum)
                              ► test-priority-engine
                              ► learning-loop-engine (test-history / drift-analysis)

invariant-formalizer
  └─ invariant-matrix.md ────► release-decision-engine
                            ──► decision-recommender

chaos-injector
  └─ chaos-report.md ────────► release-decision-engine
                            ──► decision-recommender

coverage-analyzer
  └─ coverage-report.md ─────► release-decision-engine

traceability-engine
  └─ traceability-report.md ─► release-decision-engine
  └─ rtm-updated.md ─────────► coverage-analyzer

release-decision-engine
  └─ release-decision.md ────► [deploy pipeline / insan kararı]
```

---

## Sık Sorulan Durumlar

### "Hangi girdilerle başlamalıyım?"

Her projenin başlangıç girdileri üçtür:
1. **PRD** (zorunlu — her şeyin kaynağı)
2. **Platform config** (web / ios / android)
3. **Domain config** (financial / e-commerce / general / ...)

Bu üçü ile Layer 0'ın tüm skill'leri ve test-strategy-planner çalışır.
Gerisi zincirle gelir.

---

### "scenario-set.md yoksa ne olur?"

Opsiyonel girdilerin büyük çoğunluğu `scenario-set.md`'dir.
Bu dosya yoksa skill PRD'den veya kod içeriğinden çıkarım yapar.
Çıktı kalitesi düşer ama skill çalışır.

İdeal olan: test-strategy-planner'ı ilk çalıştırıp `scenario-set.md`'yi
ürettikten sonra diğer skill'leri koşmaktır.

---

### "Aynı isimde dosya farklı klasörlerde olabilir mi?"

Evet. Dosya adı standarttır, konum esnektir.
Agent veya insan hangi klasörde çalıştığını bilir;
skill sadece dosya adına göre talep eder.

---

### "Output yoksa skill ne yapar?"

Tüm skill'ler çıktılarını üretir ve adlarını yukarıdaki tabloya göre saklar.
Skill çıktısı isimlendirilmemişse sonraki skill onu bulamaz.

---

## Machine-Readable Schema

Her skill'in JSON formatındaki tam input/output contract'ı:

```
_standards/skill-schemas.json
```

Bu dosya orchestrator, CI pipeline ve agent tarafından doğrudan parse edilebilir.
Her `"required": true` alan eksikse skill çalışmayı reddeder.

---

## Execution Order Contract

Hangi skill hangi sırayla — tam kurallar:

```
_standards/orchestrator.md
```

7 hazır pipeline tanımı:
- PIPELINE-1: New Feature Development
- PIPELINE-2: Pre-PR / Code Review
- PIPELINE-3: Staging / UAT
- PIPELINE-4: Release Decision
- PIPELINE-5: Hotfix
- PIPELINE-6: Weekly Learning
- PIPELINE-7: Production Feedback

---

## _standards/ Klasörü İçeriği

| Dosya | Amaç | Okuyan |
|-------|------|--------|
| `io-standard.md` | Tüm IO standartları, insan-okunabilir | İnsan + Agent |
| `skill-schemas.json` | Machine-readable IO contract | Orchestrator + CI |
| `orchestrator.md` | Pipeline tanımları + execution order | Agent + Otomasyon |
