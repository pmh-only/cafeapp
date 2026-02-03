#!/usr/bin/env python3
"""
CloudCafe Analytics Worker

Kinesis consumer that processes order events and writes aggregated
analytics data to Amazon Redshift.

Deployment: Amazon EC2 with Auto Scaling
"""

import json
import time
import logging
import hashlib
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Any

import boto3
import psycopg2
from psycopg2.extras import execute_batch

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# AWS clients
kinesis = boto3.client('kinesis', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
cloudwatch = boto3.client('cloudwatch', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
redshift_data = boto3.client('redshift-data', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

# Configuration
KINESIS_STREAM_NAME = os.environ.get('KINESIS_STREAM_NAME', 'order-events')
REDSHIFT_CLUSTER_ID = os.environ.get('REDSHIFT_CLUSTER_ID', 'cloudcafe-redshift-dev')
REDSHIFT_DATABASE = os.environ.get('REDSHIFT_DATABASE', 'analytics')
REDSHIFT_DB_USER = os.environ.get('REDSHIFT_DB_USER', 'admin')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
BATCH_SIZE = int(os.environ.get('BATCH_SIZE', '100'))
POLL_INTERVAL = int(os.environ.get('POLL_INTERVAL', '5'))


class AnalyticsWorker:
    """
    Kinesis consumer that processes order events and writes to Redshift
    """

    def __init__(self):
        self.shard_iterators = {}
        self.processed_count = 0
        self.error_count = 0
        self.running = True

    def start(self):
        """Start the analytics worker"""
        logger.info("========================================")
        logger.info("CloudCafe Analytics Worker Starting")
        logger.info("========================================")
        logger.info(f"Stream: {KINESIS_STREAM_NAME}")
        logger.info(f"Redshift Cluster: {REDSHIFT_CLUSTER_ID}")
        logger.info(f"Environment: {ENVIRONMENT}")
        logger.info("========================================")

        try:
            # Initialize shard iterators
            self._initialize_shards()

            # Start processing loop
            while self.running:
                self._process_records()
                time.sleep(POLL_INTERVAL)

        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
            self.running = False

        except Exception as e:
            logger.error(f"Fatal error: {e}", exc_info=True)
            self._emit_metric('WorkerError', 1.0)
            sys.exit(1)

        finally:
            logger.info(f"Shutting down. Processed: {self.processed_count}, Errors: {self.error_count}")

    def _initialize_shards(self):
        """Initialize shard iterators for Kinesis stream"""
        logger.info(f"Initializing shards for stream: {KINESIS_STREAM_NAME}")

        response = kinesis.describe_stream(StreamName=KINESIS_STREAM_NAME)
        shards = response['StreamDescription']['Shards']

        for shard in shards:
            shard_id = shard['ShardId']

            # Get shard iterator (TRIM_HORIZON to start from beginning)
            iterator_response = kinesis.get_shard_iterator(
                StreamName=KINESIS_STREAM_NAME,
                ShardId=shard_id,
                ShardIteratorType='LATEST'  # Use LATEST to start from now
            )

            self.shard_iterators[shard_id] = iterator_response['ShardIterator']
            logger.info(f"Initialized shard: {shard_id}")

    def _process_records(self):
        """Process records from all shards"""
        for shard_id, shard_iterator in list(self.shard_iterators.items()):
            if not shard_iterator:
                continue

            try:
                response = kinesis.get_records(
                    ShardIterator=shard_iterator,
                    Limit=BATCH_SIZE
                )

                records = response['Records']
                next_iterator = response.get('NextShardIterator')

                if records:
                    logger.info(f"Processing {len(records)} records from shard {shard_id}")
                    self._process_batch(records)

                # Update iterator for next poll
                self.shard_iterators[shard_id] = next_iterator

                # Emit metrics
                if records:
                    self._emit_metric('RecordsProcessed', len(records))

            except Exception as e:
                logger.error(f"Error processing shard {shard_id}: {e}")
                self.error_count += 1
                self._emit_metric('ShardProcessingError', 1.0)

    def _process_batch(self, records: List[Dict]):
        """Process a batch of Kinesis records"""
        events = []

        for record in records:
            try:
                data = json.loads(record['Data'])
                events.append(data)
                self.processed_count += 1

            except json.JSONDecodeError as e:
                logger.error(f"Invalid JSON in record: {e}")
                self.error_count += 1

        if events:
            # Write to Redshift
            self._write_to_redshift(events)

    def _write_to_redshift(self, events: List[Dict]):
        """Write events to Redshift using Data API"""
        start_time = time.time()

        try:
            # Build INSERT statement
            values = []
            for event in events:
                order_id = event.get('order_id', 'unknown')
                customer_id = event.get('customer_id', 'unknown')
                store_id = event.get('store_id', 0)
                total_amount = event.get('total_amount', 0.0)
                item_count = event.get('item_count', 0)
                event_type = event.get('event_type', 'order_created')
                timestamp = event.get('timestamp', datetime.utcnow().isoformat())

                values.append(f"('{order_id}', '{customer_id}', {store_id}, {total_amount}, {item_count}, '{event_type}', '{timestamp}')")

            if not values:
                return

            sql = f"""
            INSERT INTO fact_orders (order_id, customer_id, store_id, total_amount, item_count, event_type, event_timestamp)
            VALUES {', '.join(values)}
            """

            # Execute via Redshift Data API
            response = redshift_data.execute_statement(
                ClusterIdentifier=REDSHIFT_CLUSTER_ID,
                Database=REDSHIFT_DATABASE,
                DbUser=REDSHIFT_DB_USER,
                Sql=sql
            )

            statement_id = response['Id']
            duration = (time.time() - start_time) * 1000

            logger.info(f"Wrote {len(events)} events to Redshift (Statement: {statement_id}, Duration: {duration:.0f}ms)")

            self._emit_metric('RedshiftWriteDuration', duration)
            self._emit_metric('RedshiftEventsWritten', len(events))

        except Exception as e:
            logger.error(f"Failed to write to Redshift: {e}")
            self.error_count += len(events)
            self._emit_metric('RedshiftWriteError', 1.0)

    def _emit_metric(self, metric_name: str, value: float):
        """Emit CloudWatch metric"""
        try:
            cloudwatch.put_metric_data(
                Namespace='CloudCafe/Analytics',
                MetricData=[{
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': 'Count' if 'Count' in metric_name or 'Error' in metric_name else 'Milliseconds',
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': ENVIRONMENT}
                    ]
                }]
            )
        except Exception as e:
            logger.debug(f"Failed to emit metric {metric_name}: {e}")


class StressScenario:
    """
    Stress Scenario: Query Storm

    Story: End of quarter. Finance team runs 500 concurrent Redshift queries
    for revenue reports. Analytics Worker processes each query result.

    Expected Impact:
    - EC2 CPU → 90%
    - Redshift CPU → 90%+
    - Redshift concurrent query count spikes
    - Query queue time increases
    - Network throughput increases
    """

    @staticmethod
    def simulate_query_storm(duration_seconds: int = 600, target_cpu: int = 90):
        """Simulate analytics query storm"""
        logger.info("========================================")
        logger.info("🔥 STRESS SCENARIO: QUERY STORM")
        logger.info("========================================")
        logger.info("Story: End of quarter. 500 concurrent queries for revenue reports.")
        logger.info(f"Duration: {duration_seconds}s")
        logger.info(f"Target CPU: {target_cpu}%")
        logger.info("========================================")

        start_time = time.time()
        iteration = 0

        while time.time() - start_time < duration_seconds:
            iteration_start = time.time()

            # Execute multiple CPU-intensive queries
            for i in range(10):
                StressScenario._execute_complex_query(i)

            # CPU-intensive data processing
            for i in range(5000):
                # Simulate processing large result sets
                data = {
                    'order_id': f'order-{i}',
                    'revenue': i * 123.45,
                    'items': [f'item-{j}' for j in range(10)]
                }

                # JSON processing
                json_str = json.dumps(data)
                json.loads(json_str)

                # Hash operations
                hashlib.sha256(json_str.encode()).hexdigest()
                hashlib.md5(json_str.encode()).hexdigest()

                # Floating point operations
                revenue = data['revenue']
                for j in range(100):
                    revenue = revenue * 1.001
                    revenue = revenue / 1.001

            iteration += 1

            # Emit metrics
            if iteration % 5 == 0:
                elapsed = time.time() - start_time

                cloudwatch.put_metric_data(
                    Namespace='CloudCafe/Analytics',
                    MetricData=[
                        {
                            'MetricName': 'QueryStormCPU',
                            'Value': 90.0,  # Simulated high CPU
                            'Unit': 'Percent',
                            'Dimensions': [{'Name': 'Scenario', 'Value': 'QueryStorm'}]
                        },
                        {
                            'MetricName': 'QueryStormIterations',
                            'Value': iteration,
                            'Unit': 'Count',
                            'Dimensions': [{'Name': 'Scenario', 'Value': 'QueryStorm'}]
                        }
                    ]
                )

                logger.info(f"[{int(elapsed)}s] CPU: 90% | Iterations: {iteration}")

            # Adaptive delay
            iteration_time = time.time() - iteration_start
            if iteration_time < 1.0:
                time.sleep(0.1)  # Work harder

        logger.info("========================================")
        logger.info("✅ STRESS COMPLETE")
        logger.info(f"Total time: {int(time.time() - start_time)}s")
        logger.info(f"Total iterations: {iteration}")
        logger.info("========================================")

        cloudwatch.put_metric_data(
            Namespace='CloudCafe/Analytics',
            MetricData=[{
                'MetricName': 'QueryStormCompleted',
                'Value': 1.0,
                'Unit': 'Count',
                'Dimensions': [{'Name': 'Scenario', 'Value': 'QueryStorm'}]
            }]
        )

    @staticmethod
    def _execute_complex_query(query_num: int):
        """Execute a CPU-intensive "query" simulation"""
        try:
            # Simulate complex analytical query with aggregations
            sql = f"""
            SELECT
                store_id,
                DATE_TRUNC('day', event_timestamp) as day,
                COUNT(*) as order_count,
                SUM(total_amount) as revenue,
                AVG(total_amount) as avg_order_value
            FROM fact_orders
            WHERE event_timestamp > CURRENT_DATE - INTERVAL '90 days'
            GROUP BY store_id, day
            ORDER BY revenue DESC
            LIMIT 1000
            """

            response = redshift_data.execute_statement(
                ClusterIdentifier=REDSHIFT_CLUSTER_ID,
                Database=REDSHIFT_DATABASE,
                DbUser=REDSHIFT_DB_USER,
                Sql=sql
            )

            logger.debug(f"Executed query {query_num}, Statement ID: {response['Id']}")

        except Exception as e:
            logger.debug(f"Query execution error: {e}")


if __name__ == '__main__':
    # Check if stress scenario mode
    if len(sys.argv) > 1 and sys.argv[1] == 'stress':
        duration = int(sys.argv[2]) if len(sys.argv) > 2 else 600
        target_cpu = int(sys.argv[3]) if len(sys.argv) > 3 else 90
        StressScenario.simulate_query_storm(duration, target_cpu)
    else:
        # Normal worker mode
        worker = AnalyticsWorker()
        worker.start()
