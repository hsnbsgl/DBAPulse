# DBA Pulse — Faz 0 Keşif Raporu

## Kullanılan lab ortamı

Bu çalışma yalnızca ev/lab ortamındaki yerel SQL Server üzerinde yapıldı. Gerçek kurum MonitorSQL sunucusuna bağlantı kurulmadı.

- Lab hedefi: `LAB-MonitorSQL`
- Çalışan container: `reportserver-sql-1`
- Image: `mcr.microsoft.com/mssql/server:2025-latest`
- Edition: Developer
- Host bağlantı noktası: `localhost,1433` (container içinden `localhost`)
- Kimlik doğrulama: SQL login; parola repository’ye veya bu belgeye yazılmadı.
- Configuration sözleşmesi: `DBAPULSE_MONITORSQL_CONNECTION`

Gerçek ortama geçişte yalnızca configuration değeri değiştirilmelidir. Kod içinde lab/ev ortamına özel koşul bulunmamaktadır.

## SQL Server bağlantı sonucu

Bağlantı başarılıdır. Tüm keşif sorguları salt-okunur olarak çalıştırıldı.

| Alan | Sonuç |
| --- | --- |
| Server adı | `9fa3d46b4cff` |
| Instance adı | `MSSQLSERVER` (default instance) |
| SQL Server version | `17.0.4085.5` |
| Product level | `RTM` |
| Edition | `Enterprise Developer Edition (64-bit)` |
| SQL Server start time | `2026-09-20 09:11:18.757` |
| Uptime | `336857` saniye (keşif anındaki değer) |

## Bulunan database'ler

`master`, `tempdb`, `model`, `msdb`, `ReportServer`, `AppControl`, `SSLOps`, `DAGPortal`, `deneme` database'leri `ONLINE` durumda bulundu.

## Linked Server durumu

Linked Server bulunamadı. Bu durum lab için beklenen ve Faz 0'ı engellemeyen bir durum olarak kaydedildi. Dolayısıyla uzak linked-server erişilebilirlik testi çalıştırılacak hedef olmadığından uygulanamadı.

## Query Catalog

Aşağıdaki sorgular oluşturuldu:

- `queries/inventory/server-info.sql`
- `queries/inventory/databases.sql`
- `queries/inventory/linked-servers.sql`
- `queries/backup/last-backups.sql`
- `queries/jobs/job-status.sql`
- `queries/alwayson/ag-health.sql`
- `queries/capacity/database-size.sql`

Çalışma sonuçları:

| Sorgu alanı | Sonuç |
| --- | --- |
| Server bilgisi | Çalıştı |
| Database listesi | Çalıştı; 9 database bulundu |
| Linked Server listesi | Çalıştı; 0 kayıt |
| Son backup bilgileri | Çalıştı; `msdb` backup history içinde kayıtlar bulundu |
| SQL Agent job durumu | Çalıştı; 0 job bulundu |
| Always On AG health | Çalıştı; `NotConfigured` |
| Database size | Çalıştı; database/file türü bazında allocation bilgisi döndü |

Sorgular kaynak SQL Server üzerinde `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `ALTER`, `DROP`, `TRUNCATE`, `KILL`, `BACKUP`, `RESTORE`, `DBCC`, `sp_configure`, `xp_cmdshell` veya Linked Server configuration değişikliği yapmaz.

## Lab ortamında test edilemeyen veya mevcut olmayan özellikler

- Linked Server tanımı ve uzak SQL01/SQL02/SQL03 erişilebilirliği mevcut değil.
- Always On Availability Group mevcut değil; sorgu hata yerine `NotConfigured` döndürüyor.
- SQL Agent job mevcut değil; job sorgusu boş sonuç döndürüyor.
- Çoklu uzak SQL Server topolojisi ve kurumsal linked-server yetki/erişim davranışları lab’da doğrulanamadı.

Backup history ve temel database kapasite bilgisi lab ortamında mevcut olduğundan test edildi.

## Gerçek MonitorSQL ortamında daha sonra doğrulanacak konular

- MonitorSQL bağlantı endpoint’i, authentication yöntemi, TLS/sertifika ve minimum yetkili login.
- Linked Server adları, provider/driver uyumluluğu ve SQL01/SQL02/SQL03 erişilebilirliği.
- Gerçek Always On topolojisi, replica/database health alanları ve gerekli DMV izinleri.
- SQL Agent job history saklama süresi ve backup history kapsamı.
- MonitorSQL’deki database erişim kapsamı ve `sys.*`/`msdb` görünürlük izinleri.
- Gerçek ortamda sorgu süreleri, timeout değerleri ve merkezi logging gereksinimleri.
