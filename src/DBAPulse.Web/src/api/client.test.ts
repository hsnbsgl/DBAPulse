import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, apiFetch, getJson, onUnauthorized, sendJson } from './client';

const respond = (status: number, body: unknown = {}) => vi.fn(async () => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }));

describe('api client', () => {
  afterEach(() => { vi.unstubAllGlobals(); onUnauthorized(undefined); });

  it('returns parsed JSON for successful responses', async () => {
    vi.stubGlobal('fetch', respond(200, { value: 1 }));
    await expect(getJson<{ value: number }>('/x')).resolves.toEqual({ value: 1 });
  });

  it('calls the unauthorized handler and throws a 401 ApiError', async () => {
    const handler = vi.fn();
    onUnauthorized(handler);
    vi.stubGlobal('fetch', respond(401));
    const error = await getJson('/servers').catch(value => value);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(401);
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it('notifies on 401 for raw (streaming) requests too', async () => {
    const handler = vi.fn();
    onUnauthorized(handler);
    vi.stubGlobal('fetch', respond(401));
    await expect(apiFetch('/servers/1/ai-summary/stream', { method: 'POST' })).rejects.toMatchObject({ status: 401 });
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it('throws a typed error with status for other failures without calling the handler', async () => {
    const handler = vi.fn();
    onUnauthorized(handler);
    vi.stubGlobal('fetch', respond(500, { message: 'Boom' }));
    await expect(sendJson('/settings/ai', 'PUT', { a: 1 })).rejects.toMatchObject({ name: 'ApiError', status: 500, message: 'Boom' });
    expect(handler).not.toHaveBeenCalled();
  });

  it('sends JSON bodies with a content type', async () => {
    const fetchMock = respond(200, { ok: true });
    vi.stubGlobal('fetch', fetchMock);
    await sendJson('/settings/retention', 'PUT', { cleanupIntervalHours: 24 });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/settings/retention');
    expect(init.method).toBe('PUT');
    expect(init.body).toBe(JSON.stringify({ cleanupIntervalHours: 24 }));
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('application/json');
  });

  it('unregistering stops notifications', async () => {
    const handler = vi.fn();
    const unregister = onUnauthorized(handler);
    unregister();
    vi.stubGlobal('fetch', respond(401));
    await expect(getJson('/x')).rejects.toBeInstanceOf(ApiError);
    expect(handler).not.toHaveBeenCalled();
  });
});
