import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parseTokenFromHash, buildAuthHeaders, ApiError } from './api.ts';

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
