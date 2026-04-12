// signal-conflict-resolver.ts
// Çelişen sinyaller arasında deterministik öncelik hiyerarşisi

export const SIGNAL_PRIORITY: Record<string, number> = {
  'policy-engine':        100,
  'invariant-formalizer':  90,
  'reconciliation-sim':    80,
  'chaos-injector':        70,
  'coverage-analyzer':     60,
  'uat-executor':          60,
  'traceability-engine':   50,
  'business-rule':         50,
  'learning-loop':         30,
}

export interface WeightedSignal {
  source:     string
  finding:    string
  value:      number        // 0-1
  confidence: ConfidenceVector
  verdict:    'BLOCK' | 'PASS' | 'WARN'
  why:        string
  impact:     string
}

export interface ConfidenceVector {
  signalStrength: number   // 0-1: sinyal ne kadar güçlü?
  dataQuality:    number   // 0-1: girdi kalitesi
  coverageLevel:  number   // 0-1: kapsam yüzdesi
  composite:      number   // = signalStrength × dataQuality × coverageLevel
}

export interface ConflictResolution {
  verdict:      'BLOCK' | 'GO' | 'CONDITIONAL'
  dominant?:    WeightedSignal
  overridden?:  WeightedSignal[]
  weightedScore?: number
  explanation:  string
}

export function resolveSignalConflict(signals: WeightedSignal[]): ConflictResolution {
  const blocking = signals.filter(s => s.verdict === 'BLOCK')
  const passing  = signals.filter(s => s.verdict === 'PASS')

  if (blocking.length > 0) {
    const dominant = blocking.reduce((a, b) =>
      (SIGNAL_PRIORITY[a.source] ?? 0) >= (SIGNAL_PRIORITY[b.source] ?? 0) ? a : b
    )
    return {
      verdict:    'BLOCK',
      dominant,
      overridden: passing,
      explanation: `${dominant.source} (öncelik: ${SIGNAL_PRIORITY[dominant.source] ?? 0}) BLOCK kararı verdi. ${passing.length} geçen sinyal geçersiz sayıldı.`,
    }
  }

  const totalWeight  = signals.reduce((s, sig) => s + (SIGNAL_PRIORITY[sig.source] ?? 30), 0)
  const weightedScore = signals.reduce((s, sig) =>
    s + sig.value * (SIGNAL_PRIORITY[sig.source] ?? 30), 0
  ) / totalWeight

  return {
    verdict:      weightedScore >= 0.85 ? 'GO' : 'CONDITIONAL',
    weightedScore,
    explanation:  `Çakışan sinyal yok. Ağırlıklı skor: ${Math.round(weightedScore * 100)}/100`,
  }
}

export function buildConfidenceVector(
  source: string,
  inputMeta: { invariantCount?: number; traceabilityScore?: number; chaosHasCriticalFail?: boolean; untestedP0?: number }
): ConfidenceVector {
  switch (source) {
    case 'policy-engine':
      return { signalStrength: 1.0, dataQuality: 1.0, coverageLevel: 1.0, composite: 1.0 }
    case 'invariant-formalizer': {
      const cov = Math.min(1, (inputMeta.invariantCount ?? 0) / 20)
      return { signalStrength: 1.0, dataQuality: 0.97, coverageLevel: cov, composite: 0.97 * cov }
    }
    case 'traceability-engine': {
      const q   = inputMeta.traceabilityScore ?? 0.7
      const cov = 1 - (inputMeta.untestedP0 ?? 0) / 10
      return { signalStrength: 0.85, dataQuality: q, coverageLevel: cov, composite: 0.85 * q * cov }
    }
    case 'chaos-injector': {
      const q = inputMeta.chaosHasCriticalFail ? 0.95 : 0.80
      return { signalStrength: 0.90, dataQuality: q, coverageLevel: 0.85, composite: 0.90 * q * 0.85 }
    }
    default:
      return { signalStrength: 0.70, dataQuality: 0.70, coverageLevel: 0.70, composite: 0.343 }
  }
}
