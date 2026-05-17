import { request } from '@playwright/test';

/**
 * Pre-flight readiness probe.
 *
 * Pings the storefront once before any test runs. Without this, a missing
 * or crashed storefront container surfaces as N tests × M retries of
 * `ERR_CONNECTION_REFUSED` / 30 s timeouts — minutes of noise to read.
 * One clean failure here keeps the log honest.
 */
export default async function globalSetup(): Promise<void> {
    const baseURL = process.env.BASE_URL ?? 'http://shop.docker';
    const api = await request.newContext({ baseURL });

    const deadline = Date.now() + 30_000;
    let lastError: unknown = null;
    while (Date.now() < deadline) {
        try {
            const response = await api.get('/', { timeout: 3_000 });
            if (response.ok()) {
                await api.dispose();
                return;
            }
            lastError = new Error(`HTTP ${response.status()}`);
        } catch (error) {
            lastError = error;
        }
        await new Promise((resolve) => setTimeout(resolve, 1_000));
    }

    await api.dispose();
    throw new Error(
        `Storefront unreachable at ${baseURL} after 30 s` +
            ` — is the stack up? Run \`make up\` (local) or \`make ci-bootstrap\` (CI).` +
            ` Last error: ${lastError instanceof Error ? lastError.message : String(lastError)}`,
    );
}
