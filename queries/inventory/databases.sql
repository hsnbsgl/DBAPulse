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
    d.is_encrypted
FROM sys.databases AS d
ORDER BY d.database_id;
