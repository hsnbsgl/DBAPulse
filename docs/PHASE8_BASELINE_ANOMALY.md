# Faz 8 — Baseline & Anomaly Detection

## 1. Amaç

Faz 8, SQL Server telemetry'sini sabit threshold'ların yanında kendi tarihsel davranışıyla karşılaştırır. Sistem deterministik, açıklanabilir ve source SQL'e yazmadan çalışır.

## 2. Architecture

Collector raw telemetry'yi DBA_PULSE'a yazar. `BaselineEngine` tarihsel örneklerden baseline üretir; `AnomalyEngine` yeni örnekleri değerlendirir; sonuçlar `AnomalyFindings` ve gerekiyorsa mevcut `OperationalEvents` modeli üzerinden API ve Insights ekranına sunulur. API yalnızca DBA_PULSE bağlantısını kullanır.

## 3. Baseline Model

`dbo.Baselines` metric, server, database/entity, zaman bucket'ı, örnek sayısı, median, percentile'lar, MAD, mean/stddev, pencere, kapsam ve durum alanlarını saklar. Raw tablolar değişmez.

## 4. Baseline Window

Varsayılan rolling pencere 30 gündür (`DBAPULSE_BASELINE_WINDOW_DAYS`).

## 5. Minimum History

Baseline'ın `Usable` olması için varsayılan olarak en az 7 farklı lokal gün (`DBAPULSE_BASELINE_MIN_DAYS`) gerekir.

## 6. Minimum Samples

Varsayılan minimum 20 örnektir (`DBAPULSE_BASELINE_MIN_SAMPLES`). Gün veya örnek şartı sağlanmazsa sonuç `InsufficientData` olur; normal kabul edilmez.

## 7. Median

Sıralı değerlerde lineer percentile interpolasyonu kullanılır; çift sayıda örnekte iki merkez değer arasındaki doğru değer alınır.

## 8. Percentiles

P50, P75, P90, P95 ve P99 aynı .NET hesaplama fonksiyonuyla üretilir. SQL ve frontend ayrı percentile hesabı yapmaz.

## 9. MAD

`MAD = median(abs(value - median))` olarak hesaplanır. MAD, spike'lara mean/stddev'den daha dayanıklıdır.

## 10. Modified Z Score

MAD sıfır değilse `0.6745 * (observed - median) / MAD` kullanılır.

## 11. MAD Zero Fallback

MAD sıfır olduğunda bölme yapılmaz. P95/P99 ile median arasındaki aralık ve policy percentile'ı fallback olarak kullanılır; eşik aşılıyorsa anomaly üretilebilir.

## 12. Seasonality

Global baseline yanında Europe/Istanbul lokal `DayOfWeek + HourOfDay` bucket'ı oluşturulur. Yeterli örnek olmayan seasonal bucket üretilmez.

## 13. Timezone

Storage UTC kalır. Seasonal grouping `DBAPULSE_DISPLAY_TIMEZONE` ile yapılır; timezone offset hard-code edilmez.

## 14. Seasonal Fallback

Usable seasonal baseline yoksa usable global baseline kullanılır. Sonuç scope'u `Global` olarak korunur; UI bunu fallback bağlamı olarak gösterebilir.

## 15. Metric Types

Desteklenen örnekler: `BlockingDuration`, `BlockingFrequency`, `LongRunningDuration`, `WaitDelta`, `JobDuration`, `BackupDuration`, `DatabaseGrowth`.

## 16. Blocking Baseline

Blocking duration server/database scope'unda, frequency ise UTC saat bucket'ında observation sayısı olarak örneklenir. Full SQL text baseline'a kopyalanmaz.

## 17. Wait Baseline

Wait örneği cumulative counter değil, aynı SQL start boundary içindeki pozitif snapshot delta'sıdır. Wait exclusion listesi raw veriyi silmeden presentation/analysis katmanında uygulanır; Phase 8 örnek prosedürü excluded wait'leri anomaly sample'a dahil etmez.

## 18. Job Baseline

Başarılı job execution duration'ları job identity scope'unda kullanılır. Failed execution'lar normal duration baseline'ını kirletmez.

## 19. Backup Baseline

Backup duration `Server + Database + BackupType` scope'undadır; FULL, DIFF ve LOG birbirine karıştırılmaz.

## 20. Growth Baseline

Capacity snapshot'larından günlük/ardışık büyüme örneği çıkarılır. Negatif büyüme otomatik critical yapılmaz.

## 21. Anomaly Policy

