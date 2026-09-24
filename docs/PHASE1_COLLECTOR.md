# DBA Pulse — Faz 1 Collector

## 1. Faz 1 amacı

Faz 1, Faz 0 Query Catalog sorgularını LAB-MonitorSQL üzerinde salt-okunur çalıştıran ve sonuçları `DBA_PULSE` management database’ine Microsoft.Data.SqlClient, stored procedure ve TVP kullanarak yazan ilk çalışan veri omurgasını oluşturur.

Gerçek lab smoke testinde iki collection cycle başarıyla çalıştırıldı. Source SQL Server üzerinde tablo, procedure, type, job veya configuration oluşturulmadı.

## 2. Mimari

```text
LAB-MonitorSQL
    |
    | Query Catalog / read-only
    v
DBAPulse.Collector (.NET Worker)
    | Microsoft.Data.SqlClient
    | TVP + Stored Procedure
    v
DBA_PULSE
```

Collector source ve management connection'larını ayrı tutar. Source sorguları SQL dosyalarından okunur; sorgular C# stringlerine taşınmaz.

## 3. Source / Management ayrımı

- `DBAPULSE_SOURCE_CONNECTION`: LAB-MonitorSQL ve ileride gerçek MonitorSQL. Yalnızca Query Catalog text sorguları çalıştırılır.
- `DBAPULSE_MANAGEMENT_CONNECTION`: `DBA_PULSE` database'i. Yalnızca migration ve persistence stored procedure'leri kullanılır.
- Collector'ın source tablolarına yazma yetkisi veya source üzerinde kalıcı nesne oluşturma davranışı yoktur.

## 4. Solution yapısı

- `src/DBAPulse.Domain`: inventory ve persistence DTO/model kayıtları.
- `src/DBAPulse.Data`: SqlClient bağlantıları, migration runner, TVP/DataTable üretimi ve management stored procedure çağrıları.
- `src/DBAPulse.Collector`: Worker loop, Query Catalog execution, mapping, orchestration ve console logging.
- `database/migrations`: versionlanmış native SQL migration'lar.
- `Dockerfile`, `docker-compose.phase1.yml`: Collector image ve lab çalıştırma tanımı.

EF Core, EF Migration, Dapper, ORM, API, React veya scheduler framework kullanılmadı.

## 5. DBA_PULSE database şeması

Migration runner ilk olarak `DBA_PULSE` database'ini oluşturur. `dbo.SchemaVersions` migration uygulanma kaydını tutar. Runner dosya adlarını `V001`... sırasıyla yürütür, uygulanmış sürümleri atlar ve başarısız migration'da durur.

Uygulanan migration'lar:

1. `V001__Create_Database.sql`
2. `V002__Create_Master_Tables.sql`
3. `V003__Create_Snapshot_Tables.sql`
4. `V004__Create_Collection_Tables.sql`
5. `V005__Create_Table_Types.sql`
6. `V006__Create_Stored_Procedures.sql`
7. `V007__Create_Indexes.sql`

## 6. Master tablolar

- `dbo.Servers`: server/instance/version/edition/timezone metadata.
- `dbo.Databases`: server database metadata; `(ServerId, DatabaseName)` unique.

Server ve database sync procedure'leri mevcut kaydı günceller, yeni kaydı ekler ve ID mapping döndürür. İkinci cycle sonrasında master duplicate oluşmadı.

## 7. Snapshot tablolar

`ServerSnapshots`, `DatabaseSnapshots`, `BackupSnapshots`, `JobSnapshots`, `AlwaysOnSnapshots` ve `CapacitySnapshots` tabloları `bigint IDENTITY` anahtar ve `CollectedAtUtc datetime2(3)` kolonuyla oluşturuldu. Snapshot tabloları `ServerId`/`DatabaseId` kullanır; statik server/database metadata'sı tekrar snapshot olarak yazılmaz.

## 8. Collection tabloları

- `dbo.CollectionRuns`: lifecycle, status ve duration.
- `dbo.CollectionErrors`: bağımsız query/domain hataları.

İki çalışmada `CollectionErrors` sayısı 0 oldu.

## 9. Stored Procedure yapısı

Oluşturulan procedure'ler:

- `usp_Servers_Sync`
- `usp_Databases_Sync`
- `usp_ServerSnapshots_Insert`
- `usp_DatabaseSnapshots_Insert`
- `usp_BackupSnapshots_Insert`
- `usp_JobSnapshots_Insert`
- `usp_AlwaysOnSnapshots_Insert`
- `usp_CapacitySnapshots_Insert`
- `usp_CollectionRun_Start`
- `usp_CollectionRun_Complete`
- `usp_CollectionError_Insert`

Procedure'ler `SET NOCOUNT ON` kullanır. Snapshot insert'leri tek TVP çağrısıdır; row-by-row persistence yoktur.

## 10. TVP kullanımı

Oluşturulan table type'lar:

- `ServerInputType`
- `DatabaseInputType`
- `ServerSnapshotInputType`
- `DatabaseSnapshotInputType`
- `BackupSnapshotInputType`
- `JobSnapshotInputType`
- `AlwaysOnSnapshotInputType`
- `CapacitySnapshotInputType`

