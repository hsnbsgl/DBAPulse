# HammerDB isolated benchmark

This directory is intentionally separate from the DBAPulse application Compose file.

Defaults:
- SQL Server container: `sqlserver2025`
- Workload: HammerDB TPROC-C (TPC-C derived)
- Schema database: `DBAPULSE_HAMMERDB_TPCC`
- 1 warehouse
- 5 virtual users
- 10 minute timed run

The benchmark creates and writes only to `DBAPULSE_HAMMERDB_TPCC`. Results are written to `results/` when produced by HammerDB.

Run from the repository root in PowerShell:

```powershell
$sqlPasswordLine = docker inspect sqlserver2025 --format '{{range .Config.Env}}{{println .}}{{end}}' | Where-Object { $_ -like 'MSSQL_SA_PASSWORD=*' -or $_ -like 'SA_PASSWORD=*' } | Select-Object -First 1
$sqlPassword = $sqlPasswordLine.Substring($sqlPasswordLine.IndexOf('=') + 1)
$env:MSSQL_PASSWORD = $sqlPassword
docker compose -f benchmarks/hammerdb/compose.yaml run --rm hammerdb
```

The HammerDB image uses the SQL Server container network namespace, so the target is `127.0.0.1:1433`. Do not run this against production without changing the target and reviewing the workload settings.