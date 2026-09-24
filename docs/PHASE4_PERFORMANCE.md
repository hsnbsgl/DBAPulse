# Faz 4 — SQL Performance Telemetry

## 1. Amaç

Faz 4; SQL Server performance telemetry verilerini read-only Query Catalog sorguları ile toplayıp DBA_PULSE içinde tarihsel olarak saklar. Kapsam blocking observations, long-running requests, cumulative wait statistics ve mevcut `system_health` deadlock event okumadır. Incident correlation, anomaly detection, AI, Query Store ve automatic tuning bu fazın kapsamında değildir.

## 2. Architecture

`Source SQL / MonitorSQL -> Query Catalog -> Collector -> TVP + Stored Procedure -> DBA_PULSE -> API -> React Performance`.

Collector iki connection kullanır. API yalnızca `DBAPULSE_API_CONNECTION` ile DBA_PULSE'a bağlanır.

## 3. Source Read-Only Boundary

Performance sorguları DMV'leri ve mevcut `system_health` Extended Event ring buffer'ını okur. Source SQL üzerinde tablo, procedure, view, job, trigger veya yeni XE session oluşturulmaz; configuration değiştirilmez.

## 4. Performance Query Catalog

- `queries/performance/blocking.sql`
- `queries/performance/long-running-requests.sql`
- `queries/performance/wait-stats.sql`
- `queries/performance/deadlocks.sql`

Long-running threshold `DBAPULSE_LONG_RUNNING_SECONDS` ile yönetilir; varsayılan 60 saniyedir. Wait query açık bir noise exclusion listesi içerir.

## 5. Blocking Collection

`sys.dm_exec_requests`, `sys.dm_exec_sessions` ve `sys.dm_exec_sql_text` kullanılır. Yalnızca `blocking_session_id > 0` ve user session kayıtları alınır. Her collection ayrı observation'dır; incident correlation yapılmaz.

## 6. Blocking Observation Semantics

Aynı SPID ilişkisi sonraki cycle'larda tekrar görülebilir ve her gözlem `BlockingEvents` tablosuna ayrı yazılır. `IncidentId` yoktur.

## 7. Long Running Requests

Aktif user request'leri elapsed threshold üzerinde ise `LongRunningRequestSnapshots` tablosuna yazılır. SQL text yalnızca SHA-256 hash ve en fazla 1500 karakterlik normalize edilmiş preview olarak saklanır.

## 8. Wait Statistics

`sys.dm_os_wait_stats` kümülatif sayaçları `WaitStatsSnapshots` içine raw olarak kaydedilir. `SqlServerStartTimeUtc` SQL restart baseline'ını tanımak için saklanır.

## 9. Wait Delta Calculation

`usp_WaitStats_Top` aynı server, wait type ve SQL start time içindeki ardışık snapshot'larda `LAG` kullanır. Yalnızca negatif olmayan delta'lar dahil edilir. Dashboard delta üretir; raw snapshot kaybolmaz.

## 10. SQL Restart / Counter Reset Handling

SQL Server start time değişirse önceki baseline ile eşleştirme yapılmaz. Wait, signal wait veya task counter negatifse delta satırı dışlanır.

## 11. Wait Type Filtering

Noise wait'ler `queries/performance/wait-stats.sql` içinde açık `NOT IN` listesiyle filtrelenir. Liste; broker, sleep, checkpoint, dispatcher, trace ve XE idle wait türlerini kapsar ve ileride kaynak dosyadan güncellenebilir.

## 12. Deadlock Collection

Collector mevcut `system_health` ring buffer içindeki `xml_deadlock_report` event'lerini okur. Yeni Extended Event session oluşturulmaz. Lab SQL Server'da sorgu çalıştı ve 0 event döndü.

## 13. Deadlock Deduplication

Deadlock XML SHA-256 hash'i deterministic identity olarak kullanılır. `DeadlockHash` unique constraint'e sahiptir; insert procedure hem batch içi hem de mevcut tabloya karşı duplicate kontrolü yapar.

## 14. SQL Text Security

Tam SQL text merkezi DB'ye taşınmaz. Preview control character'lardan arındırılır ve 1500 karakterle sınırlıdır. SQL text application log'a yazılmaz. Hash veya preview'nin hassas değer içerebileceği varsayımı dokümante edilmiş olup ileride redaction değerlendirilebilir.

## 15. Database Schema

Yeni tablolar:

- `BlockingEvents`
- `LongRunningRequestSnapshots`
- `WaitStatsSnapshots`
- `DeadlockEvents`

