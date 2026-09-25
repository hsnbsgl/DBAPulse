import { useEffect, useMemo, useRef, useState, type RefObject } from 'react';
import { Alert, Box, Button, Chip, Divider, Paper, Stack, Tab, Table, TableBody, TableCell, TableHead, TableRow, TableSortLabel, Tabs, Typography } from '@mui/material';
import { KpiCard, EmptyState, StatusChip } from '../common/Ui';
import ListToolbar, { ALL_RECORDS, useListRefresh } from '../common/ListToolbar';
import DonutChart from '../charts/DonutChart';
import HorizontalBarChart from '../charts/HorizontalBarChart';
import { chartColors } from '../charts/chartTheme';

const api = import.meta.env.VITE_API_BASE_URL || '/api';
const tz = import.meta.env.VITE_DISPLAY_TIMEZONE || 'Europe/Istanbul';
const get = async <T,>(path: string): Promise<T> => {
  const response = await fetch(`${api}${path}`);
  if (!response.ok) throw new Error(`API request failed (${response.status})`);
  return response.json();
};
const date = (value?: string | null) => value ? new Intl.DateTimeFormat('en-GB', { timeZone: tz, dateStyle: 'short', timeStyle: 'medium' }).format(new Date(value)) : 'N/A';
const mb = (value?: number | null) => value == null ? 'N/A' : `${value.toLocaleString('en-US', { maximumFractionDigits: 1 })} MB`;
const bytes = (value?: number | null) => {
  if (value == null) return 'N/A';
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  let amount = value; let index = 0;
  while (amount >= 1024 && index < units.length - 1) { amount /= 1024; index += 1; }
  return `${amount.toLocaleString('en-US', { maximumFractionDigits: 1 })} ${units[index]}`;
};

type Page<T> = { items: T[]; totalCount: number };
type Server = { serverId: number; serverName: string; instanceName: string; sqlVersion: string; edition: string; databaseCount: number; lastSeenAtUtc: string; timeZoneId?: string };
type ServerDb = { databaseId: number; databaseName: string; databaseStatus: string; recoveryModel: string; lastSeenAtUtc: string };
type ServerDetail = { server: Server; databases: ServerDb[] };
type CapacityDb = { databaseId: number; databaseName: string; currentDataSizeMb: number; currentLogSizeMb: number; currentTotalSizeMb: number; growth30dMb?: number; forecastStatus: string; capacityStatus: string; lastCollectedAtUtc?: string };
type Volume = { id: number; volumeId: string; totalBytes: number; availableBytes: number; freePercent: number; capacityStatus: string; forecastStatus: string; collectedAtUtc: string };
type Backup = { databaseId: number; databaseName: string; recoveryModel: string; protectionStatus: string; lastFullBackupAtSource?: string; lastDifferentialBackupAtSource?: string; lastLogBackupAtSource?: string; backupAgeMinutes?: number; dataFreshness: string };
type AlwaysOn = { id: number; availabilityGroupName: string; replicaServerName?: string; role?: string; connectedState?: string; synchronizationHealth?: string; databaseName?: string; synchronizationState?: string; isSuspended: boolean; logSendQueueMb?: number; redoQueueMb?: number; healthStatus: string; collectedAtUtc: string };
type Job = { id: number; jobName: string; enabled: boolean; lastRunStatus: string; lastRunAtSource?: string; lastRunDurationSeconds?: number; isRunning: boolean; currentDurationSeconds?: number; failureCount24Hours: number; failureCount7Days: number; repeatedFailure: boolean };
type Blocking = { id: number; capturedAtUtc: string; serverName: string; databaseName?: string; sessionId: number; blockingSessionId: number; waitType?: string; waitDurationMs: number; applicationName?: string };
type Deadlock = { id: number; occurredAtUtc: string; serverName: string; databaseName?: string; processCount: number; victimProcessId?: string };
type LongRunning = { id: number; capturedAtUtc: string; serverName: string; databaseName?: string; sessionId: number; elapsedMs: number; status?: string; waitType?: string; applicationName?: string };
type OperationalEvent = { id: number; eventType: string; serverName: string; databaseName?: string; startedAtUtc: string; lastSeenAtUtc: string; status: string; severity: string; durationMs: number; title: string };
type Anomaly = { id: number; metricType: string; databaseName?: string; entityKey?: string; observedAtUtc: string; observedValue: number; baselineMedian: number; baselineP95: number; deviationRatio?: number; modifiedZScore?: number; baselineScope: string; sampleCount: number; severity: string; status: string; explanationCode: string; startedAtUtc: string; lastSeenAtUtc: string };
type WorkspaceData = { server: ServerDetail; capacity: Page<CapacityDb>; volumes: Page<Volume>; backups: Page<Backup>; alwaysOn: Page<AlwaysOn>; jobs: Page<Job>; blocking: Blocking[]; deadlocks: Deadlock[]; longRunning: LongRunning[]; operations: Page<OperationalEvent>; anomalies: Page<Anomaly> };

type SortState = { key: string; direction: 'asc' | 'desc' };

const compareSortValues = (left: unknown, right: unknown) => {
  if (left == null && right == null) return 0;
  if (left == null) return -1;
  if (right == null) return 1;
  if (typeof left === 'number' && typeof right === 'number') return left - right;
  return String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: 'base' });
};

const sortRows = <T,>(rows: T[], sort: SortState, getValue: (row: T, key: string) => unknown) => [...rows].sort((left, right) => {
  const result = compareSortValues(getValue(left, sort.key), getValue(right, sort.key));
  return sort.direction === 'asc' ? result : -result;
});

function SortHeader({ label, sortKey, sort, onSort }: { label: string; sortKey: string; sort: SortState; onSort: (key: string) => void }) {
  return <TableCell><TableSortLabel active={sort.key === sortKey} direction={sort.key === sortKey ? sort.direction : 'asc'} onClick={() => onSort(sortKey)}>{label}</TableSortLabel></TableCell>;
}

const toggleSort = (current: SortState, key: string): SortState => current.key === key ? { key, direction: current.direction === 'asc' ? 'desc' : 'asc' } : { key, direction: 'asc' };

const chartPageSize = 10;

function ChartPager({ page, total, onChange }: { page: number; total: number; onChange: (page: number) => void }) {
  const pageCount = Math.max(1, Math.ceil(total / chartPageSize));
  if (pageCount <= 1) return null;
  return <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 1 }}><Typography variant="caption" color="text.secondary">{total} records · Page {page} / {pageCount}</Typography><Box sx={{ flex: 1 }} /><Button size="small" disabled={page <= 1} onClick={() => onChange(page - 1)}>Previous</Button><Button size="small" disabled={page >= pageCount} onClick={() => onChange(page + 1)}>Next</Button></Stack>;
}

