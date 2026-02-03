/**
 * Menu Service - Node.js/Express on EKS
 *
 * Manages menu catalog and customizations for 30K stores.
 * Uses DocumentDB (MongoDB) for flexible schema and ElastiCache for caching.
 */

const express = require('express');
const mongoose = require('mongoose');
const redis = require('redis');
const AWS = require('aws-sdk');
const crypto = require('crypto');
const { simulateMenuSync } = require('./stress');

// Configuration
const PORT = process.env.PORT || 8080;
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/cloudcafe';
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = process.env.REDIS_PORT || 6379;
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

// Initialize Express
const app = express();
app.use(express.json());

// Initialize AWS CloudWatch
const cloudwatch = new AWS.CloudWatch({ region: AWS_REGION });

// Initialize Redis client
let redisClient;
(async () => {
    try {
        redisClient = redis.createClient({
            socket: {
                host: REDIS_HOST,
                port: REDIS_PORT
            }
        });

        redisClient.on('error', (err) => console.error('Redis Client Error', err));
        redisClient.on('connect', () => console.log('✅ Connected to Redis'));

        await redisClient.connect();
    } catch (error) {
        console.error('⚠️ Redis connection failed:', error.message);
    }
})();

// MongoDB Schema
const menuItemSchema = new mongoose.Schema({
    item_id: { type: String, required: true, unique: true },
    name: { type: String, required: true },
    description: String,
    category: String,
    price: Number,
    calories: Number,
    ingredients: [String],
    allergens: [String],
    available: { type: Boolean, default: true },
    image_url: String,
    created_at: { type: Date, default: Date.now },
    updated_at: { type: Date, default: Date.now }
});

const MenuItem = mongoose.model('MenuItem', menuItemSchema);

// Connect to MongoDB
mongoose.connect(MONGODB_URI, {
    useNewUrlParser: true,
    useUnifiedTopology: true
}).then(() => {
    console.log('✅ Connected to DocumentDB (MongoDB)');
}).catch((error) => {
    console.error('❌ MongoDB connection error:', error);
});

// Routes

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        service: 'menu-service',
        timestamp: new Date().toISOString(),
        connections: {
            mongodb: mongoose.connection.readyState === 1,
            redis: redisClient?.isOpen || false
        }
    });
});

/**
 * Get all menu items (with caching)
 */
app.get('/menu/items', async (req, res) => {
    const startTime = Date.now();
    const category = req.query.category;

    try {
        // Try cache first
        const cacheKey = category ? `menu:category:${category}` : 'menu:all';

        if (redisClient?.isOpen) {
            const cached = await redisClient.get(cacheKey);
            if (cached) {
                const duration = Date.now() - startTime;

                await emitMetric('CacheHit', 1);
                await emitMetric('QueryDuration', duration);

                return res.json({
                    items: JSON.parse(cached),
                    cached: true,
                    duration_ms: duration
                });
            }
        }

        // Cache miss - query DocumentDB
        const query = category ? { category, available: true } : { available: true };
        const items = await MenuItem.find(query).select('-__v').lean();

        // Cache for 5 minutes
        if (redisClient?.isOpen) {
            await redisClient.setEx(cacheKey, 300, JSON.stringify(items));
        }

        const duration = Date.now() - startTime;

        await emitMetric('CacheMiss', 1);
        await emitMetric('QueryDuration', duration);

        res.json({
            items,
            cached: false,
            count: items.length,
            duration_ms: duration
        });

    } catch (error) {
        console.error('Error fetching menu items:', error);
        await emitMetric('QueryError', 1);
        res.status(500).json({ error: error.message });
    }
});

/**
 * Get single menu item
 */
app.get('/menu/items/:itemId', async (req, res) => {
    const { itemId } = req.params;

    try {
        // Try cache
        const cacheKey = `menu:item:${itemId}`;

        if (redisClient?.isOpen) {
            const cached = await redisClient.get(cacheKey);
            if (cached) {
                await emitMetric('CacheHit', 1);
                return res.json({ item: JSON.parse(cached), cached: true });
            }
        }

        // Query database
        const item = await MenuItem.findOne({ item_id: itemId }).select('-__v').lean();

        if (!item) {
            return res.status(404).json({ error: 'Item not found' });
        }

        // Cache for 10 minutes
        if (redisClient?.isOpen) {
            await redisClient.setEx(cacheKey, 600, JSON.stringify(item));
        }

        await emitMetric('CacheMiss', 1);

        res.json({ item, cached: false });

    } catch (error) {
        console.error('Error fetching menu item:', error);
        await emitMetric('QueryError', 1);
        res.status(500).json({ error: error.message });
    }
});

/**
 * Create or update menu item
 */
app.post('/menu/items', async (req, res) => {
    try {
        const itemData = req.body;
        itemData.updated_at = new Date();

        const item = await MenuItem.findOneAndUpdate(
            { item_id: itemData.item_id },
            itemData,
            { upsert: true, new: true, runValidators: true }
        ).select('-__v').lean();

        // Invalidate cache
        if (redisClient?.isOpen) {
            await redisClient.del('menu:all');
            if (itemData.category) {
                await redisClient.del(`menu:category:${itemData.category}`);
            }
            await redisClient.del(`menu:item:${itemData.item_id}`);
        }

        await emitMetric('MenuItemUpdated', 1);

        res.status(201).json({ item });

    } catch (error) {
        console.error('Error creating/updating menu item:', error);
        await emitMetric('UpdateError', 1);
        res.status(500).json({ error: error.message });
    }
});

/**
 * Trigger stress scenario: Menu Sync Storm
 */
app.post('/stress/menu-sync', async (req, res) => {
    const { duration_seconds = 180, target_cpu = 70 } = req.body;

    console.log(`🔥 Starting Menu Sync Storm: ${duration_seconds}s, target CPU ${target_cpu}%`);

    // Run stress in background
    setImmediate(() => {
        simulateMenuSync(duration_seconds, target_cpu, cloudwatch);
    });

    res.json({
        status: 'stress_started',
        scenario: 'menu_sync_storm',
        duration_seconds,
        target_cpu
    });
});

/**
 * Emit CloudWatch metric
 */
async function emitMetric(metricName, value) {
    try {
        const params = {
            Namespace: 'CloudCafe/Menu',
            MetricData: [{
                MetricName: metricName,
                Value: value,
                Unit: metricName.includes('Duration') ? 'Milliseconds' : 'Count',
                Timestamp: new Date(),
                Dimensions: [
                    { Name: 'Service', Value: 'MenuService' },
                    { Name: 'Environment', Value: process.env.ENVIRONMENT || 'dev' }
                ]
            }]
        };

        await cloudwatch.putMetricData(params).promise();
    } catch (error) {
        console.error('CloudWatch metric error:', error.message);
    }
}

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
    console.log(`🚀 Menu Service listening on port ${PORT}`);
    console.log(`   Environment: ${process.env.ENVIRONMENT || 'dev'}`);
    console.log(`   MongoDB: ${MONGODB_URI}`);
    console.log(`   Redis: ${REDIS_HOST}:${REDIS_PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('SIGTERM received, shutting down gracefully...');

    if (redisClient?.isOpen) {
        await redisClient.quit();
    }

    await mongoose.connection.close();

    process.exit(0);
});
