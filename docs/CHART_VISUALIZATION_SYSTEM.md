# DBA Pulse Chart & Visualization System

## Principles

Charts are analysis and navigation surfaces, not decoration. A chart should explain change, time, magnitude, trend direction, affected resources, or forecast timing. The current implementation stays within the existing React/TypeScript/Vite/Material UI and Apache ECharts stack.

## Common infrastructure

The shared chart components are under `src/DBAPulse.Web/src/components/charts`:

- `BaseChart` applies the shared transparent dark canvas, ECharts renderer, lazy updates, and responsive container.
- `TimeSeriesChart` provides common axes, tooltip styling, legend toggling, inside/slider data zoom for longer series, and actual/area series support.
- `ForecastChart` keeps actual data solid and forecast data dashed. Forecast series are only rendered when the API supplies forecast values.
- `HorizontalBarChart` is used for ranked waits and similar top-N analysis.
- `DonutChart` is reserved for composition, not time trends.
- `ChartToolbar` provides the shared 24h/7d/30d/90d range vocabulary.
- `ChartEmptyState` distinguishes no telemetry and insufficient history from API failures.

## Semantic palette

Actual/info uses blue, healthy/success green, warning amber, critical red, forecast purple/secondary dashed lines, and unknown/insufficient data muted gray. Status labels remain visible so color is not the only signal.

## Existing integrations

- Database detail capacity history uses a shared time-series chart for Data, Log, and Total size.
- Capacity detail uses `ForecastChart`; the current lab's insufficient history does not draw synthetic forecast lines.
- Performance Top Waits uses a shared horizontal bar chart with the existing ten-row pagination. Excluded wait types remain absent from the API response and raw telemetry is untouched.
- Existing chart areas use neutral empty states for zero observations, no telemetry, and insufficient history.

## Tooltip, time, and units

The application keeps UTC in the API and uses the existing `Europe/Istanbul` display helper for chart categories. Capacity charts label their axis as MiB and use readable values in tooltip/configuration. Duration remains milliseconds in the current API display.

## Zoom, legend, and resize

Longer time-series datasets receive ECharts inside and slider data zoom controls. Multi-series legends remain interactive and can hide/show a series. `echarts-for-react` owns the responsive instance lifecycle; the wrapper is lazy and the container is width-constrained so sidebar/grid changes do not overflow.

## Zero, null, and insufficient data

Zero observations are rendered as an explanatory empty state, such as “No deadlocks observed”. Missing telemetry is not rendered as zero. `InsufficientData` is shown as a neutral message and does not produce a dotted or invented forecast.

## Drill-down

Existing table-to-detail navigation remains intact. Chart click handlers are available in the reusable bar component for future API-backed drill-downs; no new route or backend contract was invented in this frontend-only change.

## Backend data gaps

The current API does not expose the following historical series, so no fake chart was added:

1. Wait trend: requires a historical wait-delta series endpoint.
2. Blocking/deadlock/long-running trend: current endpoints expose recent observations, not a time-bucketed history endpoint.
3. Backup timeline: requires backup history grouped by database and backup type.
4. Always On topology/queue trend: current API exposes current replica rows, not historical relationships/queue series.
5. SQL Agent failure/duration trend: current API exposes current job health rows, not execution history series.
6. Volume growth trend and top-growing database chart: require historical volume/database growth data in a chart-friendly endpoint.

These are backend data gaps, not frontend fallbacks. Existing tables and empty states remain the source of truth until those endpoints exist.

## Performance and accessibility

Charts are limited to meaningful views, use compact legends and muted grids, and keep a textual table or KPI nearby. No additional chart library, synthetic production data, ML, or forecast calculation was introduced.
