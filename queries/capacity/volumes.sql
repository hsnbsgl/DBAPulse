/* Read-only: volume capacity visible to SQL Server. No filesystem or shell access. */
SELECT DISTINCT
    vs.volume_mount_point AS volume_id,
    CONVERT(bigint, vs.total_bytes) AS total_bytes,
    CONVERT(bigint, vs.available_bytes) AS available_bytes
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
WHERE vs.volume_mount_point IS NOT NULL
ORDER BY vs.volume_mount_point;
