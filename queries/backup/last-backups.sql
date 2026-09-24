/* Read-only: most recent backup recorded for each database. */
WITH latest_backup AS
(
    SELECT
        bs.database_name,
        bs.type,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.backup_size,
        bs.compressed_backup_size,
        bs.is_copy_only,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duration_seconds,
        ROW_NUMBER() OVER
        (
            PARTITION BY bs.database_name, bs.type
            ORDER BY bs.backup_finish_date DESC
        ) AS row_number
    FROM msdb.dbo.backupset AS bs
)
SELECT
    database_name,
    CASE type WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFFERENTIAL' WHEN 'L' THEN 'LOG' ELSE type END AS backup_type,
    backup_start_date,
    backup_finish_date,
    CAST(backup_size / 1048576.0 AS decimal(19, 2)) AS backup_size_mb,
    CAST(compressed_backup_size / 1048576.0 AS decimal(19, 2)) AS compressed_backup_size_mb,
    is_copy_only
FROM latest_backup
WHERE row_number = 1
ORDER BY database_name, backup_type;
