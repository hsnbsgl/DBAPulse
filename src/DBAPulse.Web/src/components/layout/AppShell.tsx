import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { Alert, AppBar, Box, ButtonBase, Chip, CircularProgress, Collapse, Drawer, FormControl, IconButton, List, ListItemButton, ListItemIcon, ListItemText, MenuItem, Select, Toolbar, Tooltip, Typography } from '@mui/material';
import DnsIcon from '@mui/icons-material/Dns';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import StorageIcon from '@mui/icons-material/Storage';
import ShieldIcon from '@mui/icons-material/Shield';
import SpeedIcon from '@mui/icons-material/Speed';
import CrisisAlertIcon from '@mui/icons-material/CrisisAlert';
import HistoryIcon from '@mui/icons-material/History';
import FactCheckIcon from '@mui/icons-material/FactCheck';
import LightModeIcon from '@mui/icons-material/LightMode';
import DarkModeIcon from '@mui/icons-material/DarkMode';
import SettingsIcon from '@mui/icons-material/Settings';
import TableChartIcon from '@mui/icons-material/TableChart';
import CodeIcon from '@mui/icons-material/Code';
import ViewModuleIcon from '@mui/icons-material/ViewModule';
import FunctionsIcon from '@mui/icons-material/Functions';
import sqlServerLogo from '../../assets/sql-server-logo.svg';

type NavItem = { key: string; label: string; icon: ReactNode; target?: string };
const nav: NavItem[] = [
  { key: 'estate', label: 'Servers & Databases', icon: <StorageIcon />, target: 'dashboard' },
  { key: 'protection', label: 'Protection', icon: <ShieldIcon /> },
  { key: 'performance', label: 'Performance', icon: <SpeedIcon /> },
  { key: 'operations', label: 'Blocking & Deadlocks', icon: <CrisisAlertIcon /> },
  { key: 'insights', label: 'Anomalies', icon: <CrisisAlertIcon /> },
  { key: 'capacity', label: 'Capacity', icon: <StorageIcon /> },
  { key: 'audit', label: 'Audit Trail', icon: <FactCheckIcon /> },
  { key: 'settings', label: 'Settings', icon: <SettingsIcon /> },
];

type SidebarServer = { serverId: number; serverName: string; databaseCount: number; healthStatus: string };
type SidebarHealth = { entityType: string; serverId: number; overallStatus: string };
type SidebarDatabase = { databaseId: number; databaseName: string; databaseStatus: string };
type ObjectExplorerItem = { schemaName: string; objectName: string };
type ObjectExplorerSnapshot = { tables: ObjectExplorerItem[]; procedures: ObjectExplorerItem[]; views: ObjectExplorerItem[]; functions: ObjectExplorerItem[] };

const healthTone = (status: string) => {
  const normalized = status.toLowerCase();
  if (['critical', 'offline', 'unhealthy', 'failed'].includes(normalized)) return 'critical';
  if (['warning', 'unknown', 'stale', 'degraded'].includes(normalized)) return 'warning';
  if (['healthy', 'online'].includes(normalized)) return 'healthy';
  return 'unknown';
};

type ServerFilterContextValue = {
  selectedServerId: number;
  setSelectedServerId: (serverId: number) => void;
  servers: SidebarServer[];
};

const ServerFilterContext = createContext<ServerFilterContextValue | null>(null);

export function useServerFilter() {
  const context = useContext(ServerFilterContext);
  if (!context) throw new Error('useServerFilter must be used inside AppShell');
  return context;
}

function SqlServerLogo() {
  return <Box className="sqlserver-logo" aria-hidden="true">
    <Box component="img" className="sqlserver-logo-image" src={sqlServerLogo} alt="SQL Server" />
  </Box>;
}
function ServerSelector({ servers, value, onChange }: { servers: SidebarServer[]; value: number; onChange: (serverId: number) => void }) {
  return <FormControl size="small" className="global-server-selector">
    <Select
      value={String(value)}
      onChange={event => onChange(Number(event.target.value))}
      displayEmpty
      inputProps={{ 'aria-label': 'Server scope' }}
    >
      <MenuItem value="0">All servers</MenuItem>
      {servers.map(server => <MenuItem key={server.serverId} value={String(server.serverId)}>{server.serverName}</MenuItem>)}
    </Select>
  </FormControl>;
}