type ResizeDirection = 'n' | 's' | 'e' | 'w' | 'ne' | 'nw' | 'se' | 'sw';

function useResizablePanels(containerRef: RefObject<HTMLDivElement | null>, serverId: number, tab: number, ready: boolean) {
  useEffect(() => {
    const container = containerRef.current;
    if (!container || !ready) return undefined;
    const panels = Array.from(container.querySelectorAll<HTMLElement>('.panel:not(.server-tabs-panel)'));
    const cleanups: Array<() => void> = [];
    const directions: ResizeDirection[] = ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'];

    panels.forEach((panel, index) => {
      const title = panel.querySelector<HTMLElement>('.MuiTypography-h6')?.textContent?.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'panel';
      const storageKey = `dbapulse.server-panel-size.v1.${serverId}.${tab}.${index}.${title}`;
      panel.classList.add('workspace-resizable-panel');
      try {
        const saved = JSON.parse(localStorage.getItem(storageKey) || 'null') as { width?: number; height?: number } | null;
        if (saved?.width) panel.style.width = `${saved.width}px`;
        if (saved?.height) panel.style.height = `${saved.height}px`;
      } catch { /* Ignore malformed local layout state. */ }

      directions.forEach(direction => {
        const handle = document.createElement('span');
        handle.className = `workspace-resize-handle workspace-resize-${direction}`;
        handle.setAttribute('aria-label', `Resize panel ${direction}`);
        handle.setAttribute('role', 'separator');
        panel.appendChild(handle);
        let cleanupDrag: (() => void) | undefined;
        const onPointerDown = (event: PointerEvent) => {
          event.preventDefault();
          event.stopPropagation();
          const start = panel.getBoundingClientRect();
          const minWidth = 280;
          const minHeight = 120;
          const horizontal = direction.includes('e') || direction.includes('w');
          const vertical = direction.includes('n') || direction.includes('s');
          const bodyCursor = document.body.style.cursor;
          const userSelect = document.body.style.userSelect;
          document.body.style.cursor = horizontal && vertical ? `${direction}-resize` : `${direction}-resize`;
          document.body.style.userSelect = 'none';
          const onPointerMove = (moveEvent: PointerEvent) => {
            const dx = moveEvent.clientX - event.clientX;
            const dy = moveEvent.clientY - event.clientY;
            const nextWidth = horizontal ? Math.max(minWidth, direction.includes('w') ? start.width - dx : start.width + dx) : start.width;
            const nextHeight = vertical ? Math.max(minHeight, direction.includes('n') ? start.height - dy : start.height + dy) : start.height;
            panel.style.width = `${nextWidth}px`;
            panel.style.height = `${nextHeight}px`;
            panel.style.transform = `${direction.includes('w') ? `translateX(${dx}px)` : ''}${direction.includes('n') ? ` translateY(${dy}px)` : ''}`.trim();
          };
          const onPointerUp = () => {
            const rect = panel.getBoundingClientRect();
            panel.style.transform = '';
            localStorage.setItem(storageKey, JSON.stringify({ width: Math.round(rect.width), height: Math.round(rect.height) }));
            document.body.style.cursor = bodyCursor;
            document.body.style.userSelect = userSelect;
            window.removeEventListener('pointermove', onPointerMove);
            window.removeEventListener('pointerup', onPointerUp);
            cleanupDrag = undefined;
          };
          window.addEventListener('pointermove', onPointerMove);
          window.addEventListener('pointerup', onPointerUp, { once: true });
          cleanupDrag = () => {
            window.removeEventListener('pointermove', onPointerMove);
            window.removeEventListener('pointerup', onPointerUp);
            document.body.style.cursor = bodyCursor;
            document.body.style.userSelect = userSelect;
          };
        };
        handle.addEventListener('pointerdown', onPointerDown);
        cleanups.push(() => { cleanupDrag?.(); handle.removeEventListener('pointerdown', onPointerDown); handle.remove(); });
      });
    });
    return () => cleanups.forEach(cleanup => cleanup());
  }, [containerRef, serverId, tab, ready]);
}

function AnomaliesTab({ data }: { data: WorkspaceData }) {
  const [pageSize, setPageSize] = useState(10);
  const [sort, setSort] = useState<SortState>({ key: 'lastSeenAtUtc', direction: 'desc' });
  const rows = useMemo(() => sortRows(data.anomalies.items, sort, (row, key) => {
    if (key === 'entity') return row.databaseName || row.entityKey || '';
    return row[key as keyof Anomaly];
  }), [data.anomalies.items, sort]);
  const visibleRows = rows.slice(0, pageSize === ALL_RECORDS ? rows.length : pageSize);
  const onSort = (key: string) => setSort(current => toggleSort(current, key));
  return <Stack spacing={2}>
    <Paper className="panel"><Stack direction="row" justifyContent="space-between" alignItems="center"><Typography variant="h6">Anomalies ({data.anomalies.totalCount})</Typography></Stack><ListToolbar filename="server-anomalies" rows={visibleRows} pageSize={pageSize} onPageSizeChange={setPageSize} /><Divider sx={{ my: 1.5 }} />{data.anomalies.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Severity" sortKey="severity" sort={sort} onSort={onSort} /><SortHeader label="Metric" sortKey="metricType" sort={sort} onSort={onSort} /><SortHeader label="Database / Entity" sortKey="entity" sort={sort} onSort={onSort} /><SortHeader label="Observed" sortKey="observedValue" sort={sort} onSort={onSort} /><SortHeader label="Median" sortKey="baselineMedian" sort={sort} onSort={onSort} /><SortHeader label="P95" sortKey="baselineP95" sort={sort} onSort={onSort} /><SortHeader label="Deviation" sortKey="deviationRatio" sort={sort} onSort={onSort} /><SortHeader label="Status" sortKey="status" sort={sort} onSort={onSort} /><SortHeader label="Last Seen" sortKey="lastSeenAtUtc" sort={sort} onSort={onSort} /></TableRow></TableHead><TableBody>{visibleRows.map(row => <TableRow key={row.id}><TableCell><StatusChip value={row.severity} /></TableCell><TableCell>{row.metricType}</TableCell><TableCell>{row.databaseName || row.entityKey || 'N/A'}</TableCell><TableCell>{row.observedValue.toLocaleString()}</TableCell><TableCell>{row.baselineMedian.toLocaleString()}</TableCell><TableCell>{row.baselineP95.toLocaleString()}</TableCell><TableCell>{row.deviationRatio == null ? 'N/A' : `${row.deviationRatio.toFixed(2)}x`}</TableCell><TableCell><StatusChip value={row.status} /></TableCell><TableCell>{date(row.lastSeenAtUtc)}</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No anomalies for this server" description="No anomaly findings are available for the selected server." />}</Paper>
  </Stack>;
}

