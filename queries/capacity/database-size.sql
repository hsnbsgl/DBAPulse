/* Read-only: allocated and used space by database and data/log file. */
SELECT
    d.name AS database_name,
    d.state_desc,
    mf.type_desc AS file_type,
    SUM(mf.size) * 8.0 / 1024 AS allocated_size_mb,
    COUNT(*) AS file_count
FROM sys.databases AS d
LEFT JOIN sys.master_files AS mf ON mf.database_id = d.database_id
GROUP BY d.name, d.state_desc, mf.type_desc
ORDER BY d.name, mf.type_desc;
