# TruthLayer Orchestrator v1.0

Hangi durumda hangi skill'lerin hangi sırayla çalışacağını tanımlar.
Her pipeline deterministic'tir — implicit reasoning yoktur.

---

## Temel Kavramlar

```
trigger       → pipeline'ı başlatan olay
pipeline      → sıralı skill çalışma planı
step          → bir pipeline adımı
condition     → adımın koşullu çalışması
parallel      → aynı anda çalışabilecek skill'ler
gate          → devam etmek için geçilmesi gereken eşik
type          → deterministic (sabit çıktı garantisi) | exploratory (öğrenme odaklı)
blockingLevel → HARD | SOFT | NONE — gate'in deploy kararına etkisi
```

---

## Pipeline Tanımları

### PIPELINE-1: New Feature Development
**Tetikleyici:** Yeni PRD veya feature branch açıldı

```json
{
  "id": "new-feature",
  "type": "deterministic",
  "trigger": "new_prd | feature_branch_opened",
  "description": "Yeni özellik geliştirme başında çalışır",
  "steps": [
    {
      "order": 1,
      "skill": "prd-quality-analyzer",
      "inputs": { "prd": "PRD_CONTENT" },
      "gate": {
        "field": "testabilityScore",
        "operator": ">=",
        "value": 60,
        "onFail": "STOP — PRD kalitesi yetersiz, geliştirme başlamayacak"
      }
    },
    {
      "order": 2,
      "skill": "architecture-validator",
      "inputs": {
        "architectureDescription": "ARCH_DESCRIPTION",
        "prd": "prd-quality-report.md",
        "domain": "DOMAIN_CONFIG"
      },
      "gate": {
        "field": "criticalPolicyViolations",
        "operator": "==",
        "value": 0,
        "onFail": "STOP — Policy ihlali var, mimari karar gerekli"
      }
    },
    {
      "order": 3,
      "skill": "test-strategy-planner",
      "inputs": {
        "prd": "PRD_CONTENT",
        "platform": "PLATFORM_CONFIG",
        "prdQualityReport": "prd-quality-report.md"
      },
      "note": "Bu adım scenario-set.md'yi üretir. Sonraki tüm adımlar buna bağlı."
    },
    {
      "order": 4,
      "parallel": true,
      "skills": [
        {
          "skill": "component-test-writer",
          "inputs": { "sourceCode": "SOURCE_FILES", "scenarioSet": "scenario-set.md" }
        },
        {
          "skill": "contract-test-writer",
          "inputs": { "apiSchema": "OPENAPI_FILE", "scenarioSet": "scenario-set.md" }
        },
        {
          "skill": "business-rule-validator",
          "inputs": { "prd": "PRD_CONTENT", "scenarioSet": "scenario-set.md" }
        },
        {
          "skill": "test-data-manager",
          "inputs": { "domainModel": "SOURCE_FILES", "scenarioSet": "scenario-set.md" }
        }
      ]
    },
    {
      "order": 5,
      "skill": "traceability-engine",
      "inputs": {
        "prd": "PRD_CONTENT",
        "scenarioSet": "scenario-set.md",
        "sourceFiles": "SOURCE_FILES",
        "testFiles": "TEST_FILES"
      }
    }
  ]
}
```

---

### PIPELINE-2: Pre-PR / Code Review
**Tetikleyici:** Pull request açıldı veya kod değişikliği push edildi

```json
{
  "id": "pre-pr",
  "type": "deterministic",
  "trigger": "pull_request_opened | push_to_branch",
  "description": "PR açılmadan önce veya açıldığında hızlı kalite kapısı",
  "steps": [
    {
      "order": 1,
      "skill": "test-priority-engine",
      "inputs": {
        "changedFiles": "GIT_DIFF_OUTPUT",
        "scenarioSet": "scenario-set.md",
        "baseline": "regression-baseline.json",
        "mode": "smart"
      }
    },
    {
      "order": 2,
      "parallel": true,
      "skills": [
        {
          "skill": "component-test-writer",
          "inputs": { "sourceCode": "CHANGED_FILES", "scenarioSet": "scenario-set.md" },
          "condition": "changedFiles contains src/"
        },
        {
          "skill": "contract-test-writer",
          "inputs": { "apiSchema": "OPENAPI_FILE" },
          "condition": "changedFiles contains api/ OR types/"
        },
        {
          "skill": "mutation-test-runner",
          "inputs": {
            "sourceFiles": "CHANGED_FILES",
            "testFiles": "TEST_FILES",
            "scope": "critical"
          },
          "condition": "changedFiles contains business logic"
        }
      ]
    },
    {
      "order": 3,
      "skill": "checklist-generator",
      "inputs": {
        "context": "pr",
        "platform": "PLATFORM_CONFIG",
        "scenarioSet": "scenario-set.md"
      }
    },
    {
      "order": 4,
      "skill": "regression-test-runner",
      "inputs": {
        "trigger": "PR_NUMBER",
        "baseline": "regression-baseline.json",
        "scope": "smoke"
      },
      "gate": {
        "field": "p0PassRate",
        "operator": "==",
        "value": 1.0,
        "onFail": "BLOCK_MERGE — P0 regresyon var"
      }
    }
  ]
}
```

