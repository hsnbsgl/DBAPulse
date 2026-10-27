import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { MouseEvent, ReactNode, SyntheticEvent } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import ServerWorkspace from './ServerWorkspace';

vi.mock('@mui/material', async () => {
  const React = await import('react');
  const passthrough = ({ children, ...props }: { children?: ReactNode; [key: string]: unknown }) => <div {...props}>{children}</div>;
  const Tabs = ({ children, value, onChange }: { children?: ReactNode; value: number; onChange?: (event: SyntheticEvent, value: number) => void }) => (
    <div role="tablist">
      {React.Children.map(children, (child, index) => React.isValidElement(child) ? React.cloneElement(child, {
        role: 'tab',
        'aria-selected': index === value,
        onClick: (event: MouseEvent) => onChange?.(event, index),
      }) : child)}
    </div>
  );
  const Tab = ({ label, ...props }: { label: string; [key: string]: unknown }) => <button type="button" {...props}>{label}</button>;
  return { Alert: passthrough, Box: passthrough, Button: passthrough, Chip: passthrough, Divider: passthrough, LinearProgress: passthrough, Paper: passthrough, Stack: passthrough, Table: passthrough, TableBody: passthrough, TableCell: passthrough, TableHead: passthrough, TableRow: passthrough, TableSortLabel: passthrough, Tabs, Tab, Typography: passthrough };
});
vi.mock('../common/Ui', () => ({
  EmptyState: ({ title }: { title: string }) => <div>{title}</div>,
  KpiCard: () => <div />,
  StatusChip: ({ value }: { value: string }) => <span>{value}</span>,
}));
vi.mock('../charts/DonutChart', () => ({ default: () => <div data-testid="donut-chart" /> }));
vi.mock('../charts/HorizontalBarChart', () => ({ default: () => <div data-testid="bar-chart" /> }));
vi.mock('../common/ListToolbar', () => ({
  ALL_RECORDS: -1,
  useListRefresh: () => undefined,
  default: () => <div />,
}));

const page = { items: [], totalCount: 0 };
const serverDetail = {
  server: {
    serverId: 1,
    serverName: 'SQL-01',
    instanceName: 'SQL-01',
    sqlVersion: 'SQL Server 2022',
    edition: 'Enterprise',
    databaseCount: 0,
    lastSeenAtUtc: '2026-10-12T10:00:00Z',
    anomalyTrackingEnabled: true,
  },
  databases: [],
};

const responseFor = (path: string) => {
  if (path === '/servers/1') return serverDetail;
  if (path.startsWith('/live/connections')) return { activeConnectionCount: 0, distinctApplicationCount: 0, applications: [] };
  if (path.startsWith('/live/who-is-active')) return [];
  if (path.startsWith('/performance/')) return [];
  if (path === '/management/health') return [];
  return page;
};

const fetchCallsFor = (mock: ReturnType<typeof vi.fn>, path: string) =>
  mock.mock.calls.filter(([request]) => String(request) === `/api${path}`);