Collector DataTable'ları bu tip adlarıyla `SqlDbType.Structured` parametre olarak gönderir.

## 11. Query Catalog

Faz 0 dosyaları korunarak kullanılmaya devam edildi:

- `queries/inventory/server-info.sql`
- `queries/inventory/databases.sql`
- `queries/backup/last-backups.sql`
- `queries/jobs/job-status.sql`
- `queries/alwayson/ag-health.sql`
- `queries/capacity/database-size.sql`

`linked-servers.sql` inventory dosyası da korunmuştur; Faz 1 persistence tablosu olmadığı için collection akışına ayrıca eklenmemiştir. Sıfır sonuçlar başarı kabul edilir: Jobs ve Always On lab'da 0 satır döndürdü.

## 12. Collector çalışma akışı

1. CollectionRun başlatılır.
2. Server inventory okunur ve master sync yapılır.
3. Server snapshot yazılır.
4. Database inventory okunur ve master sync yapılır.
5. Database snapshot yazılır.
6. Backup, Job, Always On ve Capacity sorguları bağımsız olarak çalıştırılır.
7. Her domain TVP + stored procedure ile yazılır.
8. Hata varsa `CollectionErrors` yazılır ve mümkün olduğunca sonraki domain'lere devam edilir.
9. Sonuç `Success`, `PartialSuccess` veya `Failed` olarak tamamlanır.

## 13. Configuration / Environment Variables

- `DBAPULSE_SOURCE_CONNECTION`
- `DBAPULSE_MANAGEMENT_CONNECTION`
- `DBAPULSE_DISPLAY_TIMEZONE` — varsayılan `Europe/Istanbul`
- `DBAPULSE_COLLECTION_INTERVAL_MINUTES` — varsayılan 5
- `DBAPULSE_RUN_ONCE` — smoke test için tek cycle seçeneği

Gerçek connection string ve password source code, Git, README, Dockerfile ve image içine yazılmaz. `.env.example` yalnızca placeholder içerir.

## 14. Docker

Collector image:

```text
dbapulse-collector:phase1
```

`Dockerfile` .NET 8 SDK ile build, .NET 8 runtime ile çalışır. `docker-compose.phase1.yml` `host.docker.internal:1433` üzerinden mevcut `reportserver-sql-1` SQL Server'ına ulaşır; yeni SQL Server container oluşturmaz.

## 15. Error Handling

Server inventory veya management lifecycle temel altyapısı başarısız olursa cycle `Failed` olur. Backup, Jobs, Always On veya Capacity gibi bağımsız domain'lerde hata olursa hata kaydedilir ve cycle `PartialSuccess` olarak tamamlanır. Empty result hata değildir.

## 16. Security Model

İleride `dbapulse_collector` gibi ayrı login'e yalnızca procedure `EXECUTE` yetkileri verilebilir. Bu fazda production login oluşturulmadı; şema ve çağrı modeli doğrudan table write gerektirmeyecek şekilde hazırlandı.

## 17. Time and Timezone Strategy

- Uygulama zamanları UTC olarak `datetime2(3)` saklanır.
- Collector `DateTime.UtcNow` kullanır.
- Görüntüleme timezone configuration ile `Europe/Istanbul` olarak tanımlıdır; database'e UTC+3 ayrı kolon yazılmaz.
- Source SQL Server'dan gelen backup ve SQL Agent zamanları source local datetime olarak saklanır; otomatik UTC kabul edilmez veya dönüştürülmez.
- `Servers.TimeZoneId` server bazlı ileride doğru normalization için saklanır.

Smoke test'te `CollectionRuns` ve `LastSeenAtUtc` UTC değerleriyle oluştu; `Servers.TimeZoneId` değeri `Europe/Istanbul` oldu.

## 18. Data Retention and Future Archiving

Snapshot/event PK'leri `bigint`, standart zaman kolonu `CollectedAtUtc` ve server/database zaman index'leriyle tasarlandı. Bu yapı ileride `CollectedAtUtc` üzerinden retention, purge, aylık partition, compression, archive database, hourly rollup ve daily rollup eklenmesine açıktır.

Bu fazda archive database, partition, purge job, compression veya rollup oluşturulmadı; retention süreleri hard-code edilmedi.

## 19. Lab ortamı kısıtları

- Linked Server yok; SQL01/SQL02/SQL03 erişilebilirliği test edilemedi.
- Always On `NotConfigured` ve AlwaysOnSnapshots boş kaldı.
- SQL Agent job yok ve JobSnapshots boş kaldı.
- Collector oluşturduğu `DBA_PULSE` database'i source database inventory içinde sonraki cycle'dan itibaren görünür; bu nedenle database sayısı 9'dan 10'a çıktı ve beklenen bir lab sonucudur.

## 20. Faz 2 için kalan işler

Production least-privilege login/permission kurulumu, gerçek MonitorSQL linked-server/Always On doğrulaması, API/UI, dashboard, retention/partition/rollup politikaları ve daha kapsamlı test/observability sonraki fazlara bırakıldı.
