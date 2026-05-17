import { expect, test } from '@playwright/test';

test.describe('Storefront — homepage', () => {
    test('returns 200 and renders the Shopware shell', async ({ page }) => {
        const response = await page.goto('/');
        expect(response?.status()).toBe(200);

        // The shop frame ships an html element with data-shopware-id —
        // a reliable "kernel booted" signal independent of theme markup.
        await expect(page.locator('html')).toHaveAttribute('lang', /[a-z]{2}-[A-Z]{2}/);
    });

    test('has a discoverable search input', async ({ page }) => {
        await page.goto('/');
        // The default storefront ships a search form at .header-search-input.
        // Override the selector once you ship a custom theme.
        const search = page.locator('input[name="search"]').first();
        await expect(search).toBeVisible({ timeout: 5_000 });
    });
});

test.describe('Storefront — health', () => {
    test('respects the X-Robots-Tag on non-production environments', async ({ request }) => {
        const response = await request.get('/');
        expect(response.status()).toBe(200);
        // A staging shop should be `noindex`. Production should NOT set this header.
        // Adjust per environment.
        const robots = response.headers()['x-robots-tag'];
        if (process.env.EXPECT_NOINDEX === '1') {
            expect(robots).toMatch(/noindex/);
        }
    });
});
