import time
import hashlib
import json
import random
from datetime import datetime
import psutil
import boto3
import os

cloudwatch = boto3.client('cloudwatch', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

class MorningRushStress:
    """
    Stress Scenario: Morning Rush

    Story: 7:45 AM Monday morning. Corporate offices across the city
    place bulk orders for team meetings. The order service is suddenly
    processing 50x normal traffic. Each order requires:
    - Complex validation (CPU-intensive)
    - Fraud scoring (SHA256 hashing)
    - Inventory reservation checks (Fibonacci calculations)
    - Tax calculations (floating point operations)

    Expected Impact:
    - ECS task CPU spikes to 95%+
    - Task count increases due to autoscaling
    - Response time increases from 50ms to 500ms+
    - CloudWatch dashboard shows CPU and latency anomalies
    """

    def __init__(self):
        self.scenario_name = "MorningRush"

    def _validate_complex_order(self):
        """CPU-intensive order validation"""
        order_data = {
            'items': [{'id': f'item-{i}', 'qty': random.randint(1, 10)} for i in range(100)],
            'customer_tier': random.choice(['bronze', 'silver', 'gold', 'platinum']),
            'delivery_urgency': random.choice(['standard', 'express', 'rush']),
        }

        # JSON serialization/deserialization
        for _ in range(10):
            json_str = json.dumps(order_data)
            json.loads(json_str)

        return order_data

    def _fraud_check(self, order):
        """CPU-intensive fraud scoring using SHA256"""
        score = 0
        for i in range(1000):
            # Hash calculations
            data = f"{order}{i}{random.random()}".encode()
            hash_result = hashlib.sha256(data).hexdigest()

            # Simulate pattern matching
            score += sum(c.isdigit() for c in hash_result[:10])

        return score % 100  # Return fraud score 0-100

    def _inventory_reservation(self, order):
        """CPU-intensive inventory check with Fibonacci calculations"""
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)

        # Calculate Fibonacci for each item (CPU-intensive)
        total_complexity = 0
        for item in order.get('items', [])[:10]:  # Limit to prevent stack overflow
            qty = item.get('qty', 1)
            total_complexity += fibonacci(min(20 + qty, 30))

        return total_complexity

    def _tax_calculation(self):
        """Floating point operations for tax calculation"""
        base = random.uniform(1.0, 100.0)
        result = base

        for _ in range(10000):
            result = result * 1.0825  # Sales tax
            result = result / 1.0825
            result = result + 0.001
            result = result - 0.001

        return result

    def simulate(self, duration_seconds=300, target_cpu=95):
        """
        Run the morning rush stress simulation

        Args:
            duration_seconds: How long to run the stress (default 5 minutes)
            target_cpu: Target CPU utilization percentage (default 95%)
        """
        print(f"\n{'='*80}")
        print(f"🔥 STRESS SCENARIO: MORNING RUSH")
        print(f"{'='*80}")
        print(f"Story: 7:45 AM Monday. Corporate bulk orders flooding in.")
        print(f"Duration: {duration_seconds} seconds")
        print(f"Target CPU: {target_cpu}%")
        print(f"{'='*80}\n")

        start_time = time.time()
        iteration = 0

        while time.time() - start_time < duration_seconds:
            iteration += 1

            # Simulate processing multiple concurrent orders
            for _ in range(10):
                # 1. Complex order validation
                order = self._validate_complex_order()

                # 2. Fraud scoring (SHA256 hashing)
                fraud_score = self._fraud_check(order)

                # 3. Inventory reservation (Fibonacci)
                inventory_complexity = self._inventory_reservation(order)

                # 4. Tax calculation (floating point)
                tax_amount = self._tax_calculation()

            # Get current CPU usage
            current_cpu = psutil.cpu_percent(interval=0.1)

            # Emit CloudWatch metrics
            if iteration % 10 == 0:  # Every 10 iterations
                try:
                    cloudwatch.put_metric_data(
                        Namespace='CloudCafe/OrderService',
                        MetricData=[
                            {
                                'MetricName': 'CPUStressLevel',
                                'Value': current_cpu,
                                'Unit': 'Percent',
                                'Dimensions': [
                                    {'Name': 'Scenario', 'Value': self.scenario_name}
                                ],
                                'Timestamp': datetime.utcnow()
                            },
                            {
                                'MetricName': 'StressIterations',
                                'Value': iteration,
                                'Unit': 'Count',
                                'Dimensions': [
                                    {'Name': 'Scenario', 'Value': self.scenario_name}
                                ],
                                'Timestamp': datetime.utcnow()
                            }
                        ]
                    )

                    print(f"[{int(time.time() - start_time)}s] Iteration {iteration} | CPU: {current_cpu:.1f}%")
                except Exception as e:
                    print(f"CloudWatch metric error: {e}")

            # Adaptive delay to hit target CPU
            if current_cpu < target_cpu - 10:
                time.sleep(0.001)  # Too low, work harder
            elif current_cpu > target_cpu + 10:
                time.sleep(0.1)    # Too high, back off

        elapsed = time.time() - start_time
        print(f"\n{'='*80}")
        print(f"✅ STRESS COMPLETE")
        print(f"Total time: {elapsed:.1f}s")
        print(f"Total iterations: {iteration}")
        print(f"{'='*80}\n")

        # Final metric
        try:
            cloudwatch.put_metric_data(
                Namespace='CloudCafe/OrderService',
                MetricData=[{
                    'MetricName': 'StressCompleted',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Scenario', 'Value': self.scenario_name}
                    ],
                    'Timestamp': datetime.utcnow()
                }]
            )
        except Exception as e:
            print(f"Final metric error: {e}")
