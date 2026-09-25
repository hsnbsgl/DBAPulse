import BaseChart from './BaseChart';
import { chartColors, tooltipStyle } from './chartTheme';
import { Box } from '@mui/material';

export default function DonutChart({ items, height = 250 }: { items: Array<{ name: string; value: number; color?: string }>; height?: number }) {
  const option = { tooltip: { trigger: 'item', ...tooltipStyle }, legend: { bottom: 0, type: 'scroll', textStyle: { color: chartColors.text, fontSize: 11 } }, series: [{ type: 'pie', radius: ['52%', '76%'], center: ['50%', '43%'], avoidLabelOverlap: true, label: { show: false }, itemStyle: { borderColor: chartColors.panel, borderWidth: 2 }, data: items.map(item => ({ ...item, itemStyle: { color: item.color } })) }] };
  return <Box sx={{ width: '100%', maxWidth: 380, mx: 'auto' }}><BaseChart option={option} height={height} /></Box>;
}
