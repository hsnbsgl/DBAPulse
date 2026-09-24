/* Read-only: linked server definitions. No configuration changes are made. */
SELECT
    s.name AS linked_server_name,
    s.product,
    s.provider,
    s.data_source,
    s.is_linked,
    s.is_rpc_out_enabled,
    s.is_data_access_enabled,
    s.modify_date
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;