---

### PIPELINE-3: Staging / UAT
**Tetikleyici:** Staging'e deploy edildi, UAT başladı

```json
{
  "id": "staging-uat",
  "type": "deterministic",
  "trigger": "staging_deployed | uat_started",
  "description": "Staging ortamında tam doğrulama",
  "steps": [
    {
      "order": 1,
      "skill": "environment-orchestrator",
      "inputs": {
        "testType": "e2e",
        "platform": "PLATFORM_CONFIG"
      }
    },
    {
      "order": 2,
      "parallel": true,
      "skills": [
        {
          "skill": "e2e-test-writer",
          "inputs": {
            "scenarioSet": "scenario-set.md",
            "platform": "PLATFORM_CONFIG",
            "appUrl": "STAGING_URL"
          }
        },
        {
          "skill": "invariant-formalizer",
          "inputs": {
            "prdOrRules": "business-rules.md",
            "domain": "DOMAIN_CONFIG",
            "targetFormat": "zod"
          },
          "condition": "domain == financial OR businessRulesExist"
        },
        {
          "skill": "chaos-injector",
          "inputs": {
            "systemTarget": "STAGING_URL",
            "profile": "moderate",
            "scenarioSet": "scenario-set.md"
          }
        }
      ]
    },
    {
      "order": 3,
      "skill": "uat-executor",
      "inputs": {
        "scenarioSet": "scenario-set.md",
        "appUrl": "STAGING_URL",
        "testStrategy": "test-strategy.md"
      }
    },
    {
      "order": 4,
      "parallel": true,
      "skills": [
        {
          "skill": "test-result-analyzer",
          "inputs": {
            "testOutput": "uat-raw-report.md",
            "scenarioSet": "scenario-set.md",
            "rtm": "rtm.md"
          }
        },
        {
          "skill": "observability-analyzer",
          "inputs": { "testOutput": "uat-raw-report.md" }
        },
        {
          "skill": "coverage-analyzer",
          "inputs": {
            "coverageSummary": "coverage-summary.json",
            "rtm": "rtm-updated.md",
            "scenarioSet": "scenario-set.md"
          }
        }
      ]
    },
    {
      "order": 5,
      "skill": "traceability-engine",
      "inputs": {
        "prd": "PRD_CONTENT",
        "scenarioSet": "scenario-set.md",
        "testFiles": "TEST_FILES"
      }
    }
  ]
}
```

---

### PIPELINE-4: Release Decision
**Tetikleyici:** UAT tamamlandı, production deploy kararı bekleniyor

```json
{
  "id": "release-decision",
  "type": "deterministic",
  "trigger": "uat_completed | release_requested",
  "description": "Go / Conditional / Blocked kararı üretir",
  "prerequisite": "staging-uat pipeline tamamlanmış olmalı",
  "steps": [
    {
      "order": 1,
      "skill": "release-decision-engine",
      "inputs": {
        "coverageReport":       "coverage-report.md",
        "uatReport":            "uat-raw-report.md",
        "testResults":          "test-results.md",
        "domain":               "DOMAIN_CONFIG",
        "riskTolerance":        "RISK_TOLERANCE",
        "invariantMatrix":      "invariant-matrix.md",
        "chaosReport":          "chaos-report.md",
        "traceabilityReport":   "traceability-report.md",
        "reconciliationReport": "reconciliation-report.md"
      },
      "gate": {
        "field": "decision",
        "operator": "!=",
        "value": "BLOCKED",
        "onFail": "STOP — Release blocked. decision-recommender çalıştır."
      }
    },
    {
      "order": 2,
      "skill": "decision-recommender",
      "inputs": {
        "findings": "release-decision.md"
      },
      "condition": "release-decision.decision == BLOCKED OR release-decision.decision == CONDITIONAL"
    }
  ]
}
```

---

### PIPELINE-5: Hotfix
**Tetikleyici:** Production bug, acil fix gerekiyor