const chartStatusColor = (status: string) => {
  const normalized = status.toLowerCase();
  if (['healthy', 'protected', 'success', 'succeeded', 'online'].includes(normalized)) return chartColors.success;
  if (['critical', 'failed', 'offline'].includes(normalized)) return chartColors.critical;
  if (['warning', 'running', 'active'].includes(normalized)) return chartColors.warning;
  return chartColors.muted;
};

const chartCounts = (values: string[]) => Array.from(values.reduce((counts, value) => counts.set(value, (counts.get(value) || 0) + 1), new Map<string, number>()).entries()).map(([name, value]) => ({ name, value, color: chartStatusColor(name) }));

function ServerSummary({ data }: { data: WorkspaceData }) {
  const online = data.server.databases.filter(x => x.databaseStatus.toUpperCase() === 'ONLINE').length;
  const backupRisk = data.backups.items.filter(x => ['Warning', 'Critical', 'NeverBackedUp'].includes(x.protectionStatus)).length;
  const failedJobs = data.jobs.items.filter(x => x.lastRunStatus === 'Failed').length;
  const activeEvents = data.operations.items.filter(x => x.status === 'Active').length;
  const databaseHealth = chartCounts(data.server.databases.map(x => x.databaseStatus));
  const sizedDatabases = data.capacity.items.filter(x => Number.isFinite(x.currentTotalSizeMb)).sort((left, right) => right.currentTotalSizeMb - left.currentTotalSizeMb);
  const [chartPage, setChartPage] = useState(1);
  useEffect(() => setChartPage(1), [data.capacity.items]);
  const sizedPage = sizedDatabases.slice((chartPage - 1) * chartPageSize, chartPage * chartPageSize);
  return <Stack spacing={2}>
    <Box className="metric-grid">
      <KpiCard title="Databases" value={data.server.databases.length} subtitle={`${online} online`} tone={online === data.server.databases.length ? 'success' : 'warning'} />
      <KpiCard title="Backup Risk" value={backupRisk} subtitle="Warning / Critical / Never backed up" tone={backupRisk ? 'warning' : 'success'} />
      <KpiCard title="Failed Jobs" value={failedJobs} subtitle="Latest job state" tone={failedJobs ? 'error' : 'success'} />
      <KpiCard title="Active Events" value={activeEvents} subtitle="Operational events" tone={activeEvents ? 'warning' : 'success'} />
    </Box>
    <Paper className="panel">
      <Typography variant="h6">Server Information</Typography>
      <Divider sx={{ my: 1.5 }} />
      <Box className="detail-grid">
        <Typography>Instance<br /><b>{data.server.server.instanceName}</b></Typography>
        <Typography>SQL Version<br /><b>{data.server.server.sqlVersion}</b></Typography>
        <Typography>Edition<br /><b>{data.server.server.edition}</b></Typography>
        <Typography>Timezone<br /><b>{data.server.server.timeZoneId || 'Europe/Istanbul'}</b></Typography>
        <Typography>Last Seen<br /><b>{date(data.server.server.lastSeenAtUtc)}</b></Typography>
        <Typography>Capacity Telemetry<br /><b>{data.capacity.items.length} database rows</b></Typography>
      </Box>
    </Paper>
    <Box className="two-col">
      <Paper className="panel"><Typography variant="h6">Database Health</Typography><Divider sx={{ my: 1.5 }} /><DonutChart items={databaseHealth} height={260} /></Paper>
      <Paper className="panel"><Typography variant="h6">Database Size</Typography><Divider sx={{ my: 1.5 }} />{sizedDatabases.length ? <><Box sx={{ width: '100%', mr: 'auto' }}><HorizontalBarChart labels={sizedPage.map(x => x.databaseName)} values={sizedPage.map(x => x.currentTotalSizeMb)} valueName="Size (MB)" color={chartColors.info} height={Math.max(220, Math.min(420, sizedPage.length * 34 + 70))} /></Box><ChartPager page={chartPage} total={sizedDatabases.length} onChange={setChartPage} /></> : <EmptyState title="No capacity chart data" description="Database size telemetry is not available for this server." />}</Paper>
    </Box>
  </Stack>;
}

