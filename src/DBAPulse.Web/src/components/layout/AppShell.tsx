import { useEffect, useState, type ReactNode } from 'react';
import { AppBar, Box, Chip, Collapse, Drawer, List, ListItemButton, ListItemIcon, ListItemText, Toolbar, Typography } from '@mui/material';
import DnsIcon from '@mui/icons-material/Dns';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import StorageIcon from '@mui/icons-material/Storage';
import ShieldIcon from '@mui/icons-material/Shield';
import SpeedIcon from '@mui/icons-material/Speed';
import CrisisAlertIcon from '@mui/icons-material/CrisisAlert';
import TimelineIcon from '@mui/icons-material/Timeline';
import HistoryIcon from '@mui/icons-material/History';
import FactCheckIcon from '@mui/icons-material/FactCheck';

type NavItem = { key: string; label: string; icon: ReactNode; target?: string };
const nav: NavItem[] = [
  { key: 'estate', label: 'Servers & Databases', icon: <StorageIcon />, target: 'dashboard' },
  { key: 'protection', label: 'Protection', icon: <ShieldIcon /> },
  { key: 'performance', label: 'Performance', icon: <SpeedIcon /> },
  { key: 'operations', label: 'Blocking & Deadlocks', icon: <CrisisAlertIcon /> },
  { key: 'insights', label: 'Anomalies', icon: <CrisisAlertIcon /> },
  { key: 'capacity', label: 'FinOps & Capacity', icon: <StorageIcon /> },
  { key: 'audit', label: 'Audit Trail', icon: <FactCheckIcon /> },
];

type SidebarServer = { serverId: number; serverName: string; databaseCount: number; healthStatus: string };
type SidebarHealth = { entityType: string; serverId: number; overallStatus: string };

export default function AppShell({ activeView, onNavigate, onServerSelect, children }: { activeView: string; onNavigate: (view: string) => void; onServerSelect?: (serverId: number) => void; children: ReactNode }) {
  const active = ['server', 'database'].includes(activeView) ? 'estate' : activeView;
  const [servers, setServers] = useState<SidebarServer[]>([]);
  const [serversOpen, setServersOpen] = useState(active === 'estate');
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
  return <Box className="app-shell">
    <AppBar position="fixed" className="topbar"><Toolbar>
      <Typography className="topbar-title">DBA PULSE</Typography>
      <Typography className="topbar-subtitle">SQL Server Performance Monitor</Typography>
      <Box sx={{ flex: 1 }} />
      <Chip size="small" label="Europe/Istanbul" variant="outlined" />
      <Typography className="identity-label">anonymous</Typography>
    </Toolbar></AppBar>
    <Drawer variant="permanent" className="drawer"><Toolbar className="drawer-brand"><Box className="brand-mark"><TimelineIcon /></Box><Box><Typography className="brand-title">DBA PULSE</Typography><Typography className="brand-caption">SQL operations cockpit</Typography></Box></Toolbar>
      <List className="nav-list">{nav.map(item => item.key === 'estate' ? <Box key={item.key} className="estate-nav-group"><ListItemButton className="estate-nav-item" selected={active === item.key || active === 'dashboard'} onClick={() => { onNavigate(item.target || item.key); setServersOpen(open => !open); }}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /><Box className="nav-expand-icon">{serversOpen ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}</Box></ListItemButton><Collapse in={serversOpen} timeout="auto" unmountOnExit><List component="div" disablePadding className="server-nav-sublist">{servers.map(server => <ListItemButton key={server.serverId} className="server-nav-item" onClick={() => onServerSelect?.(server.serverId)}><ListItemIcon><Box component="span" className={`server-health-led server-health-${server.healthStatus.toLowerCase()}`} title={`${server.serverName}: ${server.healthStatus}`} aria-label={`${server.serverName}: ${server.healthStatus}`} /></ListItemIcon><ListItemText primary={server.serverName} secondary={`${server.healthStatus} · ${server.databaseCount} DB`} /></ListItemButton>)}</List></Collapse></Box> : <ListItemButton key={item.key} selected={active === item.key} onClick={() => onNavigate(item.target || item.key)}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /></ListItemButton>)}</List>
    </Drawer>
    <Box component="main" className="main"><Box className="content">{children}</Box></Box>
  </Box>;
}
