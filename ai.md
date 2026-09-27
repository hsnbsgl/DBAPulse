# AI Kullanımı

DBA Pulse, server detayındaki **AI Summary** sekmesinde SQL Server durumunu kısa bir operasyon özeti olarak gösterir.

## Desteklenen provider ayarları

Ayarlar web arayüzünde `Settings > AI Settings` bölümünden yapılır.

| Alan | Açıklama |
|---|---|
| Provider | `none`, `onprem` veya OpenAI uyumlu provider adı |
| Model | Kullanılacak model adı; örnek `qwen2.5-coder:3b` |
| Base URL | Provider adresi; Ollama için `http://dbapulse-ollama:11434/v1` |
| Protocol | `chat-completions` veya `responses` |
| API Key | Provider erişim anahtarı; Ollama için `ollama` kullanılabilir |

API key uygulama ayarlarında maskeli gösterilir. Gerçek anahtarları Git’e, README’ye veya loglara yazmayın.

## Google Gemini

Gemini native API için Settings ekranında şu değerleri kullanın:

| Alan | Değer |
|---|---|
| Provider | `gemini` |
| Model | `gemini-flash-latest` veya hesabınızda aktif olan model |
| Base URL | `https://generativelanguage.googleapis.com/v1beta` |
| Protocol | `gemini` |
| API Key | Google AI Studio anahtarı |

Uygulama Gemini için `generateContent` ve streaming sırasında `streamGenerateContent?alt=sse` endpointlerini kullanır. API key `Authorization` yerine `X-goog-api-key` header’ında gönderilir. Paylaşılan anahtarları döndürün ve yeni anahtar kullanın.
## Local LLM / Ollama

Red Hat kurulumunda `scripts/setup.sh` local LLM seçilirse:

1. `dbapulse-ollama` containerı oluşturulur veya başlatılır.
2. Seçilen model indirilir.
3. Ollama, API containerı ile aynı Docker networküne bağlanır.
4. AI ayarları otomatik olarak on-prem Chat Completions protokolüne ayarlanır.

Varsayılan model:

```text
qwen2.5-coder:3b
```

GPU tanımlı değilse model CPU üzerinde çalışır ve yanıt süresi uzayabilir. Daha küçük modeller daha hızlı, büyük modeller genellikle daha kaliteli özet üretir.

Model durumu:

```bash
docker exec dbapulse-ollama ollama ps
docker exec dbapulse-ollama ollama list
```

## Streaming

AI Summary yanıtı Server-Sent Events (SSE) ile parça parça gönderilir. Kullanıcı model yanıtını tamamlanmasını beklemeden görür.

Streaming endpointi:

```text
POST /api/servers/{serverId}/ai-summary/stream
```

Endpoint authentication gerektirir. Nginx buffering kapatılmıştır ve uzun AI yanıtları için timeout ayarları artırılmıştır.

## Yanıt sınırı

AI Summary backend ve frontend tarafında maksimum **1000 karakter** ile sınırlıdır.

- Prompt modelden 1000 karakteri aşmamasını ister.
- Chat Completions için token sınırı uygulanır.
- Streaming 1000 karaktere ulaştığında durur.
- Frontend de ek güvenlik olarak metni 1000 karakterde keser.

Bu sınır sonsuz veya gereksiz uzun model yanıtlarını önlemek içindir.

## Prompt davranışı

Modelden Türkçe ve şu bölümlerle kısa bir özet istenir:

- Genel Durum
- Riskler
- Önerilen Aksiyonlar

Prompt server bilgisi, database listesi ve health sinyallerini içerir. Modelden veri uydurmaması ve eksik veriyi açıkça belirtmesi istenir.

## AI bağlantı testi

`Settings > AI Settings > Test` bağlantı ve kimlik doğrulama kontrolü yapar. Test başarılı olsa bile gerçek Summary üretim süresi modelin CPU/GPU durumuna ve prompt boyutuna bağlıdır.

Yararlı log komutu:

```bash
docker compose -f docker-compose.phase2.yml logs -f dbapulse-api
```

## OpenAI veya başka on-prem API

Local LLM kullanılmıyorsa provider `none` bırakılabilir. OpenAI uyumlu bir API kullanılacaksa provider, model, base URL, protocol ve API key Settings üzerinden tanımlanır. API key’i `.env` içinde saklamak yerine mümkünse secret yönetimi kullanın.