function DatabasesTab({ data, onDatabase }: { data: WorkspaceData; onDatabase: (id: number) => void }) {
  const capacityByDatabase = useMemo(() => new Map(data.capacity.items.map(x => [x.databaseId, x])), [data.capacity.items]);
  const chartRows = data.capacity.items.filter(x => Number.isFinite(x.currentTotalSizeMb)).sort((left, right) => right.currentTotalSizeMb - left.currentTotalSizeMb);
  const [sort, setSort] = useState<SortState>({ key: 'databaseName', direction: 'asc' });
  const rows = useMemo(() => sortRows(data.server.databases, sort, (row, key) => {
    if (key === 'currentTotalSizeMb') return capacityByDatabase.get(row.databaseId)?.currentTotalSizeMb;
    if (key === 'growth30dMb') return capacityByDatabase.get(row.databaseId)?.growth30dMb;
    if (key === 'lastSeenAtUtc') return new Date(row.lastSeenAtUtc).getTime();
    return row[key as keyof ServerDb];
  }), [data.server.databases, capacityByDatabase, sort]);
  const onSort = (key: string) => setSort(current => toggleSort(current, key));
  const [chartPage, setChartPage] = useState(1);
  useEffect(() => setChartPage(1), [data.capacity.items]);
  const chartPageRows = chartRows.slice((chartPage - 1) * chartPageSize, chartPage * chartPageSize);
  return <Stack spacing={2}><Paper className="panel"><Typography variant="h6">Database Size by Database</Typography><Divider sx={{ my: 1.5 }} />{chartRows.length ? <><Box sx={{ width: '100%', mr: 'auto' }}><HorizontalBarChart labels={chartPageRows.map(x => x.databaseName)} values={chartPageRows.map(x => x.currentTotalSizeMb)} valueName="Size (MB)" color={chartColors.actual} height={Math.max(240, Math.min(480, chartPageRows.length * 36 + 80))} /></Box><ChartPager page={chartPage} total={chartRows.length} onChange={setChartPage} /></> : <EmptyState title="No capacity chart data" description="Database size telemetry is not available for this server." />}</Paper><Paper className="panel"><Typography variant="h6">Databases ({data.server.databases.length})</Typography><ListToolbar filename="server-databases" rows={rows} showPageSize={false} /><Divider sx={{ my: 1.5 }} />
    {data.server.databases.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Database" sortKey="databaseName" sort={sort} onSort={onSort} /><SortHeader label="Status" sortKey="databaseStatus" sort={sort} onSort={onSort} /><SortHeader label="Recovery" sortKey="recoveryModel" sort={sort} onSort={onSort} /><SortHeader label="Current Size" sortKey="currentTotalSizeMb" sort={sort} onSort={onSort} /><SortHeader label="Growth 30d" sortKey="growth30dMb" sort={sort} onSort={onSort} /><SortHeader label="Last Seen" sortKey="lastSeenAtUtc" sort={sort} onSort={onSort} /></TableRow></TableHead><TableBody>{rows.map(db => { const capacity = capacityByDatabase.get(db.databaseId); return <TableRow hover className="clickable" key={db.databaseId} onClick={() => onDatabase(db.databaseId)}><TableCell>{db.databaseName}</TableCell><TableCell><StatusChip value={db.databaseStatus} /></TableCell><TableCell>{db.recoveryModel}</TableCell><TableCell>{mb(capacity?.currentTotalSizeMb)}</TableCell><TableCell>{capacity?.growth30dMb == null ? 'N/A' : `${capacity.growth30dMb.toLocaleString()} MB`}</TableCell><TableCell>{date(db.lastSeenAtUtc)}</TableCell></TableRow>; })}</TableBody></Table> : <EmptyState title="No databases found" description="No database telemetry is associated with this server." />}
  </Paper></Stack>;
}

function PerformanceTab({ data }: { data: WorkspaceData }) {
  const blockingByWait = Array.from(data.blocking.reduce((counts, row) => counts.set(row.waitType || 'Unknown', (counts.get(row.waitType || 'Unknown') || 0) + 1), new Map<string, number>()).entries()).sort((a, b) => b[1] - a[1]);
  const longRunningRows = data.longRunning.slice().sort((a, b) => b.elapsedMs - a.elapsedMs).slice(0, 10);
  const deadlockByDatabase = Array.from(data.deadlocks.reduce((counts, row) => counts.set(row.databaseName || 'Unknown', (counts.get(row.databaseName || 'Unknown') || 0) + 1), new Map<string, number>()).entries()).sort((a, b) => b[1] - a[1]);
  const [blockingSort, setBlockingSort] = useState<SortState>({ key: 'capturedAtUtc', direction: 'desc' });
  const sortedBlocking = useMemo(() => sortRows(data.blocking, blockingSort, (row, key) => row[key as keyof Blocking]), [data.blocking, blockingSort]);
  const onBlockingSort = (key: string) => setBlockingSort(current => toggleSort(current, key));
  return <Stack spacing={2}>
    <Box className="metric-grid"><KpiCard title="Blocking" value={data.blocking.length} tone={data.blocking.length ? 'warning' : 'success'} /><KpiCard title="Deadlocks" value={data.deadlocks.length} tone={data.deadlocks.length ? 'error' : 'success'} /><KpiCard title="Long Running" value={data.longRunning.length} tone={data.longRunning.length ? 'warning' : 'success'} /></Box>
    {(blockingByWait.length > 0 || longRunningRows.length > 0 || deadlockByDatabase.length > 0) && <Box className="two-col">
      <Paper className="panel"><Typography variant="h6">Blocking by Wait Type</Typography><Divider sx={{ my: 1.5 }} />{blockingByWait.length ? <HorizontalBarChart labels={blockingByWait.map(([label]) => label)} values={blockingByWait.map(([, value]) => value)} valueName="Observations" color={chartColors.warning} height={Math.max(220, Math.min(360, blockingByWait.length * 38 + 70))} /> : <EmptyState title="No blocking observations" description="Zero is a real observation for this server." />}</Paper>
      <Paper className="panel"><Typography variant="h6">Long-running Duration</Typography><Divider sx={{ my: 1.5 }} />{longRunningRows.length ? <HorizontalBarChart labels={longRunningRows.map(x => `${x.databaseName || 'Unknown'} · SPID ${x.sessionId}`)} values={longRunningRows.map(x => x.elapsedMs)} valueName="Elapsed (ms)" color={chartColors.critical} height={Math.max(220, Math.min(360, longRunningRows.length * 38 + 70))} /> : <EmptyState title="No long-running requests" description="Zero is a real observation for this server." />}</Paper>
    </Box>}
    {deadlockByDatabase.length > 0 && <Paper className="panel"><Typography variant="h6">Deadlocks by Database</Typography><Divider sx={{ my: 1.5 }} /><HorizontalBarChart labels={deadlockByDatabase.map(([label]) => label)} values={deadlockByDatabase.map(([, value]) => value)} valueName="Events" color={chartColors.critical} height={Math.max(220, Math.min(340, deadlockByDatabase.length * 38 + 70))} /></Paper>}
    <Paper className="panel"><Typography variant="h6">Blocking</Typography><ListToolbar filename="server-blocking" rows={sortedBlocking} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.blocking.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Time" sortKey="capturedAtUtc" sort={blockingSort} onSort={onBlockingSort} /><SortHeader label="Database" sortKey="databaseName" sort={blockingSort} onSort={onBlockingSort} /><SortHeader label="Session" sortKey="sessionId" sort={blockingSort} onSort={onBlockingSort} /><SortHeader label="Blocked By" sortKey="blockingSessionId" sort={blockingSort} onSort={onBlockingSort} /><SortHeader label="Wait" sortKey="waitDurationMs" sort={blockingSort} onSort={onBlockingSort} /><SortHeader label="Application" sortKey="applicationName" sort={blockingSort} onSort={onBlockingSort} /></TableRow></TableHead><TableBody>{sortedBlocking.map(x => <TableRow key={x.id}><TableCell>{date(x.capturedAtUtc)}</TableCell><TableCell>{x.databaseName || 'N/A'}</TableCell><TableCell>{x.sessionId}</TableCell><TableCell>{x.blockingSessionId}</TableCell><TableCell>{x.waitType || 'N/A'} · {x.waitDurationMs} ms</TableCell><TableCell>{x.applicationName || 'N/A'}</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No blocking observations" description="No blocking telemetry was observed for this server in the selected period." />}</Paper>
    <Box className="two-col"><Paper className="panel"><Typography variant="h6">Deadlocks</Typography><ListToolbar filename="server-deadlocks" rows={data.deadlocks} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.deadlocks.length ? data.deadlocks.map(x => <Typography key={x.id} sx={{ mt: 1 }}>{date(x.occurredAtUtc)} · {x.databaseName || 'N/A'} · {x.processCount} processes</Typography>) : <EmptyState title="No deadlocks observed" description="Zero is a real observation for this server." />}</Paper><Paper className="panel"><Typography variant="h6">Long Running Requests</Typography><ListToolbar filename="server-long-running" rows={data.longRunning} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.longRunning.length ? data.longRunning.map(x => <Typography key={x.id} sx={{ mt: 1 }}>{date(x.capturedAtUtc)} · {x.databaseName || 'N/A'} · {x.elapsedMs.toLocaleString()} ms · {x.waitType || 'N/A'}</Typography>) : <EmptyState title="No long-running requests" description="No long-running request telemetry was observed for this server." />}</Paper></Box>
    <EmptyState title="Wait statistics are estate-wide" description="The current wait endpoint does not expose server identity, so wait rows are intentionally not attributed to this server." />
  </Stack>;
}

