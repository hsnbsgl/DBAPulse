import React, { useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { CssBaseline } from '@mui/material';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import App from './App';
import './theme.css';

type ThemeMode = 'dark' | 'light';

const buildTheme = (mode: ThemeMode) => createTheme({
  palette: mode === 'dark' ? {
    mode: 'dark', primary: { main: '#f08a24' }, secondary: { main: '#9c9c9c' },
    background: { default: '#151515', paper: '#202020' }, text: { primary: '#f2f2f2', secondary: '#a9a9a9' },
    divider: '#383838', success: { main: '#46c878' }, warning: { main: '#e0a53a' }, error: { main: '#ed6262' }, info: { main: '#6ea7d8' },
  } : {
    mode: 'light', primary: { main: '#b45309' }, secondary: { main: '#5b6472' },
    background: { default: '#f4f6f8', paper: '#ffffff' }, text: { primary: '#1f2937', secondary: '#5b6472' },
    divider: '#d7dde5', success: { main: '#16834b' }, warning: { main: '#b7791f' }, error: { main: '#c53030' }, info: { main: '#2563a8' },
  },
  typography: { fontFamily: 'Inter, Roboto, Arial, sans-serif', h4: { fontSize: '1.65rem', fontWeight: 700 }, h6: { fontSize: '1rem', fontWeight: 650 }, body2: { fontSize: '0.82rem' } },
  shape: { borderRadius: 8 },
  components: {
    MuiPaper: { styleOverrides: { root: { backgroundImage: 'none' } } },
    MuiTableCell: { styleOverrides: { root: { borderColor: mode === 'dark' ? '#383838' : '#d7dde5' }, head: { color: mode === 'dark' ? '#a5a5a5' : '#4b5563', fontWeight: 650, backgroundColor: mode === 'dark' ? '#292929' : '#eef1f5' } } },
    MuiTableRow: { styleOverrides: { root: { '&:hover': { backgroundColor: mode === 'dark' ? '#2a251f' : '#f3f6f9' } } } },
    MuiButton: { styleOverrides: { root: { textTransform: 'none', fontWeight: 600 } } },
  },
});

const getInitialMode = (): ThemeMode => localStorage.getItem('dbapulse-theme') === 'light' ? 'light' : 'dark';

function Root() {
  const [mode, setMode] = useState<ThemeMode>(getInitialMode);
  const theme = useMemo(() => buildTheme(mode), [mode]);
  const toggleTheme = () => setMode(current => {
    const next = current === 'dark' ? 'light' : 'dark';
    localStorage.setItem('dbapulse-theme', next);
    return next;
  });
  document.documentElement.dataset.theme = mode;
  return <ThemeProvider theme={theme}><CssBaseline /><App themeMode={mode} onToggleTheme={toggleTheme} /></ThemeProvider>;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><Root /></React.StrictMode>);