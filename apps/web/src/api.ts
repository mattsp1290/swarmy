export type RunSummary = {
  run_id: string;
  repo_path: string;
  status: string;
  created_at: string;
  updated_at: string;
  latest_event_at: string;
  bead_count: number;
  active_bead_count: number;
  agent_count: number;
  event_count: number;
  latest_seq: number;
};

export type AgentSummary = {
  id: string;
  name: string;
  kind: string;
  created_at?: string;
  updated_at?: string;
  event_count?: number;
  last_event_at?: string;
};

export type BeadStage = {
  event_id: string;
  seq: number;
  occurred_at: string;
  stage: string;
  agent: AgentSummary | null;
  payload?: unknown;
};

export type BeadSummary = {
  id: string;
  title: string;
  status: string;
  status_source?: string;
  priority: number;
  issue_type: string;
  updated_at?: string;
  event_count?: number;
  last_event_at?: string;
  current_stage?: BeadStage | null;
  swarm_stage?: string;
};

export type RunError = {
  id: number;
  occurred_at: string;
  severity: string;
  message: string;
  context?: unknown;
};

export type RunDetail = RunSummary & {
  beads: BeadSummary[];
  agents: AgentSummary[];
  errors?: RunError[];
};

const authTokenStorageKey = 'swarmy.authToken';

/**
 * Raised when an API request fails. `isAuth` is true for HTTP 401 responses so
 * the UI can surface a distinct, actionable authentication panel.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly isAuth: boolean;

  constructor(message: string, status: number, isAuth: boolean) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.isAuth = isAuth;
  }
}

/**
 * Pure helper: extract the `swarmy_token` value from a location hash string and
 * return the hash with that parameter removed. No DOM access. The returned
 * `nextHash` never includes a leading `#`. `token` is `null` when the parameter
 * is absent (including an empty value, which is treated as "no token").
 */
export function parseTokenFromHash(rawHash: string): {
  token: string | null;
  nextHash: string;
} {
  const hash = rawHash.startsWith('#') ? rawHash.slice(1) : rawHash;
  const hashParams = new URLSearchParams(hash);
  const suppliedToken = hashParams.get('swarmy_token');
  if (suppliedToken === null) {
    return { token: null, nextHash: hashParams.toString() };
  }

  hashParams.delete('swarmy_token');
  const nextHash = hashParams.toString();
  return {
    token: suppliedToken.length > 0 ? suppliedToken : null,
    nextHash
  };
}

/**
 * Pure helper: build request headers for the API. Always includes the JSON
 * accept header; only attaches `X-Swarmy-Token` when a non-empty token exists.
 */
export function buildAuthHeaders(token: string): Record<string, string> {
  const headers: Record<string, string> = { accept: 'application/json' };
  if (token.length > 0) {
    headers['X-Swarmy-Token'] = token;
  }
  return headers;
}

function hashHasTokenParam(rawHash: string): boolean {
  const hash = rawHash.startsWith('#') ? rawHash.slice(1) : rawHash;
  return new URLSearchParams(hash).has('swarmy_token');
}

function readBrowserToken(): string {
  if (typeof window === 'undefined') {
    return '';
  }

  // A token param may be present but empty; presence (not just a non-empty
  // value) means we should strip it from the URL and update storage.
  if (hashHasTokenParam(window.location.hash)) {
    const { token, nextHash } = parseTokenFromHash(window.location.hash);
    try {
      if (token !== null) {
        window.localStorage.setItem(authTokenStorageKey, token);
      } else {
        window.localStorage.removeItem(authTokenStorageKey);
      }
    } catch {
      // localStorage can be unavailable in restricted browser contexts.
    }

    const nextUrl =
      window.location.pathname +
      window.location.search +
      (nextHash.length > 0 ? `#${nextHash}` : '');
    window.history.replaceState(null, '', nextUrl);
    return token ?? '';
  }

  try {
    return window.localStorage.getItem(authTokenStorageKey) ?? '';
  } catch {
    return '';
  }
}

/**
 * Returns true when a token is persisted in storage. Pure read with no side
 * effects (unlike readBrowserToken, which consumes/strips the URL hash), so it
 * is safe to call from reactive markup to tailor the auth-failure message.
 */
export function hasStoredToken(): boolean {
  if (typeof window === 'undefined') {
    return false;
  }
  try {
    return (window.localStorage.getItem(authTokenStorageKey) ?? '').length > 0;
  } catch {
    return false;
  }
}

function jsonHeaders(): Record<string, string> {
  return buildAuthHeaders(readBrowserToken());
}

export async function fetchRuns(): Promise<RunSummary[]> {
  const response = await fetch('/api/runs', {
    headers: jsonHeaders()
  });
  if (!response.ok) {
    const message =
      response.status === 401
        ? 'Local token required or rejected (401).'
        : `Run list request failed: ${response.status}`;
    throw new ApiError(message, response.status, response.status === 401);
  }

  const payload = (await response.json()) as { runs?: RunSummary[] };
  return payload.runs ?? [];
}

export async function fetchRunDetail(runId: string): Promise<RunDetail> {
  const response = await fetch(`/api/runs/${encodeURIComponent(runId)}`, {
    headers: jsonHeaders()
  });
  if (!response.ok) {
    const message =
      response.status === 401
        ? 'Local token required or rejected (401).'
        : `Run detail request failed: ${response.status}`;
    throw new ApiError(message, response.status, response.status === 401);
  }

  return (await response.json()) as RunDetail;
}