function ObjectExplorer({ servers, onServerSelect }: { servers: SidebarServer[]; onServerSelect?: (serverId: number) => void }) {
  const base = import.meta.env.VITE_API_BASE_URL || '/api';
  const [expandedServers, setExpandedServers] = useState<Set<number>>(new Set());
  const [expandedDatabases, setExpandedDatabases] = useState<Set<string>>(new Set());
  const [databases, setDatabases] = useState<Record<number, SidebarDatabase[]>>({});
  const [objects, setObjects] = useState<Record<string, ObjectExplorerSnapshot>>({});
  const [loadingServers, setLoadingServers] = useState<Set<number>>(new Set());
  const [loadingDatabases, setLoadingDatabases] = useState<Set<string>>(new Set());
  const [errors, setErrors] = useState<Record<string, string>>({});

  const loadDatabases = async (serverId: number) => {
    if (databases[serverId] || loadingServers.has(serverId)) return;
    setLoadingServers(current => new Set(current).add(serverId));
    try {
      const response = await fetch(`${base}/servers/${serverId}`);
      if (!response.ok) throw new Error(`API request failed (${response.status})`);
      const detail = await response.json() as { databases: SidebarDatabase[] };
      setDatabases(current => ({ ...current, [serverId]: detail.databases }));
    } catch (error) {
      setErrors(current => ({ ...current, [`server:${serverId}`]: error instanceof Error ? error.message : String(error) }));
    } finally {
      setLoadingServers(current => { const next = new Set(current); next.delete(serverId); return next; });
    }
  };

  const toggleServer = (serverId: number) => {
    setExpandedServers(current => { const next = new Set(current); if (next.has(serverId)) next.delete(serverId); else next.add(serverId); return next; });
    void loadDatabases(serverId);
  };

  const loadObjects = async (serverId: number, databaseName: string) => {
    const key = `${serverId}:${databaseName}`;
    if (objects[key] || loadingDatabases.has(key)) return;
    setLoadingDatabases(current => new Set(current).add(key));
    try {
      const query = new URLSearchParams({ serverId: String(serverId), databaseName });
      const response = await fetch(`${base}/live/object-explorer?${query}`);
      if (!response.ok) throw new Error(`API request failed (${response.status})`);
      const snapshot = await response.json() as ObjectExplorerSnapshot;
      setObjects(current => ({ ...current, [key]: snapshot }));
    } catch (error) {
      setErrors(current => ({ ...current, [key]: error instanceof Error ? error.message : String(error) }));
    } finally {
      setLoadingDatabases(current => { const next = new Set(current); next.delete(key); return next; });
    }
  };

  const toggleDatabase = (serverId: number, databaseName: string) => {
    const key = `${serverId}:${databaseName}`;
    setExpandedDatabases(current => { const next = new Set(current); if (next.has(key)) next.delete(key); else next.add(key); return next; });
    void loadObjects(serverId, databaseName);
  };

  const folder = (label: string, icon: ReactNode, items: ObjectExplorerItem[]) => <List component="div" disablePadding sx={{ pl: 2.5 }}>{<ListItemButton dense sx={{ minHeight: 28, py: 0 }}><ListItemIcon sx={{ minWidth: 28 }}>{icon}</ListItemIcon><ListItemText primary={`${label} (${items.length})`} primaryTypographyProps={{ variant: 'caption', noWrap: true }} /></ListItemButton>}{items.map(item => <ListItemButton key={`${item.schemaName}.${item.objectName}`} dense sx={{ minHeight: 26, py: 0, pl: 4.5 }}><ListItemText primary={`${item.schemaName}.${item.objectName}`} primaryTypographyProps={{ variant: 'caption', noWrap: true, title: `${item.schemaName}.${item.objectName}` }} /></ListItemButton>)}</List>;

  return <List component="div" disablePadding className="server-nav-sublist">{servers.map(server => {
    const serverOpen = expandedServers.has(server.serverId);
    const serverDbs = databases[server.serverId] || [];
    return <Box key={server.serverId}><ListItemButton className="server-nav-item" onClick={() => { toggleServer(server.serverId); onServerSelect?.(server.serverId); }}><ListItemIcon>{serverOpen ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}<Box component="span" className={`server-health-led server-health-${healthTone(server.healthStatus)}`} title={`${server.serverName}: ${server.healthStatus}`} /></ListItemIcon><ListItemText primary={server.serverName} secondary={`${server.healthStatus} · ${server.databaseCount} DB`} /></ListItemButton><Collapse in={serverOpen} timeout="auto" unmountOnExit><List component="div" disablePadding sx={{ pl: 2 }}><ListItemButton dense sx={{ minHeight: 30, py: 0 }} onClick={() => toggleServer(server.serverId)}><ListItemIcon sx={{ minWidth: 28 }}>{loadingServers.has(server.serverId) ? <CircularProgress size={14} /> : <StorageIcon fontSize="small" />}</ListItemIcon><ListItemText primary="Databases" primaryTypographyProps={{ variant: 'caption', fontWeight: 600 }} /></ListItemButton>{errors[`server:${server.serverId}`] && <Alert severity="warning" sx={{ ml: 2, mr: 1, py: 0 }}>{errors[`server:${server.serverId}`]}</Alert>}{serverDbs.map(database => { const key = `${server.serverId}:${database.databaseName}`; const databaseOpen = expandedDatabases.has(key); const snapshot = objects[key]; return <Box key={database.databaseId}><ListItemButton dense sx={{ minHeight: 28, py: 0, pl: 2 }} onClick={() => toggleDatabase(server.serverId, database.databaseName)}><ListItemIcon sx={{ minWidth: 28 }}>{databaseOpen ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}<StorageIcon fontSize="small" /></ListItemIcon><ListItemText primary={database.databaseName} secondary={database.databaseStatus} primaryTypographyProps={{ variant: 'caption', noWrap: true, title: database.databaseName }} secondaryTypographyProps={{ variant: 'caption', noWrap: true }} /></ListItemButton><Collapse in={databaseOpen} timeout="auto" unmountOnExit><Box>{loadingDatabases.has(key) && <Box sx={{ pl: 7, py: 0.5 }}><CircularProgress size={13} /></Box>}{errors[key] && <Alert severity="warning" sx={{ ml: 5, mr: 1, py: 0 }}>{errors[key]}</Alert>}{snapshot && <>{folder('Tables', <TableChartIcon fontSize="small" />, snapshot.tables)}{folder('Stored Procedures', <CodeIcon fontSize="small" />, snapshot.procedures)}{folder('Views', <ViewModuleIcon fontSize="small" />, snapshot.views)}{folder('Functions', <FunctionsIcon fontSize="small" />, snapshot.functions)}</>}</Box></Collapse></Box>; })}</List></Collapse></Box>;
  })}</List>;
}