function ProtectionTab({ data }: { data: WorkspaceData }) {
  const protectionCounts = chartCounts(data.backups.items.map(x => x.protectionStatus));
  const ageRows = data.backups.items.filter(x => x.backupAgeMinutes != null).sort((a, b) => (b.backupAgeMinutes || 0) - (a.backupAgeMinutes || 0)).slice(0, 10);
  const [sort, setSort] = useState<SortState>({ key: 'databaseName', direction: 'asc' });
  const rows = useMemo(() => sortRows(data.backups.items, sort, (row, key) => key === 'backupAgeMinutes' ? row.backupAgeMinutes : row[key as keyof Backup]), [data.backups.items, sort]);
  const onSort = (key: string) => setSort(current => toggleSort(current, key));
  return <Stack spacing={2}>
    {data.backups.items.length > 0 && <Box className="two-col"><Paper className="panel"><Typography variant="h6">Protection Status</Typography><Divider sx={{ my: 1.5 }} /><DonutChart items={protectionCounts} height={260} /></Paper><Paper className="panel"><Typography variant="h6">Backup Age</Typography><Divider sx={{ my: 1.5 }} />{ageRows.length ? <HorizontalBarChart labels={ageRows.map(x => x.databaseName)} values={ageRows.map(x => x.backupAgeMinutes || 0)} valueName="Age (min)" color={chartColors.warning} height={Math.max(220, Math.min(360, ageRows.length * 38 + 70))} /> : <EmptyState title="No backup age data" description="Backup age is not available for this server." />}</Paper></Box>}
    <Paper className="panel"><Typography variant="h6">Backup Protection</Typography><ListToolbar filename="server-backups" rows={rows} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.backups.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Status" sortKey="protectionStatus" sort={sort} onSort={onSort} /><SortHeader label="Database" sortKey="databaseName" sort={sort} onSort={onSort} /><SortHeader label="Recovery" sortKey="recoveryModel" sort={sort} onSort={onSort} /><SortHeader label="Last Full" sortKey="lastFullBackupAtSource" sort={sort} onSort={onSort} /><SortHeader label="Last Diff" sortKey="lastDifferentialBackupAtSource" sort={sort} onSort={onSort} /><SortHeader label="Last Log" sortKey="lastLogBackupAtSource" sort={sort} onSort={onSort} /><SortHeader label="Age" sortKey="backupAgeMinutes" sort={sort} onSort={onSort} /></TableRow></TableHead><TableBody>{rows.map(x => <TableRow key={x.databaseId}><TableCell><StatusChip value={x.protectionStatus} /></TableCell><TableCell>{x.databaseName}</TableCell><TableCell>{x.recoveryModel}</TableCell><TableCell>{date(x.lastFullBackupAtSource)}</TableCell><TableCell>{date(x.lastDifferentialBackupAtSource)}</TableCell><TableCell>{date(x.lastLogBackupAtSource)}</TableCell><TableCell>{x.backupAgeMinutes == null ? 'N/A' : `${x.backupAgeMinutes} min`}</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No backup protection data" description="Backup telemetry has not been collected for this server." />}</Paper>
  </Stack>;
}

function AvailabilityTab({ data }: { data: WorkspaceData }) {
  const healthCounts = chartCounts(data.alwaysOn.items.map(x => x.healthStatus));
  const queueRows = data.alwaysOn.items.filter(x => x.logSendQueueMb != null && x.redoQueueMb != null).slice(0, 10);
  const [sort, setSort] = useState<SortState>({ key: 'availabilityGroupName', direction: 'asc' });
  const rows = useMemo(() => sortRows(data.alwaysOn.items, sort, (row, key) => row[key as keyof AlwaysOn]), [data.alwaysOn.items, sort]);
  const onSort = (key: string) => setSort(current => toggleSort(current, key));
  return <Stack spacing={2}>
    {data.alwaysOn.items.length > 0 && <Box className="two-col"><Paper className="panel"><Typography variant="h6">Replica Health</Typography><Divider sx={{ my: 1.5 }} /><DonutChart items={healthCounts} height={260} /></Paper><Paper className="panel"><Typography variant="h6">Replica Queues</Typography><Divider sx={{ my: 1.5 }} />{queueRows.length ? <HorizontalBarChart labels={queueRows.map(x => `${x.replicaServerName || 'Replica'} · ${x.databaseName || 'Database'}`)} values={queueRows.map(x => (x.logSendQueueMb || 0) + (x.redoQueueMb || 0))} valueName="Queue (MB)" color={chartColors.info} height={Math.max(220, Math.min(360, queueRows.length * 38 + 70))} /> : <EmptyState title="No queue metrics available" description="Always On queue telemetry is not available for this server." />}</Paper></Box>}
    <Paper className="panel"><Typography variant="h6">Always On Availability</Typography><ListToolbar filename="server-always-on" rows={rows} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.alwaysOn.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Health" sortKey="healthStatus" sort={sort} onSort={onSort} /><SortHeader label="AG / Replica" sortKey="availabilityGroupName" sort={sort} onSort={onSort} /><SortHeader label="Role" sortKey="role" sort={sort} onSort={onSort} /><SortHeader label="Database" sortKey="databaseName" sort={sort} onSort={onSort} /><SortHeader label="Sync" sortKey="synchronizationState" sort={sort} onSort={onSort} /><SortHeader label="Queues" sortKey="logSendQueueMb" sort={sort} onSort={onSort} /></TableRow></TableHead><TableBody>{rows.map(x => <TableRow key={x.id}><TableCell><StatusChip value={x.healthStatus} /></TableCell><TableCell>{x.availabilityGroupName} / {x.replicaServerName || 'N/A'}</TableCell><TableCell>{x.role || 'N/A'}</TableCell><TableCell>{x.databaseName || 'N/A'}</TableCell><TableCell>{x.synchronizationState || 'N/A'} · {x.synchronizationHealth || 'N/A'}</TableCell><TableCell>{x.logSendQueueMb ?? 'N/A'} / {x.redoQueueMb ?? 'N/A'} MB</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="Always On is not configured" description="Always On telemetry is not available for this server." />}</Paper>
  </Stack>;
}

