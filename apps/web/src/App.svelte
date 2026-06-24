<script lang="ts">
  type Stage = 'coding' | 'validation' | 'review';

  const runs = [
    {
      id: 'local-swarm',
      repo: 'swarmy',
      activeBeads: 1,
      updated: 'waiting for events'
    }
  ];

  const stages: Array<{ name: Stage; count: number }> = [
    { name: 'coding', count: 0 },
    { name: 'validation', count: 0 },
    { name: 'review', count: 0 }
  ];
</script>

<main class="app-shell" aria-labelledby="page-title">
  <aside class="run-list" aria-label="Swarm runs">
    <h1 id="page-title">Swarmy</h1>
    {#each runs as run}
      <button class="run-row" type="button" aria-pressed="true">
        <span>
          <strong>{run.repo}</strong>
          <small>{run.id}</small>
        </span>
        <span class="count">{run.activeBeads}</span>
      </button>
    {/each}
  </aside>

  <section class="detail" aria-label="Selected run">
    <header class="detail-header">
      <div>
        <p>Selected run</p>
        <h2>local-swarm</h2>
      </div>
      <span>waiting for events</span>
    </header>

    <div class="stage-grid" aria-label="Bead stages">
      {#each stages as stage}
        <section class="stage-column" aria-label={stage.name}>
          <header>
            <h3>{stage.name}</h3>
            <span>{stage.count}</span>
          </header>
          <div class="empty-slot"></div>
        </section>
      {/each}
    </div>
  </section>
</main>
