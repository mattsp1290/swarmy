import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  parseTokenFromHash,
  buildAuthHeaders,
  ApiError,
  recentEventsCursor,
  mergeRecentEvents,
  isBlockedEvent,
  eventActor,
  lastReviewVerdicts,
  hasOutstandingRequestChanges,
  degradedReviewState,
  latestIterationHealth,
  type RunEvent,
  type RunHealth,
  type IterationHealth
} from './api.ts';

const makeIteration = (
  overrides: Partial<IterationHealth> = {}
): IterationHealth => ({
  iteration: 1,
  branch: 'bead-swarm/iteration-1-x',
  status: 'complete',
  execution_mode: '',
  degraded_reason: '',
  review_mode: 'reviewer-subagents',
  review_assurance: 'normal',
  findings_fixed_re_reviewed: false,
  validation_passed: true,
  reviews: [{ reviewer: 'redowl', verdict: 'APPROVE' }],
  review_blocker_summary: [],
  ...overrides
});

const makeHealth = (iterations: IterationHealth[]): RunHealth => ({
  run_id: 'run-1',
  summary: {
    run_id: 'run-1',
    last_iteration: iterations.at(-1)?.iteration ?? 0,
    last_branch: iterations.at(-1)?.branch ?? '',
    status: iterations.at(-1)?.status ?? '',
    execution_mode: iterations.at(-1)?.execution_mode ?? '',
    degraded_reason: iterations.at(-1)?.degraded_reason ?? '',
    review_mode: iterations.at(-1)?.review_mode ?? '',
    reviews: iterations.at(-1)?.reviews ?? [],
    latest_validation: { passed: true, entries: [] },
    unresolved_risks: []
  },
  iterations
});

const makeEvent = (overrides: Partial<RunEvent> = {}): RunEvent => ({
  event_id: 'evt-1',
  seq: 1,
  occurred_at: '2026-06-24T10:00:00Z',
  source: 'system',
  event_type: 'stage.changed',
  bead_id: null,
  stage: null,
  agent: null,
  ...overrides
});

test('parseTokenFromHash extracts token and strips it from the hash', () => {
  const result = parseTokenFromHash('#swarmy_token=abc123');
  assert.equal(result.token, 'abc123');
  assert.equal(result.nextHash, '');
});

test('parseTokenFromHash preserves other hash params', () => {
  const result = parseTokenFromHash('#view=runs&swarmy_token=abc123&tab=beads');
  assert.equal(result.token, 'abc123');
  assert.equal(result.nextHash, 'view=runs&tab=beads');
});

test('parseTokenFromHash works without a leading #', () => {
  const result = parseTokenFromHash('swarmy_token=tok&other=1');
  assert.equal(result.token, 'tok');
  assert.equal(result.nextHash, 'other=1');
});

test('parseTokenFromHash returns null when the token param is absent', () => {
  const result = parseTokenFromHash('#view=runs');
  assert.equal(result.token, null);
  assert.equal(result.nextHash, 'view=runs');
});

test('parseTokenFromHash returns null for an empty token value but strips it', () => {
  const result = parseTokenFromHash('#swarmy_token=&keep=1');
  assert.equal(result.token, null);
  assert.equal(result.nextHash, 'keep=1');
});

test('parseTokenFromHash handles an empty hash', () => {
  const result = parseTokenFromHash('');
  assert.equal(result.token, null);
  assert.equal(result.nextHash, '');
});

test('buildAuthHeaders adds X-Swarmy-Token only for a non-empty token', () => {
  const withToken = buildAuthHeaders('secret');
  assert.equal(withToken['X-Swarmy-Token'], 'secret');
  assert.equal(withToken.accept, 'application/json');
});

test('buildAuthHeaders omits the token header for an empty token', () => {
  const withoutToken = buildAuthHeaders('');
  assert.equal('X-Swarmy-Token' in withoutToken, false);
  assert.equal(withoutToken.accept, 'application/json');
});

