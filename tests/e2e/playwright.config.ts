import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.BASE_URL ?? 'http://shop.docker';

export default defineConfig({
    testDir: './tests',
    globalSetup: './global-setup.ts',
    fullyParallel: false,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 1 : 0,
    workers: process.env.CI ? 1 : 2,
    reporter: [
        ['html', { open: 'never', outputFolder: 'playwright-report' }],
        ['list'],
        ...(process.env.CI ? ([['junit', { outputFile: 'test-results/junit.xml' }]] as const) : []),
    ],
    use: {
        baseURL,
        trace:      process.env.CI ? 'retain-on-failure' : 'on-first-retry',
        screenshot: 'only-on-failure',
        video:      process.env.CI ? 'off' : 'retain-on-failure',
        viewport:   { width: 1280, height: 800 },
    },
    projects: [
        { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
        // Uncomment when you want full cross-browser coverage in CI.
        // { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
        // { name: 'webkit',  use: { ...devices['Desktop Safari']  } },
    ],
});
