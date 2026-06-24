<script lang="ts">
  import { onMount } from 'svelte';
  import {
    ApiError,
    fetchRunDetail,
    fetchRunEvents,
    fetchRuns,
    hasStoredToken,
    recentEventsCursor,
    mergeRecentEvents,
    isBlockedEvent,
    eventActor,
    type BeadSummary,
    type RunDetail,
    type RunEvent,
    type RunSummary
  } from './api';

  const POLL_INTERVAL_MS = 5000;
  const RECENT_EVENTS_CAP = 50;

  const stages = ['coding', 'validation', 'review', 'merge', 'blocked', 'complete', 'unknown'];
  const stageLabels: Record<string, string> = {
    coding: 'Coding',
    validation: 'Validation',
    review: 'Review',
    merge: 'Merge',
    blocked: 'Blocked',
    complete: 'Complete',
    unknown: 'Unknown',
    unassigned: 'Unassigned'
  };

  let runs: RunSummary[] = [];
  let selectedRunId = '';
  let selectedRun: RunDetail | null = null;
  let loadingRuns = true;
  let loadingDetail = false;
  let error = '';
  let authError = false;
  let detailRequest = 0;
  let recentEvents: RunEvent[] = [];
  let loadingEvents = false;
  let eventsError = '';
  let eventsCursor = 0;
  let pollFailed = false;

  const repoName = (path: string) => {
    const normalized = path.replace(/\\/g, '/');
    const parts = normalized.split('/').filter(Boolean);
    return parts.at(-1) ?? path;
  };

  const activityLabel = (run: RunSummary | RunDetail) =>
    run.latest_event_at || run.updated_at || run.created_at || 'no activity';

  const parseTime = (value: string) => {
    const time = Date.parse(value);
    return Number.isNaN(time) ? 0 : time;
  };

  const relativeTime = (value: string) => {
    const time = parseTime(value);
    if (time === 0) {
      return 'unknown';
    }

    const seconds = Math.max(0, Math.floor((Date.now() - time) / 1000));
    if (seconds < 60) {
      return `${seconds}s`;
    }

    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) {
      return `${minutes}m`;
    }

    const hours = Math.floor(minutes / 60);
    if (hours < 48) {
      return `${hours}h`;
    }

    return `${Math.floor(hours / 24)}d`;
  };

  const activeBeadCount = (run: RunSummary | RunDetail) => {
    if ('beads' in run) {
      return run.beads.filter((bead) => bead.status !== 'closed').length;
    }

    return run.active_bead_count;
  };

  const stageFor = (bead: BeadSummary) =>
    bead.current_stage?.stage ?? bead.swarm_stage ?? 'unassigned';

  const beadsForStage = (stage: string) =>
    selectedRun?.beads.filter((bead) => stageFor(bead) === stage) ?? [];

  const agentName = (bead: BeadSummary) => bead.current_stage?.agent?.name ?? '';

  const agentKind = (bead: BeadSummary) => bead.current_stage?.agent?.kind ?? '';

  const unassignedBeads = () =>
    selectedRun?.beads.filter((bead) => !stages.includes(stageFor(bead))) ?? [];

  const blockedEvents = () => recentEvents.filter((event) => isBlockedEvent(event));

  const hasFailures = () =>
    (selectedRun?.errors?.length ?? 0) > 0 || blockedEvents().length > 0;

  const selectRun = async (runId: string) => {
    const requestId = detailRequest + 1;
    detailRequest = requestId;
    selectedRunId = runId;
    selectedRun = null;
    loadingDetail = true;
    error = '';
    authError = false;
    recentEvents = [];
    eventsError = '';
    loadingEvents = true;

    try {
      const detail = await fetchRunDetail(runId);
      if (detailRequest === requestId && selectedRunId === runId) {
        selectedRun = detail;
      }
    } catch (caught) {
      if (detailRequest === requestId && selectedRunId === runId) {
        error = caught instanceof Error ? caught.message : 'Run detail request failed';
        authError = caught instanceof ApiError && caught.isAuth;
      }
    } finally {
      if (detailRequest === requestId) {
        loadingDetail = false;
      }
    }

    // A timeline fetch failure must never blank the whole detail pane, so this
    // runs after the detail is settled and only touches the events-scoped
    // state. Skip entirely if the detail load did not succeed for this request.
    if (detailRequest !== requestId || selectedRunId !== runId || !selectedRun) {
      if (detailRequest === requestId) {
        loadingEvents = false;
      }
      return;
    }

    try {
      const after = recentEventsCursor(selectedRun.latest_seq, RECENT_EVENTS_CAP);
      const page = await fetchRunEvents(runId, after);
      if (detailRequest === requestId && selectedRunId === runId) {
        recentEvents = page.events.slice().reverse();
        eventsCursor = page.latest_seq;
      }
    } catch (caught) {
      if (detailRequest === requestId && selectedRunId === runId) {
        eventsError =
          caught instanceof Error ? caught.message : 'Run events request failed';
      }
    } finally {
      if (detailRequest === requestId) {
        loadingEvents = false;
      }
    }
  };

  const loadRuns = async () => {
    loadingRuns = true;
    error = '';
    authError = false;

    try {
      runs = await fetchRuns();
      if (runs.length === 0) {
        detailRequest += 1;
        selectedRunId = '';
        selectedRun = null;
        loadingDetail = false;
        return;
      }

      const nextRun = runs.find((run) => run.run_id === selectedRunId) ?? runs[0];
      await selectRun(nextRun.run_id);
    } catch (caught) {
      error = caught instanceof Error ? caught.message : 'Run list request failed';
      authError = caught instanceof ApiError && caught.isAuth;
    } finally {
      loadingRuns = false;
    }
  };

  // Silent background refresh. This path must NEVER cause a layout shift: it
  // does not toggle any loading flags, never nulls `selectedRun`, and never
  // clears `recentEvents`. Populated state is only REPLACED with populated
  // state, so the rendered DOM keeps the same shape. Errors are swallowed (a
  // transient poll failure must not blank the UI); `pollFailed` is a non-layout
  // status flag only.
  async function refreshActive() {
    let fresh: RunSummary[];
    try {
      fresh = await fetchRuns();
    } catch {
      pollFailed = true;
      return;
    }

    // Nothing to refresh; never throw on an empty run list.
    runs = fresh;
    pollFailed = false;

    const runId = selectedRunId;
    if (!runId) {
      return;
    }

    // Race-guard: capture the in-flight request id so a selection change
    // mid-poll discards stale results instead of applying them.
    const requestId = detailRequest;

    try {
      const detail = await fetchRunDetail(runId);
      if (detailRequest === requestId && selectedRunId === runId) {
        selectedRun = detail;
      }

      const page = await fetchRunEvents(runId, eventsCursor);
      if (
        detailRequest === requestId &&
        selectedRunId === runId &&
        page.events.length > 0
      ) {
        recentEvents = mergeRecentEvents(recentEvents, page.events, RECENT_EVENTS_CAP);
        eventsCursor = page.latest_seq;
      }
    } catch {
      pollFailed = true;
    }
  }

  onMount(() => {
    void loadRuns();
    const timer = setInterval(() => {
      void refreshActive();
    }, POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  });
</script>

<main class="app-shell" aria-labelledby="page-title">
  <!-- Visually-hidden, zero-footprint status for background polls. It carries no
       layout dimensions (sr-only), so toggling pollFailed cannot shift or resize
       any visible control. -->
  <p class="sr-only" role="status" aria-live="polite">
    {pollFailed ? 'Background refresh failed; showing last known data.' : ''}
  </p>
  <aside class="run-list" aria-label="Swarm runs">
    <div class="brand-row">
      <h1 id="page-title">Swarmy</h1>
      <button class="refresh-button" type="button" on:click={loadRuns}>
        Refresh
      </button>
    </div>

    {#if loadingRuns}
      <div class="state-block">Loading runs</div>
    {:else if runs.length === 0 && !error}
      <div class="state-block">No runs found</div>
    {:else}
      <nav class="runs" aria-label="Run navigation">
        {#each runs as run}
          <button
            class:selected={run.run_id === selectedRunId}
            class="run-row"
            type="button"
            aria-pressed={run.run_id === selectedRunId}
            on:click={() => selectRun(run.run_id)}
          >
            <span class="run-main">
              <strong>{repoName(run.repo_path)}</strong>
              <small>{run.run_id}</small>
              <small>{run.repo_path}</small>
            </span>
            <span class="run-meta">
              <span>{run.status}</span>
              <strong>{activeBeadCount(run)}</strong>
            </span>
            <span class="run-timing">
              <small>age {relativeTime(run.created_at)}</small>
              <small>active {relativeTime(activityLabel(run))}</small>
            </span>
          </button>
        {/each}
      </nav>
    {/if}
  </aside>

  <section class="detail" aria-label="Selected run">
    {#if authError}
      <div class="detail-state auth-state" role="alert">
        <strong>Authentication required</strong>
        <span>
          This Swarmy server requires a local token. Open the dashboard using the
          URL printed by <code>swarmy serve</code>, or append
          <code>#swarmy_token=YOUR_TOKEN</code> to the address bar and retry.
        </span>
        <span class="auth-detail">
          {#if hasStoredToken()}
            The stored token was rejected.
          {:else}
            No token found.
          {/if}
        </span>
        <button type="button" on:click={loadRuns}>Retry</button>
      </div>
    {:else if error}
      <div class="detail-state error-state">
        <strong>Request failed</strong>
        <span>{error}</span>
        <button type="button" on:click={loadRuns}>Retry</button>
      </div>
    {:else if loadingRuns}
      <div class="detail-state">Loading dashboard</div>
    {:else if loadingDetail}
      <div class="detail-state">Loading run detail</div>
    {:else if !selectedRun}
      <div class="detail-state">Select a run</div>
    {:else}
      <header class="detail-header">
        <div>
          <p>{repoName(selectedRun.repo_path)}</p>
          <h2>{selectedRun.run_id}</h2>
        </div>
        <dl class="run-stats" aria-label="Run totals">
          <div>
            <dt>Active</dt>
            <dd>{activeBeadCount(selectedRun)}</dd>
          </div>
          <div>
            <dt>Agents</dt>
            <dd>{selectedRun.agent_count}</dd>
          </div>
          <div>
            <dt>Events</dt>
            <dd>{selectedRun.event_count}</dd>
          </div>
        </dl>
      </header>

      <div class="status-strip">
        <span>{selectedRun.status}</span>
        <span>{activityLabel(selectedRun)}</span>
      </div>

      <div class="stage-grid" aria-label="Bead stages">
        {#each stages as stage}
          <section class="stage-column" aria-label={stage}>
            <header>
              <h3>{stageLabels[stage]}</h3>
              <span>{beadsForStage(stage).length}</span>
            </header>
            {#if beadsForStage(stage).length === 0}
              <div class="stage-empty">No beads</div>
            {:else}
              <div class="stage-beads">
                {#each beadsForStage(stage) as bead}
                  <article class="stage-card">
                    <div>
                      <strong>{bead.id}</strong>
                      <span>{bead.title}</span>
                    </div>
                    <footer>
                      <span>{bead.status}</span>
                      {#if agentName(bead)}
                        <span>{agentName(bead)}{agentKind(bead) ? ` / ${agentKind(bead)}` : ''}</span>
                      {:else}
                        <span>No agent</span>
                      {/if}
                    </footer>
                  </article>
                {/each}
              </div>
            {/if}
          </section>
        {/each}
      </div>

      {#if unassignedBeads().length > 0}
        <section class="detail-band" aria-label="Unassigned beads">
          <header>
            <h3>{stageLabels.unassigned}</h3>
            <span>{unassignedBeads().length}</span>
          </header>
          <div class="bead-list">
            {#each unassignedBeads() as bead}
              <article class="bead-row">
                <div>
                  <strong>{bead.id}</strong>
                  <span>{bead.title}</span>
                </div>
                <div class="bead-meta">
                  <span>{bead.status}</span>
                  <span>{bead.issue_type || 'bead'}</span>
                </div>
              </article>
            {/each}
          </div>
        </section>
      {/if}

      <section class="detail-band" aria-label="Beads">
        <header>
          <h3>Beads</h3>
          <span>{selectedRun.beads.length}</span>
        </header>
        {#if selectedRun.beads.length === 0}
          <div class="empty-row">No beads in this run</div>
        {:else}
          <div class="bead-list">
            {#each selectedRun.beads as bead}
              <article class="bead-row">
                <div>
                  <strong>{bead.id}</strong>
                  <span>{bead.title}</span>
                </div>
                <div class="bead-meta">
                  <span>{stageFor(bead)}</span>
                  <span>{bead.status}</span>
                </div>
              </article>
            {/each}
          </div>
        {/if}
      </section>

      <section class="detail-band" aria-label="Agents">
        <header>
          <h3>Agents</h3>
          <span>{selectedRun.agents.length}</span>
        </header>
        {#if selectedRun.agents.length === 0}
          <div class="empty-row">No agents recorded</div>
        {:else}
          <div class="agent-list">
            {#each selectedRun.agents as agent}
              <article>
                <strong>{agent.name}</strong>
                <span>{agent.kind}</span>
              </article>
            {/each}
          </div>
        {/if}
      </section>

      <section class="detail-band" aria-label="Failures">
        <header>
          <h3>Failures</h3>
          <span>{(selectedRun.errors?.length ?? 0) + blockedEvents().length}</span>
        </header>
        {#if !hasFailures()}
          <div class="empty-row failures-empty">No failures</div>
        {:else}
          <div class="failure-list">
            {#each selectedRun.errors ?? [] as runError}
              <article class="failure-row">
                <div class="failure-main">
                  <strong>{runError.severity || 'error'}</strong>
                  <span>{runError.message}</span>
                </div>
                <div class="failure-meta">
                  <span>—</span>
                  <small title={runError.occurred_at}>{relativeTime(runError.occurred_at)}</small>
                </div>
              </article>
            {/each}
            {#each blockedEvents() as event}
              <article class="failure-row blocked-row">
                <div class="failure-main">
                  <strong>blocked</strong>
                  <span>
                    {event.bead_id ?? event.event_type}{event.stage ? ` · ${event.stage}` : ''}
                  </span>
                </div>
                <div class="failure-meta">
                  <span>{eventActor(event)}</span>
                  <small title={event.occurred_at}>{relativeTime(event.occurred_at)}</small>
                </div>
              </article>
            {/each}
          </div>
        {/if}
      </section>

      <section class="detail-band" aria-label="Activity">
        <header>
          <h3>Recent events</h3>
          <span>{recentEvents.length}</span>
        </header>
        {#if loadingEvents}
          <div class="empty-row">Loading activity</div>
        {:else if eventsError}
          <div class="events-error">
            <small>{eventsError}</small>
            <small class="events-error-note">
              The run detail above is still current; only the activity timeline
              failed to load.
            </small>
          </div>
        {:else if recentEvents.length === 0}
          <div class="empty-row">No recent activity</div>
        {:else}
          <div class="timeline-list">
            {#each recentEvents as event}
              <article class="timeline-row" class:blocked-row={isBlockedEvent(event)}>
                <div class="timeline-main">
                  <strong>{event.event_type}{event.stage ? ` · ${event.stage}` : ''}</strong>
                  {#if event.bead_id}
                    <span class="timeline-bead">{event.bead_id}</span>
                  {/if}
                  <span class="timeline-actor">{eventActor(event)}</span>
                </div>
                <small class="timeline-time" title={event.occurred_at}>
                  {relativeTime(event.occurred_at)}
                </small>
              </article>
            {/each}
          </div>
        {/if}
      </section>
    {/if}
  </section>
</main>
