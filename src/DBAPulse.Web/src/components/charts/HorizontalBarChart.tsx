import BaseChart from './BaseChart';
import { axisStyle, chartColors, tooltipStyle } from './chartTheme';

export default function HorizontalBarChart({ labels, values, color = chartColors.info, height = 280, valueName = 'Value', onClick }: { labels: string[]; values: number[]; color?: string; height?: number; valueName?: string; onClick?: (index: number) => void }) {
  const option = { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, ...tooltipStyle }, grid: { top: 12, right: 28, bottom: 28, left: 110, containLabel: true }, xAxis: { type: 'value', name: valueName, ...axisStyle }, yAxis: { type: 'category', inverse: true, data: labels, ...axisStyle }, series: [{ name: valueName, type: 'bar', data: values, barMaxWidth: 18, itemStyle: { color, borderRadius: [0, 3, 3, 0] } }] };
  return <BaseChart option={option} height={height} onEvents={onClick ? { click: params => { const item = params as { dataIndex?: number }; if (item.dataIndex != null) onClick(item.dataIndex); } } : undefined} />;
}
