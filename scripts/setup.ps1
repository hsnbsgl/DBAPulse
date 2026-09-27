[CmdletBinding()]
param(
    [switch]$AllowInsecureModelPull
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Gerekli komut bulunamadı: $Name"
    }
}

function Read-Default([string]$Prompt, [string]$Default) {
    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Read-Required([string]$Prompt) {
    do { $value = Read-Host $Prompt } while ([string]::IsNullOrWhiteSpace($value))
    return $value.Trim()
}

function Read-Password([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Quote-ConnectionValue([string]$Value) {
    return '"' + $Value.Replace('"', '""') + '"'
}

function Quote-DotEnv([string]$Value) {
    if ($null -eq $Value) { return "''" }
    if ($Value.Contains("`r") -or $Value.Contains("`n")) { throw 'Şifrelerde satır sonu kullanılamaz.' }
    return "'" + $Value.Replace("'", "\'") + "'"
}

function Write-DotEnv([string]$Path, [hashtable]$Values) {
    $lines = foreach ($key in $Values.Keys) { "$key=$(Quote-DotEnv ([string]$Values[$key]))" }
    [IO.File]::WriteAllText((Join-Path (Get-Location) $Path), ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
}

function Ensure-Certificate {
    $certDir = Join-Path (Get-Location) 'certs'
    $certPath = Join-Path $certDir 'dbapulse.crt'
    $keyPath = Join-Path $certDir 'dbapulse.key'
    if ((Test-Path $certPath) -and (Test-Path $keyPath)) { return }
    New-Item -ItemType Directory -Force $certDir | Out-Null
    Write-Host 'Self-signed HTTPS sertifikası oluşturuluyor...' -ForegroundColor Cyan
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        & openssl req -x509 -nodes -newkey rsa:2048 -keyout $keyPath -out $certPath -days 825 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
    } else {
        Write-Host 'Host OpenSSL bulunamadı; Docker içindeki OpenSSL kullanılıyor...' -ForegroundColor DarkGray
        docker run --rm --mount "type=bind,source=$certDir,target=/out" alpine/openssl req -x509 -nodes -newkey rsa:2048 -keyout /out/dbapulse.key -out /out/dbapulse.crt -days 825 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
    }
    if ($LASTEXITCODE -ne 0) { throw 'HTTPS sertifikası oluşturulamadı.' }
}

function Ensure-Ollama([string]$Model) {
    $name = 'dbapulse-ollama'
    $existing = docker ps -a --filter "name=^/$name$" --format '{{.Names}}'
    if ($existing -eq $name) {
        docker start $name 2>$null | Out-Null
    } else {
        docker run -d --name $name --restart unless-stopped -p 127.0.0.1:11434:11434 -v dbapulse_ollama:/root/.ollama ollama/ollama:latest | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw 'Ollama containerı başlatılamadı.' }
    Write-Host "Local LLM indiriliyor: $Model" -ForegroundColor Cyan
    docker exec $name ollama pull $Model
    if ($LASTEXITCODE -ne 0 -and $AllowInsecureModelPull) {
        Write-Warning 'Normal model indirme başarısız oldu; --insecure ile tekrar deneniyor.'
        docker exec $name ollama pull --insecure $Model
    }
    if ($LASTEXITCODE -ne 0) { throw "Model indirilemedi: $Model. TLS sorunu için -AllowInsecureModelPull ile tekrar çalıştırabilirsiniz." }
}

Require-Command 'docker'
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose kullanılabilir değil.' }

Write-Host 'DBA Pulse tek komut kurulum sihirbazı' -ForegroundColor Green
Write-Host 'Kurulum Docker çalışan bu makineye yapılır. SQL Server uzak olabilir.' -ForegroundColor DarkGray

$sqlServer = Read-Default 'SQL Server adresi veya hostname' 'host.docker.internal'
$sqlPort = Read-Default 'SQL Server portu' '1433'
$sqlLogin = Read-Default 'SQL Server login kullanıcı adı' 'sa'
$sqlPassword = Read-Password 'SQL Server login şifresi'
if ([string]::IsNullOrWhiteSpace($sqlPassword)) { throw 'SQL Server şifresi boş olamaz.' }

$adminUser = Read-Default 'DBA Pulse admin kullanıcı adı' 'admin'
$adminPassword = Read-Password 'DBA Pulse admin şifresi'
if ($adminPassword.Length -lt 8) { throw 'Admin şifresi en az 8 karakter olmalıdır.' }

$installLlmAnswer = Read-Default 'Local LLM kurulsun mu? (Y/N)' 'N'
$installLlm = $installLlmAnswer -match '^(Y|E|YES|EVET)$'
$webHttpsPort = Read-Default 'Web HTTPS host portu' '8443'
[int]$webHttpsPortNumber = 0
if (-not [int]::TryParse($webHttpsPort, [ref]$webHttpsPortNumber) -or $webHttpsPortNumber -lt 1 -or $webHttpsPortNumber -gt 65535) { throw 'HTTPS portu 1-65535 arasında olmalıdır.' }
$llmModel = 'qwen2.5-coder:3b'
if ($installLlm) { $llmModel = Read-Default 'Local LLM modeli' $llmModel }

$serverPart = $sqlServer
if (-not [string]::IsNullOrWhiteSpace($sqlPort)) { $serverPart = "$sqlServer,$sqlPort" }
$quotedPassword = Quote-ConnectionValue $sqlPassword
$sourceConnection = "Server=$serverPart;Database=master;User Id=$sqlLogin;Password=$quotedPassword;Encrypt=False;TrustServerCertificate=True;"
$managementConnection = "Server=$serverPart;Database=DBA_PULSE;User Id=$sqlLogin;Password=$quotedPassword;Encrypt=False;TrustServerCertificate=True;"

New-Item -ItemType Directory -Force '.secrets' | Out-Null
[IO.File]::WriteAllText((Join-Path (Get-Location) '.secrets\dbapulse-admin-password'), $adminPassword, [Text.UTF8Encoding]::new($false))
Ensure-Certificate

$aiProvider = if ($installLlm) { 'onprem' } else { 'gemini' }
$aiBaseUrl = if ($installLlm) { 'http://host.docker.internal:11434/v1' } else { 'https://generativelanguage.googleapis.com/v1beta' }
$aiProtocol = if ($installLlm) { 'chat-completions' } else { 'gemini' }
$aiApiKey = if ($installLlm) { 'ollama' } else { '' }

$values = [ordered]@{
    DBAPULSE_SOURCE_CONNECTION = $sourceConnection
    DBAPULSE_MANAGEMENT_CONNECTION = $managementConnection
    DBAPULSE_API_CONNECTION = $managementConnection
    DBAPULSE_ADMIN_USERNAME = $adminUser
    DBAPULSE_DISPLAY_TIMEZONE = 'Europe/Istanbul'
    DBAPULSE_AI_PROVIDER = $aiProvider
    DBAPULSE_AI_MODEL = $(if ($installLlm) { $llmModel } else { 'gemini-flash-latest' })
    DBAPULSE_AI_BASE_URL = $aiBaseUrl
    DBAPULSE_AI_PROTOCOL = $aiProtocol
    DBAPULSE_AI_API_KEY = $aiApiKey
    DBAPULSE_COLLECTION_INTERVAL_MINUTES = '5'
    DBAPULSE_WEB_HTTPS_PORT = $webHttpsPort
}
Write-DotEnv '.env' $values

if ($installLlm) { Ensure-Ollama $llmModel }

Write-Host 'DBA Pulse image build ve container başlatma işlemi başlıyor...' -ForegroundColor Cyan
docker compose -f docker-compose.phase2.yml up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose başlatılamadı.' }

Write-Host 'Migration ve API health kontrolü bekleniyor...' -ForegroundColor Cyan
$healthy = $false
for ($i = 1; $i -le 45; $i++) {
    Start-Sleep -Seconds 2
    try {
        $health = Invoke-WebRequest -SkipCertificateCheck -UseBasicParsing -Uri "https://127.0.0.1:$webHttpsPort/api/health" -TimeoutSec 5
        if ($health.StatusCode -eq 200) { $healthy = $true; break }
    } catch { }
}
if (-not $healthy) {
    Write-Warning 'API health kontrolü zaman aşımına uğradı. Logları kontrol edin: docker compose -f docker-compose.phase2.yml logs dbapulse-api dbapulse-collector'
    exit 1
}

Write-Host ''
Write-Host 'Kurulum tamamlandı.' -ForegroundColor Green
Write-Host "Web:      https://localhost:$webHttpsPort" -ForegroundColor White
Write-Host "Admin:    $adminUser" -ForegroundColor White
Write-Host "AI:       $aiProvider$(if ($installLlm) { " / $llmModel" } else { '' })" -ForegroundColor White
Write-Host 'SQL ve admin secret bilgileri .env ve .secrets altında tutulur; bu dosyaları Git''e göndermeyin.' -ForegroundColor Yellow