`dbo.AnomalyPolicies` metric bazında warning/critical percentile, modified-Z ve minimum gözlenen değer policy'si tutar. Varsayılanlar kurumsal SLA değildir.

## 22. Severity

Deterministik başlangıç kuralı: P95 üstü Warning, P99 veya kritik modified-Z üstü Critical. Minimum gözlenen değer sağlanmıyorsa küçük değerler anomaly sayılmaz.

## 23. Absolute Significance

Relative oran tek başına yeterli değildir; policy'deki minimum observed value ile birlikte değerlendirilir.

## 24. Anomaly Findings

`dbo.AnomalyFindings` observed value, baseline referansları, MAD/Z, scope, explanation code, fingerprint ve lifecycle alanlarını raw telemetry'den ayrı saklar.

## 25. Correlation

Fingerprint metric, server, database/entity, baseline scope ve lokal zaman bucket'ından SHA-256 ile deterministik üretilir. Aynı active fingerprint upsert edilir; her cycle duplicate oluşturulmaz.

## 26. Resolution

Stale active finding, konfigüre edilmiş `DBAPULSE_ANOMALY_RESOLVE_AFTER_SECONDS` sonrasında resolve edilir. Normal örnek sayısı için daha sıkı hysteresis ileriki genişletmedir; mevcut lab pipeline'ı telemetry failure sırasında resolve yapmaz.

## 27. Failure Semantics

Collection başarısızsa anomaly evaluation çağrılmaz. Bu nedenle FAILED, normal veya zero observation değildir; active finding ve operational event korunur.

## 28. Stale Telemetry

Stale telemetry yeni anomaly üretmek veya mevcut anomaly'yi resolve etmek için kullanılmaz. Freshness policy'si collector başarısı ve son collection zamanı üzerinden izlenir.

## 29. OperationalEvents

Anomaly türleri mevcut mutable event modeline `PerformanceAnomaly`, `JobDurationAnomaly`, `BackupDurationAnomaly` ve `GrowthAnomaly` olarak bağlanır. SQL text/XML summary'ye yazılmaz.

## 30. API

`GET /api/anomalies/overview`, `/api/anomalies`, `/api/anomalies/{id}`, `/api/baselines`, `/api/baselines/{id}` endpoint'leri filtreleme ve pagination destekler. Baseline detail teknik istatistikleri döndürür.

## 31. Audit

Anomaly ve baseline endpoint'leri Faz 3 audit middleware tarafından `Anomaly.*` ve `Baseline.*` action'larıyla kaydedilir; hassas query text kaydedilmez.

## 32. UI

Insights ekranı active anomaly, severity, coverage, observed/normal değerler ve detail drill-down gösterir. Baseline yokluğu normal aktivite olarak etiketlenmez.

## 33. Charts

Mevcut ECharts system'i kullanılabilir; median/P95 referansları ve historical series gösterilebilir. `InsufficientData` durumunda sahte çizgi çizilmez.

## 34. Baseline Coverage

Coverage, `Usable` baseline sayısının baseline kayıtlarına oranı olarak hesaplanır. Denominator yoksa yüzde üretilmez.

## 35. Testing

Percentile/MAD/MAD-zero, minimum sample/day, seasonal fallback, spike, duplicate ve failure semantics için unit/integration testleri eklenmeye hazır saf hesaplama bileşenleri kullanılır. Production telemetry synthetic veriyle kirletilmez.

## 36. Lab Validation

V039–V046 migration'ları lab DBA_PULSE'a uygulandı. Collector gerçek raw telemetry ile başarılı cycle tamamladı; anomaly overview 200 döndü. Mevcut kısa lab geçmişi minimum 7 gün şartını karşılamadığı için baseline coverage `0 usable / 116 insufficient`, active anomaly `0` sonucudur. Bu doğru `InsufficientData` davranışıdır.

## 37. Known Limitations

Lab'da blocking, long-running request, SQL Agent job ve backup duration spike pozitif senaryoları bulunmadığından gerçek anomaly finding lifecycle'ı doğrulanmamıştır. Wait delta geçmişi ve frequency örnekleme eklidir ancak pozitif lab anomaly'si gözlenmemiştir. Normal örnek sayısına dayalı hysteresis ayrıca genişletilebilir.

## 38. Sonraki Faz

Daha uzun gerçek telemetry geçmişi, kontrollü lab workload'u, anomaly lifecycle hysteresis'i, kapsamlı baseline detail chart'ları ve domain-specific policy tuning sonraki çalışmalardır. AI/LLM, otomatik müdahale ve source SQL değişikliği bu fazın dışındadır.
