export type RunSummary = {
  run_id: string;
  repo_path: string;
  status: string;
  created_at: string;
  updated_at: string;
  latest_event_at: string;
  bead_count: number;
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

export async function fetchRuns(): Promise<RunSummary[]> {
  const response = await fetch('/api/runs', {
    headers: { accept: 'application/json' }
  });
  if (!response.ok) {
    throw new Error(`Run list request failed: ${response.status}`);
  }

  const payload = (await response.json()) as { runs?: RunSummary[] };
  return payload.runs ?? [];
}

export async function fetchRunDetail(runId: string): Promise<RunDetail> {
  const response = await fetch(`/api/runs/${encodeURIComponent(runId)}`, {
    headers: { accept: 'application/json' }
  });
  if (!response.ok) {
    throw new Error(`Run detail request failed: ${response.status}`);
  }

  return (await response.json()) as RunDetail;
}
