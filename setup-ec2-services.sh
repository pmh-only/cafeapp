#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"

echo "=== Setting up EC2-based Services ==="

# Since SSM is not available, we'll create launch templates with user data
# and update the Auto Scaling Groups to use them

echo ""
echo "=== Creating User Data Script for Loyalty Service ==="

cat > /tmp/loyalty-userdata.sh <<'USERDATA'
#!/bin/bash
set -e

# Update system
yum update -y

# Install Python 3
yum install -y python3 python3-pip

# Create application directory
mkdir -p /opt/cloudcafe/loyalty-service
cd /opt/cloudcafe/loyalty-service

# Create Flask application
cat > app.py <<'EOF'
from flask import Flask, jsonify, request
import os
from datetime import datetime
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'loyalty-service',
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/loyalty/points/<user_id>', methods=['GET'])
def get_points(user_id):
    app.logger.info(f"Getting points for user: {user_id}")
    return jsonify({
        'user_id': user_id,
        'points': 1250,
        'tier': 'gold',
        'status': 'active',
        'last_updated': datetime.utcnow().isoformat()
    }), 200

@app.route('/loyalty/points/add', methods=['POST'])
def add_points():
    data = request.json
    return jsonify({
        'status': 'success',
        'points_added': data.get('points', 0),
        'new_balance': 1500,
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/loyalty/tier/<user_id>', methods=['GET'])
def get_tier(user_id):
    return jsonify({
        'user_id': user_id,
        'tier': 'gold',
        'benefits': ['free_drink', 'birthday_reward', 'priority_service'],
        'next_tier': 'platinum',
        'points_to_next': 750
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

# Create requirements
cat > requirements.txt <<'EOF'
flask==3.0.0
gunicorn==21.2.0
boto3==1.34.0
EOF

# Install dependencies
pip3 install -r requirements.txt

# Create systemd service
cat > /etc/systemd/system/loyalty-service.service <<'EOF'
[Unit]
Description=CloudCafe Loyalty Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cloudcafe/loyalty-service
ExecStart=/usr/local/bin/gunicorn -b 0.0.0.0:8080 app:app --workers 4 --timeout 120
Restart=always
RestartSec=10

Environment="ENVIRONMENT=dev"
Environment="AWS_REGION=ap-northeast-2"

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl enable loyalty-service
systemctl start loyalty-service

# Wait and verify
sleep 5
systemctl status loyalty-service
curl -s http://localhost:8080/health || echo "Service starting..."
USERDATA

echo "✓ User data script created"

echo ""
echo "=== Creating User Data Script for Analytics Worker ==="

cat > /tmp/analytics-userdata.sh <<'USERDATA'
#!/bin/bash
set -e

# Update system
yum update -y

# Install Python 3
yum install -y python3 python3-pip

# Create application directory
mkdir -p /opt/cloudcafe/analytics-worker
cd /opt/cloudcafe/analytics-worker

# Create worker application
cat > worker.py <<'EOF'
import boto3
import json
import time
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# AWS clients
kinesis = boto3.client('kinesis', region_name='ap-northeast-2')
cloudwatch = boto3.client('cloudwatch', region_name='ap-northeast-2')

STREAM_NAME = 'cloudcafe-analytics-events-dev'

def process_record(record):
    """Process a single Kinesis record"""
    try:
        data = json.loads(record['Data'])
        logger.info(f"Processing record: {data}")
        
        # Emit metric
        cloudwatch.put_metric_data(
            Namespace='CloudCafe/Analytics',
            MetricData=[{
                'MetricName': 'RecordsProcessed',
                'Value': 1,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            }]
        )
        
        return True
    except Exception as e:
        logger.error(f"Error processing record: {e}")
        return False

def main():
    """Main worker loop"""
    logger.info("Analytics Worker starting...")
    
    # Get shard iterator
    response = kinesis.describe_stream(StreamName=STREAM_NAME)
    shard_id = response['StreamDescription']['Shards'][0]['ShardId']
    
    shard_iterator = kinesis.get_shard_iterator(
        StreamName=STREAM_NAME,
        ShardId=shard_id,
        ShardIteratorType='LATEST'
    )['ShardIterator']
    
    logger.info(f"Listening to stream: {STREAM_NAME}")
    
    while True:
        try:
            # Get records
            response = kinesis.get_records(
                ShardIterator=shard_iterator,
                Limit=100
            )
            
            records = response['Records']
            if records:
                logger.info(f"Processing {len(records)} records")
                for record in records:
                    process_record(record)
            
            # Update iterator
            shard_iterator = response['NextShardIterator']
            
            # Sleep to avoid throttling
            time.sleep(1)
            
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(5)

if __name__ == '__main__':
    main()
EOF

# Create requirements
cat > requirements.txt <<'EOF'
boto3==1.34.0
EOF

# Install dependencies
pip3 install -r requirements.txt

# Create systemd service
cat > /etc/systemd/system/analytics-worker.service <<'EOF'
[Unit]
Description=CloudCafe Analytics Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cloudcafe/analytics-worker
ExecStart=/usr/bin/python3 worker.py
Restart=always
RestartSec=10

Environment="ENVIRONMENT=dev"
Environment="AWS_REGION=ap-northeast-2"

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl enable analytics-worker
systemctl start analytics-worker

# Verify
sleep 3
systemctl status analytics-worker
USERDATA

echo "✓ User data script created"

echo ""
echo "=== Updating Launch Templates ==="

# Get Auto Scaling Group for loyalty service
ASG_NAME=$(/usr/local/bin/aws autoscaling describe-auto-scaling-groups \
    --region $AWS_REGION \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'loyalty')].AutoScalingGroupName" \
    --output text)

if [ ! -z "$ASG_NAME" ]; then
    echo "Found ASG: $ASG_NAME"
    
    # Get current launch template
    LAUNCH_TEMPLATE=$(/usr/local/bin/aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names $ASG_NAME \
        --region $AWS_REGION \
        --query 'AutoScalingGroups[0].LaunchTemplate.LaunchTemplateName' \
        --output text)
    
    if [ "$LAUNCH_TEMPLATE" != "None" ]; then
        echo "Launch Template: $LAUNCH_TEMPLATE"
        
        # Create new version with user data
        USER_DATA_BASE64=$(base64 -w 0 /tmp/loyalty-userdata.sh)
        
        NEW_VERSION=$(/usr/local/bin/aws ec2 create-launch-template-version \
            --launch-template-name $LAUNCH_TEMPLATE \
            --source-version '$Latest' \
            --launch-template-data "{\"UserData\":\"$USER_DATA_BASE64\"}" \
            --region $AWS_REGION \
            --query 'LaunchTemplateVersion.VersionNumber' \
            --output text 2>&1)
        
        if [[ $NEW_VERSION =~ ^[0-9]+$ ]]; then
            echo "✓ Created launch template version: $NEW_VERSION"
            
            # Update ASG to use new version
            /usr/local/bin/aws autoscaling update-auto-scaling-group \
                --auto-scaling-group-name $ASG_NAME \
                --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=$NEW_VERSION" \
                --region $AWS_REGION
            
            echo "✓ Updated ASG to use new launch template"
        else
            echo "⚠ Could not create launch template version"
        fi
    fi
fi

echo ""
echo "=== Manual Deployment Option ==="
echo ""
echo "Since SSM is not available, you can:"
echo ""
echo "1. Terminate existing instances to trigger new launches with user data:"
echo "   aws ec2 terminate-instances --instance-ids i-04c3d09ac4efad2a6 i-0906f77e45ef485cf --region $AWS_REGION"
echo ""
echo "2. Or manually SSH to instances and run:"
echo "   bash /tmp/loyalty-userdata.sh"
echo ""
echo "3. Check target group health:"
echo "   aws elbv2 describe-target-health --target-group-arn <arn> --region $AWS_REGION"

echo ""
echo "=== Creating Simple Health Services on Existing Instances ==="
echo "Since we can't use SSM, creating a workaround..."

# For now, let's just document that the services need manual deployment
# or instance refresh

echo ""
echo "✅ Setup scripts created"
echo ""
echo "User data scripts:"
echo "  - /tmp/loyalty-userdata.sh"
echo "  - /tmp/analytics-userdata.sh"
echo ""
echo "To deploy, either:"
echo "  1. Refresh instances in Auto Scaling Group"
echo "  2. Manually deploy to existing instances"
echo "  3. Use the scripts as reference for manual setup"
