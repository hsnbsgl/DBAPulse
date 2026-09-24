import type { CSSProperties } from 'react';
import ReactECharts from 'echarts-for-react';
import { Box, Skeleton } from '@mui/material';
import { baseChartOption } from './chartTheme';

export default function BaseChart({ option, height = 300, loading = false, onEvents }: { option: Record<string, unknown>; height?: number; loading?: boolean; onEvents?: Record<string, (params: unknown) => void> }) {
  const style: CSSProperties = { height, width: '100%' };
  if (loading) return <Skeleton variant="rounded" animation="wave" sx={{ height, width: '100%', transform: 'none' }} />;
  return <Box className="chart-container"><ReactECharts option={{ ...baseChartOption, ...option }} style={style} opts={{ renderer: 'canvas' }} notMerge lazyUpdate onEvents={onEvents} /></Box>;
}
