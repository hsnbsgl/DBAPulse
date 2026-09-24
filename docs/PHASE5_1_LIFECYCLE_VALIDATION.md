# Faz 5.1 — Operational Event Lifecycle Validation

## 1. Kapsam ve güvenlik

Test yalnızca local `reportserver-sql-1` lab SQL Server üzerinde çalıştırıldı. Production MonitorSQL, Linked Server veya kurumsal SQL Server'a bağlantı yapılmadı. Workload için geçici `DBAPULSE_LIFECYCLE_TEST` database'i ve `dbo.BlockingTest` tablosu kullanıldı. Faz 5 production Query Catalog dosyaları kalıcı olarak değiştirilmedi.

## 2. Workload

İki bağımsız SQLCMD session kullanıldı:

- Session A: SPID 82, transaction açık ve `BlockingTest.Id=1` satırını update lock ile tuttu.
- Session B: SPID 83, aynı satırı update etmeye çalıştı ve bekledi.

Source DMV doğrulaması:

```text
session_id=83
blocking_session_id=82
database=DBAPULSE_LIFECYCLE_TEST
wait_type=LCK_M_X
```

## 3. Blocking correlation

İlk lifecycle serisinde:

| Cycle | EventId | Status | ObservationCount | DurationMs | Fingerprint |
|---|---:|---|---:|---:|---|
| 1 | 1 | Active | 1 | 28,365 | `455d05316b8a2829d5941754a25cf0502d706f93e47719727f8061c4a47b2666` |
| 2 | 1 | Active | 2 | 1,331,673 | aynı |
| 3 | 1 | Active | 3 | 1,505,231 | aynı |

Collector restart sonrası aynı Active event tekrar bulundu; duplicate oluşmadı. Test sonunda event aynı ID ile ObservationCount 7 seviyesine kadar güncellendi.

Sonuç:

- Aynı EventId korundu: PASS
- Fingerprint sabit kaldı: PASS
- ObservationCount arttı: PASS
- DurationMs monotonik arttı: PASS
- Duplicate Active event oluşmadı: PASS

## 4. Blocking resolution

Session A `ROLLBACK` yaptı. Session B transaction'ı tamamlandı. Source DMV'de ActiveBlocking sayısı 0 oldu.

Normal blocking query başarılı şekilde 0 satır döndürdü. Resolve threshold sonrasında EventId 1:

- Status: `Resolved`
- EndedAtUtc: dolu
- LastSeenAtUtc: korundu
- DurationMs: pozitif

Sonuç: PASS.

## 5. Collection failure semantics

Production query dosyası değiştirilmeden `/tmp/phase5_1_queries` altında geçici mounted Query Catalog kullanıldı. Sadece `blocking.sql` invalid kolon ile failure verecek şekilde override edildi.

Collection:

- CollectionRun: `30016`
- Status: `PartialSuccess`
- Error: `performance/blocking.sql` invalid column

Bu cycle sırasında:

- Active Blocking event Active kaldı.
- `EndedAtUtc` NULL kaldı.
- Event resolve edilmedi.
- `CollectionErrors` kaydı oluştu.

Sonuç: PASS. `FAILED` ile `SUCCESS + 0 rows` ayrımı doğrulandı.

Failure injection kaldırıldıktan sonra normal query ile recovery cycle çalıştırıldı.

## 6. Long-running lifecycle

Blocking bekleyen Session B gerçek `sys.dm_exec_requests` kaydı olarak long-running telemetry içinde görüldü. Test override ile `DBAPULSE_LONG_RUNNING_SECONDS=5` kullanıldı.

Ana lifecycle serisinde LongRunning EventId 2 için:

- ObservationCount: 1 → 2 → 3 ve restart sonrası artmaya devam etti.
- Fingerprint sabit kaldı.
- Aynı EventId kullanıldı.
- Request sonlandıktan sonra event Resolved oldu.
- EndedAtUtc set edildi.

Sonuç: PASS. Workload ayrı CPU yoğun bir sorgu değil, gerçek lock bekleyen request'ti; bu nedenle long-running telemetry ile düşük etkili ve gerçek bir senaryo olarak doğrulandı.

## 7. Collector restart

Blocking devam ederken geçici Collector container restart edildi. Restart öncesi ve sonrası aynı OperationalEvent ID ve fingerprint kullanıldı. State memory'de kaybolmadı.

Sonuç: PASS.

## 8. Deadlock

Deadlock workload üretilmedi. Faz 5'teki `DeadlockHash`, unique index ve deduplication Stored Procedure mantığı korunuyor. Pozitif deadlock lifecycle senaryosu: NOT TESTED.

## 9. Wait Stats regression

- Raw `WaitStatsSnapshots` collection devam etti.
- `usp_WaitStats_Top` çalıştı.
- `WaitTypeExclusions` uygulanmaya devam etti.
- Excluded wait'ler raw tablodan silinmedi.

Sonuç: PASS.

## 10. Audit ve UI regression

Operations endpoint çağrıları AuditLogs'a yazıldı. Active UI smoke testinde Operations ekranı gerçek veriyi gösterdi:

- Active Events: 2
- Blocking: 1
- Long Running: 1
- Deadlock: 0

Resolved lifecycle sonrası event'ler Resolved olarak API/database tarafında doğrulandı.

Sonuç: PASS.

## 11. Bulunan bug ve düzeltme

Lifecycle state doğru update edildiği halde `usp_OperationalEvents_Upsert` COMMIT sonrasında `@@ROWCOUNT` okuduğu için Collector logunda `correlated: 0` görünüyordu.

Minimum düzeltme:

- `V028__Fix_Operational_Event_Upsert_Count.sql`
- Update ve insert row count değerleri COMMIT öncesi ayrı alınıp toplam döndürülüyor.

V028 gerçek lab database'e uygulandı ve normal Collector cycle başarıyla çalıştı.

## 12. Cleanup

- Açık transaction bırakılmadı.
- Blocking session'ları kapatıldı.
- Geçici Collector container kaldırıldı.
- `DBAPULSE_LIFECYCLE_TEST` database'i kaldırıldı.
- Test database master kaydı silindi.
- Test raw telemetry ve OperationalEvents silindi.
- Failure injection error kaydı temizlendi.
- Normal `dbapulse-collector` compose servisi tekrar başlatıldı.

## 13. Final status

**PASS**

Blocking, long-running, failure semantics, restart persistence, resolution, wait filtering, audit ve UI doğrulamaları tamamlandı. Deadlock pozitif workload'u risk ve gereksiz karmaşıklık nedeniyle çalıştırılmadı; deadlock deduplication implementation seviyesinde mevcut ve korunuyor.
