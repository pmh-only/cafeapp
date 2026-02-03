import os
import json
import time
import uuid
from datetime import datetime
from flask import Flask, request, jsonify
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
from stress import MorningRushStress

app = Flask(__name__)

# AWS Clients
dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
kinesis = boto3.client('kinesis', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
cloudwatch = boto3.client('cloudwatch', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

# DynamoDB Table
active_orders_table = dynamodb.Table(os.environ.get('DYNAMODB_ACTIVE_ORDERS_TABLE', 'cloudcafe-active-orders-dev'))

# Redis Client
redis_client = None
if os.environ.get('REDIS_HOST'):
    redis_client = redis.Redis(
        host=os.environ.get('REDIS_HOST'),
        port=int(os.environ.get('REDIS_PORT', 6379)),
        decode_responses=True
    )

# PostgreSQL Connection
def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('DB_HOST'),
        port=int(os.environ.get('DB_PORT', 5432)),
        database=os.environ.get('DB_NAME', 'cloudcafe'),
        user=os.environ.get('DB_USER'),
        password=os.environ.get('DB_PASSWORD')
    )

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'order-service',
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/orders', methods=['POST'])
def create_order():
    """Create a new order"""
    start_time = time.time()

    try:
        data = request.json
        order_id = str(uuid.uuid4())
        customer_id = data.get('customer_id')
        store_id = data.get('store_id')
        items = data.get('items', [])

        # Calculate total
        total_amount = sum(item.get('price', 5.0) * item.get('quantity', 1) for item in items)

        created_at = int(time.time())

        order = {
            'order_id': order_id,
            'customer_id': customer_id,
            'store_id': str(store_id),
            'items': items,
            'total_amount': total_amount,
            'status': 'pending',
            'created_at': created_at,
            'ttl': created_at + 86400  # 24 hours TTL
        }

        # Write to DynamoDB (fast cache)
        active_orders_table.put_item(Item=order)

        # Write to RDS (persistent storage)
        try:
            conn = get_db_connection()
            cursor = conn.cursor()

            # Insert into orders table
            cursor.execute("""
                INSERT INTO orders (order_id, customer_id, store_id, total_amount, status, created_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (order_id) DO NOTHING
            """, (order_id, customer_id, store_id, total_amount, 'pending', datetime.utcnow()))

            conn.commit()
            cursor.close()
            conn.close()
        except Exception as e:
            app.logger.error(f"RDS write error: {e}")
            # Continue even if RDS fails

        # Publish event to Kinesis
        try:
            kinesis.put_record(
                StreamName=os.environ.get('KINESIS_ORDER_EVENTS_STREAM', 'cloudcafe-order-events-dev'),
                Data=json.dumps(order),
                PartitionKey=customer_id
            )
        except Exception as e:
            app.logger.error(f"Kinesis publish error: {e}")

        # Emit custom metric
        duration = time.time() - start_time
        try:
            cloudwatch.put_metric_data(
                Namespace='CloudCafe/OrderService',
                MetricData=[
                    {
                        'MetricName': 'OrderCreationDuration',
                        'Value': duration * 1000,  # milliseconds
                        'Unit': 'Milliseconds',
                        'Timestamp': datetime.utcnow()
                    },
                    {
                        'MetricName': 'OrdersCreated',
                        'Value': 1,
                        'Unit': 'Count',
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
        except Exception as e:
            app.logger.error(f"CloudWatch metric error: {e}")

        return jsonify({
            'order_id': order_id,
            'status': 'pending',
            'total_amount': total_amount,
            'created_at': created_at
        }), 201

    except Exception as e:
        app.logger.error(f"Order creation error: {e}")

        # Emit error metric
        try:
            cloudwatch.put_metric_data(
                Namespace='CloudCafe/OrderService',
                MetricData=[{
                    'MetricName': 'OrderCreationErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }]
            )
        except:
            pass

        return jsonify({'error': str(e)}), 500

@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    """Get order by ID"""
    try:
        # Try DynamoDB first (cache)
        response = active_orders_table.get_item(Key={'order_id': order_id})

        if 'Item' in response:
            return jsonify(response['Item']), 200

        # Fall back to RDS
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM orders WHERE order_id = %s", (order_id,))
        order = cursor.fetchone()
        cursor.close()
        conn.close()

        if order:
            return jsonify(dict(order)), 200
        else:
            return jsonify({'error': 'Order not found'}), 404

    except Exception as e:
        app.logger.error(f"Get order error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/stress/morning-rush', methods=['POST'])
def trigger_morning_rush():
    """Trigger CPU stress scenario - Morning Rush"""
    try:
        data = request.json or {}
        duration = data.get('duration_seconds', 300)
        target_cpu = data.get('target_cpu', 95)

        app.logger.info(f"Starting Morning Rush stress scenario: {duration}s, target CPU {target_cpu}%")

        # Run stress in background (for demo purposes, blocking in real scenario)
        stress = MorningRushStress()
        stress.simulate(duration_seconds=duration, target_cpu=target_cpu)

        return jsonify({
            'status': 'stress_started',
            'scenario': 'morning_rush',
            'duration_seconds': duration,
            'target_cpu': target_cpu
        }), 200

    except Exception as e:
        app.logger.error(f"Stress scenario error: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
