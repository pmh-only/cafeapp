import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const orderCreationErrors = new Rate('order_creation_errors');
const orderCreationDuration = new Trend('order_creation_duration');
const menuFetchDuration = new Trend('menu_fetch_duration');
const totalOrders = new Counter('total_orders_created');

// Configuration
export const options = {
    scenarios: {
        morning_rush: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '2m', target: 100 },   // Ramp up to 100 users
                { duration: '5m', target: 500 },   // Scale to peak: 500 users
                { duration: '3m', target: 1000 },  // Surge: 1000 concurrent users
                { duration: '2m', target: 100 },   // Ramp down
                { duration: '1m', target: 0 },     // Cool down
            ],
        },
    },
    thresholds: {
        http_req_duration: ['p(95)<500', 'p(99)<1000'],  // 95% < 500ms, 99% < 1s
        http_req_failed: ['rate<0.05'],                   // Error rate < 5%
        order_creation_errors: ['rate<0.02'],             // Order errors < 2%
        order_creation_duration: ['p(95)<800'],           // Order creation < 800ms (p95)
        menu_fetch_duration: ['p(95)<200'],               // Menu fetch < 200ms (p95)
    },
};

// Test data generators
const STORE_IDS = ['1', '2', '3', '4', '5'];
const ITEMS = [
    { item_id: 'latte', name: 'Caffe Latte', price: 5.00 },
    { item_id: 'cappuccino', name: 'Cappuccino', price: 4.50 },
    { item_id: 'espresso', name: 'Espresso', price: 3.00 },
    { item_id: 'mocha', name: 'Mocha', price: 5.50 },
    { item_id: 'americano', name: 'Americano', price: 3.50 },
    { item_id: 'cold_brew', name: 'Cold Brew', price: 4.00 },
    { item_id: 'croissant', name: 'Croissant', price: 3.50 },
    { item_id: 'muffin', name: 'Blueberry Muffin', price: 3.00 },
];

function randomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomChoice(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}

function generateOrder() {
    const numItems = randomInt(1, 5);
    const items = [];
    let total = 0;

    for (let i = 0; i < numItems; i++) {
        const item = randomChoice(ITEMS);
        const quantity = randomInt(1, 3);
        items.push({
            item_id: item.item_id,
            name: item.name,
            quantity: quantity,
            price: item.price,
        });
        total += item.price * quantity;
    }

    return {
        customer_id: `user-${__VU}-${randomInt(1, 1000)}`,
        store_id: randomChoice(STORE_IDS),
        items: items,
        total_amount: total,
    };
}

// Environment setup
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
    // Scenario: Morning coffee rush
    // Customers ordering coffee, checking menu, loyalty points

    group('Customer Journey', function () {
        // Step 1: Fetch menu (60% of users)
        if (Math.random() < 0.6) {
            group('View Menu', function () {
                const menuStart = Date.now();
                const menuRes = http.get(`${BASE_URL}/api/menu/items`, {
                    tags: { name: 'GetMenu' },
                });

                check(menuRes, {
                    'menu status is 200': (r) => r.status === 200,
                    'menu has items': (r) => {
                        try {
                            return JSON.parse(r.body).length > 0;
                        } catch {
                            return false;
                        }
                    },
                });

                menuFetchDuration.add(Date.now() - menuStart);
            });

            sleep(randomInt(1, 3)); // Browse menu
        }

        // Step 2: Create order (80% of users)
        if (Math.random() < 0.8) {
            group('Place Order', function () {
                const order = generateOrder();
                const orderStart = Date.now();

                const orderRes = http.post(
                    `${BASE_URL}/api/orders`,
                    JSON.stringify(order),
                    {
                        headers: { 'Content-Type': 'application/json' },
                        tags: { name: 'CreateOrder' },
                    }
                );

                const success = check(orderRes, {
                    'order status is 201': (r) => r.status === 201,
                    'order has order_id': (r) => {
                        try {
                            return JSON.parse(r.body).order_id !== undefined;
                        } catch {
                            return false;
                        }
                    },
                    'order response time OK': (r) => r.timings.duration < 1000,
                });

                if (success) {
                    totalOrders.add(1);

                    // Step 3: Retrieve order (optional - 30% of users double-check)
                    if (Math.random() < 0.3) {
                        try {
                            const orderId = JSON.parse(orderRes.body).order_id;
                            sleep(1);

                            const getOrderRes = http.get(
                                `${BASE_URL}/api/orders/${orderId}`,
                                {
                                    tags: { name: 'GetOrder' },
                                }
                            );

                            check(getOrderRes, {
                                'get order status is 200': (r) => r.status === 200,
                            });
                        } catch (e) {
                            console.error('Failed to retrieve order:', e);
                        }
                    }
                } else {
                    orderCreationErrors.add(1);
                }

                orderCreationDuration.add(Date.now() - orderStart);
            });
        }

        // Step 4: Check loyalty points (20% of users)
        if (Math.random() < 0.2) {
            group('Check Loyalty', function () {
                const userId = `user-${__VU}-${randomInt(1, 1000)}`;
                const loyaltyRes = http.get(
                    `${BASE_URL}/api/loyalty/points/${userId}`,
                    {
                        tags: { name: 'GetLoyalty' },
                    }
                );

                check(loyaltyRes, {
                    'loyalty status is 200 or 404': (r) =>
                        r.status === 200 || r.status === 404,
                });
            });
        }
    });

    // Think time - simulate user interaction
    sleep(randomInt(2, 5));
}

// Summary handler
export function handleSummary(data) {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 Morning Rush Load Test Summary');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    const metrics = data.metrics;

    console.log('🔢 Request Statistics:');
    console.log(`  Total Requests: ${metrics.http_reqs.values.count}`);
    console.log(
        `  Request Rate: ${metrics.http_reqs.values.rate.toFixed(2)} req/s`
    );
    console.log(
        `  Failed Requests: ${(metrics.http_req_failed.values.rate * 100).toFixed(2)}%`
    );

    console.log('\n⏱️  Response Times:');
    console.log(`  Average: ${metrics.http_req_duration.values.avg.toFixed(2)}ms`);
    console.log(`  p95: ${metrics.http_req_duration.values['p(95)'].toFixed(2)}ms`);
    console.log(`  p99: ${metrics.http_req_duration.values['p(99)'].toFixed(2)}ms`);
    console.log(`  Max: ${metrics.http_req_duration.values.max.toFixed(2)}ms`);

    if (metrics.order_creation_duration) {
        console.log('\n📦 Order Creation:');
        console.log(
            `  Total Orders: ${metrics.total_orders_created.values.count}`
        );
        console.log(
            `  Avg Duration: ${metrics.order_creation_duration.values.avg.toFixed(2)}ms`
        );
        console.log(
            `  p95 Duration: ${metrics.order_creation_duration.values['p(95)'].toFixed(2)}ms`
        );
        console.log(
            `  Error Rate: ${(metrics.order_creation_errors.values.rate * 100).toFixed(2)}%`
        );
    }

    console.log('\n🎯 Threshold Results:');
    for (const [name, threshold] of Object.entries(data.thresholds)) {
        const status = threshold.ok ? '✓' : '✗';
        console.log(`  ${status} ${name}`);
    }

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    return {
        'summary.json': JSON.stringify(data, null, 2),
        stdout: '', // Prevent default summary
    };
}
