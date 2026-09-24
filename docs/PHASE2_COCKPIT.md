# DBA Pulse — Faz 2 Management API + First DBA Cockpit

## 1. Amaç

Faz 2, Faz 1 Collector tarafından `DBA_PULSE` içine yazılan gerçek verileri yalnızca management database üzerinden okuyan ASP.NET Core API ve React cockpit ekler.

## 2. Mimari

```text
LAB-MonitorSQL -> Collector -> DBA_PULSE -> DBAPulse.Api -> Nginx/React -> Browser
```

API source SQL Server, Query Catalog veya Linked Server görmez. API bağlantısı yalnızca `DBAPULSE_API_CONNECTION` ile `DBA_PULSE` database'ine gider.

## 3. Security Boundary

- Collector: source + management connection kullanır.
- API: yalnızca management connection kullanır.
- Web: yalnızca aynı-origin `/api` proxy'sine istek yapar.
- API'de source connection environment variable veya source query dosyası yoktur.
- API endpoint'leri management stored procedure çağırır; doğrudan tablo write işlemi yoktur.
- Production'da `dbapulse_reader` benzeri login'e procedure `EXECUTE` yetkisi verilebilir.

## 4. API Architecture

- `src/DBAPulse.Api`: .NET 8 minimal REST API.
- `DBAPulse.Data/DashboardStore.cs`: Microsoft.Data.SqlClient ve strongly typed DataReader mapping.
- Controller-heavy veya generic repository katmanı eklenmedi.
- API exception middleware ile anlaşılır problem response üretir.

## 5. Dashboard Stored Procedures

Yeni migration'lar:

- `V008__Create_Dashboard_Stored_Procedures.sql`
- `V009__Create_Dashboard_Indexes.sql`
- `V010__Fix_Dashboard_Capacity_Procedure.sql`

Procedure'ler:

- `usp_Dashboard_Overview`
- `usp_Dashboard_DatabaseHealth`
- `usp_Dashboard_BackupStatus`
- `usp_Dashboard_Capacity`
- `usp_Dashboard_RecentCollections`
- `usp_Servers_List`
- `usp_Server_Detail`
- `usp_Databases_List`
- `usp_Database_Detail`
- `usp_Database_CapacityHistory`

V010, V008'deki iki result set arasında CTE scope hatasını düzeltir; V008/V009 dosyaları değiştirilmemiştir.

## 6. API Endpoints

- `GET /api/health`
- `GET /api/dashboard/overview`
- `GET /api/dashboard/database-health`
- `GET /api/dashboard/backup-status`
- `GET /api/dashboard/capacity`
- `GET /api/collections/recent?limit=20`
- `GET /api/servers`
- `GET /api/servers/{id}`
- `GET /api/databases?page=1&pageSize=50&search=`
- `GET /api/databases/{id}`
- `GET /api/databases/{id}/capacity-history?days=30`

Database page size API ve procedure tarafında en fazla 100'dür. Capacity history günleri 7, 30, 90, 180 veya 365 ile sınırlandırılır.

## 7. React Architecture

`src/DBAPulse.Web` bağımsız React + TypeScript + Vite uygulamasıdır. Material UI layout ve components, Apache ECharts capacity chart için kullanılır. API base URL `VITE_API_BASE_URL` üzerinden gelir; production container'da `/api` kullanılır.

## 8. Dashboard

Dashboard gerçek overview, database health, capacity ve recent collections endpoint'lerini çağırır. Server/database/healthy/warning/critical/collection kartları; health tablosu; capacity özeti ve collection tablosu bulunur.

## 9. SQL Estate

SQL Estate server listesini ve database listesini gösterir. Server satırı server detail'e, database satırı database detail'e gider. Fake server veya fake database eklenmedi.

## 10. Server Detail

Server adı, instance, SQL version, edition, last seen ve database listesi gösterilir. Always On, Jobs veya performance için fake alan eklenmedi.

## 11. Database Detail

