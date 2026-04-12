// cost-avoidance-calculator.ts
// PRD kalite bulgularının finansal etkisini CFO-readable formatta üretir

interface CostAvoidanceConfig {
  avgDevHourCost:   number  // USD/saat — varsayılan: 80
  reworkMultiplier: number  // rework, orijinalin kaç katı — varsayılan: 3
  ambiguityHours:   number  // ambiguity başına saat — varsayılan: 8
  conflictHours:    number  // conflict başına saat — varsayılan: 24
  missingFlowHours: number  // missing flow başına saat — varsayılan: 16
}

interface CostAvoidanceReport {
  ambiguityCount:     number
  conflictCount:      number
  missingFlowCount:   number
  avoidedDevWaste:    number
  avoidedRework:      number
  totalCostAvoidance: number
  sprintsSaved:       number
  roiMultiplier:      number
}

export function calculateCostAvoidance(
  findings: { type: 'AMB' | 'CONF' | 'MISSING' | string }[],
  config: CostAvoidanceConfig = {
    avgDevHourCost: 80, reworkMultiplier: 3,
    ambiguityHours: 8, conflictHours: 24, missingFlowHours: 16,
  }
): CostAvoidanceReport {
  const ambiguities  = findings.filter(f => f.type === 'AMB').length
  const conflicts    = findings.filter(f => f.type === 'CONF').length
  const missingFlows = findings.filter(f => f.type === 'MISSING').length

  const avoidedDevWaste =
    ambiguities  * config.ambiguityHours   * config.avgDevHourCost +
    conflicts    * config.conflictHours    * config.avgDevHourCost +
    missingFlows * config.missingFlowHours * config.avgDevHourCost

  const avoidedRework = avoidedDevWaste * (config.reworkMultiplier - 1)
  const total         = avoidedDevWaste + avoidedRework
  const reviewCost    = 4 * config.avgDevHourCost
  const sprintsSaved  = Math.round(
    (ambiguities * config.ambiguityHours +
     conflicts   * config.conflictHours  +
     missingFlows * config.missingFlowHours) / 80
  )

  return {
    ambiguityCount: ambiguities, conflictCount: conflicts, missingFlowCount: missingFlows,
    avoidedDevWaste, avoidedRework, totalCostAvoidance: total,
    sprintsSaved, roiMultiplier: Math.round(total / reviewCost),
  }
}

// Kullanım: raporun sonuna ekle
export function formatCFOSection(report: CostAvoidanceReport): string {
  return `
## Cost Avoidance Summary (CFO View)

| Bulgu Türü   | Adet | Kaçınılan Maliyet |
|-------------|------|------------------|
| Ambiguity   | ${report.ambiguityCount}  | $${(report.ambiguityCount * 8 * 80 * 3).toLocaleString()} |
| Conflict    | ${report.conflictCount}   | $${(report.conflictCount * 24 * 80 * 3).toLocaleString()} |
| Missing flow| ${report.missingFlowCount}| $${(report.missingFlowCount * 16 * 80 * 3).toLocaleString()} |
| **Toplam**  | **${report.ambiguityCount + report.conflictCount + report.missingFlowCount}** | **$${report.totalCostAvoidance.toLocaleString()}** |

PRD kalite analizi yatırımı: $${(4 * 80).toLocaleString()} (4 saat)
**ROI: ${report.roiMultiplier}×**
Sprint tasarrufu: ~${report.sprintsSaved} sprint erken teslimat
`
}
