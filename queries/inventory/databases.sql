/* Read-only: databases visible to the login. */
SELECT
    d.name AS database_name,
    d.database_id,
    d.state_desc,
    d.recovery_model_desc,
    d.user_access_desc,
    d.compatibility_level,
    d.create_date,
    d.is_read_only,
    d.is_encrypted,
    CAST(CASE WHEN dm.mirroring_guid IS NULL THEN 0 ELSE 1 END AS bit) AS is_mirrored,
    dm.mirroring_role_desc AS mirroring_role
FROM sys.databases AS d
LEFT JOIN sys.database_mirroring AS dm ON dm.database_id = d.database_id
ORDER BY d.database_id;
