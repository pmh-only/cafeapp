-- CloudCafe RDS Aurora PostgreSQL Schema Initialization
-- Run this script after deploying infrastructure

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
    order_id VARCHAR(255) PRIMARY KEY,
    customer_id VARCHAR(255) NOT NULL,
    store_id VARCHAR(255) NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_store_id ON orders(store_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_customer_created ON orders(customer_id, created_at DESC);

-- Order items table
CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id VARCHAR(255) NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    item_id VARCHAR(255) NOT NULL,
    item_name VARCHAR(255),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_item_id ON order_items(item_id);

-- Stores table
CREATE TABLE IF NOT EXISTS stores (
    store_id VARCHAR(255) PRIMARY KEY,
    store_name VARCHAR(255) NOT NULL,
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(50),
    zip_code VARCHAR(20),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_stores_city ON stores(city);
CREATE INDEX IF NOT EXISTS idx_stores_state ON stores(state);
CREATE INDEX IF NOT EXISTS idx_stores_status ON stores(status);

-- Users table (for loyalty service)
CREATE TABLE IF NOT EXISTS users (
    user_id VARCHAR(255) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    loyalty_points INTEGER NOT NULL DEFAULT 0,
    loyalty_tier VARCHAR(50) NOT NULL DEFAULT 'bronze',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_loyalty_tier ON users(loyalty_tier);
CREATE INDEX IF NOT EXISTS idx_users_loyalty_points ON users(loyalty_points DESC);

-- Loyalty transactions table
CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    order_id VARCHAR(255) REFERENCES orders(order_id) ON DELETE SET NULL,
    points_change INTEGER NOT NULL,
    transaction_type VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_user_id ON loyalty_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_order_id ON loyalty_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_created_at ON loyalty_transactions(created_at DESC);

-- Inventory table (complementary to DynamoDB)
CREATE TABLE IF NOT EXISTS inventory_sync_log (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(255) NOT NULL,
    sku VARCHAR(255) NOT NULL,
    quantity_before INTEGER,
    quantity_after INTEGER,
    sync_source VARCHAR(100),
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_inventory_sync_store_id ON inventory_sync_log(store_id);
CREATE INDEX IF NOT EXISTS idx_inventory_sync_sku ON inventory_sync_log(sku);
CREATE INDEX IF NOT EXISTS idx_inventory_sync_synced_at ON inventory_sync_log(synced_at DESC);

-- Insert sample stores
INSERT INTO stores (store_id, store_name, address, city, state, zip_code, latitude, longitude, status)
VALUES
    ('1', 'CloudCafe Downtown', '123 Main St', 'Seattle', 'WA', '98101', 47.6062, -122.3321, 'active'),
    ('2', 'CloudCafe University', '456 Campus Dr', 'Seattle', 'WA', '98105', 47.6553, -122.3035, 'active'),
    ('3', 'CloudCafe Airport', '789 Airport Way', 'SeaTac', 'WA', '98188', 47.4502, -122.3088, 'active'),
    ('4', 'CloudCafe Tech Hub', '321 Innovation Blvd', 'Redmond', 'WA', '98052', 47.6740, -122.1215, 'active'),
    ('5', 'CloudCafe Waterfront', '654 Harbor St', 'Seattle', 'WA', '98101', 47.6097, -122.3331, 'active')
ON CONFLICT (store_id) DO NOTHING;

-- Insert sample users
INSERT INTO users (user_id, email, first_name, last_name, loyalty_points, loyalty_tier)
VALUES
    ('user-1', 'alice@example.com', 'Alice', 'Johnson', 150, 'silver'),
    ('user-2', 'bob@example.com', 'Bob', 'Smith', 50, 'bronze'),
    ('user-3', 'carol@example.com', 'Carol', 'Williams', 500, 'gold'),
    ('user-4', 'david@example.com', 'David', 'Brown', 1200, 'platinum'),
    ('user-5', 'eve@example.com', 'Eve', 'Davis', 75, 'bronze')
ON CONFLICT (user_id) DO NOTHING;

-- Update trigger for orders
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_stores_updated_at BEFORE UPDATE ON stores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to calculate loyalty points
CREATE OR REPLACE FUNCTION calculate_loyalty_points(order_total DECIMAL)
RETURNS INTEGER AS $$
BEGIN
    -- 1 point per dollar spent
    RETURN FLOOR(order_total);
END;
$$ LANGUAGE plpgsql;

-- Function to get loyalty tier
CREATE OR REPLACE FUNCTION get_loyalty_tier(total_points INTEGER)
RETURNS VARCHAR AS $$
BEGIN
    IF total_points >= 1000 THEN
        RETURN 'platinum';
    ELSIF total_points >= 500 THEN
        RETURN 'gold';
    ELSIF total_points >= 100 THEN
        RETURN 'silver';
    ELSE
        RETURN 'bronze';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- View for order analytics
CREATE OR REPLACE VIEW order_analytics AS
SELECT
    DATE(o.created_at) as order_date,
    o.store_id,
    s.store_name,
    COUNT(*) as total_orders,
    SUM(o.total_amount) as total_revenue,
    AVG(o.total_amount) as avg_order_value,
    COUNT(DISTINCT o.customer_id) as unique_customers
FROM orders o
JOIN stores s ON o.store_id = s.store_id
GROUP BY DATE(o.created_at), o.store_id, s.store_name;

-- View for top customers
CREATE OR REPLACE VIEW top_customers AS
SELECT
    u.user_id,
    u.email,
    u.first_name,
    u.last_name,
    u.loyalty_points,
    u.loyalty_tier,
    COUNT(o.order_id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    MAX(o.created_at) as last_order_date
FROM users u
LEFT JOIN orders o ON u.user_id = o.customer_id
GROUP BY u.user_id, u.email, u.first_name, u.last_name, u.loyalty_points, u.loyalty_tier
ORDER BY u.loyalty_points DESC;

-- Grant permissions (adjust as needed for your app user)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO cloudcafe_admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cloudcafe_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO cloudcafe_admin;

-- Verify tables created
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ CloudCafe database schema initialized successfully!';
    RAISE NOTICE '   Tables created: orders, order_items, stores, users, loyalty_transactions, inventory_sync_log';
    RAISE NOTICE '   Sample data inserted: 5 stores, 5 users';
    RAISE NOTICE '   Views created: order_analytics, top_customers';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Deploy microservices';
    RAISE NOTICE '  2. Test order creation';
    RAISE NOTICE '  3. Monitor CloudWatch metrics';
END $$;
