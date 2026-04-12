// decision-audit-logger.ts
// Her release kararını immutable olarak kayıt altına alır + determinism check

import crypto from 'crypto'

export interface DecisionAuditEntry {
  auditId:       string
  timestamp:     string
  inputHash:     string
  inputSnapshot: Record<string, unknown>
  signals:       { raw: unknown[]; conflicts: unknown[]; resolved: unknown[] }
  weights:       Record<string, number>
  hardBlockers:  unknown[]
  riskScore:     number
  decision:      'GO' | 'CONDITIONAL' | 'BLOCKED'
  confidence:    number
  reasoning:     string
  findings:      { source: string; finding: string; why: string; impact: string; confidence: number }[]
  override?:     { by: string; reason: string; approvedBy: string; timestamp: string }
}

// In-memory store (üretimde DB/append-only log ile değiştirin)
const auditLog: DecisionAuditEntry[] = []

export function logDecision(entry: Omit<DecisionAuditEntry, 'auditId' | 'timestamp' | 'inputHash'>): DecisionAuditEntry {
  const full: DecisionAuditEntry = {
    ...entry,
    auditId:   crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    inputHash: hashObject(entry.inputSnapshot),
  }
  auditLog.push(full)   // immutable append — delete/update yasak
  return full
}

export function checkDeterminism(
  inputSnapshot: Record<string, unknown>,
  currentDecision: 'GO' | 'CONDITIONAL' | 'BLOCKED'
): { status: 'FIRST_RUN' | 'CONSISTENT' | 'INCONSISTENT'; alert?: string } {
  const inputHash = hashObject(inputSnapshot)
  const previous  = auditLog.find(e => e.inputHash === inputHash)

  if (!previous) return { status: 'FIRST_RUN' }

  if (previous.decision === currentDecision) return { status: 'CONSISTENT' }

  return {
    status: 'INCONSISTENT',
    alert:  `KRİTİK: Aynı input farklı karar üretti. Önceki: ${previous.decision}, Şimdi: ${currentDecision}. Weights veya logic değişmiş olabilir.`,
  }
}

export function getHistory(): DecisionAuditEntry[] {
  return [...auditLog]
}

function hashObject(obj: unknown): string {
  return crypto.createHash('sha256').update(JSON.stringify(obj)).digest('hex').slice(0, 16)
}
