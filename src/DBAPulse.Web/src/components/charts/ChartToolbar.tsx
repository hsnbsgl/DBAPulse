import { MenuItem, Select, Stack, Typography } from '@mui/material';

export const chartRanges = [24, 7, 30, 90] as const;
export type ChartRange = typeof chartRanges[number];

export default function ChartToolbar({ value, onChange, label = 'Range', ranges = chartRanges }: { value: ChartRange; onChange: (value: ChartRange) => void; label?: string; ranges?: readonly number[] }) {
  return <Stack direction="row" spacing={1} alignItems="center"><Typography variant="caption" color="text.secondary">{label}</Typography><Select size="small" value={value} onChange={event => onChange(Number(event.target.value) as ChartRange)} sx={{ minWidth: 92 }}>
    {ranges.map(range => <MenuItem key={range} value={range}>{range === 24 ? '24h' : `${range}d`}</MenuItem>)}
  </Select></Stack>;
}