Event/snapshot tablolarında `bigint` identity ve UTC observation zamanı bulunur. Server/database foreign key'leri ve zaman bazlı index'ler oluşturulmuştur. Long-running request başlangıç zamanı `RequestStartTimeSource` adıyla kaynak SQL Server zamanı olarak saklanır; otomatik UTC varsayımı yapılmaz.

## 16. TVP

- `dbo.BlockingEventInputType`
- `dbo.LongRunningRequestInputType`
- `dbo.WaitStatsSnapshotInputType`
- `dbo.DeadlockEventInputType`

Collector row-by-row SQL insert yapmaz.

## 17. Stored Procedures

Insert:

- `usp_BlockingEvents_Insert`
- `usp_LongRunningRequests_Insert`
- `usp_WaitStatsSnapshots_Insert`
- `usp_DeadlockEvents_Insert`

Dashboard:

- `usp_Performance_Overview`
- `usp_Blocking_Recent`
- `usp_Deadlocks_Recent`
- `usp_LongRunning_Recent`
- `usp_WaitStats_Top`

## 18. Collection Scheduling

Mevcut basit Worker loop korunmuştur. Performance sorguları her collection cycle'da bağımsız `RunDomainAsync` blokları ile çalışır. Bir performance sorgusu hata verirse `CollectionErrors` yazılır ve diğer domain'ler devam eder. Threshold config'den gelir; karmaşık scheduler eklenmemiştir.

## 19. Required SQL Permissions

DMV sorguları için SQL Server sürüm ve güvenlik modeline göre `VIEW SERVER STATE` veya ilgili yeni sürüm DMV permission'ları gerekebilir. Collector'a `sysadmin` verilmemelidir. Lab'ta mevcut `sa` credential yalnızca geliştirme smoke testinde kullanılmıştır; production minimum permission hesabı ayrıca tanımlanmalıdır.

## 20. SQL Version Compatibility

Sorgular temel DMV kolonları ve mevcut `system_health` yapısı üzerine kuruludur. SQL Server 2019/2022/2025 estate'inde DMV permission ve XE XML farkları ayrıca doğrulanmalıdır. Version-specific varyant gerekirse Query Catalog altında ayrı sorgu dosyaları kullanılmalıdır.

## 21. API

- `GET /api/performance/overview?hours=24`
- `GET /api/performance/blocking?hours=24`
- `GET /api/performance/deadlocks?hours=24`
- `GET /api/performance/long-running?hours=24`
- `GET /api/performance/waits?hours=24`

İzin verilen hours değerleri: `1, 6, 12, 24, 48, 168`; diğer değerler 24'e düşürülür. API source SQL veya DMV'lere bağlanmaz.

## 22. Audit Integration

Performance endpoint'leri Faz 3 middleware ile audit edilir: `Performance.View`, `Performance.Blocking.View`, `Performance.Deadlock.View`, `Performance.LongRunning.View`, `Performance.Waits.View`. SQL text ve deadlock XML audit'e yazılmaz.

## 23. Performance UI

Sidebar'a Performance eklendi. Ekran KPI kartları, top waits bar chart, recent blocking, deadlock ve long-running listelerini gösterir. Boş sonuçlar hata değil bilgi durumudur.

## 24. Timezone

Database zamanları UTC saklanır ve API UTC ISO 8601 döndürür. UI `Europe/Istanbul` configuration'ı ile gösterir. Source request start time gibi local kaynak zamanları otomatik UTC olarak yorumlanmamalıdır; duration/counter telemetry için Collector observation zamanı esas alınır.

## 25. Retention Readiness

Raw telemetry `bigint` ID ve zaman kolonlarıyla saklanır. Bu fazda purge, partition, archive, compression veya rollup yoktur.

## 26. Lab Validation

İki gerçek collection cycle çalıştırıldı. Her iki cycle'da blocking 0, long-running 0, deadlock 0 ve wait stats 86 satır alındı. Toplam `WaitStatsSnapshots` 172 oldu. V014–V018 ilk cycle'da uygulandı; ikinci cycle'da skip edildi. V019 deadlock duplicate hardening migration'ıdır. V020 kaynak request başlangıç zamanı kolonunun UTC varsayılmamasını netleştirir.

## 27. Known Limitations

Lab'de aktif blocking, long-running request ve deadlock bulunmadığından event persistence pozitif örneklerle test edilmedi. Deadlock collection teknik olarak çalıştı ve 0 kayıt verdi. Wait delta için iki baseline snapshot saklandı; aynı sayaç değerleri nedeniyle anlamlı pozitif delta oluşmayabilir.

## 28. Faz 5'e kalan işler

Incident correlation, anomaly detection, Query Store, execution plan, automatic tuning, retention/archive, minimum-permission production login ve daha kapsamlı performance drill-down sonraki fazlara bırakılmıştır.
