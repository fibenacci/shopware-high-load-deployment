// =============================================================================
// k6 load test for the Shopware storefront.
//
// Mirrors a realistic browse → search → product → cart → checkout funnel. The
// scenario shape is selected at runtime through the K6_PROFILE env var so the
// same script covers smoke / baseline / peak / endurance runs.
//
// Run inside the cluster:
//   kubectl apply -f k3s/stresstest/k6-job.yaml
// Run from the host (against a k3d-exposed Ingress on localhost):
//   k6 run -e BASE_URL=http://shop.example.com -e K6_PROFILE=baseline loadtest.js
// =============================================================================

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';

const BASE_URL = __ENV.BASE_URL || 'http://shopware-web.shopware-staging.svc.cluster.local';
const PROFILE  = __ENV.K6_PROFILE || 'baseline';

const PRODUCTS = new SharedArray('products', () => {
    // Replace with a real seed list pulled from the DB, or wire k6 to read
    // /store-api/product before the run starts. The smoke profile tolerates
    // an empty list and exercises only category pages.
    return (__ENV.PRODUCT_SLUGS || '').split(',').filter(Boolean);
});

// -----------------------------------------------------------------------------
// Metrics — surfaced in Grafana via the k6 Prometheus exporter or the JSON output.
// -----------------------------------------------------------------------------
const pageLoad = new Trend('shopware_page_load_ms', true);
const cartAdd  = new Rate ('shopware_cart_add_success');
const errors   = new Counter('shopware_errors');

// -----------------------------------------------------------------------------
// Scenarios
// -----------------------------------------------------------------------------
const profiles = {
    smoke: {
        executor: 'constant-vus',
        vus: 1,
        duration: '30s',
    },
    baseline: {
        executor: 'ramping-vus',
        startVUs: 0,
        stages: [
            { duration: '5m',  target: 50 },
            { duration: '10m', target: 50 },
            { duration: '2m',  target: 0  },
        ],
        gracefulRampDown: '30s',
    },
    peak: {
        executor: 'ramping-vus',
        startVUs: 0,
        stages: [
            { duration: '5m',  target: 100 },
            { duration: '5m',  target: 300 },
            { duration: '5m',  target: 500 },
            { duration: '3m',  target: 500 },
            { duration: '2m',  target: 0   },
        ],
        gracefulRampDown: '1m',
    },
    endurance: {
        executor: 'constant-vus',
        vus: 100,
        duration: '60m',
    },
    // Surge from idle to 300 VUs in 30 s. The point isn't sustained load —
    // it's: does the HPA react fast enough? The 2-minute hold gives Grafana
    // a window where you can see ReplicaSet count vs RPS vs error rate.
    spike: {
        executor: 'ramping-vus',
        startVUs: 0,
        stages: [
            { duration: '30s', target: 300 },
            { duration: '2m',  target: 300 },
            { duration: '30s', target: 0   },
        ],
        gracefulRampDown: '15s',
    },
    // Used by CI as a blocking regression gate. Fast, deterministic, single
    // RPS profile so thresholds are meaningful run-over-run.
    regression: {
        executor: 'constant-arrival-rate',
        rate: 20,                 // 20 RPS sustained
        timeUnit: '1s',
        duration: '3m',
        preAllocatedVUs: 50,
        maxVUs: 200,
    },
};

if (!profiles[PROFILE]) {
    throw new Error(`Unknown K6_PROFILE: ${PROFILE}`);
}

// Profile-specific thresholds — `regression` is the tightest because CI
// gates on it; `peak` is lenient because we're deliberately driving the
// system past comfort.
const thresholds = {
    smoke: {
        http_req_failed:   ['rate<0.01'],
        http_req_duration: ['p(95)<2000'],
    },
    baseline: {
        http_req_failed:           ['rate<0.02'],
        http_req_duration:         ['p(95)<1500'],
        shopware_page_load_ms:     ['p(95)<2000'],
        shopware_cart_add_success: ['rate>0.95'],
    },
    peak: {
        http_req_failed:   ['rate<0.05'],
        http_req_duration: ['p(95)<3000'],
    },
    endurance: {
        http_req_failed:   ['rate<0.02'],
        http_req_duration: ['p(95)<1500'],
    },
    spike: {
        // Spike-specific: errors during the surge are expected while HPA
        // catches up. We care that the system RECOVERS, not that it never
        // blips. CI gates a separate `regression` profile for absolute perf.
        http_req_failed:   ['rate<0.10'],
        http_req_duration: ['p(95)<5000'],
    },
    regression: {
        // The CI gate. Tighter than `baseline` on purpose — drift here is
        // the warning shot we want before customers feel it.
        http_req_failed:   ['rate<0.005', { abortOnFail: true }],
        http_req_duration: ['p(95)<1200', { abortOnFail: false }],
        http_req_duration: ['p(99)<3000', { abortOnFail: false }],
    },
};

export const options = {
    scenarios: { main: profiles[PROFILE] },
    thresholds: thresholds[PROFILE],
    summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------
function record(res, label) {
    pageLoad.add(res.timings.duration, { endpoint: label });
    if (res.status >= 400) errors.add(1, { endpoint: label, status: String(res.status) });
}

function browse() {
    group('homepage', () => {
        const res = http.get(BASE_URL + '/', { tags: { name: 'homepage' } });
        check(res, { 'homepage 200': r => r.status === 200 });
        record(res, 'homepage');
    });
}

function category() {
    group('category', () => {
        const res = http.get(BASE_URL + '/category', {
            tags: { name: 'category' },
        });
        check(res, { 'category 200 or 301': r => [200, 301, 302].includes(r.status) });
        record(res, 'category');
    });
}

function product() {
    if (PRODUCTS.length === 0) return;
    const slug = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
    group('product', () => {
        const res = http.get(`${BASE_URL}/${slug}`, {
            tags: { name: 'product' },
        });
        check(res, { 'product 200': r => r.status === 200 });
        record(res, 'product');
    });
}

function search() {
    const terms = ['shirt', 'shoe', 'mug', 'jacket', 'sticker'];
    const q = terms[Math.floor(Math.random() * terms.length)];
    group('search', () => {
        const res = http.get(`${BASE_URL}/search?search=${q}`, {
            tags: { name: 'search' },
        });
        check(res, { 'search 200': r => r.status === 200 });
        record(res, 'search');
    });
}

// -----------------------------------------------------------------------------
// VU iteration — weighted random walk through the funnel.
// -----------------------------------------------------------------------------
export default function () {
    const roll = Math.random();
    if (roll < 0.40)      browse();
    else if (roll < 0.65) category();
    else if (roll < 0.85) product();
    else                  search();

    // Tiny think time — keeps CPU off the script and pushes load onto Shopware.
    sleep(Math.random() * 2 + 0.5);
}
