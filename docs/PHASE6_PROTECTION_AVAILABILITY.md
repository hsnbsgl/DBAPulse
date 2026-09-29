# Faz 6 — Database Protection & Availability Intelligence

## Amaç

Faz 6, backup protection, Always On availability ve SQL Agent job health telemetrilerini read-only Query Catalog sorguları ile toplayıp DBA_PULSE üzerinden yöneticinin görebileceği deterministic durumlara dönüştürür.

## Mimari ve read-only sınır

Kaynak SQL Server yalnızca DMV, `msdb` metadata ve `backupset` üzerinden okunur. Collector kaynakta tablo, procedure, job, Extended Event veya configuration değişikliği yapmaz. API yalnızca `DBAPULSE_API_CONNECTION` ile DBA_PULSE'a bağlanır; source SQL'i bilmez.

## Existing schema analysis

Faz 1'deki `BackupSnapshots`, `JobSnapshots` ve `AlwaysOnSnapshots` korunmuştur. V029 ile eksik duration, job execution, running state, failure count ve Always On queue/suspend alanları eklenmiştir. Yeni paralel raw telemetry tabloları oluşturulmamıştır.

## Backup collection and protection

`queries/backup/last-backups.sql`, `msdb.dbo.backupset` içindeki her database/type için son başarılı kaydı okur. Full, differential, log ve copy-only ayrımı korunur. Protection freshness hesabında son geçerli Full **veya** Differential backup kullanılır; günlük Differential backup, aynı policy penceresi içinde yeni Full alınmamış olsa bile database'i korumalı kabul ettirebilir. Hiç Full/Differential görülmeyen database `NeverBackedUp` olur. Collector geçmişinde base Full bulunmasa bile yeni Differential telemetry'si freshness sinyali olarak kabul edilir; restore chain geçerliliği ayrıca DBA/source sorumluluğundadır. `FULL`/`BULK_LOGGED` recovery modelinde log backup yaşı değerlendirilir; `SIMPLE` için log backup eksikliği üretilmez. `tempdb` `NotApplicable`, collection verisi bulunmayan durum `Unknown` olarak ele alınır.

V029 ile `dbo.BackupPolicies` ve başlangıç Default policy oluşturulmuştur: full 24 saat, differential 24 saat, log 60 dakika, warning yüzde 80. V052, differential freshness kuralını `usp_BackupProtection_List` ve `usp_ProtectionAvailability_Overview` içinde uygular. Bunlar kurumsal SLA değildir; ileride policy yönetimi genişletilebilir. Kaynak `backup_start_date`/`backup_finish_date` alanları source-local semantics ile saklanır; otomatik UTC etiketi verilmez.

## Always On

Always On sorgusu availability group, replica, synchronization, connection, suspend ve queue alanlarını read-only DMV'lerden toplar. Always On yoksa sorgu başarılı biçimde sıfır satır döner; UI `Always On is not configured` gösterir. `Disconnected`, suspended veya `NOT_HEALTHY` durumları Critical; partial/not-synchronizing durumları Warning; queue değerleri ise gözlem olarak gösterilir, tek başına incident/anomaly değildir. Commit zamanı source-local semantics ile tutulur.

## SQL Agent

Job sorgusu overall `step_id = 0` history sonucunu kullanır. `Succeeded`, `Failed`, `Retry`, `Canceled`, `NeverRun` ve disabled ayrımı korunur. `run_duration` SQL Agent'in HHMMSS integer formatından aritmetik olarak saniyeye çevrilir; son 24 saat/7 gün failure sayısı, son üç execution'da tekrarlı failure ve running duration toplanır. Job command/step command audit veya UI'ya taşınmaz.

## Freshness ve failure semantics

List read model'leri son collection zamanını döndürür ve 30 dakikayı aşan telemetry `Stale` olarak işaretlenir. `FAILED collection` problem yok anlamına gelmez; mevcut fazın CollectionErrors/PartialSuccess davranışı korunur. `SUCCESS + zero rows` ise gerçek boş durumdur. Lab'da Agent ve Always On yoksa bu durum `0 jobs` ve `NotConfigured` olarak görünür.

## Stored procedures, API ve UI

V029–V034 migration'ları policy, extended input types, persistence procedures, dashboard read models ve indexleri içerir. API endpointleri:

- `GET /api/protection/overview`
- `GET /api/protection/backups`
- `GET /api/protection/backups/{databaseId}`
- `GET /api/availability/alwayson`
- `GET /api/availability/alwayson/{id}`
- `GET /api/jobs`
- `GET /api/jobs/{id}`

Yeni React ekranı Protection & Availability; backup, Always On ve SQL Agent bölümlerini ayrı gösterir ve her bölümde 10 kayıt/sayfa kullanır. Yeni endpointler audit middleware tarafından `Protection.*`, `Availability.*` ve `Jobs.*` action'ları ile audit edilir.

## Operational Events

Bu uygulamada protection read model ve cockpit görünürlüğü eklenmiştir. Lab'da backup policy state transition, Always On positive state ve SQL Agent failure event senaryoları için sahte veri üretilmemiştir; bu alanlar pozitif telemetry mevcut olduğunda Faz 5 correlator'a bağlanmak üzere ayrıdır.

## Permissions and compatibility

Collector için sysadmin hedeflenmez. Backup/job sorguları `msdb` okuma erişimi; DMV/Always On sorguları SQL Server sürümüne göre `VIEW SERVER STATE` veya ilgili yeni `VIEW SERVER PERFORMANCE STATE` ve HADR DMV izinlerini gerektirebilir. SQL Server 2019/2022/2025 farkları Query Catalog sürümlemesi ile yönetilmelidir.

## Lab validation and limitations

V029–V034 gerçek lab DBA_PULSE üzerinde uygulandı ve ikinci başlatmada skip edildi. Collector cycle başarıyla tamamlandı: 1 server, 10 database, 7 backup row, 0 SQL Agent job, 0 Always On row. API health ve üç Faz 6 endpointi gerçek management verisiyle yanıt verdi. Always On positive test ve SQL Agent positive success/failure testleri lab özellikleri bulunmadığı için `NOT TESTED` kapsamındadır. Backup history sınırlı olduğundan protection listesi gerçek veriye göre risk durumlarını gösterir.

## Timezone, retention ve sonraki işler

Collector üretimli zamanlar UTC; source `msdb`/`backupset` tarihleri source-local olarak açıkça ayrılır. Faz 6'da purge, archive, partition, automatic remediation, failover, job start/stop veya backup/restore yoktur. Sonraki fazlarda source timezone normalization, policy yönetimi, protection/AG/job OperationalEvent lifecycle'ı ve gerçek estate positive testleri ele alınabilir.
