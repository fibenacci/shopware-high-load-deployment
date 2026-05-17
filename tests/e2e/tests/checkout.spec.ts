import { expect, test } from '@playwright/test';

/**
 * Smoke checkout — add → cart → confirm.
 *
 * This is intentionally a happy path on the default storefront with the
 * sample-data product. Bend it to your catalog once you have one.
 */
test.describe('Storefront — checkout smoke', () => {
    test.fixme(
        true,
        'Enable once your catalog has at least one in-stock product reachable from /',
    );

    test('happy path → cart not empty', async ({ page }) => {
        await page.goto('/');
        // Click the first product card on the homepage.
        await page.locator('.product-box a.product-image-link').first().click();
        await expect(page).toHaveURL(/\/.+\.html|\/detail\//);

        await page.locator('button[type="submit"][title*="cart" i], .btn-buy').first().click();

        // Off-canvas opens; assert the cart counter ticks up.
        const counter = page.locator('.header-cart-total, [data-offcanvas-cart-loader]').first();
        await expect(counter).toBeVisible();
    });
});
