// gap-risk-scorer.ts
// Her traceability gap'e etki-bazlı risk skoru ekler

type GapType = 'UNTESTED_REQ' | 'PARTIAL_COVERAGE' | 'STALE_TRACE' | 'DEAD_REQ' | 'UNLINKED_TEST'
type Priority = 'P0' | 'P1' | 'P2' | 'P3'

const PRIORITY_WEIGHT: Record<Priority, number> = { P0: 40, P1: 25, P2: 10, P3: 3 }

const DOMAIN_MULTIPLIER: Record<string, number> = {
  'payment-flow':      2.5,
  'authentication':    2.0,
  'data-persistence':  1.8,
  'business-rule':     1.5,
  'api-contract':      1.3,
  'ui-interaction':    1.0,
  'ui-label':          0.3,
}

const GAP_MULTIPLIER: Record<GapType, number> = {
  'UNTESTED_REQ':     1.0,
  'STALE_TRACE':      0.8,
  'PARTIAL_COVERAGE': 0.6,
  'DEAD_REQ':         0.4,
  'UNLINKED_TEST':    0.2,
}

export interface ScoredGap {
  reqId:         string
  gapType:       GapType
  priority:      Priority
  businessDomain:string
  riskScore:     number   // 0-100
  riskLabel:     'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW'
  finding:       string
  why:           string
  impact:        string
  confidence:    'HIGH' | 'MEDIUM' | 'LOW'
}

export function scoreGap(
  reqId: string,
  gapType: GapType,
  priority: Priority,
  businessDomain: string
): ScoredGap {
  const base   = PRIORITY_WEIGHT[priority]
  const domain = DOMAIN_MULTIPLIER[businessDomain] ?? 1.0
  const gap    = GAP_MULTIPLIER[gapType]
  const score  = Math.min(100, Math.round(base * domain * gap))

  const label: ScoredGap['riskLabel'] =
    score >= 80 ? 'CRITICAL' :
    score >= 50 ? 'HIGH'     :
    score >= 20 ? 'MEDIUM'   : 'LOW'

  return {
    reqId, gapType, priority, businessDomain,
    riskScore: score, riskLabel: label,
    finding: `${reqId}: ${gapType} — ${businessDomain}`,
    why:    gapType === 'UNTESTED_REQ'
      ? 'Bu gereksinim için hiç test senaryosu yazılmamış'
      : gapType === 'PARTIAL_COVERAGE'
      ? 'Sadece happy path test edilmiş; error/edge case yok'
      : gapType === 'STALE_TRACE'
      ? 'Gereksinim değişmiş ama test güncellenmemiş'
      : 'Gereksinim ile test arasındaki bağlantı kopuk',
    impact: score >= 80
      ? `KRİTİK: ${businessDomain} ${priority} gereksinimi doğrulanmıyor`
      : `${label}: deployment sonrası sessiz başarısızlık riski`,
    confidence: priority === 'P0' ? 'HIGH' : priority === 'P1' ? 'HIGH' : 'MEDIUM',
  }
}

export function sortByRisk(gaps: ScoredGap[]): ScoredGap[] {
  return [...gaps].sort((a, b) => b.riskScore - a.riskScore)
}

export function formatRiskTable(gaps: ScoredGap[]): string {
  const sorted = sortByRisk(gaps)
  const header = '| REQ-ID | Gap Türü | Domain | Öncelik | Risk | Label |\n|--------|---------|--------|---------|------|-------|'
  const rows   = sorted.map(g =>
    `| ${g.reqId} | ${g.gapType} | ${g.businessDomain} | ${g.priority} | ${g.riskScore} | ${g.riskLabel} |`
  ).join('\n')
  return `${header}\n${rows}`
}
