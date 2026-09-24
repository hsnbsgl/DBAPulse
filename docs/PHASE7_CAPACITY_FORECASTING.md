# Faz 7 — Capacity & Growth Forecasting

## Amaç ve mimari

Faz 7, mevcut `CapacitySnapshots` geçmişini DBA_PULSE üzerinden analiz eder. Source SQL yalnızca read-only capacity query'leri çalıştırır; API source SQL'e bağlanmaz. Collector, mevcut simple loop içinde capacity domainini `DBAPULSE_CAPACITY_INTERVAL_MINUTES` ile planlar; varsayılan 60 dakikadır.

## Existing capacity model

`CapacitySnapshots` mevcut data/log file allocation telemetry'sini tutar. Database total, data ve log allocation toplamıdır; used space değildir. V035 ile `VolumeCapacitySnapshots` eklendi. Volume query `sys.master_files` ve `sys.dm_os_volume_stats` kullanır; shell, WMI, PowerShell veya `xp_cmdshell` kullanılmaz.

## Collection ve source sınırı

Yeni Query Catalog: `queries/capacity/volumes.sql`. Database size query mevcut `database-size.sql` dosyasında kalmıştır. V035–V038 migration'ları yalnızca DBA_PULSE'a uygulanır. Source SQL'e tablo, view, procedure, job veya configuration kurulmaz.

## Database growth ve günlük seri

Read model aynı UTC gün içindeki snapshot'ların sonuncusunu daily end-of-day noktası olarak seçer. Data ve log allocation ayrı tutulur, total `data + log` olarak gösterilir. Collector raw snapshot'ları overwrite etmez. 7/30/90 günlük büyüme için hedef tarihten önceki en yakın daily sample kullanılır; sample yoksa sonuç `NULL` kalır, sıfır growth'a çevrilmez.

## Minimum history ve linear regression

`CapacityForecastCalculator` .NET içinde deterministic ordinary least squares regression uygular: `size = intercept + slope * day`. Varsayılan minimum 7 distinct daily sample ve 7 history day şartı vardır. Slope MB/day, 30 ve 90 günlük forecast, R² ve sample/history metrikleri üretilir. `R² < 0.5` `LowFit`; negatif slope `StableOrShrinking`; epsilon altı slope `Stable`; yeterli veri yoksa `InsufficientData` olur. LowFit yönetici ekranında kesin tahmin olarak sunulmaz.

Forecast hesabı frontend'de yapılmaz. API yalnızca DBA_PULSE stored procedure'lerinden history okur ve merkezi calculator ile DTO üretir. Gelecekte batch read model ile N+1 history çağrısı optimize edilebilir; mevcut lab hacminde bu yaklaşım bilinçli olarak basit tutulmuştur.

## Volume capacity ve exhaustion

Volume snapshot'ları total/available bytes ve free percentage gösterir. Volume growth/exhaustion için yeterli tarihçe olmadığında `InsufficientData` ve `Not forecastable` döner. Tek database rate'i ile volume exhaustion uydurulmaz; ileride aynı volume üzerindeki tüm file growth'leri aggregate edilmelidir. Current free space yüzde 10 altında Critical, yüzde 15 altında Warning olarak başlangıç sunum kuralıdır; bu eşikler kurumsal SLA değildir.

## Status ve freshness

`Healthy`, `Warning`, `Critical`, `InsufficientData`, `Unknown` ayrımı korunur. Low free space, forecast history'sinden bağımsız bir risk sinyalidir. Capacity telemetry üç saatten eskiyse `Stale` olur. Collection failure `0 capacity` değildir; stale/unknown veriden yeni risk üretilmez ve mevcut CapacityRisk event'i yalnızca veri yok diye resolve edilmez.

## Operational Events

CapacityRisk için model ve API hazırlığı korunmuştur. Bu lab'da volume telemetry `0 rows` döndüğü ve database history yalnızca aynı gün kısa aralıkta bulunduğu için deterministic exhaustion event üretilmemiştir. Fake historical snapshot eklenmemiştir. Positive CapacityRisk lifecycle testi `NOT TESTED` durumundadır.

## Stored procedures ve API

V036 persistence procedure: `dbo.usp_VolumeCapacitySnapshots_Insert`.

Read procedures:

- `dbo.usp_Capacity_Overview`
- `dbo.usp_Capacity_Databases`
- `dbo.usp_Capacity_DatabaseHistory`
- `dbo.usp_Capacity_Volumes`

API:

- `GET /api/capacity/overview`
- `GET /api/capacity/databases`
- `GET /api/capacity/databases/{id}`
- `GET /api/capacity/databases/{id}/history?days=30`
- `GET /api/capacity/volumes`
- `GET /api/capacity/volumes/{volumeId}`

Endpointler audit middleware ile Capacity action convention'ına dahil edilmiştir. Physical path audit'e yazılmaz.

## UI ve units

Capacity ekranı database growth, volume capacity ve history chart bölümlerinden oluşur. Actual history ile forecast ayrımı korunur; forecast yoksa `Insufficient data` gösterilir. Database allocation mevcut UI convention ile MB, volume byte değerleri MiB/GiB/TiB olarak gösterilir. Database içindeki zamanlar UTC, UI Europe/Istanbul'dur.

## Lab validation

V035–V038 gerçek lab DBA_PULSE üzerinde uygulandı. V038'de ilk migration denemesinde bir SQL alias hatası bulundu; migration mark edilmeden düzeltildi ve tekrar başarıyla uygulandı. İkinci çalıştırmada V038 skip edildi. Son Collector cycle `Success`: 1 server, 10 database, 20 capacity rows, 0 volume rows, 0 collection error. API health `Healthy`; capacity overview ve database/history endpointleri gerçek verilerle yanıt verdi. Lab sonucu database forecastlerinde `InsufficientData`, volume tarafında no telemetry/`Not forecastable`'dır; bu beklenen ve doğru sonuçtur.

## Known limitations ve sonraki faz

Lab volume DMV sonucu boş olduğundan volume growth/exhaustion pozitif senaryosu test edilmedi. Synthetic regression, shrink, LowFit ve volume aggregation test dataset'i için ayrı unit test projesi oluşturulmadı; calculator deterministik ve production history'ye fake veri eklenmedi. Gelecekte batch history read model, volume growth aggregation, max-size/autogrowth telemetry, configurable policy table ve CapacityRisk lifecycle testleri eklenebilir. Retention, purge, partition, archive, ML/AI ve automatic expansion bu fazda yoktur.
