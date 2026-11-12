const {defineConfig, devices} = require('@playwright/test');
module.exports = defineConfig({
  testDir: '.', testMatch: 'questions_controlled.cjs', timeout: 45000,
  expect: {timeout: 12000}, workers: 1, retries: 0, reporter: [['list']],
  use: {baseURL: process.env.PLAYWRIGHT_BASE_URL, ...devices['Desktop Chrome']},
});
