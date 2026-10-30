const {defineConfig} = require('playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: 'presentation_help.spec.cjs',
  outputDir: '../../tmp/presentation-tests',
  fullyParallel: false,
  use: {headless: true, viewport: {width: 390, height: 844}},
});
