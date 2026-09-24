import BaseChart from './BaseChart';
import { axisStyle, chartColors, tooltipStyle } from './chartTheme';

export type ChartSeries = { name: string; data: Array<number | null>; color?: string; type?: 'line' | 'bar'; dashed?: boolean; area?: boolean };

export default function TimeSeriesChart({ categories, series, height = 320, yAxisName, loading = false, tooltipFormatter }: { categories: string[]; series: ChartSeries[]; height?: number; yAxisName?: string; loading?: boolean; tooltipFormatter?: (params: unknown[]) => string }) {
  const option = {
    tooltip: { trigger: 'axis', ...tooltipStyle, formatter: tooltipFormatter },
    legend: { type: 'scroll', top: 0, right: 0, textStyle: { color: chartColors.text, fontSize: 11 } },
    xAxis: { type: 'category', data: categories, ...axisStyle },
    yAxis: { type: 'value', name: yAxisName, ...axisStyle },
    dataZoom: categories.length > 12 ? [{ type: 'inside', throttle: 80 }, { type: 'slider', height: 16, bottom: 4, borderColor: chartColors.grid, fillerColor: 'rgba(240,138,36,.18)', textStyle: { color: chartColors.text } }] : [],
    series: series.map(item => ({ name: item.name, type: item.type || 'line', data: item.data, smooth: true, symbol: 'none', symbolSize: 4, itemStyle: { color: item.color || chartColors.actual }, lineStyle: { color: item.color || chartColors.actual, type: item.dashed ? 'dashed' : 'solid', width: 1.8 }, areaStyle: item.area ? { opacity: 0.12, color: item.color || chartColors.actual } : undefined })),
  };
  return <BaseChart option={option} height={height} loading={loading} />;
}