test('ApiError marks 401 responses as auth failures', () => {
  const err = new ApiError('unauthorized', 401, true);
  assert.equal(err.status, 401);
  assert.equal(err.isAuth, true);
  assert.equal(err.name, 'ApiError');
  assert.ok(err instanceof Error);
});

test('ApiError treats non-401 responses as non-auth failures', () => {
  const err = new ApiError('server error', 500, false);
  assert.equal(err.status, 500);
  assert.equal(err.isAuth, false);
});

test('recentEventsCursor subtracts the window from the latest seq', () => {
  assert.equal(recentEventsCursor(100, 50), 50);
});

test('recentEventsCursor clamps to 0 when the window exceeds latest seq', () => {
  assert.equal(recentEventsCursor(10, 50), 0);
});

test('recentEventsCursor returns 0 for NaN or negative latest seq', () => {
  assert.equal(recentEventsCursor(Number.NaN, 50), 0);
  assert.equal(recentEventsCursor(-5, 50), 0);
});

test('mergeRecentEvents prepends incoming reversed ahead of existing (newest-first)', () => {
  const existing = [makeEvent({ event_id: 'e2', seq: 2 })];
  const incoming = [
    makeEvent({ event_id: 'e3', seq: 3 }),
    makeEvent({ event_id: 'e4', seq: 4 })
  ];
  const merged = mergeRecentEvents(existing, incoming, 50);
  assert.deepEqual(
    merged.map((e) => e.event_id),
    ['e4', 'e3', 'e2']
  );
});

test('mergeRecentEvents dedupes by event_id keeping the newest occurrence', () => {
  const existing = [
    makeEvent({ event_id: 'e3', seq: 3 }),
    makeEvent({ event_id: 'e2', seq: 2 })
  ];
  const incoming = [
    makeEvent({ event_id: 'e3', seq: 3 }),
    makeEvent({ event_id: 'e4', seq: 4 })
  ];
  const merged = mergeRecentEvents(existing, incoming, 50);
  assert.deepEqual(
    merged.map((e) => e.event_id),
    ['e4', 'e3', 'e2']
  );
});

test('mergeRecentEvents caps to N dropping the oldest', () => {
  const existing = [
    makeEvent({ event_id: 'e2', seq: 2 }),
    makeEvent({ event_id: 'e1', seq: 1 })
  ];
  const incoming = [
    makeEvent({ event_id: 'e3', seq: 3 }),
    makeEvent({ event_id: 'e4', seq: 4 })
  ];
  const merged = mergeRecentEvents(existing, incoming, 3);
  assert.deepEqual(
    merged.map((e) => e.event_id),
    ['e4', 'e3', 'e2']
  );
});

test('mergeRecentEvents returns existing unchanged for empty incoming', () => {
  const existing = [
    makeEvent({ event_id: 'e2', seq: 2 }),
    makeEvent({ event_id: 'e1', seq: 1 })
  ];
  const merged = mergeRecentEvents(existing, [], 50);
  assert.deepEqual(
    merged.map((e) => e.event_id),
    ['e2', 'e1']
  );
});

test('mergeRecentEvents does not mutate its inputs', () => {
  const existing = [makeEvent({ event_id: 'e2', seq: 2 })];
  const incoming = [makeEvent({ event_id: 'e3', seq: 3 })];
  const existingCopy = existing.slice();
  const incomingCopy = incoming.slice();
  const merged = mergeRecentEvents(existing, incoming, 50);
  assert.notEqual(merged, existing);
  assert.deepEqual(existing, existingCopy);
  assert.deepEqual(incoming, incomingCopy);
});

test('isBlockedEvent is true only for the blocked stage', () => {
  assert.equal(isBlockedEvent(makeEvent({ stage: 'blocked' })), true);
  assert.equal(isBlockedEvent(makeEvent({ stage: 'coding' })), false);
  assert.equal(isBlockedEvent(makeEvent({ stage: null })), false);
});

