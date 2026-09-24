export const chartColors = {
  actual: '#f08a24',
  forecast: '#6ea7d8',
  success: '#46c878',
  warning: '#e0a53a',
  critical: '#ed6262',
  info: '#6ea7d8',
  muted: '#858585',
  grid: '#3a3a3a',
  text: '#a9a9a9',
  panel: '#202020',
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