```json
{
  "id": "hotfix",
  "type": "deterministic",
  "trigger": "production_incident | hotfix_branch",
  "description": "Minimum gecikme ile kritik fix doğrulaması",
  "steps": [
    {
      "order": 1,
      "skill": "test-priority-engine",
      "inputs": {
        "changedFiles": "GIT_DIFF_OUTPUT",
        "scenarioSet": "scenario-set.md",
        "mode": "quick"
      }
    },
    {
      "order": 2,
      "skill": "regression-test-runner",
      "inputs": {
        "trigger": "HOTFIX_COMMIT",
        "baseline": "regression-baseline.json",
        "scope": "smoke"
      },
      "gate": {
        "field": "p0PassRate",
        "operator": "==",
        "value": 1.0,
        "onFail": "ESCALATE — Hotfix P0 kırdı, rollback değerlendirin"
      }
    },
    {
      "order": 3,
      "skill": "cross-run-consistency",
      "inputs": {
        "scenario": "scenario-set.md",
        "runCount": 3,
        "tolerance": "strict"
      }
    }
  ]
}
```

---

### PIPELINE-6: Weekly Learning
**Tetikleyici:** Her hafta otomatik, veya sprint sonunda

```json
{
  "id": "weekly-learning",
  "type": "exploratory",
  "trigger": "weekly_schedule | sprint_end",
  "description": "Sistem öğrenir, maturity stage güncellenir",
  "steps": [
    {
      "order": 1,
      "parallel": true,
      "skills": [
        {
          "skill": "learning-loop-engine",
          "mode": "test-history",
          "inputs": {
            "baseline": "regression-baseline.json",
            "bugTickets": "bug-tickets.md",
            "scenarioSet": "scenario-set.md"
          }
        },
        {
          "skill": "learning-loop-engine",
          "mode": "drift-analysis",
          "inputs": { "baselines": "regression-baselines/*.json" }
        }
      ]
    },
    {
      "order": 2,
      "skill": "mutation-test-runner",
      "inputs": {
        "sourceFiles": "SOURCE_FILES",
        "testFiles": "TEST_FILES",
        "scope": "standard"
      },
      "condition": "weeklySchedule OR mutationScoreBelow70"
    }
  ]
}
```

---

### PIPELINE-7: Production Feedback (On-Demand)
**Tetikleyici:** Production bug raporlandı

```json
{
  "id": "production-feedback",
  "type": "exploratory",
  "trigger": "production_bug_reported",
  "description": "Production kaçan bug'dan öğren, eksik testi tespit et",
  "steps": [
    {
      "order": 1,
      "skill": "learning-loop-engine",
      "mode": "production-feedback",
      "inputs": { "bugReport": "BUG_REPORT_CONTENT" }
    },
    {
      "order": 2,
      "skill": "business-rule-validator",
      "inputs": {
        "prd": "PRD_CONTENT",
        "testFiles": "TEST_FILES"
      },
      "condition": "learning-report.failType == WRONG_ASSUMPTION"
    },
    {
      "order": 3,
      "skill": "mutation-test-runner",
      "inputs": {
        "sourceFiles": "AFFECTED_FILES",
        "testFiles": "TEST_FILES",
        "scope": "critical"
      },
      "condition": "learning-report.failType == WEAK_ASSERTION"
    }
  ]
}
```

---

## Execution Order Contract

Hangi pipeline'da hangi sıranın neden önemli olduğu:

### Kural 1: test-strategy-planner ilk — scenario-based skill'lerde

```
IF pipeline contains ANY OF:
  component-test-writer, contract-test-writer, e2e-test-writer,
  uat-executor, chaos-injector, coverage-analyzer,
  test-priority-engine, checklist-generator

THEN test-strategy-planner MUST run FIRST
REASON: scenario-set.md upstream dependency
```

### Kural 2: prd-quality-analyzer ilk — PRD-based pipeline'larda

```
IF trigger == new_prd OR feature_branch_opened
THEN prd-quality-analyzer MUST run FIRST
REASON: testability score gate — yetersiz PRD downstream'i kirletir
```

### Kural 3: environment-orchestrator — e2e/uat'tan önce

```
IF pipeline contains e2e-test-writer OR uat-executor
THEN environment-orchestrator SHOULD run BEFORE them
REASON: kirli ortam yanlış pozitif/negatif üretir
```

### Kural 4: release-decision-engine — en son

```
release-decision-engine ALWAYS runs LAST
REASON: tüm diğer skill çıktılarını tüketir
PREREQUISITE outputs:
  coverage-report.md    (coverage-analyzer)
  uat-raw-report.md     (uat-executor)
  test-results.md       (test-result-analyzer)
```

### Kural 5: learning-loop-engine — bağımsız

```
learning-loop-engine NEVER blocks other pipelines
REASON: öğrenme asenkron — sonuç bir sonraki dönemde uygulanır
```

---

## Paralel Çalışma Kuralları

