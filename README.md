# DBA Pulse

DBA Pulse, SQL Server ortamlarının sağlık, performans, koruma, kapasite ve operasyon sinyallerini tek ekranda izlemek için kullanılan Docker tabanlı bir uygulamadır.
Ayrıntılı belgeler:

- [AI kullanımı ve AI Summary](ai.md)
- [Kurulum ve işletim rehberi](setup.md)

## Mimari

- `dbapulse-collector`: Kaynak SQL Server’dan telemetri toplar, migration’ları çalıştırır ve `DBA_PULSE` veritabanına yazar.
- `dbapulse-api`: Dashboard, rapor, ayar, audit ve AI Summary API’lerini sunar.
- `dbapulse-web`: HTTPS üzerinden web arayüzünü sunan Nginx frontend containerıdır.
- `dbapulse-ollama` (opsiyonel): Local LLM çalıştırır; ana compose servislerine dahil değildir.

## Gereksinimler

- Red Hat Enterprise Linux 8/9 veya Windows 10/11
- Docker Engine/Desktop + Docker Compose v2
- SQL Server 2019+ veya uyumlu SQL Server erişimi
- Kurulum makinesinden SQL Server’a TCP erişimi
- Red Hat için `openssl` ve `curl`
- Local LLM için yaklaşık 4–8 GB boş RAM; GPU opsiyoneldir

## Tek komut kurulum

### Red Hat Linux

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Script SQL Server adresi/portu, SQL login/şifresi, DBA Pulse admin kullanıcı/şifresi, web HTTPS host portunu (HTTP yönlendirme portu sabit 8088) ve local LLM tercihini sorar. Varsayılan web portları HTTP 8088, HTTPS 8443 değerleridir. Local LLM seçilirse varsayılan `qwen2.5-coder:3b` modeli ayrı Ollama containerında indirilir. Ollama host portuna açılmaz; API containerı ile aynı Docker network’üne bağlanır ve AI ayarı otomatik yapılır.

Model registry TLS hatası alınırsa script içinde sorulduğunda `Y` seçerek `--insecure` pull işlemini onaylayabilirsiniz.

### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup.ps1
```

Windows scripti de aynı bilgileri sorar, HTTPS sertifikası üretir, migration’ları başlatır ve isteğe bağlı local LLM ayarını yapar. Registry TLS hatası için:

```powershell
.\scripts\setup.ps1 -AllowInsecureModelPull
```

Her iki script de kurulumu Docker çalışan mevcut makineye yapar; SQL Server uzak olabilir.
## Erişim

- Web: `https://localhost:<HTTPS_PORT>` (varsayılan `8443`)
- HTTP: http://localhost:8088 (sabit yönlendirme portu, HTTPS’e yönlenir)
- Health: `https://localhost:<HTTPS_PORT>/api/health`

Self-signed sertifika tarayıcıda ilk kullanımda uyarı gösterebilir.

## Migration ve veritabanı

Collector başlarken `database/migrations` altındaki `V*.sql` dosyalarını sürüm sırasıyla çalıştırır. Uygulanan sürümler `dbo.SchemaVersions` tablosunda tutulur ve tekrar çalıştırılmaz. Manuel migration komutu gerekmez.

Migration logları:

```powershell
docker compose -f docker-compose.phase2.yml logs dbapulse-collector
```

`DBA_PULSE` yönetim ve raporlama verilerini tutar. Kaynak SQL Server’da uygulama tablosu oluşturulmaz; collector tanımlı sorgularla okuma yapar.

## Secret ve ayar dosyaları

Setup scripti şunları oluşturur:

- `.env`: SQL bağlantıları ve uygulama ayarları
- `.secrets/dbapulse-admin-password`: Admin şifresi
- `certs/dbapulse.crt`, `certs/dbapulse.key`: HTTPS sertifikası

Bu yollar `.gitignore` içindedir; Git’e veya açık yedeklere gönderilmemelidir. `.env` SQL Server şifresi içerir.

## AI Summary

Server detayındaki AI Summary sekmesi OpenAI uyumlu `chat-completions` ve `responses` protokollerini destekler. On-prem servisler için Settings > AI Settings bölümünden provider, model, base URL, protokol ve API key tanımlanabilir.

Yanıtlar streaming olarak gösterilir; uygulama katmanında karakter limiti yoktur. Yanıt boyutu modelin kendi context/output limitleriyle sınırlıdır. Local Ollama varsayılan adresi `http://host.docker.internal:11434/v1`, API key değeri `ollama`dır.

## Yönetim komutları

```powershell
docker compose -f docker-compose.phase2.yml ps
docker compose -f docker-compose.phase2.yml logs -f dbapulse-api dbapulse-collector dbapulse-web
docker compose -f docker-compose.phase2.yml restart
docker compose -f docker-compose.phase2.yml up -d --build
docker exec dbapulse-ollama ollama ps
```

Son komut yalnızca local LLM kurulmuşsa kullanılmalıdır.

## Güvenlik

- Production’da self-signed yerine kurumsal CA veya geçerli reverse-proxy sertifikası kullanın.
- Mümkünse `sa` yerine sınırlı yetkili servis hesabı kullanın.
- `.env`, `.secrets` ve `certs` dosyalarını paylaşmayın.
- API endpointleri cookie authentication ile korunur; health ve login endpointleri public’tir.
- Linux kurulumunda Ollama host portuna açılmaz; yalnızca DBA Pulse Docker networkünde erişilebilirdir. Windows kurulumunda loopback portu kullanılır.
- `-AllowInsecureModelPull` seçeneğini yalnızca güvenilir ağlarda kullanın.

## Sorun giderme

```powershell
docker compose -f docker-compose.phase2.yml logs dbapulse-collector dbapulse-api
```

SQL bağlantısı için SQL Server TCP/IP, firewall, port, login yetkileri ve `.env` değerlerini kontrol edin. AI yavaşsa model CPU üzerinde çalışıyor olabilir; `docker exec dbapulse-ollama ollama ps` ile modeli kontrol edin.
