# Phase 9 — Management Intelligence & Cross-Domain Correlation

## Purpose
Phase 9 aggregates existing domain read models into deterministic management intelligence. It does not recalculate protection, capacity, anomaly, or operational business rules and does not make causal or remediation claims.

## Architecture
Existing telemetry and domain analysis remain the source of truth. The management layer consumes active operational events and anomaly findings, derives bounded entity health, and exposes management read models. `ManagementCorrelationGroups` and `ManagementRelatedSignals` preserve traceability for temporal/entity relationships.

## Status semantics
`Critical > Warning > Attention > Unknown > Healthy` for overall precedence, with the important rule that Critical/Warning are never hidden by Unknown. Unknown is returned when required telemetry is absent or stale; no data is not Healthy. No 0–100 score is produced.

Domain health is categorical: Performance, Protection, Availability, Capacity, and Anomaly. Explanation codes remain stable (`ACTIVE_CRITICAL_EVENT`, `BACKUP_CRITICAL`, `AG_UNHEALTHY`, `COLLECTION_STALE`, `TELEMETRY_UNAVAILABLE`).

## Correlation
The intended window is configurable through `DBAPULSE_CORRELATION_WINDOW_MINUTES` and defaults to 15 minutes; lookback defaults to 24 hours. Same DatabaseId plus temporal overlap is Strong, same ServerId without a database match is Moderate, and wider server-level proximity is Weak. Fingerprints use SHA-256 over server, database, and time bucket. Unique keys prevent duplicate signal insertion. Groups are Active/Resolved and collection failure does not resolve a group.

Correlation means `Related signals`, `Temporally related`, or `Observed concurrently`; it never means caused by, because of, or root cause.

## API and audit
- `GET /api/management/overview`
- `GET /api/management/attention`
- `GET /api/management/health`
- `GET /api/management/changes`
- `GET /api/management/correlations`
- `GET /api/management/correlations/{id}`

The management routes are audited as `Management.View`, `Management.Attention.View`, and `Management.Health.View`; audit failures do not break requests. Empty results are HTTP 200.

## Dashboard
The existing Dashboard route is now management-focused and retains the dark enterprise design system. It shows categorical Critical, Warning, Attention, Unknown counts, a deterministic summary, estate health/domain matrix, and Needs Attention. Existing Operations, Protection, Capacity, Performance, and Insights pages remain the drill-down surfaces.

## Performance and security
Management reads use bounded procedures and active/recent rows. Raw blocking, wait, and capacity histories are not full-scanned by the dashboard procedure. The API connection targets `DBA_PULSE`; source SQL remains collector read-only.

## Testing and lab limitations
The schema is introduced by V047–V049 and leaves V001–V046 unchanged. Synthetic same-database, different-database, out-of-window, duplicate, failure, status precedence, Unknown, and causality tests should be run against a DBA_PULSE integration database. Short lab history, including `InsufficientData` baselines, must remain Unknown/insufficient rather than Healthy.

## Phase 10 readiness
The bounded records (`ManagementOverview`, `ManagementAttentionRow`, `ManagementHealthRow`, correlation records) are structured and traceable for future controlled consumers. No LLM, AI summary, vector database, embedding, or tool endpoint is part of Phase 9.