describe('ServerWorkspace tab refresh', () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  let failingPath: string | undefined;
  let pendingPath: string | undefined;
  let releasePending: (() => void) | undefined;

  beforeEach(() => {
    failingPath = undefined;
    pendingPath = undefined;
    releasePending = undefined;
    fetchMock = vi.fn(async (request: RequestInfo | URL) => {
      const requestUrl = new URL(String(request), 'http://localhost');
      const path = requestUrl.pathname.replace(/^\/api/, '') + requestUrl.search;
      if (path === failingPath) return { ok: false, json: async () => ({}) };
      if (path === pendingPath) return await new Promise<{ ok: boolean; json: () => Promise<unknown> }>(resolve => { releasePending = () => resolve({ ok: true, json: async () => responseFor(path) }); });
      return { ok: true, json: async () => responseFor(path) };
    });
    vi.stubGlobal('fetch', fetchMock);
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it('refreshes Always On when its tab is opened without using the toolbar button', async () => {
    render(<ServerWorkspace serverId={1} onDatabase={() => undefined} />);

    await screen.findByRole('tab', { name: 'Always On' });
    expect(fetchCallsFor(fetchMock, '/availability/alwayson?serverId=1&page=1&pageSize=100')).toHaveLength(1);

    fireEvent.click(screen.getByRole('tab', { name: 'Always On' }));

    await waitFor(() => expect(fetchCallsFor(fetchMock, '/availability/alwayson?serverId=1&page=1&pageSize=100')).toHaveLength(2));
  });

  it.each([
    ['Protection', ['/protection/backups?serverId=1&page=1&pageSize=100']],
    ['Jobs', ['/jobs?serverId=1&page=1&pageSize=100']],
    ['Operations', ['/operations/events?serverId=1&page=1&pageSize=100']],
    ['Anomalies', ['/anomalies?serverId=1&page=1&pageSize=100']],
    ['Capacity', ['/capacity/databases?serverId=1&page=1&pageSize=100', '/capacity/volumes?serverId=1&page=1&pageSize=100']],
  ] as const)('refreshes %s lists when its tab is opened', async (_label, paths) => {
    render(<ServerWorkspace serverId={1} onDatabase={() => undefined} />);
    await screen.findByRole('tab', { name: 'Always On' });

    fireEvent.click(screen.getByRole('tab', { name: _label }));

    await waitFor(() => {
      for (const path of paths) expect(fetchCallsFor(fetchMock, path)).toHaveLength(2);
    });
  });

  it('refreshes all performance lists when the Performance tab is opened', async () => {
    render(<ServerWorkspace serverId={1} onDatabase={() => undefined} />);
    await screen.findByRole('tab', { name: 'Always On' });

    fireEvent.click(screen.getByRole('tab', { name: 'Performance' }));

    await waitFor(() => {
      expect(fetchCallsFor(fetchMock, '/performance/blocking?hours=24')).toHaveLength(2);
      expect(fetchCallsFor(fetchMock, '/performance/deadlocks?hours=24')).toHaveLength(2);
      expect(fetchCallsFor(fetchMock, '/performance/long-running?hours=24')).toHaveLength(2);
    });
  });

  it('refreshes a list again when returning to the tab', async () => {
    render(<ServerWorkspace serverId={1} onDatabase={() => undefined} />);
    await screen.findByRole('tab', { name: 'Always On' });

    fireEvent.click(screen.getByRole('tab', { name: 'Always On' }));
    await waitFor(() => expect(fetchCallsFor(fetchMock, '/availability/alwayson?serverId=1&page=1&pageSize=100')).toHaveLength(2));
    fireEvent.click(screen.getByRole('tab', { name: 'Databases' }));
    fireEvent.click(screen.getByRole('tab', { name: 'Always On' }));

    await waitFor(() => expect(fetchCallsFor(fetchMock, '/availability/alwayson?serverId=1&page=1&pageSize=100')).toHaveLength(3));
  });

  it('keeps the workspace visible when a background list refresh fails', async () => {
    render(<ServerWorkspace serverId={1} onDatabase={() => undefined} />);
    await screen.findByRole('tab', { name: 'Always On' });
    failingPath = '/performance/blocking?hours=24';

    fireEvent.click(screen.getByRole('tab', { name: 'Performance' }));

    await waitFor(() => expect(screen.getByText(/Some server telemetry could not be refreshed/)).toBeTruthy());
    expect(screen.getByRole('tab', { name: 'Performance' })).toBeTruthy();
  });

  it('shows a progress indicator while a tab list is refreshing', async () => {
    render(<ServerWorkspace serverId={1} onDatabase={() => undefined} />);
    await screen.findByRole('tab', { name: 'Always On' });
    pendingPath = '/availability/alwayson?serverId=1&page=1&pageSize=100';

    fireEvent.click(screen.getByRole('tab', { name: 'Always On' }));

    expect(await screen.findByText('Refreshing tab data…')).toBeTruthy();
    releasePending?.();
    await waitFor(() => expect(screen.queryByText('Refreshing tab data…')).toBeNull());
  });
});