Bu skill'ler birbirinden bağımsız, aynı anda çalışabilir:

```
component-test-writer    ─┐
contract-test-writer     ─┤─ PARALEL (hepsi scenario-set.md'yi okur, birbirini değiştirmez)
business-rule-validator  ─┤
test-data-manager        ─┘

e2e-test-writer          ─┐
chaos-injector           ─┤─ PARALEL (farklı test türleri)
invariant-formalizer     ─┘

test-result-analyzer     ─┐
observability-analyzer   ─┤─ PARALEL (aynı uat-raw-report.md'yi okur)
coverage-analyzer        ─┘

learning-loop (history)  ─┐
learning-loop (drift)    ─┘─ PARALEL (farklı modlar)
```

Bu skill'ler sıralı çalışmalı (önceki çıktı gerekli):

```
prd-quality-analyzer → test-strategy-planner
test-strategy-planner → component-test-writer (ve diğerleri)
uat-executor → test-result-analyzer
test-result-analyzer → release-decision-engine
```

---

## Gate Seviyeleri

| Seviye | Davranış | Kullanım |
|--------|----------|---------|
| `STOP` | Pipeline durur, sonraki adım çalışmaz | P0 kalite hatası |
| `BLOCK_MERGE` | PR merge engellenir | Regresyon tespiti |
| `WARN` | Pipeline devam eder, uyarı üretilir | P1/P2 sorunlar |
| `ESCALATE` | İnsan kararı beklenir | Hotfix kriz durumu |

---

## Blocking Level Hiyerarşisi

Her gate bir blocking level taşır. Çakışma durumunda yüksek seviye kazanır:

```
HARD   → Policy engine, invariant ihlali
         Sonuç: deploy asla olmaz. İnsan müdahalesi bile yetmez.
         Örnekler: POL-FIN-001, criticalInvariantViolations > 0

SOFT   → Coverage eksikliği, traceability gap, UAT P1 başarısızlığı
         Sonuç: deploy olabilir, ancak koşullu (CONDITIONAL).
         Ekip kararı ile devam edilebilir.
         Örnekler: coverageBelow80, untestedP1Reqs > 0

NONE   → Learning loop, observability, mutation skoru
         Sonuç: deploy kararını etkilemez. Sonraki sprint için girdi.
         Örnekler: learningReport, mutationScore
```

Skill → Blocking Level eşlemesi:

| Skill | Blocking Level |
|-------|---------------|
| policy-engine | HARD |
| invariant-formalizer | HARD |
| uat-executor (P0 fail) | HARD |
| prd-quality-analyzer (score < 40) | HARD |
| coverage-analyzer | SOFT |
| traceability-engine | SOFT |
| uat-executor (P1 fail) | SOFT |
| chaos-injector | SOFT |
| regression-test-runner | SOFT |
| learning-loop-engine | NONE |
| mutation-test-runner | NONE |
| observability-analyzer | NONE |
| visual-ai-analyzer | NONE |

---

## Değişken Referansları

Pipeline tanımlarında büyük harfle yazılan değerler çalışma zamanında doldurulur:

| Değişken | Açıklama | Kaynak |
|----------|----------|--------|
| `PRD_CONTENT` | PRD metin içeriği | Kullanıcı / dosya |
| `ARCH_DESCRIPTION` | Mimari açıklama | Kullanıcı |
| `DOMAIN_CONFIG` | financial / e-commerce / general | Proje config |
| `PLATFORM_CONFIG` | web / ios / android / all | Proje config |
| `RISK_TOLERANCE` | low / medium / high | Proje config |
| `SOURCE_FILES` | src/ klasör yolu | CI ortamı |
| `TEST_FILES` | Test klasör yolu | CI ortamı |
| `OPENAPI_FILE` | openapi.yaml yolu | Proje |
| `STAGING_URL` | Staging ortam URL | CI ortamı |
| `GIT_DIFF_OUTPUT` | `git diff --name-only` çıktısı | CI ortamı |
| `PR_NUMBER` | PR numarası | CI ortamı |
| `HOTFIX_COMMIT` | Hotfix commit hash | CI ortamı |
| `BUG_REPORT_CONTENT` | Production bug açıklaması | İnsan |

---

## Proje Config Dosyası

Her projede tek bir config dosyası ile değişkenler sabitlenir:

```json
{
  "project": "MyApp",
  "domain": "e-commerce",
  "platform": "web",
  "riskTolerance": "medium",
  "stagingUrl": "https://staging.myapp.com",
  "sourceDir": "src/",
  "testDir": "src/",
  "openapiFile": "openapi.yaml",
  "defaultPipeline": "new-feature"
}
```

Bu dosya varsa pipeline'lardaki değişkenler otomatik doldurulur.
