export const chartColors = {
  actual: '#63a4ff',
  forecast: '#a78bfa',
  success: '#4dcc8a',
  warning: '#e9aa4c',
  critical: '#ed6a75',
  info: '#63a4ff',
  muted: '#7186a4',
  grid: '#20324b',
  text: '#8fa2bd',
  panel: '#101b2d',
};

export const chartFont = 'Inter, Roboto, Arial, sans-serif';

export const baseChartOption = {
  backgroundColor: 'transparent',
  textStyle: { fontFamily: chartFont, color: chartColors.text },
  grid: { top: 28, right: 24, bottom: 42, left: 58, containLabel: true },
  animationDuration: 350,
};

export const axisStyle = {
  axisLine: { lineStyle: { color: chartColors.grid } },
  axisTick: { show: false },
  axisLabel: { color: chartColors.text, fontSize: 11 },
  splitLine: { lineStyle: { color: chartColors.grid, opacity: 0.65 } },
};

export const tooltipStyle = {
  backgroundColor: chartColors.panel,
  borderColor: chartColors.grid,
  textStyle: { color: '#e8eef8', fontFamily: chartFont, fontSize: 12 },
  extraCssText: 'box-shadow: 0 8px 24px rgba(0,0,0,.28);',
};

export const formatChartValue = (value: number, unit = '') => {
  if (!Number.isFinite(value)) return '—';
  const abs = Math.abs(value);
  const formatted = abs >= 1024 * 1024 ? `${(value / (1024 * 1024)).toFixed(1)} GiB` : abs >= 1024 ? `${(value / 1024).toFixed(1)} GiB` : `${value.toLocaleString('en-US', { maximumFractionDigits: 1 })} ${unit}`.trim();
  return formatted;
};