function JobsTab({ data }: { data: WorkspaceData }) {
  const statusCounts = chartCounts(data.jobs.items.map(x => x.isRunning ? 'Running' : x.lastRunStatus));
  const durationRows = data.jobs.items.map(x => ({ name: x.jobName, duration: x.isRunning ? x.currentDurationSeconds : x.lastRunDurationSeconds })).filter(x => x.duration != null).sort((a, b) => (b.duration || 0) - (a.duration || 0)).slice(0, 10);
  const [sort, setSort] = useState<SortState>({ key: 'jobName', direction: 'asc' });
  const rows = useMemo(() => sortRows(data.jobs.items, sort, (row, key) => row[key as keyof Job]), [data.jobs.items, sort]);
  const onSort = (key: string) => setSort(current => toggleSort(current, key));
  return <Stack spacing={2}>
    {data.jobs.items.length > 0 && <Box className="two-col"><Paper className="panel"><Typography variant="h6">Job Status</Typography><Divider sx={{ my: 1.5 }} /><DonutChart items={statusCounts} height={260} /></Paper><Paper className="panel"><Typography variant="h6">Execution Duration</Typography><Divider sx={{ my: 1.5 }} />{durationRows.length ? <HorizontalBarChart labels={durationRows.map(x => x.name)} values={durationRows.map(x => x.duration || 0)} valueName="Duration (s)" color={chartColors.actual} height={Math.max(220, Math.min(360, durationRows.length * 38 + 70))} /> : <EmptyState title="No duration data" description="SQL Agent duration telemetry is not available for this server." />}</Paper></Box>}
    <Paper className="panel"><Typography variant="h6">SQL Agent Jobs</Typography><ListToolbar filename="server-jobs" rows={rows} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.jobs.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Status" sortKey="lastRunStatus" sort={sort} onSort={onSort} /><SortHeader label="Job" sortKey="jobName" sort={sort} onSort={onSort} /><SortHeader label="Enabled" sortKey="enabled" sort={sort} onSort={onSort} /><SortHeader label="Last Run" sortKey="lastRunAtSource" sort={sort} onSort={onSort} /><SortHeader label="Duration" sortKey="lastRunDurationSeconds" sort={sort} onSort={onSort} /><SortHeader label="Failures 24h / 7d" sortKey="failureCount24Hours" sort={sort} onSort={onSort} /><SortHeader label="Running" sortKey="isRunning" sort={sort} onSort={onSort} /></TableRow></TableHead><TableBody>{rows.map(x => <TableRow key={x.id}><TableCell><StatusChip value={x.lastRunStatus} /></TableCell><TableCell>{x.jobName}</TableCell><TableCell>{x.enabled ? 'Yes' : 'No'}</TableCell><TableCell>{date(x.lastRunAtSource)}</TableCell><TableCell>{x.isRunning ? `${x.currentDurationSeconds ?? 0}s` : `${x.lastRunDurationSeconds ?? 0}s`}</TableCell><TableCell>{x.failureCount24Hours} / {x.failureCount7Days}</TableCell><TableCell>{x.isRunning ? 'Running' : 'No'}</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No SQL Agent jobs found" description="No SQL Agent job telemetry is associated with this server." />}</Paper>
  </Stack>;
}

