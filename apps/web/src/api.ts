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

export type RunEvent = {
  event_id: string;
  seq: number;
  occurred_at: string;
  source: string;
  event_type: string;
  bead_id: string | null;
  stage: string | null;
  agent: { id: string; name: string; kind: string } | null;
  payload?: unknown;
};

export type RunEventsPage = {
  run_id: string;
  events: RunEvent[];
  next_cursor: number;
  has_more: boolean;
  latest_seq: number;
};

export type ReviewVerdict = {
  reviewer: string;
  verdict: string;
  artifact?: string;
};

export type IterationHealth = {
  iteration: number;
  branch: string;
  status: string;
  execution_mode: string;
  degraded_reason: string;
  review_mode: string;
  review_assurance: string;
  findings_fixed_re_reviewed: boolean;
  validation_passed: boolean;
  reviews: ReviewVerdict[];
  review_blocker_summary: string[];
};

export type RunHealthSummary = {
  run_id: string;
  last_iteration: number;
  last_branch: string;
  status: string;
  execution_mode: string;
  degraded_reason: string;
  review_mode: string;
  reviews: ReviewVerdict[];
  latest_validation: { passed: boolean; entries: string[] };
  unresolved_risks: string[];
};

export type RunHealth = {
  run_id: string;
  summary: RunHealthSummary;
  iterations: IterationHealth[];
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

/**
 * Fetch a page of run-scoped events using the cursor endpoint. `after` is the
 * exclusive seq cursor (events with seq > after are returned, ascending).
 */
export async function fetchRunEvents(
  runId: string,
  after = 0,
  limit?: number
): Promise<RunEventsPage> {
  let url = `/api/runs/${encodeURIComponent(runId)}/events?after=${after}`;
  if (limit !== undefined) {
    url += `&limit=${limit}`;
  }

  const response = await fetch(url, {
    headers: jsonHeaders()
  });
  if (!response.ok) {
    const message =
      response.status === 401
        ? 'Local token required or rejected (401).'
        : `Run events request failed: ${response.status}`;
    throw new ApiError(message, response.status, response.status === 401);
  }

  return (await response.json()) as RunEventsPage;
}

/**
 * Pure helper: compute the `after` cursor to fetch roughly the last
 * `windowSize` events given the run's latest seq. Guards against NaN/negative
 * latestSeq by clamping to 0.
 */
export function recentEventsCursor(latestSeq: number, windowSize: number): number {
  if (!Number.isFinite(latestSeq) || latestSeq < 0) {
    return 0;
  }
  return Math.max(0, latestSeq - windowSize);
}

/**
 * Pure helper: merge a freshly-fetched ascending-seq page of events into an
 * existing newest-first list. `incoming` arrives in ASCENDING seq order; it is
 * reversed and prepended ahead of `existing` so the combined list stays
 * newest-first. Events are deduped by `event_id` (the first/newest occurrence
 * wins) and the result is capped to `cap` items, dropping the oldest beyond the
 * cap. Returns a new array; inputs are not mutated.
 */
export function mergeRecentEvents(
  existing: RunEvent[],
  incoming: RunEvent[],
  cap: number
): RunEvent[] {
  const incomingNewestFirst = incoming.slice().reverse();
  const combined = incomingNewestFirst.concat(existing);

  const seen = new Set<string>();
  const deduped: RunEvent[] = [];
  for (const event of combined) {
    if (seen.has(event.event_id)) {
      continue;
    }
    seen.add(event.event_id);
    deduped.push(event);
  }

  if (cap >= 0 && deduped.length > cap) {
    return deduped.slice(0, cap);
  }
  return deduped;
}

/**
 * Fetch the review/run-health surface for a run: the compact summary manifest
 * plus per-iteration review verdicts and degraded-review signals.
 */
export async function fetchRunHealth(runId: string): Promise<RunHealth> {
  const response = await fetch(
    `/api/runs/${encodeURIComponent(runId)}/health`,
    { headers: jsonHeaders() }
  );
  if (!response.ok) {
    const message =
      response.status === 401
        ? 'Local token required or rejected (401).'
        : `Run health request failed: ${response.status}`;
    throw new ApiError(message, response.status, response.status === 401);
  }

  return (await response.json()) as RunHealth;
}

/** Pure helper: the most recent iteration's health, or null when none exist. */
export function latestIterationHealth(h: RunHealth): IterationHealth | null {
  return h.iterations.length > 0 ? h.iterations[h.iterations.length - 1] : null;
}

/**
 * Pure helper: the distinct review verdicts recorded for the latest iteration,
 * in the order reviewers reported them (e.g. ['APPROVE'] or ['REQUEST_CHANGES']).
 */
export function lastReviewVerdicts(h: RunHealth): string[] {
  const iteration = latestIterationHealth(h);
  return iteration ? iteration.reviews.map((r) => r.verdict) : [];
}

/**
 * Pure helper: true when the latest iteration has a REQUEST_CHANGES verdict that
 * has not yet been fixed-and-re-reviewed (the `findings_fixed_re_reviewed`
 * positive signal). This is the "outstanding REQUEST_CHANGES" condition.
 */
export function hasOutstandingRequestChanges(h: RunHealth): boolean {
  const iteration = latestIterationHealth(h);
  if (!iteration) {
    return false;
  }
  const requested = iteration.reviews.some(
    (r) => r.verdict === 'REQUEST_CHANGES'
  );
  return requested && !iteration.findings_fixed_re_reviewed;
}

/**
 * Pure helper: the degraded-REVIEW state label for the latest iteration, or null
 * when the review ran normally. This is derived from the review-assurance signal
 * (`review_assurance`), NOT from `execution_mode`: a degraded *orchestration*
 * mode like `parent-degraded` (orchestrator wrote the change directly) is a
 * normal review and must not be labelled a degraded review — see the guidance in
 * `BeadSwarmGuidance` and docs/LOOPS.md. A non-`normal` `review_assurance` maps
 * to one of the canonical degraded-review states (e.g. `local_fallback`,
 * `reviewers_unavailable`).
 */
export function degradedReviewState(h: RunHealth): string | null {
  const iteration = latestIterationHealth(h);
  if (!iteration) {
    return null;
  }
  const assurance = (iteration.review_assurance ?? '').trim();
  if (assurance.length > 0 && assurance.toLowerCase() !== 'normal') {
    return assurance;
  }
  return null;
}

/** Pure helper: true when an event marks a bead entering the blocked stage. */
export function isBlockedEvent(e: RunEvent): boolean {
  return e.stage === 'blocked';
}

/**
 * Pure helper: human label for the source agent of an event. Falls back to the
 * event `source` string when no agent is attached.
 */
export function eventActor(e: RunEvent): string {
  return e.agent
    ? e.agent.kind
      ? `${e.agent.name} / ${e.agent.kind}`
      : e.agent.name
    : e.source;
}
