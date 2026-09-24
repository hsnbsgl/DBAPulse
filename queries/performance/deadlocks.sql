;WITH RingBuffer AS
(
    SELECT CAST(t.target_data AS xml) AS target_data
    FROM sys.dm_xe_session_targets AS t
    INNER JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
    WHERE s.name = N'system_health' AND t.target_name = N'ring_buffer'
), Events AS
(
    SELECT n.query('.') AS event_xml
    FROM RingBuffer
    CROSS APPLY target_data.nodes('/RingBufferTarget/event[@name="xml_deadlock_report"]') AS x(n)
)
SELECT
    event_xml.value('(/event/@timestamp)[1]', 'datetime2(3)') AS occurred_at,
    event_xml.value('(/event/data[@name="xml_report"]/value/deadlock/victim-list/victimProcess/@id)[1]', 'nvarchar(256)') AS victim_process_id,
    event_xml.value('count(/event/data[@name="xml_report"]/value/deadlock/process-list/process)', 'int') AS process_count,
    CONVERT(varchar(64), HASHBYTES('SHA2_256', CONVERT(nvarchar(max), event_xml)), 2) AS deadlock_hash,
    CONVERT(xml, event_xml.value('(/event/data[@name="xml_report"]/value)[1]', 'nvarchar(max)')) AS deadlock_xml
FROM Events;