function CapacityTab({ data }: { data: WorkspaceData }) {
  const databaseRows = data.capacity.items.filter(x => Number.isFinite(x.currentTotalSizeMb)).sort((left, right) => right.currentTotalSizeMb - left.currentTotalSizeMb);
  const volumeRows = data.volumes.items.filter(x => Number.isFinite(x.freePercent));
  const [databaseSort, setDatabaseSort] = useState<SortState>({ key: 'databaseName', direction: 'asc' });
  const [volumeSort, setVolumeSort] = useState<SortState>({ key: 'volumeId', direction: 'asc' });
  const sortedDatabases = useMemo(() => sortRows(data.capacity.items, databaseSort, (row, key) => row[key as keyof CapacityDb]), [data.capacity.items, databaseSort]);
  const sortedVolumes = useMemo(() => sortRows(data.volumes.items, volumeSort, (row, key) => row[key as keyof Volume]), [data.volumes.items, volumeSort]);
  const onDatabaseSort = (key: string) => setDatabaseSort(current => toggleSort(current, key));
  const onVolumeSort = (key: string) => setVolumeSort(current => toggleSort(current, key));
  const [databaseChartPage, setDatabaseChartPage] = useState(1);
  useEffect(() => setDatabaseChartPage(1), [data.capacity.items]);
  const databaseChartPageRows = databaseRows.slice((databaseChartPage - 1) * chartPageSize, databaseChartPage * chartPageSize);
  return <Stack spacing={2}>
    {(databaseRows.length > 0 || volumeRows.length > 0) && <Box className="two-col"><Paper className="panel"><Typography variant="h6">Database Size</Typography><Divider sx={{ my: 1.5 }} />{databaseRows.length ? <><Box sx={{ width: '100%', mr: 'auto' }}><HorizontalBarChart labels={databaseChartPageRows.map(x => x.databaseName)} values={databaseChartPageRows.map(x => x.currentTotalSizeMb)} valueName="Size (MB)" color={chartColors.info} height={Math.max(220, Math.min(360, databaseChartPageRows.length * 38 + 70))} /></Box><ChartPager page={databaseChartPage} total={databaseRows.length} onChange={setDatabaseChartPage} /></> : <EmptyState title="No database size data" description="Database capacity telemetry is not available for this server." />}</Paper><Paper className="panel"><Typography variant="h6">Volume Free Capacity</Typography><Divider sx={{ my: 1.5 }} />{volumeRows.length ? <HorizontalBarChart labels={volumeRows.map(x => x.volumeId)} values={volumeRows.map(x => x.freePercent)} valueName="Free (%)" color={chartColors.success} height={Math.max(220, Math.min(360, volumeRows.length * 38 + 70))} /> : <EmptyState title="No volume data" description="Volume capacity telemetry is not available for this server." />}</Paper></Box>}
    <Paper className="panel"><Typography variant="h6">Database Capacity</Typography><ListToolbar filename="server-capacity-databases" rows={sortedDatabases} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.capacity.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Status" sortKey="capacityStatus" sort={databaseSort} onSort={onDatabaseSort} /><SortHeader label="Database" sortKey="databaseName" sort={databaseSort} onSort={onDatabaseSort} /><SortHeader label="Current" sortKey="currentTotalSizeMb" sort={databaseSort} onSort={onDatabaseSort} /><SortHeader label="Growth 30d" sortKey="growth30dMb" sort={databaseSort} onSort={onDatabaseSort} /><SortHeader label="Forecast" sortKey="forecastStatus" sort={databaseSort} onSort={onDatabaseSort} /></TableRow></TableHead><TableBody>{sortedDatabases.map(x => <TableRow key={x.databaseId}><TableCell><StatusChip value={x.capacityStatus} /></TableCell><TableCell>{x.databaseName}</TableCell><TableCell>{mb(x.currentTotalSizeMb)}</TableCell><TableCell>{x.growth30dMb == null ? 'N/A' : `${x.growth30dMb.toLocaleString()} MB`}</TableCell><TableCell><StatusChip value={x.forecastStatus} /></TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No capacity data" description="No database capacity telemetry is associated with this server." />}</Paper><Paper className="panel"><Typography variant="h6">Volume Capacity</Typography><ListToolbar filename="server-capacity-volumes" rows={sortedVolumes} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.volumes.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Status" sortKey="capacityStatus" sort={volumeSort} onSort={onVolumeSort} /><SortHeader label="Volume" sortKey="volumeId" sort={volumeSort} onSort={onVolumeSort} /><SortHeader label="Total" sortKey="totalBytes" sort={volumeSort} onSort={onVolumeSort} /><SortHeader label="Available" sortKey="availableBytes" sort={volumeSort} onSort={onVolumeSort} /><SortHeader label="Free" sortKey="freePercent" sort={volumeSort} onSort={onVolumeSort} /></TableRow></TableHead><TableBody>{sortedVolumes.map(x => <TableRow key={x.id}><TableCell><StatusChip value={x.capacityStatus} /></TableCell><TableCell>{x.volumeId}</TableCell><TableCell>{bytes(x.totalBytes)}</TableCell><TableCell>{bytes(x.availableBytes)}</TableCell><TableCell>{x.freePercent}%</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No volume data available" description="Volume capacity telemetry has not been collected for this server." />}</Paper></Stack>;
}

function OperationsTab({ data }: { data: WorkspaceData }) {
  const severityCounts = chartCounts(data.operations.items.map(x => x.severity));
  const typeCounts = Array.from(data.operations.items.reduce((counts, row) => counts.set(row.eventType, (counts.get(row.eventType) || 0) + 1), new Map<string, number>()).entries()).sort((a, b) => b[1] - a[1]);
  const [sort, setSort] = useState<SortState>({ key: 'lastSeenAtUtc', direction: 'desc' });
  const rows = useMemo(() => sortRows(data.operations.items, sort, (row, key) => row[key as keyof OperationalEvent]), [data.operations.items, sort]);
  const onSort = (key: string) => setSort(current => toggleSort(current, key));
  return <Stack spacing={2}>
    {data.operations.items.length > 0 && <Box className="two-col"><Paper className="panel"><Typography variant="h6">Event Severity</Typography><Divider sx={{ my: 1.5 }} /><DonutChart items={severityCounts} height={260} /></Paper><Paper className="panel"><Typography variant="h6">Event Types</Typography><Divider sx={{ my: 1.5 }} /><HorizontalBarChart labels={typeCounts.map(([label]) => label)} values={typeCounts.map(([, value]) => value)} valueName="Events" color={chartColors.warning} height={Math.max(220, Math.min(360, typeCounts.length * 38 + 70))} /></Paper></Box>}
    <Paper className="panel"><Typography variant="h6">Operational Events</Typography><ListToolbar filename="server-operational-events" rows={rows} showPageSize={false} /><Divider sx={{ my: 1.5 }} />{data.operations.items.length ? <Table size="small"><TableHead><TableRow><SortHeader label="Severity" sortKey="severity" sort={sort} onSort={onSort} /><SortHeader label="Status" sortKey="status" sort={sort} onSort={onSort} /><SortHeader label="Type" sortKey="eventType" sort={sort} onSort={onSort} /><SortHeader label="Started" sortKey="startedAtUtc" sort={sort} onSort={onSort} /><SortHeader label="Last Seen" sortKey="lastSeenAtUtc" sort={sort} onSort={onSort} /><SortHeader label="Duration" sortKey="durationMs" sort={sort} onSort={onSort} /><SortHeader label="Title" sortKey="title" sort={sort} onSort={onSort} /></TableRow></TableHead><TableBody>{rows.map(x => <TableRow key={x.id}><TableCell><StatusChip value={x.severity} /></TableCell><TableCell><StatusChip value={x.status} /></TableCell><TableCell>{x.eventType}</TableCell><TableCell>{date(x.startedAtUtc)}</TableCell><TableCell>{date(x.lastSeenAtUtc)}</TableCell><TableCell>{x.durationMs.toLocaleString()} ms</TableCell><TableCell>{x.title}</TableCell></TableRow>)}</TableBody></Table> : <EmptyState title="No operational events" description="No operational events are associated with this server." />}</Paper>
  </Stack>;
}

