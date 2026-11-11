import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Alert, Box, Button, Paper, Stack, Typography } from '@mui/material';

type State = { error?: Error };

export default class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = {};

  static getDerivedStateFromError(error: Error): State { return { error }; }

  componentDidCatch(error: Error, info: ErrorInfo) { console.error('Unhandled UI error', error, info.componentStack); }

  render() {
    if (!this.state.error) return this.props.children;
    return <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center', p: 2 }}><Paper className="panel" sx={{ width: '100%', maxWidth: 520, p: 3 }}><Stack spacing={2}><Typography variant="h5">Something went wrong</Typography><Typography color="text.secondary">DBA Pulse hit an unexpected error while rendering this page.</Typography><Alert severity="error" sx={{ wordBreak: 'break-word' }}>{this.state.error.message || 'Unknown error'}</Alert><Stack direction="row" spacing={1}><Button variant="contained" onClick={() => window.location.reload()}>Reload</Button><Button variant="outlined" onClick={() => this.setState({ error: undefined })}>Try again</Button></Stack></Stack></Paper></Box>;
  }
}
