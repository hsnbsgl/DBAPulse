import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { AppBar, Box, ButtonBase, Chip, Collapse, Drawer, FormControl, IconButton, List, ListItemButton, ListItemIcon, ListItemText, MenuItem, Select, Toolbar, Tooltip, Typography } from '@mui/material';
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
import tskbLogo from '../../assets/tskb-logo.svg';

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

function TskbLogo() {
  return <Box className="tskb-logo" aria-hidden="true">
    <Box component="img" className="tskb-logo-image" src={tskbLogo} alt="TSKB" />
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
    <Drawer variant="permanent" className="drawer"><ButtonBase className="drawer-brand" onClick={() => onNavigate('dashboard')} aria-label="TSKB ana ekrana dön"><TskbLogo /></ButtonBase>
      <List className="nav-list">{nav.map(item => item.key === 'estate' ? <Box key={item.key} className="estate-nav-group"><ListItemButton className="estate-nav-item" selected={active === item.key || active === 'dashboard'} onClick={() => { onNavigate(item.target || item.key); setServersOpen(open => !open); }}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /><Box className="nav-expand-icon">{serversOpen ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}</Box></ListItemButton><Collapse in={serversOpen} timeout="auto" unmountOnExit><List component="div" disablePadding className="server-nav-sublist">{servers.map(server => <ListItemButton key={server.serverId} className="server-nav-item" onClick={() => { setSelectedServerId(server.serverId); onServerSelect?.(server.serverId); }}><ListItemIcon><Box component="span" className={`server-health-led server-health-${healthTone(server.healthStatus)}`} title={`${server.serverName}: ${server.healthStatus}`} aria-label={`${server.serverName}: ${server.healthStatus}`} /></ListItemIcon><ListItemText primary={server.serverName} secondary={`${server.healthStatus} · ${server.databaseCount} DB`} /></ListItemButton>)}</List></Collapse></Box> : <ListItemButton key={item.key} selected={active === item.key} onClick={() => onNavigate(item.target || item.key)}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /></ListItemButton>)}</List>
    </Drawer>
    <Box component="main" className="main"><Box className="content">{children}</Box></Box>
  </Box></ServerFilterContext.Provider>;
}
