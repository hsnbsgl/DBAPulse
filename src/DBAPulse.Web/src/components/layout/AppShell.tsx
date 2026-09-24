import type { ReactNode } from 'react';
import { AppBar, Box, Chip, Drawer, List, ListItemButton, ListItemIcon, ListItemText, Toolbar, Typography } from '@mui/material';
import DashboardIcon from '@mui/icons-material/Dashboard';
import StorageIcon from '@mui/icons-material/Storage';
import ShieldIcon from '@mui/icons-material/Shield';
import SpeedIcon from '@mui/icons-material/Speed';
import CrisisAlertIcon from '@mui/icons-material/CrisisAlert';
import TimelineIcon from '@mui/icons-material/Timeline';
import HistoryIcon from '@mui/icons-material/History';
import FactCheckIcon from '@mui/icons-material/FactCheck';

type NavItem = { key: string; label: string; icon: ReactNode; target?: string };
const nav: NavItem[] = [
  { key: 'dashboard', label: 'Dashboard', icon: <DashboardIcon /> },
  { key: 'estate', label: 'SQL Estate', icon: <StorageIcon /> },
  { key: 'protection', label: 'Protection & Availability', icon: <ShieldIcon /> },
  { key: 'performance', label: 'Performance', icon: <SpeedIcon /> },
  { key: 'operations', label: 'Operations', icon: <CrisisAlertIcon /> },
  { key: 'insights', label: 'Insights', icon: <CrisisAlertIcon /> },
  { key: 'capacity', label: 'Capacity', icon: <StorageIcon /> },
  { key: 'collections', label: 'Collections', icon: <TimelineIcon />, target: 'dashboard' },
  { key: 'audit', label: 'Audit', icon: <FactCheckIcon /> },
];

export default function AppShell({ activeView, onNavigate, children }: { activeView: string; onNavigate: (view: string) => void; children: ReactNode }) {
  const active = ['server', 'database'].includes(activeView) ? 'estate' : activeView;
  return <Box className="app-shell">
    <AppBar position="fixed" className="topbar"><Toolbar>
      <Typography className="topbar-title">DBA PULSE</Typography>
      <Typography className="topbar-subtitle">Database Operations Intelligence Platform</Typography>
      <Box sx={{ flex: 1 }} />
      <Chip size="small" label="Europe/Istanbul" variant="outlined" />
      <Typography className="identity-label">anonymous</Typography>
    </Toolbar></AppBar>
    <Drawer variant="permanent" className="drawer"><Toolbar className="drawer-brand"><Box className="brand-mark"><TimelineIcon /></Box><Box><Typography className="brand-title">DBA PULSE</Typography><Typography className="brand-caption">SQL operations cockpit</Typography></Box></Toolbar>
      <List className="nav-list">{nav.map(item => <ListItemButton key={item.key} selected={active === item.key} onClick={() => onNavigate(item.target || item.key)}><ListItemIcon>{item.icon}</ListItemIcon><ListItemText primary={item.label} /></ListItemButton>)}</List>
    </Drawer>
    <Box component="main" className="main"><Box className="content">{children}</Box></Box>
  </Box>;
}