Database status, server, recovery model, last seen, current data/log/total capacity ve full/differential/log backup alanları gösterilir. Backup zamanı source local datetime olarak tutulur; kurumsal timezone normalization bu fazda yapılmaz.

## 12. Capacity History

Database detail ekranı ECharts line chart ile Data, Log ve Total serilerini gösterir. 7D/30D/90D/180D/365D seçimleri vardır. History SQL tarafında `CollectionRunId` bazında gruplanır ve `CollectedAtUtc ASC` döner.

## 13. Backup Semantics

Current backup status, her database ve backup type için `CollectedAtUtc`/identity sırasındaki son snapshot'ı kullanır. Historical duplicate snapshot'lar current değere tekrar eklenmez. Full/differential/log yoksa `Unknown` veya `N/A` gösterilir. Recovery model'e göre log backup eksikliği kritik SLA kuralına dönüştürülmez.

## 14. Current Snapshot Semantics

Capacity current değerleri database ve file type başına en son snapshot'tan seçilir. Eski snapshot'ların tamamı toplanmaz. Lab doğrulamasında toplam current capacity `398.88 MB` olarak döndü ve historical kayıtların toplamı kullanılmadı.

## 15. Timezone Handling

API UTC `DateTimeOffset` değerlerini ISO 8601 offset ile döndürür. React, `VITE_DISPLAY_TIMEZONE` veya varsayılan `Europe/Istanbul` ile gösterim yapar. Database'e local display zamanı yazılmaz.

## 16. Configuration

- `DBAPULSE_API_CONNECTION`: API'nin tek SQL connection'ı; `Database=DBA_PULSE`.
- `DBAPULSE_DISPLAY_TIMEZONE`: varsayılan `Europe/Istanbul`.
- `VITE_API_BASE_URL`: varsayılan `/api`.
- Gerçek password `.env.example`, source code, Dockerfile veya README'ye yazılmaz.

## 17. Docker

Faz 2 Compose servisleri:

- `dbapulse-collector`
- `dbapulse-api`
- `dbapulse-web`

Mevcut `reportserver-sql-1` kullanılır; yeni SQL Server oluşturulmaz. API ve web aynı Compose network'ündedir. Collector/API SQL Server'a `host.docker.internal:1433` üzerinden gider.

## 18. Nginx

React production build Nginx ile servis edilir. `/api/` istekleri `dbapulse-api:8080` adresine proxy edilir; `/` React `index.html`'e fallback yapar. Browser aynı-origin çalıştığı için geniş CORS açılmaz.

## 19. Health Checks

`GET /api/health` API status ve yalnızca `DBA_PULSE` connectivity kontrolü döndürür. Source SQL connectivity kontrol edilmez.

## 20. Lab Validation

Gerçek lab doğrulaması:

- V008, V009 ve V010 uygulandı.
- İkinci migration çalışmasında uygulanmış migration'lar atlandı.
- Collector yeni cycle'ı `Success` tamamladı.
- API health: `Healthy` / database `Healthy`.
- Overview: 1 server, 10 database, 10 online, 0 warning, 0 offline, last collection `Success`.
- Server list, database list, server detail, database detail, backup status ve capacity history endpoint'leri gerçek veri döndürdü.
- Web root ve Nginx `/api` proxy HTTP 200 döndürdü.
- Chromium browser screenshot'ında dashboard gerçek verilerle render oldu.

## 21. Known Limitations

- Lab'da Always On ve SQL Agent verisi yok; ilgili alanlar boş/0'dır.
- Backup source local datetime'lerinin UTC normalization'ı sonraki faza bırakıldı.
- Authentication, SSO, RBAC, operations ve incident özellikleri yoktur.
- Frontend bundle ECharts ve Material UI nedeniyle büyüktür; code splitting sonraki iyileştirmedir.

## 22. Faz 3'e kalan işler

Production reader login/permissions, AD/SSO, RBAC, operational actions, advanced performance/incident/AI özellikleri, retention/archive/partition/rollup ve gerçek MonitorSQL linked-server/Always On doğrulaması Faz 3 ve sonrasına bırakıldı.
