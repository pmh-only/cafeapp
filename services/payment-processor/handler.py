"""
Payment Processor Lambda Function

Processes payment transactions from SQS FIFO queue. Validates payment methods,
processes charges (mock Stripe/Square API), and writes transactions to DynamoDB.

Stress Scenario: Cold Start Avalanche
- Simulates Black Friday traffic spike
- 10K concurrent Lambda invocations
- All experience cold starts (3s initialization)
- CPU-intensive fraud validation
"""

import json
import os
import time
import hashlib
import random
from datetime import datetime
from decimal import Decimal

import boto3

# Initialize AWS clients (outside handler for connection reuse)
dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
cloudwatch = boto3.client('cloudwatch', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

# DynamoDB table
TRANSACTIONS_TABLE = os.environ.get('DYNAMODB_TABLE', 'cloudcafe-payment-transactions-dev')
transactions_table = dynamodb.Table(TRANSACTIONS_TABLE)

# Cold start detection
COLD_START = True


def lambda_handler(event, context):
    """
    Lambda handler for payment processing

    Triggered by: SQS FIFO queue
    Processes: Payment transactions
    Outputs: DynamoDB transaction records
    """
    global COLD_START

    start_time = time.time()
    is_cold_start = COLD_START
    COLD_START = False

    # Stress mode: Simulate cold start delay
    if os.environ.get('STRESS_MODE') == 'cold_start' and is_cold_start:
        print("⚠️ STRESS MODE: Simulating cold start delay (3s)")
        time.sleep(3)

        # Additional CPU stress during cold start
        cold_start_cpu_stress()

    processed_count = 0
    failed_count = 0

    try:
        # Process SQS records
        for record in event.get('Records', []):
            try:
                # Parse payment message
                payment = json.loads(record['body'])

                # Validate payment
                if not validate_payment(payment):
                    print(f"❌ Invalid payment: {payment.get('payment_id')}")
                    failed_count += 1
                    continue

                # Process payment (mock)
                transaction = process_payment(payment)

                # Fraud scoring (CPU-intensive)
                fraud_score = calculate_fraud_score(payment)
                transaction['fraud_score'] = fraud_score

                if fraud_score > 80:
                    print(f"⚠️ High fraud score: {fraud_score} for payment {payment['payment_id']}")
                    transaction['status'] = 'flagged_for_review'
                else:
                    transaction['status'] = 'completed'

                # Write to DynamoDB
                write_transaction(transaction)

                processed_count += 1
                print(f"✅ Processed payment: {payment['payment_id']}")

            except Exception as e:
                print(f"❌ Error processing record: {e}")
                failed_count += 1

        duration = time.time() - start_time

        # Emit CloudWatch metrics
        emit_metrics({
            'ProcessedPayments': processed_count,
            'FailedPayments': failed_count,
            'Duration': duration * 1000,  # milliseconds
            'ColdStart': 1 if is_cold_start else 0,
        })

        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed': processed_count,
                'failed': failed_count,
                'cold_start': is_cold_start,
                'duration_ms': duration * 1000
            })
        }

    except Exception as e:
        print(f"❌ Lambda error: {e}")

        emit_metrics({
            'LambdaErrors': 1
        })

        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def validate_payment(payment):
    """Validate payment data structure"""
    required_fields = ['payment_id', 'order_id', 'customer_id', 'amount', 'payment_method']

    for field in required_fields:
        if field not in payment:
            return False

    # Validate amount
    try:
        amount = float(payment['amount'])
        if amount <= 0 or amount > 10000:
            return False
    except (ValueError, TypeError):
        return False

    return True


def process_payment(payment):
    """
    Process payment through payment gateway (mock)

    In production, this would call Stripe, Square, or other payment API
    """
    payment_id = payment['payment_id']
    amount = float(payment['amount'])

    # Mock API call delay
    time.sleep(random.uniform(0.05, 0.15))

    # Create transaction record
    transaction = {
        'transaction_id': f"txn-{payment_id}",
        'payment_id': payment_id,
        'order_id': payment['order_id'],
        'customer_id': payment['customer_id'],
        'amount': Decimal(str(amount)),
        'payment_method': payment['payment_method'],
        'gateway_response': {
            'status': 'approved',
            'authorization_code': hashlib.sha256(payment_id.encode()).hexdigest()[:12],
            'timestamp': datetime.utcnow().isoformat()
        },
        'processed_at': datetime.utcnow().isoformat(),
        'status': 'processing'
    }

    return transaction


def calculate_fraud_score(payment):
    """
    Calculate fraud score (CPU-intensive)

    Stress Scenario: This simulates complex fraud detection algorithms
    that analyze transaction patterns, device fingerprints, etc.
    """
    score = 0

    # CPU-intensive operations
    for i in range(10000):
        # Hash various payment attributes
        data = f"{payment['payment_id']}{i}{random.random()}".encode()
        hash_result = hashlib.sha256(data).hexdigest()

        # Pattern matching (CPU-intensive)
        score += sum(c.isdigit() for c in hash_result[:10])

    # Additional fraud checks (more CPU)
    amount = float(payment['amount'])

    # Suspicious amount patterns
    if amount > 1000:
        for _ in range(1000):
            hashlib.sha256(str(amount).encode()).hexdigest()
        score += 5

    # Normalize score to 0-100
    fraud_score = min((score % 100), 100)

    return fraud_score


def write_transaction(transaction):
    """Write transaction to DynamoDB"""
    try:
        # Convert float to Decimal for DynamoDB
        if isinstance(transaction.get('amount'), float):
            transaction['amount'] = Decimal(str(transaction['amount']))

        if isinstance(transaction.get('fraud_score'), float):
            transaction['fraud_score'] = Decimal(str(transaction['fraud_score']))

        transactions_table.put_item(Item=transaction)

    except Exception as e:
        print(f"❌ DynamoDB write error: {e}")
        raise


def cold_start_cpu_stress():
    """
    CPU stress during cold start initialization

    Simulates loading ML models, initializing payment SDKs, etc.
    """
    print("🔥 Cold start CPU stress: Loading payment processing models...")

    # Heavy computation during cold start
    for i in range(10_000_000):
        hashlib.sha256(str(random.random()).encode()).digest()

    print("✅ Cold start initialization complete")


def emit_metrics(metrics):
    """Emit custom CloudWatch metrics"""
    try:
        metric_data = []

        for metric_name, value in metrics.items():
            metric_data.append({
                'MetricName': metric_name,
                'Value': value,
                'Unit': 'Count' if 'Count' in metric_name or 'Payments' in metric_name else 'Milliseconds',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [
                    {'Name': 'Service', 'Value': 'PaymentProcessor'},
                    {'Name': 'Environment', 'Value': os.environ.get('ENVIRONMENT', 'dev')}
                ]
            })

        cloudwatch.put_metric_data(
            Namespace='CloudCafe/Lambda',
            MetricData=metric_data
        )

    except Exception as e:
        print(f"⚠️ CloudWatch metric error: {e}")


# For local testing
if __name__ == '__main__':
    # Mock SQS event
    test_event = {
        'Records': [
            {
                'body': json.dumps({
                    'payment_id': 'pay-test-123',
                    'order_id': 'ord-123',
                    'customer_id': 'cust-456',
                    'amount': 25.99,
                    'payment_method': 'credit_card'
                })
            }
        ]
    }

    test_context = {}

    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2))
