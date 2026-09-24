import React from 'react';
import { createRoot } from 'react-dom/client';
import { CssBaseline } from '@mui/material';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import App from './App';
import './theme.css';

const theme = createTheme({
  palette: {
    mode: 'dark',
    primary: { main: '#f08a24' },
    secondary: { main: '#9c9c9c' },
    background: { default: '#151515', paper: '#202020' },
    text: { primary: '#f2f2f2', secondary: '#a9a9a9' },
    divider: '#383838',
    success: { main: '#46c878' },
    warning: { main: '#e0a53a' },
    error: { main: '#ed6262' },
    info: { main: '#6ea7d8' },
  },
  typography: { fontFamily: 'Inter, Roboto, Arial, sans-serif', h4: { fontSize: '1.65rem', fontWeight: 700 }, h6: { fontSize: '1rem', fontWeight: 650 }, body2: { fontSize: '0.82rem' } },
  shape: { borderRadius: 8 },
  components: {
    MuiPaper: { styleOverrides: { root: { backgroundImage: 'none' } } },
    MuiTableCell: { styleOverrides: { root: { borderColor: '#20324b' }, head: { color: '#8fa2bd', fontWeight: 650, backgroundColor: '#0d1829' } } },
    MuiTableRow: { styleOverrides: { root: { '&:hover': { backgroundColor: '#14253c' } } } },
    MuiButton: { styleOverrides: { root: { textTransform: 'none', fontWeight: 600 } } },
  },
});

createRoot(document.getElementById('root')!).render(<React.StrictMode><ThemeProvider theme={theme}><CssBaseline /><App /></ThemeProvider></React.StrictMode>);
