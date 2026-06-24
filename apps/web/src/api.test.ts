import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  parseTokenFromHash,
  buildAuthHeaders,
  ApiError,
  recentEventsCursor,
  isBlockedEvent,
  eventActor,
  type RunEvent
} from './api.ts';

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
