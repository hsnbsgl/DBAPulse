# DBA Pulse UI Design System

## Scope

Phase UI redesign is presentation-only. Existing API endpoints, routes, data-fetching, and business rules remain unchanged. The interface renders the real DBA Pulse response and keeps `Unknown`, `InsufficientData`, `NotConfigured`, and empty collections distinct from API errors.

## Visual language

DBA Pulse uses a dark navy/charcoal enterprise palette: `#08111f` for the application background, `#101b2d` for surfaces, `#20324b` for borders, and a restrained blue accent for navigation and focus. Cards use subtle borders and no heavy shadows. The layout is optimized for desktop operations work at 1280px and above and collapses the navigation to an icon rail on narrow screens.

## Typography and spacing

Inter/Roboto is used through the MUI theme. The visual hierarchy is intentionally compact: page titles are approximately 26px, section titles 16px, KPI values 27px, body text 13–14px, and table text 12–13px. Spacing follows an 8px base rhythm and surfaces use 8px corner radii.

## Reusable components

- `AppShell`: shared sidebar, top bar, identity/timezone context, and content frame.
- `KpiCard`: consistent executive metric presentation.
- `StatusChip`: shared semantic rendering for health, protection, collection, event, and forecast states.
- `EmptyState`: neutral presentation for no telemetry, NotConfigured, and insufficient history.
- `SectionCard`: shared panel heading and surface treatment.
- `LoadingState`, `ErrorState`, and `FreshnessIndicator`: shared state vocabulary for future page extraction.

These components live under `src/components` and are consumed without changing backend contracts.

## Status semantics

Green is used for healthy/success/protected states, amber for warning or partial states, red for critical/failed states, blue for active/running information, and neutral gray for unknown, not configured, or insufficient data. Status text is always rendered with the chip label; color is not the sole signal.

## Tables and charts

Tables use dark headers, subtle row separators, compact density, and hover feedback. Technical identifiers may use the browser's compact monospace rendering only where appropriate. ECharts charts keep a transparent background, muted axes, restrained grid lines, dark tooltips, and explicit legends. Forecast series must remain visually distinct from actual telemetry.

## Formatting

The existing frontend timezone and API formatting helpers remain authoritative: API timestamps are UTC and are displayed in `Europe/Istanbul`. Capacity values continue to use the existing API units; new UI surfaces must not invent values when a field is absent.

## Responsive behavior

The desktop cockpit keeps a 244px navigation rail and dense content area. Below 1100px, grids reduce their columns; below 760px, the sidebar becomes an icon rail, tables retain horizontal scrollability, and cards use a two-column metric layout.

## Empty, loading, and error states

Loading indicates an in-flight request. API errors are shown as errors. Empty data is neutral and explanatory: no volume telemetry, no SQL Agent jobs, Always On not configured, or insufficient forecast history are not presented as failures.

## Backend boundary

No database, migration, stored procedure, collector, API endpoint, operational event rule, or forecast algorithm was changed for this redesign. No fake telemetry or reference screenshot values are embedded in the UI.
