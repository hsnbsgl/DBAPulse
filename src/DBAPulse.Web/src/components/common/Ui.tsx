import type { ReactNode } from 'react';
import { Alert, Box, Card, CardContent, Chip, CircularProgress, Paper, Skeleton, Stack, Typography } from '@mui/material';

const labelFor = (value: string) => value.replace(/([a-z])([A-Z])/g, '$1 $2');

const toneFor = (value: string): 'success' | 'warning' | 'error' | 'info' | 'default' => {
  if (['Healthy', 'Protected', 'Success', 'Succeeded', 'ONLINE'].includes(value)) return 'success';
  if (['Critical', 'Failed', 'Offline', 'SUSPECT'].includes(value)) return 'error';
  if (['Warning', 'PartialSuccess', 'LowFit'].includes(value)) return 'warning';
  if (['Active', 'Running', 'Info'].includes(value)) return 'info';
  return 'default';
};

export function StatusChip({ value }: { value: string }) {
  return <Chip size="small" variant="outlined" color={toneFor(value)} label={labelFor(value)} className={`status-chip status-${value.toLowerCase()}`} />;
}

export function KpiCard({ title, value, subtitle, icon, tone, loading }: { title: string; value: ReactNode; subtitle?: ReactNode; icon?: ReactNode; tone?: 'success' | 'warning' | 'error' | 'info'; loading?: boolean }) {
  return <Card className="metric"><CardContent>
    <Stack direction="row" justifyContent="space-between" alignItems="flex-start" spacing={1}>
      <Typography className="kpi-label" variant="overline">{title}</Typography>
      {icon && <Box className="kpi-icon">{icon}</Box>}
    </Stack>
    {loading ? <Skeleton width="65%" height={44} /> : <Typography className="kpi-value" color={tone ? `${tone}.main` : 'text.primary'}>{value}</Typography>}
    {subtitle && <Typography className="kpi-subtitle" color="text.secondary">{subtitle}</Typography>}
  </CardContent></Card>;
}

export function PageHeader({ title, subtitle, icon, actions }: { title: string; subtitle?: string; icon?: ReactNode; actions?: ReactNode }) {
  return <Stack className="page-header" direction="row" justifyContent="space-between" alignItems="flex-start" spacing={2}>
    <Stack direction="row" spacing={1.5} alignItems="flex-start">
      {icon && <Box className="page-icon">{icon}</Box>}
      <Box><Typography variant="h4">{title}</Typography>{subtitle && <Typography color="text.secondary">{subtitle}</Typography>}</Box>
    </Stack>
    {actions && <Box>{actions}</Box>}
  </Stack>;
}

export function SectionCard({ title, subtitle, actions, children }: { title: string; subtitle?: string; actions?: ReactNode; children: ReactNode }) {
  return <Paper className="panel section-card"><Stack direction="row" justifyContent="space-between" alignItems="flex-start" spacing={2} className="section-heading"><Box><Typography variant="h6">{title}</Typography>{subtitle && <Typography variant="body2" color="text.secondary">{subtitle}</Typography>}</Box>{actions}</Stack>{children}</Paper>;
}

export function EmptyState({ title, description, icon }: { title: string; description?: string; icon?: ReactNode }) {
  return <Box className="empty-state">{icon && <Box className="empty-icon">{icon}</Box>}<Typography variant="subtitle1">{title}</Typography>{description && <Typography variant="body2" color="text.secondary">{description}</Typography>}</Box>;
}

export function LoadingState({ rows = false }: { rows?: boolean }) {
  return rows ? <Stack spacing={1.5}>{Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} variant="rounded" height={34} />)}</Stack> : <Stack spacing={1}><Skeleton variant="rounded" height={28} width="32%" /><Skeleton variant="rounded" height={52} width="100%" /></Stack>;
}

export function ErrorState({ message }: { message: string }) { return <Alert severity="error">{message}</Alert>; }

export function FreshnessIndicator({ value }: { value?: string | null }) {
  if (!value) return <Typography variant="caption" color="text.secondary">Last updated: —</Typography>;
  return <Typography variant="caption" color="text.secondary">Last updated: {value}</Typography>;
}

export function Spinner() { return <Box className="loading-state"><CircularProgress size={26} /></Box>; }
