/**
 * Stress Scenario: Menu Sync Storm
 *
 * Story: Marketing department launches seasonal menu (Pumpkin Spice season!).
 * All 50 Kubernetes pods receive webhook to sync 10,000 menu items from
 * upstream API. Each pod downloads high-res images and processes JSON.
 *
 * Expected Impact:
 * - Node.js CPU → 70%
 * - DocumentDB CPU spike
 * - ElastiCache evictions (memory pressure)
 * - Network throughput increases
 * - Pod memory usage increases
 */

const crypto = require('crypto');
const os = require('os');

/**
 * Simulate menu synchronization from upstream API
 */
function simulateMenuSync(durationSeconds, targetCpu, cloudwatch) {
    console.log('========================================');
    console.log('🔥 STRESS SCENARIO: MENU SYNC STORM');
    console.log('========================================');
    console.log(`Story: Marketing pushes seasonal menu. All pods sync 10K items.`);
    console.log(`Duration: ${durationSeconds}s`);
    console.log(`Target CPU: ${targetCpu}%`);
    console.log('========================================');

    const startTime = Date.now();
    let iteration = 0;

    const worker = () => {
        const elapsed = (Date.now() - startTime) / 1000;

        if (elapsed >= durationSeconds) {
            console.log('========================================');
            console.log('✅ STRESS COMPLETE');
            console.log(`Total time: ${elapsed.toFixed(1)}s`);
            console.log(`Total iterations: ${iteration}`);
            console.log('========================================');

            // Final metric
            emitMetric(cloudwatch, 'MenuSyncCompleted', 1, 'MenuSyncStorm');
            return;
        }

        // Simulate syncing 100 menu items per iteration
        for (let i = 0; i < 100; i++) {
            const menuItem = generateMenuItem(i);

            // CPU-intensive operations

            // 1. JSON processing (parse/stringify)
            for (let j = 0; j < 100; j++) {
                JSON.stringify(menuItem);
                JSON.parse(JSON.stringify(menuItem));
            }

            // 2. Image hash validation (SHA256)
            const imageData = Buffer.alloc(100 * 1024); // 100KB image
            imageData.fill(Math.random() * 256);
            const imageHash = crypto.createHash('sha256').update(imageData).digest('hex');

            // 3. Nutritional calculation (floating point ops)
            let calories = 0;
            for (let k = 0; k < 1000; k++) {
                calories += Math.sqrt(menuItem.price * k) * 1.5;
                calories = calories / 1.001;
            }

            // 4. Text processing (description generation)
            const description = generateDescription(menuItem.name, 50);

            // 5. More crypto operations
            crypto.createHash('sha256').update(description).digest('hex');
        }

        iteration++;

        // Emit metrics every 10 iterations
        if (iteration % 10 === 0) {
            const cpuUsage = getCpuUsage();

            emitMetric(cloudwatch, 'MenuSyncCPU', cpuUsage, 'MenuSyncStorm');
            emitMetric(cloudwatch, 'MenuSyncIterations', iteration, 'MenuSyncStorm');

            console.log(`[${elapsed.toFixed(0)}s] CPU: ${cpuUsage.toFixed(1)}% | Iterations: ${iteration}`);
        }

        // Adaptive delay to hit target CPU
        const cpuUsage = getCpuUsage();
        let delay = 0;

        if (cpuUsage < targetCpu - 10) {
            delay = 1; // Too low, work harder
        } else if (cpuUsage > targetCpu + 10) {
            delay = 100; // Too high, back off
        } else {
            delay = 10; // Just right
        }

        setTimeout(worker, delay);
    };

    // Start worker
    worker();
}

/**
 * Generate synthetic menu item
 */
function generateMenuItem(id) {
    const categories = ['Coffee', 'Tea', 'Pastries', 'Sandwiches', 'Desserts'];
    const names = [
        'Caffe Latte', 'Cappuccino', 'Espresso', 'Mocha', 'Americano',
        'Green Tea', 'Earl Grey', 'Chai Latte', 'Matcha Latte',
        'Croissant', 'Muffin', 'Scone', 'Danish', 'Bagel',
        'Turkey Sandwich', 'Veggie Wrap', 'Club Sandwich',
        'Chocolate Cake', 'Cheesecake', 'Brownie', 'Cookie'
    ];

    return {
        item_id: `item-${id}`,
        name: names[id % names.length],
        description: 'A delicious menu item crafted with care and premium ingredients.',
        category: categories[id % categories.length],
        price: (Math.random() * 10 + 3).toFixed(2),
        calories: Math.floor(Math.random() * 500 + 100),
        ingredients: ['ingredient-a', 'ingredient-b', 'ingredient-c'],
        allergens: ['milk', 'soy', 'wheat'],
        available: true,
        image_url: `https://cloudcafe.com/images/item-${id}.jpg`,
        image_data: Buffer.alloc(100 * 1024).toString('base64') // 100KB base64 image
    };
}

/**
 * Generate description with repeated text processing
 */
function generateDescription(name, repeatCount) {
    let description = `Our signature ${name} is made with the finest ingredients. `;

    for (let i = 0; i < repeatCount; i++) {
        description += `Crafted by expert baristas with ${Math.random() * 10} years of experience. `;
    }

    return description;
}

/**
 * Get current CPU usage percentage
 */
function getCpuUsage() {
    const cpus = os.cpus();
    let totalIdle = 0;
    let totalTick = 0;

    cpus.forEach(cpu => {
        for (const type in cpu.times) {
            totalTick += cpu.times[type];
        }
        totalIdle += cpu.times.idle;
    });

    const idle = totalIdle / cpus.length;
    const total = totalTick / cpus.length;
    const usage = 100 - (100 * idle / total);

    return usage;
}

/**
 * Emit CloudWatch metric
 */
function emitMetric(cloudwatch, metricName, value, scenario) {
    const params = {
        Namespace: 'CloudCafe/Menu',
        MetricData: [{
            MetricName: metricName,
            Value: value,
            Unit: metricName.includes('CPU') ? 'Percent' : 'Count',
            Timestamp: new Date(),
            Dimensions: [
                { Name: 'Scenario', Value: scenario }
            ]
        }]
    };

    cloudwatch.putMetricData(params, (err) => {
        if (err) {
            console.error('CloudWatch metric error:', err.message);
        }
    });
}

module.exports = {
    simulateMenuSync
};
