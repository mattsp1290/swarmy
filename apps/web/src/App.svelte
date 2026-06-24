<script lang="ts">
  import { onMount } from 'svelte';
  import {
    fetchRunDetail,
    fetchRuns,
    type BeadSummary,
    type RunDetail,
    type RunSummary
  } from './api';

  const stages = ['coding', 'validation', 'review', 'merge', 'blocked', 'complete'];

  let runs: RunSummary[] = [];
  let selectedRunId = '';
  let selectedRun: RunDetail | null = null;
  let loadingRuns = true;
  let loadingDetail = false;
  let error = '';
  let detailRequest = 0;

  const repoName = (path: string) => {
    const normalized = path.replace(/\\/g, '/');
    const parts = normalized.split('/').filter(Boolean);
    return parts.at(-1) ?? path;
  };

  const activityLabel = (run: RunSummary | RunDetail) =>
    run.latest_event_at || run.updated_at || run.created_at || 'no activity';

  const stageFor = (bead: BeadSummary) =>
    bead.current_stage?.stage ?? bead.swarm_stage ?? 'unassigned';

  const countStage = (stage: string) =>
    selectedRun?.beads.filter((bead) => stageFor(bead) === stage).length ?? 0;

  const visibleBeads = () => selectedRun?.beads.slice(0, 6) ?? [];

  const selectRun = async (runId: string) => {
    const requestId = detailRequest + 1;
    detailRequest = requestId;
    selectedRunId = runId;
    selectedRun = null;
    loadingDetail = true;
    error = '';

    try {
      const detail = await fetchRunDetail(runId);
      if (detailRequest === requestId && selectedRunId === runId) {
        selectedRun = detail;
      }
    } catch (caught) {
      if (detailRequest === requestId && selectedRunId === runId) {
        error = caught instanceof Error ? caught.message : 'Run detail request failed';
      }
    } finally {
      if (detailRequest === requestId) {
        loadingDetail = false;
      }
    }
  };

  const loadRuns = async () => {
    loadingRuns = true;
    error = '';

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
      detailRequest += 1;
      runs = [];
      selectedRunId = '';
      selectedRun = null;
      loadingDetail = false;
    } finally {
      loadingRuns = false;
    }
  };

  onMount(() => {
    void loadRuns();
  });
</script>

<main class="app-shell" aria-labelledby="page-title">
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
            </span>
            <span class="run-meta">
              <span>{run.status}</span>
              <strong>{run.bead_count}</strong>
            </span>
          </button>
        {/each}
      </nav>
    {/if}
  </aside>

  <section class="detail" aria-label="Selected run">
    {#if error}
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
            <dt>Beads</dt>
            <dd>{selectedRun.bead_count}</dd>
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
              <h3>{stage}</h3>
              <span>{countStage(stage)}</span>
            </header>
          </section>
        {/each}
      </div>

      <section class="detail-band" aria-label="Beads">
        <header>
          <h3>Beads</h3>
          <span>{selectedRun.beads.length}</span>
        </header>
        {#if selectedRun.beads.length === 0}
          <div class="empty-row">No beads in this run</div>
        {:else}
          <div class="bead-list">
            {#each visibleBeads() as bead}
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
    {/if}
  </section>
</main>