export default function ServerWorkspace({ serverId, onDatabase, onBack, fullPage = false }: { serverId: number; onDatabase: (id: number) => void; onBack?: () => void; fullPage?: boolean }) {
  const [data, setData] = useState<WorkspaceData>();
  const [tab, setTab] = useState(0);
  const [error, setError] = useState('');
  const panelRoot = useRef<HTMLDivElement>(null);
  useResizablePanels(panelRoot, serverId, tab, Boolean(data));
  useEffect(() => {
    let cancelled = false;
    setData(undefined); setError('');
    Promise.all([
      get<ServerDetail>(`/servers/${serverId}`),
      get<Page<CapacityDb>>(`/capacity/databases?serverId=${serverId}&page=1&pageSize=100`),
      get<Page<Volume>>(`/capacity/volumes?serverId=${serverId}&page=1&pageSize=100`),
      get<Page<Backup>>(`/protection/backups?serverId=${serverId}&page=1&pageSize=100`),
      get<Page<AlwaysOn>>(`/availability/alwayson?serverId=${serverId}&page=1&pageSize=100`),
      get<Page<Job>>(`/jobs?serverId=${serverId}&page=1&pageSize=100`),
      get<Blocking[]>('/performance/blocking?hours=24'),
      get<Deadlock[]>('/performance/deadlocks?hours=24'),
      get<LongRunning[]>('/performance/long-running?hours=24'),
      get<Page<OperationalEvent>>(`/operations/events?serverId=${serverId}&page=1&pageSize=100`),
      get<Page<Anomaly>>(`/anomalies?serverId=${serverId}&page=1&pageSize=100`),
    ]).then(([server, capacity, volumes, backups, alwaysOn, jobs, blocking, deadlocks, longRunning, operations, anomalies]) => {
      if (cancelled) return;
      const serverName = server.server.serverName;
      setData({ server, capacity, volumes, backups, alwaysOn, jobs, blocking: blocking.filter(x => x.serverName === serverName), deadlocks: deadlocks.filter(x => x.serverName === serverName), longRunning: longRunning.filter(x => x.serverName === serverName), operations, anomalies });
    }).catch(errorValue => { if (!cancelled) setError(errorValue.message); });
    return () => { cancelled = true; };
  }, [serverId]);

  type ServerListKey = 'server-databases' | 'server-blocking' | 'server-deadlocks' | 'server-long-running' | 'server-backups' | 'server-always-on' | 'server-jobs' | 'server-capacity-databases' | 'server-capacity-volumes' | 'server-operational-events' | 'server-anomalies';
  const refreshServerList = async (key: ServerListKey) => {
    if (!data) return;
    try {
      const serverName = data.server.server.serverName;
      switch (key) {
        case 'server-databases': {
          const server = await get<ServerDetail>(`/servers/${serverId}`);
          setData(current => current ? { ...current, server } : current);
          break;
        }
        case 'server-capacity-databases': {
          const capacity = await get<Page<CapacityDb>>(`/capacity/databases?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, capacity } : current);
          break;
        }
        case 'server-capacity-volumes': {
          const volumes = await get<Page<Volume>>(`/capacity/volumes?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, volumes } : current);
          break;
        }
        case 'server-backups': {
          const backups = await get<Page<Backup>>(`/protection/backups?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, backups } : current);
          break;
        }
        case 'server-always-on': {
          const alwaysOn = await get<Page<AlwaysOn>>(`/availability/alwayson?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, alwaysOn } : current);
          break;
        }
        case 'server-jobs': {
          const jobs = await get<Page<Job>>(`/jobs?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, jobs } : current);
          break;
        }
        case 'server-operational-events': {
          const operations = await get<Page<OperationalEvent>>(`/operations/events?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, operations } : current);
          break;
        }
        case 'server-anomalies': {
          const anomalies = await get<Page<Anomaly>>(`/anomalies?serverId=${serverId}&page=1&pageSize=100`);
          setData(current => current ? { ...current, anomalies } : current);
          break;
        }
        case 'server-blocking': {
          const blocking = await get<Blocking[]>('/performance/blocking?hours=24');
          setData(current => current ? { ...current, blocking: blocking.filter(row => row.serverName === serverName) } : current);
          break;
        }
        case 'server-deadlocks': {
          const deadlocks = await get<Deadlock[]>('/performance/deadlocks?hours=24');
          setData(current => current ? { ...current, deadlocks: deadlocks.filter(row => row.serverName === serverName) } : current);
          break;
        }
        case 'server-long-running': {
          const longRunning = await get<LongRunning[]>('/performance/long-running?hours=24');
          setData(current => current ? { ...current, longRunning: longRunning.filter(row => row.serverName === serverName) } : current);
          break;
        }
      }
    } catch (errorValue) {
      setError(errorValue instanceof Error ? errorValue.message : String(errorValue));
    }
  };
  useListRefresh('server-databases', () => { void refreshServerList('server-databases'); });
  useListRefresh('server-blocking', () => { void refreshServerList('server-blocking'); });
  useListRefresh('server-deadlocks', () => { void refreshServerList('server-deadlocks'); });
  useListRefresh('server-long-running', () => { void refreshServerList('server-long-running'); });
  useListRefresh('server-backups', () => { void refreshServerList('server-backups'); });
  useListRefresh('server-always-on', () => { void refreshServerList('server-always-on'); });
  useListRefresh('server-jobs', () => { void refreshServerList('server-jobs'); });
  useListRefresh('server-capacity-databases', () => { void refreshServerList('server-capacity-databases'); });
  useListRefresh('server-capacity-volumes', () => { void refreshServerList('server-capacity-volumes'); });
  useListRefresh('server-operational-events', () => { void refreshServerList('server-operational-events'); });
  useListRefresh('server-anomalies', () => { void refreshServerList('server-anomalies'); });

  if (error) return <Alert severity="error">Unable to load server data: {error}</Alert>;
  if (!data) return <Typography color="text.secondary">Loading server telemetry…</Typography>;
  const tabs = ['Overview', 'Databases', 'Performance', 'Protection', 'Always On', 'Jobs', 'Capacity', 'Operations', 'Anomalies'];
  return <Stack ref={panelRoot} spacing={2}>
    {fullPage && onBack && <Button variant="text" onClick={onBack}>← Servers &amp; Databases</Button>}
    <Stack direction="row" justifyContent="space-between" alignItems="flex-start" spacing={2}>
      <Box><Typography variant="h4">{data.server.server.serverName}</Typography><Typography color="text.secondary">Server operations workspace · {data.server.server.instanceName}</Typography></Box>
      <Chip label={data.server.server.sqlVersion} variant="outlined" />
    </Stack>
    <Paper className="panel server-tabs-panel"><Tabs value={tab} onChange={(_, value) => setTab(value)} variant="scrollable" scrollButtons="auto" allowScrollButtonsMobile>{tabs.map(label => <Tab key={label} label={label} />)}</Tabs></Paper>
    {tab === 0 && <ServerSummary data={data} />}
    {tab === 1 && <DatabasesTab data={data} onDatabase={onDatabase} />}
    {tab === 2 && <PerformanceTab data={data} />}
    {tab === 3 && <ProtectionTab data={data} />}
    {tab === 4 && <AvailabilityTab data={data} />}
    {tab === 5 && <JobsTab data={data} />}
    {tab === 6 && <CapacityTab data={data} />}
    {tab === 7 && <OperationsTab data={data} />}
    {tab === 8 && <AnomaliesTab data={data} />}
  </Stack>;
}
