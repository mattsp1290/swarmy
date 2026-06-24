import { expect, test, type Page } from '@playwright/test';

/**
 * Dashboard UI smoke test.
 *
 * The API is fully stubbed with fixture JSON via page.route, so no real Swarmy
 * backend is needed. The fixtures match the RunSummary / RunDetail shapes in
 * src/api.ts. Two beads sit in the `coding` and `review` stages; we assert they
 * render in the matching `.stage-column` of the `.stage-grid` produced by
 * App.svelte. The auth block exercises the 401 -> "Authentication required"
 * path. Each test runs under both the desktop and mobile Playwright projects,
 * giving real desktop/mobile framing coverage.
 */

const RUN_ID = 'run-fixture-001';

const RUN_SUMMARY = {
  run_id: RUN_ID,
  repo_path: '/Users/dev/git/swarmy',
  status: 'running',
  created_at: '2026-06-24T10:00:00Z',
  updated_at: '2026-06-24T10:05:00Z',
  latest_event_at: '2026-06-24T10:05:00Z',
  bead_count: 2,
  active_bead_count: 2,
  agent_count: 0,
  event_count: 4,
  latest_seq: 4
};

const CODING_BEAD = {
  id: 'swarmy-code-01',
  title: 'Implement the dashboard renderer',
  status: 'in_progress',
  priority: 1,
  issue_type: 'task',
  swarm_stage: 'coding',
  current_stage: {
    event_id: 'evt-1',
    seq: 3,
    occurred_at: '2026-06-24T10:04:00Z',
    stage: 'coding',
    agent: { id: 'a1', name: 'coder-agent', kind: 'coding' }
  }
};

const REVIEW_BEAD = {
  id: 'swarmy-review-02',
  title: 'Review the auth boundary',
  status: 'in_progress',
  priority: 1,
  issue_type: 'task',
  swarm_stage: 'review',
  current_stage: {
    event_id: 'evt-2',
    seq: 4,
    occurred_at: '2026-06-24T10:05:00Z',
    stage: 'review',
    agent: { id: 'a2', name: 'review-agent', kind: 'review' }
  }
};

const RUN_DETAIL = {
  ...RUN_SUMMARY,
  beads: [CODING_BEAD, REVIEW_BEAD],
  agents: [],
  errors: []
};

const CODING_EVENT = {
  event_id: 'evt-coding',
  seq: 3,
  occurred_at: '2026-06-24T10:04:00Z',
  source: 'orchestrator',
  event_type: 'stage.changed',
  bead_id: 'swarmy-code-01',
  stage: 'coding',
  agent: { id: 'a1', name: 'coder-agent', kind: 'coding' },
  payload: {}
};

const BLOCKED_EVENT = {
  event_id: 'evt-blocked',
  seq: 4,
  occurred_at: '2026-06-24T10:05:00Z',
  source: 'orchestrator',
  event_type: 'stage.changed',
  bead_id: 'swarmy-review-02',
  stage: 'blocked',
  agent: { id: 'a2', name: 'review-agent', kind: 'review' },
  payload: {}
};

const RUN_EVENTS_PAGE = {
  run_id: RUN_ID,
  events: [CODING_EVENT, BLOCKED_EVENT],
  next_cursor: 4,
  has_more: false,
  latest_seq: 4
};

const json = (body: unknown) => ({
  status: 200,
  contentType: 'application/json',
  body: JSON.stringify(body)
});

// Stub /api/runs (list), /api/runs/<id> (detail) and /api/runs/<id>/events
// (timeline). Playwright evaluates routes in reverse registration order
// (last-registered wins), and the detail glob also matches the events URL, so
// the events route is registered LAST to take precedence for that request.
async function stubHappyApi(page: Page): Promise<void> {
  await page.route('**/api/runs', (route) =>
    route.fulfill(json({ source_repo: '/Users/dev/git/swarmy', runs: [RUN_SUMMARY] }))
  );
  await page.route('**/api/runs/*', (route) =>
    route.fulfill(json(RUN_DETAIL))
  );
  await page.route('**/api/runs/*/events*', (route) =>
    route.fulfill(json(RUN_EVENTS_PAGE))
  );
}

test('renders coding and review beads from fixture API data', async ({ page }) => {
  await stubHappyApi(page);
  await page.goto('/');

  const grid = page.locator('.stage-grid');
  await expect(grid).toBeVisible();

  const codingColumn = grid.locator('section.stage-column[aria-label="coding"]');
  const reviewColumn = grid.locator('section.stage-column[aria-label="review"]');

  // Coding column shows the coding bead's id + title.
  const codingCard = codingColumn.locator('.stage-card');
  await expect(codingCard).toHaveCount(1);
  await expect(codingCard.locator('strong')).toHaveText(CODING_BEAD.id);
  await expect(codingCard.locator('span').first()).toHaveText(CODING_BEAD.title);

  // Review column shows the review bead's id + title.
  const reviewCard = reviewColumn.locator('.stage-card');
  await expect(reviewCard).toHaveCount(1);
  await expect(reviewCard.locator('strong')).toHaveText(REVIEW_BEAD.id);
  await expect(reviewCard.locator('span').first()).toHaveText(REVIEW_BEAD.title);

  // The coding bead must NOT appear in the review column and vice versa.
  await expect(reviewColumn).not.toContainText(CODING_BEAD.id);
  await expect(codingColumn).not.toContainText(REVIEW_BEAD.id);

  // The Activity band renders the recent events from the cursor endpoint.
  const activityBand = page.locator('section.detail-band[aria-label="Activity"]');
  await expect(activityBand).toBeVisible();
  const timelineRows = activityBand.locator('.timeline-row');
  await expect(timelineRows).toHaveCount(2);
  await expect(activityBand).toContainText(CODING_EVENT.bead_id);
  await expect(activityBand).toContainText(BLOCKED_EVENT.agent.name);

  // The blocked event is surfaced in the Failures band with its source agent
  // and the distinct blocked/failure highlight class.
  const failuresBand = page.locator('section.detail-band[aria-label="Failures"]');
  await expect(failuresBand).toBeVisible();
  const failureRow = failuresBand.locator('.failure-row.blocked-row');
  await expect(failureRow).toHaveCount(1);
  await expect(failureRow).toContainText(BLOCKED_EVENT.agent.name);
  await expect(failureRow).toContainText('blocked');
});

test('surfaces the auth panel on a 401 from the API', async ({ page }) => {
  await page.route('**/api/runs', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: '{"error":"unauthorized"}'
    })
  );

  await page.goto('/');

  const authPanel = page.locator('.auth-state[role="alert"]');
  await expect(authPanel).toBeVisible();
  await expect(authPanel).toContainText('Authentication required');
});
