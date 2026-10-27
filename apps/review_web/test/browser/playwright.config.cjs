const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  testMatch: /.*\.spec\.cjs/,
  timeout: 45000,
  expect: { timeout: 12000 },
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:4000',
    ...devices['Desktop Chrome'],
  },
  workers: 1,
  retries: 0,
  reporter: [['list']],
});
