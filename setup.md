# Kurulum Rehberi

DBA Pulse Docker Compose ile kurulur. Kurulum scripti SQL Server bağlantısını, admin secret’ını, HTTPS sertifikasını, migration’ları ve isteğe bağlı local LLM’i hazırlar.

## Red Hat Linux

Gereksinimler:

```bash
sudo dnf install -y openssl curl
```

Docker Engine ve Docker Compose v2 kurulu, Docker daemon çalışır ve mevcut kullanıcı Docker kullanabilir olmalıdır.

Kurulum:

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Script şu bilgileri sorar:

- SQL Server hostname/adresi
- SQL Server portu
- SQL login kullanıcı adı ve şifresi
- DBA Pulse admin kullanıcı adı ve şifresi
- Local LLM kurulumu
- Local LLM modeli
- HTTPS host portu

HTTP portu kullanıcıdan sorulmaz ve sabit `8088` olarak kalır. HTTPS portunun varsayılanı `8443`’tür.

Local LLM kurulacaksa model registry TLS hatasında script tekrar denemek için onay ister. Yalnızca güvenilir ağlarda `--insecure` pull onaylayın.

## Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup.ps1
```

Windows scripti aynı kurulum adımlarını uygular. HTTPS portunu sorar; HTTP portu `8088` olarak sabittir.

## Oluşturulan dosyalar

| Dosya | İçerik |
|---|---|
| `.env` | SQL, AI, port ve uygulama ayarları |
| `.secrets/dbapulse-admin-password` | Admin şifresi |
| `certs/dbapulse.crt` | HTTPS sertifikası |
| `certs/dbapulse.key` | HTTPS private key |

Bu dosyalar secret içerir ve Git’e gönderilmemelidir. `.gitignore` içinde yer alırlar.

## Docker servisleri

```bash
docker compose -f docker-compose.phase2.yml ps
docker compose -f docker-compose.phase2.yml logs -f dbapulse-api dbapulse-collector dbapulse-web
```

Ana servisler:

- `dbapulse-collector`: migration ve telemetry toplama
- `dbapulse-api`: API, authentication, settings ve AI Summary
- `dbapulse-web`: HTTPS frontend
- `dbapulse-ollama`: yalnızca local LLM seçilirse oluşturulur

## Portlar

| Host portu | Container portu | Kullanım |
|---:|---:|---|
| `8088` | `80` | HTTP, HTTPS’e yönlendirme |
| Kullanıcı seçimi, varsayılan `8443` | `443` | HTTPS web uygulaması |

Port değişkeni:

```env
DBAPULSE_WEB_HTTPS_PORT=9443
```

Değişiklikten sonra:

```bash
docker compose -f docker-compose.phase2.yml up -d
```

## Migration

Collector başlarken `database/migrations/V*.sql` dosyalarını sürüm sırasıyla çalıştırır. Uygulanan migration’lar `DBA_PULSE.dbo.SchemaVersions` tablosunda tutulur. Aynı migration tekrar çalıştırılmaz.

Migration logları:

```bash
docker compose -f docker-compose.phase2.yml logs dbapulse-collector
```

## İlk kontrol

```bash
curl -k https://localhost:8443/api/health
```

Özel HTTPS portu kullanıldıysa `8443` yerine seçilen portu yazın. Tarayıcıda self-signed sertifika uyarısı görülmesi beklenir.

## Sorun giderme

Container durumu:

```bash
docker compose -f docker-compose.phase2.yml ps
docker compose -f docker-compose.phase2.yml logs --tail=100 dbapulse-api dbapulse-collector
```

SQL bağlantısı için SQL Server TCP/IP, firewall, port ve login yetkilerini kontrol edin. Red Hat SELinux etkinse compose volume’larında kullanılan `:Z` etiketleri dosya erişimi için gereklidir.

Local LLM bağlantısı için:

```bash
docker exec dbapulse-ollama ollama ps
docker network inspect dbapulse_default
```