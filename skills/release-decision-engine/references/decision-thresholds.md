# Release Karar Eşikleri

## Domain Bazlı GO / CONDITIONAL / BLOCKED Eşikleri

| Domain | GO Eşiği | CONDITIONAL Eşiği | BLOCKED |
|--------|---------|------------------|---------|
| financial | ≥ 90 | 75-89 | < 75 |
| e-commerce | ≥ 85 | 70-84 | < 70 |
| healthcare | ≥ 90 | 80-89 | < 80 |
| general | ≥ 80 | 65-79 | < 65 |
| internal-tool | ≥ 70 | 55-69 | < 55 |

## Hard Blocker Kriterleri (Skora Bakılmaksızın BLOCKED)

Aşağıdakilerden biri varsa skor ne olursa olsun karar BLOCKED:

1. P0 requirement coverage < %100
2. UAT P0 pass rate < %100
3. Kritik invariant ihlali > 0
4. Self-contradiction > 0
5. Financial domain: double-entry violation > 0
6. Policy engine CRITICAL bulgusu > 0

## Signal Öncelik Hiyerarşisi

```
policy-engine         100  deterministik
invariant-formalizer   90  matematiksel kanıt
reconciliation-sim     80  finansal domain (yalnızca)
chaos-injector         70  davranışsal
coverage-analyzer      60  ölçümsel
uat-executor           60  manuel doğrulama
traceability-engine    50  yapısal
business-rule          50  semantik
learning-loop          30  danışman — karar verici değil
```

Tek BLOCK yeterli — en yüksek öncelikli kaynaktan geliyorsa diğerleri geçersiz sayılır.
