import React from 'react';
import { createRoot } from 'react-dom/client';
import { CssBaseline } from '@mui/material';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import App from './App';
import './theme.css';

const theme = createTheme({
  palette: {
    mode: 'dark',
    primary: { main: '#5b9bf8' },
    secondary: { main: '#7d8fb2' },
    background: { default: '#08111f', paper: '#101b2d' },
    text: { primary: '#e8eef8', secondary: '#8fa2bd' },
    divider: '#20324b',
    success: { main: '#4dcc8a' },
    warning: { main: '#e9aa4c' },
    error: { main: '#ed6a75' },
    info: { main: '#63a4ff' },
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
