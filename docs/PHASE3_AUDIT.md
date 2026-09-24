# DBA Pulse — Faz 3 Audit Foundation

## 1. Amaç

Faz 3, API erişimlerini ve önemli business ekranı görüntülemelerini `DBA_PULSE.dbo.AuditLogs` içinde sorgulanabilir hale getirir. AD, Kerberos, SSO, LDAP, RBAC veya authentication/authorization bu fazda uygulanmadı.

## 2. Audit Architecture

```text
Browser -> React/Nginx -> ASP.NET Core API
                         |
                         +-- AuditMiddleware
                              |
                              +-- usp_AuditLog_Insert -> DBA_PULSE.AuditLogs
```

Audit yazımı merkezi middleware üzerinden yapılır. Controller/endpoint içinde tekrarlanan `InsertAudit` çağrıları yoktur.

## 3. Audit vs Application Logging

- Application log: startup, exception, SQL/network error, debug ve warning.
- Audit log: kim, hangi action, hangi resource, zaman, sonuç, status ve duration.
- `CollectionRuns`/`CollectionErrors`: Collector operational telemetry.

Bu üç veri türü birbirine karıştırılmadı.

## 4. Database Schema

V001–V010 korunarak aşağıdaki migration'lar eklendi:

- `V011__Create_Audit_Tables.sql`
- `V012__Create_Audit_Stored_Procedures.sql`
- `V013__Create_Audit_Indexes.sql`

`dbo.AuditLogs` içinde UTC zaman, user identity placeholder'ları, action/resource, HTTP metadata, result/status, duration, correlation, client IP, sınırlı user agent ve kontrollü JSON `AdditionalData` tutulur.

## 5. Stored Procedures

- `dbo.usp_AuditLog_Insert`: audit insert için tek yazma noktası.
- `dbo.usp_AuditLogs_List`: filtreli ve paginated read.

API AuditLogs tablosuna doğrudan INSERT/UPDATE/DELETE yapmaz.

## 6. Audit Action Convention

Action formatı `Resource.Action` şeklindedir:

- `Dashboard.View`
- `Server.List`
- `Server.View`
- `Database.List`
- `Database.View`
- `Database.CapacityHistory.View`
- `Collection.List`
- `Audit.List`

`GET /api/health` bilerek audit edilmez.

## 7. Resource Convention

- `Dashboard`, `Server`, `Database`, `Collection`, `Audit` resource type'ları kullanılır.
- Liste işlemlerinde `ResourceId` NULL'dır.
- Detail işlemlerinde server/database ID string olarak saklanır.

## 8. Correlation ID

Her API request için `X-Correlation-ID` okunur; geçerli UUID ise korunur, değilse yeni UUID üretilir. Aynı değer response header'a ve AuditLogs kaydına yazılır.

## 9. API Audit Middleware

`src/DBAPulse.Api/AuditMiddleware.cs` yalnızca tanımlı business GET endpoint'lerini audit eder. Stopwatch ile request süresi ölçülür. 2xx/3xx `Success`, 4xx/5xx `Failed` olarak kaydedilir. User authentication olmadığından şimdilik `anonymous` ve `Unauthenticated` kullanılır.

## 10. Sensitive Data Protection

Audit'e password, connection string, cookie, authorization/bearer header, token, secret, API key veya request body yazılmaz. Query string saklanmaz; capacity history için yalnızca izinli gün değeri `{"days":30}` şeklinde kontrollü AdditionalData olarak tutulur. User-Agent 512, path 512, AdditionalData 2000 karakterle sınırlandırılır.

## 11. Reverse Proxy / Client IP

API kör biçimde `X-Forwarded-For` güvenmez. `HttpContext.Connection.RemoteIpAddress` kullanılır. Lab'da container/network IP görünmesi kabul edilir; güvenilir proxy forwarding ayarı ileride deployment topology ile birlikte tanımlanabilir.

## 12. Audit API

`GET /api/audit` aşağıdaki filtreleri ve pagination'ı destekler:

`fromUtc`, `toUtc`, `userName`, `action`, `resourceType`, `result`, `correlationId`, `page`, `pageSize`.

Page size maksimum 100'dür ve sorgu `usp_AuditLogs_List` üzerinden çalışır.

## 13. Audit UI

Sidebar'a `Audit` eklendi. Material UI tablosunda time, user, action, resource, result, duration ve correlation ID gösterilir. User/action/resource/result/time filtreleri, pagination ve seçilen kayıt için detail paneli bulunur.

## 14. Timezone

Audit database zamanı `OccurredAtUtc datetime2(3)` olarak UTC saklanır. API ISO 8601 UTC/offset döndürür. React `VITE_DISPLAY_TIMEZONE` veya `Europe/Istanbul` ile gösterir. Database'e local display zamanı yazılmaz.

## 15. Performance

Audit insert kısa, synchronous async SqlClient çağrısıdır; queue/broker eklenmedi. Audit failure ana request'i 500'e dönüştürmez; application log'a ERROR yazılır. Zaman sorgusu, user/action ve correlation sorguları için sınırlı index seti oluşturuldu.

## 16. Failure Handling

Audit insert başarısız olursa middleware exception'ı loglar ve business response'u bozmadan devam eder. Audit failure sessizce yutulmaz.

## 17. Retention Readiness

`OccurredAtUtc` ve bigint identity primary key retention/partition için hazırdır. Bu fazda purge job, partition, archive database veya compression uygulanmadı; retention süresi hard-code edilmedi.

## 18. Lab Validation

- V011–V013 gerçek `DBA_PULSE` üzerinde uygulandı.
- İkinci migration çalıştırmasında migration'lar skip edildi.
- `AuditLogs` ve iki audit procedure'ü oluştu.
- Dashboard, server, database detail, capacity history ve collection request'leri gerçek audit kayıtları oluşturdu.
- `/api/health` response'a correlation ID ekledi ancak AuditLogs'a kayıt oluşturmadı.
- Action, resource, result, correlation ID filtreleri ve `pageSize=1` pagination gerçek veride çalıştı.
- Audit kayıtlarında `anonymous`, `Unauthenticated`, UTC zaman, duration ve correlation ID doğrulandı.
- Web proxy üzerinden `/api/audit` çalıştı; React production build başarılıdır.
- Collector normal çalışmaya devam etti ve son cycle `Success` oldu.

## 19. Known Limitations

- Authentication olmadığı için tüm kullanıcılar `anonymous` görünür.
- AD/SSO identity mapping, role resolution ve authorization sonraki fazlara bırakıldı.
- Reverse proxy forwarding güven modeli deployment altyapısı kesinleştiğinde sıkılaştırılmalıdır.
- SIEM, queue, archive ve retention otomasyonu yoktur.

## 20. Future AD/SSO Integration

İleride authenticated principal'dan `UserName` ve `UserRole` beslenebilir. Mevcut kolonlar `DOMAIN\\username` ve `username@domain` formatlarını destekler. Audit action/resource/correlation modelinin değişmesi gerekmez.