test('eventActor labels an agent with kind as "name / kind"', () => {
  const actor = eventActor(
    makeEvent({ agent: { id: 'a1', name: 'coder', kind: 'coding' } })
  );
  assert.equal(actor, 'coder / coding');
});

test('eventActor uses just the name when the agent has no kind', () => {
  const actor = eventActor(
    makeEvent({ agent: { id: 'a1', name: 'coder', kind: '' } })
  );
  assert.equal(actor, 'coder');
});

test('eventActor falls back to the event source when there is no agent', () => {
  assert.equal(eventActor(makeEvent({ source: 'orchestrator' })), 'orchestrator');
});

test('latestIterationHealth returns the last iteration or null', () => {
  assert.equal(latestIterationHealth(makeHealth([])), null);
  const h = makeHealth([makeIteration({ iteration: 1 }), makeIteration({ iteration: 2 })]);
  assert.equal(latestIterationHealth(h)?.iteration, 2);
});

test('lastReviewVerdicts reads the latest iteration verdicts', () => {
  const h = makeHealth([
    makeIteration({ iteration: 1, reviews: [{ reviewer: 'a', verdict: 'REQUEST_CHANGES' }] }),
    makeIteration({
      iteration: 2,
      reviews: [
        { reviewer: 'redowl', verdict: 'APPROVE' },
        { reviewer: 'scout', verdict: 'APPROVE' }
      ]
    })
  ]);
  assert.deepEqual(lastReviewVerdicts(h), ['APPROVE', 'APPROVE']);
  assert.deepEqual(lastReviewVerdicts(makeHealth([])), []);
});

test('hasOutstandingRequestChanges is true only for unresolved REQUEST_CHANGES', () => {
  const outstanding = makeHealth([
    makeIteration({
      reviews: [{ reviewer: 'scout', verdict: 'REQUEST_CHANGES' }],
      findings_fixed_re_reviewed: false
    })
  ]);
  assert.equal(hasOutstandingRequestChanges(outstanding), true);

  const resolved = makeHealth([
    makeIteration({
      reviews: [{ reviewer: 'scout', verdict: 'REQUEST_CHANGES' }],
      findings_fixed_re_reviewed: true
    })
  ]);
  assert.equal(hasOutstandingRequestChanges(resolved), false);

  const approved = makeHealth([makeIteration()]);
  assert.equal(hasOutstandingRequestChanges(approved), false);
  assert.equal(hasOutstandingRequestChanges(makeHealth([])), false);

  // A split panel (one APPROVE, one unresolved REQUEST_CHANGES) is outstanding.
  const mixed = makeHealth([
    makeIteration({
      reviews: [
        { reviewer: 'redowl', verdict: 'APPROVE' },
        { reviewer: 'scout', verdict: 'REQUEST_CHANGES' }
      ],
      findings_fixed_re_reviewed: false
    })
  ]);
  assert.equal(hasOutstandingRequestChanges(mixed), true);
});

test('degradedReviewState flags degraded review assurance, not execution mode', () => {
  // A degraded ORCHESTRATION mode (parent-degraded) with normal review assurance
  // is NOT a degraded review — it must not be flagged.
  const orchestrationDegraded = makeHealth([
    makeIteration({
      execution_mode: 'parent-degraded',
      degraded_reason: 'single docs change',
      review_assurance: 'normal'
    })
  ]);
  assert.equal(degradedReviewState(orchestrationDegraded), null);

  // A non-normal review_assurance IS a degraded review and is surfaced verbatim.
  const degradedReview = makeHealth([
    makeIteration({ review_assurance: 'local_fallback' })
  ]);
  assert.equal(degradedReviewState(degradedReview), 'local_fallback');

  const normal = makeHealth([makeIteration({ review_assurance: 'normal' })]);
  assert.equal(degradedReviewState(normal), null);
  assert.equal(degradedReviewState(makeHealth([])), null);
});
