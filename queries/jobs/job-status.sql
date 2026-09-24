/* Read-only: SQL Agent job health. Source-local dates are retained as source values. */
WITH latest_run AS
(
    SELECT
        h.job_id,
        h.run_status,
        h.run_date,
        h.run_time,
        h.message,
        (h.run_duration / 10000) * 3600 + ((h.run_duration / 100) % 100) * 60 + (h.run_duration % 100) AS run_duration_seconds,
        ROW_NUMBER() OVER (PARTITION BY h.job_id ORDER BY h.instance_id DESC) AS row_number
    FROM msdb.dbo.sysjobhistory AS h
    WHERE h.step_id = 0
), history AS
(
 SELECT h.job_id, h.run_status, h.run_date, h.run_time, h.run_duration,
        ROW_NUMBER() OVER (PARTITION BY h.job_id ORDER BY h.instance_id DESC) AS execution_number
 FROM msdb.dbo.sysjobhistory AS h WHERE h.step_id=0
), activity AS
(
 SELECT ja.job_id, ja.start_execution_date, ja.stop_execution_date, ja.next_scheduled_run_date,
        ROW_NUMBER() OVER (PARTITION BY ja.job_id ORDER BY ja.session_id DESC) AS row_number
 FROM msdb.dbo.sysjobactivity AS ja
 INNER JOIN (SELECT MAX(session_id) AS session_id FROM msdb.dbo.syssessions) AS ss ON ss.session_id=ja.session_id
)
SELECT
    CONVERT(nvarchar(36), j.job_id) AS job_id,
    j.name AS job_name,
    j.enabled,
    CASE lr.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
        ELSE 'NeverRun'
    END AS last_run_status,
    lr.run_date,
    lr.run_time,
    lr.run_duration_seconds AS last_run_duration_seconds,
    lr.message AS last_run_message,
    CAST(CASE WHEN a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL THEN 1 ELSE 0 END AS bit) AS is_running,
    a.start_execution_date AS current_start_at_source,
    CASE WHEN a.start_execution_date IS NULL OR a.stop_execution_date IS NOT NULL THEN NULL ELSE DATEDIFF(SECOND,a.start_execution_date,GETDATE()) END AS current_duration_seconds,
    a.next_scheduled_run_date AS next_run_at_source,
    (SELECT COUNT(*) FROM history h24 WHERE h24.job_id=j.job_id AND h24.run_status=0 AND DATEADD(SECOND,(h24.run_duration/10000)*3600+((h24.run_duration/100)%100)*60+(h24.run_duration%100), CONVERT(datetime,CONVERT(char(8),h24.run_date),112)) >= DATEADD(DAY,-1,GETDATE())) AS failure_count_24h,
    (SELECT COUNT(*) FROM history h7 WHERE h7.job_id=j.job_id AND h7.run_status=0 AND DATEADD(SECOND,(h7.run_duration/10000)*3600+((h7.run_duration/100)%100)*60+(h7.run_duration%100), CONVERT(datetime,CONVERT(char(8),h7.run_date),112)) >= DATEADD(DAY,-7,GETDATE())) AS failure_count_7d,
    CAST(CASE WHEN (SELECT COUNT(*) FROM history hr WHERE hr.job_id=j.job_id AND hr.execution_number<=3 AND hr.run_status=0)>=2 THEN 1 ELSE 0 END AS bit) AS repeated_failure,
    (SELECT AVG((hs.run_duration/10000)*3600+((hs.run_duration/100)%100)*60+(hs.run_duration%100)) FROM history hs WHERE hs.job_id=j.job_id AND hs.run_status=1 AND hs.execution_number<=10) AS average_duration_seconds,
    (SELECT MAX((hm.run_duration/10000)*3600+((hm.run_duration/100)%100)*60+(hm.run_duration%100)) FROM history hm WHERE hm.job_id=j.job_id AND hm.run_status=1 AND hm.execution_number<=10) AS max_duration_seconds
FROM msdb.dbo.sysjobs AS j
LEFT JOIN latest_run AS lr ON lr.job_id = j.job_id AND lr.row_number = 1
LEFT JOIN activity AS a ON a.job_id=j.job_id AND a.row_number=1
ORDER BY j.name;
