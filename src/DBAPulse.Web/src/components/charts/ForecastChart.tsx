import TimeSeriesChart, { type ChartSeries } from './TimeSeriesChart';
import { chartColors } from './chartTheme';

export default function ForecastChart({ categories, actual, forecast30, forecast90, height = 340 }: { categories: string[]; actual: Array<number | null>; forecast30?: Array<number | null>; forecast90?: Array<number | null>; height?: number }) {
  const series: ChartSeries[] = [{ name: 'Actual', data: actual, color: chartColors.actual }];
  if (forecast30?.some(value => value != null)) series.push({ name: 'Forecast 30d', data: forecast30, color: chartColors.forecast, dashed: true });
  if (forecast90?.some(value => value != null)) series.push({ name: 'Forecast 90d', data: forecast90, color: chartColors.warning, dashed: true });
  return <TimeSeriesChart categories={categories} series={series} height={height} yAxisName="Size" />;
}
