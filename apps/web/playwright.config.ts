import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright config for the Swarmy dashboard UI smoke test.
 *
 * The webServer builds the app and serves the production `dist/` bundle via
 * `vite preview` (default 127.0.0.1:4173). The same spec runs under a desktop
 * and a mobile project so we exercise both framings against the real bundle.
 *
 * Only `tests/**` specs are matched (testDir), so this runner never touches the
 * node:test suite in `src/*.test.ts`.
 */
const PREVIEW_PORT = 4173;
const BASE_URL = `http://127.0.0.1:${PREVIEW_PORT}`;

export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry'
  },
  projects: [
    {
      name: 'desktop',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 800 },
        deviceScaleFactor: 1
      }
    },
    {
      // Real Chromium-based mobile emulation (mobile viewport, touch, mobile
      // UA) so this is honest mobile framing, not just a narrow desktop window.
      name: 'mobile',
      use: { ...devices['Pixel 5'] }
    }
  ],
  webServer: {
    command: 'npm run build && npm run preview',
    url: BASE_URL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000
  }
});
