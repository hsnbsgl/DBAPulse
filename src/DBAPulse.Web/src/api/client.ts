export const apiBase: string = import.meta.env.VITE_API_BASE_URL || '/api';

export class ApiError extends Error {
  readonly status: number;
  readonly body: unknown;
  constructor(message: string, status: number, body?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.body = body;
  }
}

let unauthorizedHandler: (() => void) | undefined;

/** Registers the handler invoked whenever the API answers 401 (expired or missing session). Returns an unregister function. */
export const onUnauthorized = (handler: (() => void) | undefined) => {
  unauthorizedHandler = handler;
  return () => { if (unauthorizedHandler === handler) unauthorizedHandler = undefined; };
};

const readBody = async (response: Response): Promise<unknown> => {
  try { return await response.json(); } catch { return undefined; }
};

/** Low-level fetch against the API base. Notifies the unauthorized handler and throws on 401; other statuses are returned as-is (useful for streaming). */
export const apiFetch = async (path: string, init?: RequestInit): Promise<Response> => {
  const response = await fetch(`${apiBase}${path}`, init);
  if (response.status === 401) {
    unauthorizedHandler?.();
    throw new ApiError('Your session has expired. Please sign in again.', 401);
  }
  return response;
};

const ensureOk = async (response: Response) => {
  if (response.ok) return;
  const body = await readBody(response);
  const detail = body && typeof body === 'object' ? (body as { message?: unknown; detail?: unknown; title?: unknown }) : undefined;
  const message = [detail?.message, detail?.detail, detail?.title].find(value => typeof value === 'string' && value) as string | undefined;
  throw new ApiError(message || `API request failed (${response.status})`, response.status, body);
};

export const getJson = async <T,>(path: string, init?: RequestInit): Promise<T> => {
  const response = await apiFetch(path, init);
  await ensureOk(response);
  return response.json() as Promise<T>;
};

export const sendJson = async <T = unknown,>(path: string, method: 'POST' | 'PUT' | 'PATCH' | 'DELETE', body?: unknown, init?: RequestInit): Promise<T> => {
  const response = await apiFetch(path, {
    ...init,
    method,
    headers: body === undefined ? init?.headers : { 'Content-Type': 'application/json', ...init?.headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  await ensureOk(response);
  if (response.status === 204) return undefined as T;
  return await readBody(response) as T;
};

export const errorMessage = (error: unknown, fallback: string) => error instanceof Error && error.message ? error.message : fallback;