export default function AppShell({ activeView, onNavigate, onServerSelect, themeMode, onToggleTheme, children }: { activeView: string; onNavigate: (view: string) => void; onServerSelect?: (serverId: number) => void; themeMode: 'dark' | 'light'; onToggleTheme: () => void; children: ReactNode }) {
  const active = ['server', 'database'].includes(activeView) ? 'estate' : activeView;
  const [servers, setServers] = useState<SidebarServer[]>([]);
  const [serversOpen, setServersOpen] = useState(active === 'estate');
  const [selectedServerId, setSelectedServerId] = useState(0);
  useEffect(() => {
    const base = import.meta.env.VITE_API_BASE_URL || '/api';
    Promise.all([fetch(`${base}/servers`), fetch(`${base}/management/health`)]).then(async ([serverResponse, healthResponse]) => {
      if (!serverResponse.ok) throw new Error('Unable to load servers');
      const serverRows = await serverResponse.json() as Array<Omit<SidebarServer, 'healthStatus'>>;
      const healthRows = healthResponse.ok ? await healthResponse.json() as SidebarHealth[] : [];
      const healthByServer = new Map(healthRows.filter(row => row.entityType === 'Server').map(row => [row.serverId, row.overallStatus]));
      setServers(serverRows.map(server => ({ ...server, healthStatus: healthByServer.get(server.serverId) || 'Unknown' })));
    }).catch(() => setServers([]));
  }, []);
  useEffect(() => { if (active === 'estate') setServersOpen(true); }, [active]);
  const showServerSelector = !['dashboard', 'estate', 'server', 'database', 'settings'].includes(activeView);
  return <ServerFilterContext.Provider value={{ selectedServerId, setSelectedServerId, servers }}><Box className="app-shell">
    <AppBar position="fixed" className="topbar"><Toolbar>
      <Typography className="topbar-title">DBA PULSE</Typography>
      <Typography className="topbar-subtitle">SQL Server Performance Monitor</Typography>
      <Box sx={{ flex: 1 }} />
      {showServerSelector && <><Typography className="server-selector-label">Server</Typography><ServerSelector servers={servers} value={selectedServerId} onChange={setSelectedServerId} /></>}
      <Chip size="small" label="Europe/Istanbul" variant="outlined" />
      <Tooltip title={themeMode === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'}><IconButton className="theme-toggle" size="small" onClick={onToggleTheme} aria-label={themeMode === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'}>{themeMode === 'dark' ? <LightModeIcon fontSize="small" /> : <DarkModeIcon fontSize="small" />}</IconButton></Tooltip><Typography className="identity-label">anonymous</Typography>
    </Toolbar></AppBar>
    <Drawer variant="permanent" className="drawer"><ButtonBase className="drawer-brand" onClick={() => onNavigate('dashboard')} aria-label="SQL Server ana ekrana dön"><SqlServerLogo /></ButtonBase>
      <List className="nav-list">{nav.map(item => item.key === 'estate' ? <Box key={item.key} className="estate-nav-group"><ListItemButton className="estate-nav-item" selected={active === item.key || active === 'dashboard'} onClick={() => { onNavigate(item.target || item.key); setServersOpen(open => !open); }}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /><Box className="nav-expand-icon">{serversOpen ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}</Box></ListItemButton><Collapse in={serversOpen} timeout="auto" unmountOnExit><ObjectExplorer servers={servers} onServerSelect={serverId => { setSelectedServerId(serverId); onServerSelect?.(serverId); }} /></Collapse></Box> : <ListItemButton key={item.key} selected={active === item.key} onClick={() => onNavigate(item.target || item.key)}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /></ListItemButton>)}</List>
    </Drawer>
    <Box component="main" className="main"><Box className="content">{children}</Box></Box>
  </Box></ServerFilterContext.Provider>;
}
