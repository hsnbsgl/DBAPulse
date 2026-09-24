# Faz 5 — Operational Event Correlation

## 1. Amaç

Faz 4 raw performance observations kayıtlarını yöneticiye anlamlı, mutable Operational Event kayıtları olarak sunar. Kapsam Blocking, LongRunning ve Deadlock'tır. Wait statistics OperationalEvent değildir.

## 2. Architecture

`Performance Query Catalog -> Collector -> Fingerprint/Correlation -> DBA_PULSE.OperationalEvents -> API -> Operations UI`.

Raw telemetry korunur; correlation Collector process'i içinde `OperationalEventCorrelator` ve management Stored Procedure'leri ile yapılır.

## 3. Operational Event Model

`dbo.OperationalEvents` event state'ini tutar. Aynı olay devam ederken kayıt UPDATE edilir; event sourcing veya immutable event store değildir.

## 4. Mutable Event Design

Aktif fingerprint bulunursa `LastSeenAtUtc`, `DurationMs`, `ObservationCount`, `Severity` ve `UpdatedAtUtc` güncellenir. Kayıt yoksa `Active` event oluşturulur.

## 5. Event Types

- `Blocking`
- `LongRunning`
- `Deadlock`

## 6. Status Model

Yalnızca `Active` ve `Resolved` kullanılır. Acknowledged, Assigned, Closed ve Suppressed workflow'ları bu fazda yoktur.

## 7. Severity Model

Blocking ve LongRunning duration eşikleri configuration'dan gelir. Varsayılanlar:

- Blocking warning: 30 saniye
- Blocking critical: 120 saniye
- Long-running warning: 60 saniye
- Long-running critical: 300 saniye
- Deadlock: `Warning`

Bu değerler kurumsal SLA değildir. `Info`, `Warning`, `Critical` deterministic olarak üretilir.

## 8. Fingerprint Design

SHA-256 kullanılır. Blocking input: `EventType|ServerId|DatabaseId|BlockingSessionId|SessionId|SqlTextHash`. Preview fingerprint'e dahil edilmez. LongRunning input: `EventType|ServerId|DatabaseId|SessionId|SqlTextHash|RequestStartTimeSource`. Deadlock fingerprint mevcut `DeadlockHash` değeridir.

## 9. Blocking Correlation

Aynı server/database, blocker session, blocked session ve SQL hash aynıysa event update edilir. Aynı cycle içindeki tekrarlar application tarafında fingerprint ile gruplanır.

## 10. Blocking Resolution

Başarılı blocking query 0 satır döndürdüğünde stale resolution değerlendirilir. Varsayılan 180 saniye boyunca görülmeyen Active blocking event `Resolved` olur; `EndedAtUtc = LastSeenAtUtc` set edilir.

## 11. Session ID Reuse

SPID tek başına fingerprint değildir. Event type, server, database, blocker/blocked session, SQL hash ve zaman penceresi birlikte kullanılır. Resolved event aynı fingerprint ile yeni bir Active event olarak yeniden başlayabilir.

## 12. Long Running Correlation

Request start source zamanı, session ve SQL hash fingerprint'e dahil edilir. Source local zaman otomatik UTC olarak yorumlanmaz; event lifecycle zamanı Collector observation UTC'sidir.

## 13. Long Running Resolution

Başarılı zero-row long-running collection sonrası varsayılan 180 saniyeyi aşan stale Active event'ler Resolved olur. Query başarısızsa resolution çalışmaz.

## 14. Deadlock Mapping

Yeni `DeadlockEvents` kaydı Resolved OperationalEvent olarak map edilir. Occurred time hem start hem end kabul edilir ve duration 0'dır.

## 15. Deadlock Deduplication

`DeadlockHash` hem raw deadlock hem OperationalEvent tarafında deterministic identity'dir. Unique index ve insert procedure duplicate event oluşmasını engeller.

## 16. OperationalEvents Schema

Tablo; EventType, ServerId, DatabaseId, Fingerprint, Started/LastSeen/Ended UTC zamanları, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary ve sınırlı metadata alanlarını içerir.

## 17. Stored Procedures

- `usp_OperationalEvents_Upsert`
- `usp_OperationalEvents_ResolveStale`
- `usp_OperationalEvents_Overview`
- `usp_OperationalEvents_List`
- `usp_OperationalEvent_Detail`

TVP: `dbo.OperationalEventInputType`.

## 18. Wait Noise Filtering

Raw `WaitStatsSnapshots` korunur. Presentation/dashboard tarafında `WaitTypeExclusions` ile filtreleme yapılır.

## 19. Wait Exclusion List

`dbo.WaitTypeExclusions` seed kayıtları:

- `QDS_ASYNC_QUEUE`
- `SOS_WORK_DISPATCHER`
- `HADR_FILESTREAM_IOMGR_IOCOMPLETION`

Her kayıt Reason ve IsEnabled alanlarına sahiptir. Liste büyütülebilir; raw telemetry silinmez.

## 20. Collection Failure Semantics

Collector domain query başarısız olursa `CollectionErrors` yazılır ve ilgili event type için resolve çalıştırılmaz. Başarısız query, “event yok” anlamına gelmez.

## 21. Zero Row Semantics

`SUCCESS + 0 rows` ilgili telemetry'nin başarıyla değerlendirildiğini ve stale resolution yapılabileceğini ifade eder. `FAILED` ise state bilinmiyor kabul edilir.

## 22. Collector Restart Behavior

Active event state memory'de tutulmaz; `OperationalEvents` source of state'tir. Collector restart sonrası migration ve correlation state DB'den devam eder.

## 23. API

- `GET /api/operations/overview?hours=24`
- `GET /api/operations/events`
- `GET /api/operations/events/{id}`

List filtreleri status, severity, eventType, serverId, databaseId, fromUtc, toUtc ve page/pageSize'dır. PageSize 100 ile sınırlıdır.

## 24. Audit Integration

Operations endpoint'leri şu action'larla audit edilir:

- `Operations.View`
- `Operations.EventList.View`
- `Operations.EventDetail.View`

SQL text, deadlock XML veya hassas query parametreleri audit'e yazılmaz.

## 25. Operations UI

Sidebar'a Operations eklendi. KPI kartları Active/Critical/Warning/Resolved durumlarını, event type özetini, filtreli/pagination'lı listeyi ve event detail panelini gösterir.

## 26. Timezone

DB UTC saklar, API UTC ISO 8601 döndürür, React Europe/Istanbul gösterir.

## 27. Retention Readiness

Purge, archive, partition ve compression uygulanmadı. Raw performance telemetry ile OperationalEvents için ileride farklı retention politikaları uygulanabilir; süreler hard-code edilmedi.

## 28. Lab Validation

V021–V028 gerçek lab DBA_PULSE üzerinde uygulandı. Collector `Collection #30002` başarıyla çalıştı; blocking/long-running/deadlock query'leri başarılı zero-row döndürdü. Operations ekranı gerçek DB'den 0 event durumunu gösterdi. Wait exclusion kayıtları ve Operations audit kayıtları doğrulandı.

## 29. Known Limitations

Lab ortamında aktif blocking, uzun request ve deadlock olmadığı için pozitif correlation/update/resolve lifecycle'ı gerçek event üzerinde gözlemlenemedi. Fingerprint ve upsert mantığı production event akışı için hazırdır; kontrollü event üretimi bu fazda yapılmadı.

## 30. Sonraki Faz

Incident/ITSM workflow, acknowledgement, anomaly detection, AI/LLM, Query Store, tuning, retention ve production authentication sonraki fazlara bırakılmıştır.
