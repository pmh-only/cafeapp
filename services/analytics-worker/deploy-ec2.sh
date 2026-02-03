#!/bin/bash
# Deploy Analytics Worker to EC2 instances
# This script should be added to EC2 User Data or run via Systems Manager

set -e

echo "========================================="
echo "CloudCafe Analytics Worker - EC2 Deployment"
echo "========================================="

# Install Python 3.11
echo "Installing Python 3.11..."
sudo yum install -y python3.11 python3.11-pip

# Verify Python installation
python3.11 --version
pip3.11 --version

# Create application directory
APP_DIR="/opt/cloudcafe/analytics-worker"
sudo mkdir -p $APP_DIR
cd $APP_DIR

# Clone source code (adjust with your repo URL)
# git clone https://github.com/yourorg/cloudcafe.git .
# For now, assuming code is already present

# Install Python dependencies
echo "Installing Python dependencies..."
pip3.11 install -r requirements.txt

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/analytics-worker.service > /dev/null <<EOF
[Unit]
Description=CloudCafe Analytics Worker
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3.11 $APP_DIR/worker.py
Restart=always
RestartSec=10

# Environment variables
Environment="KINESIS_STREAM_NAME=\${KINESIS_STREAM_NAME}"
Environment="REDSHIFT_CLUSTER_ID=\${REDSHIFT_CLUSTER_ID}"
Environment="REDSHIFT_DATABASE=\${REDSHIFT_DATABASE}"
Environment="REDSHIFT_DB_USER=\${REDSHIFT_DB_USER}"
Environment="ENVIRONMENT=\${ENVIRONMENT}"
Environment="AWS_REGION=us-east-1"
Environment="BATCH_SIZE=100"
Environment="POLL_INTERVAL=5"

[Install]
WantedBy=multi-user.target
EOF

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
sudo yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent config
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json > /dev/null <<EOF
{
  "metrics": {
    "namespace": "CloudCafe/Analytics",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"},
          {"name": "cpu_usage_iowait", "rename": "CPU_IOWAIT", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEM_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {"name": "tcp_established", "rename": "TCP_CONNECTIONS", "unit": "Count"}
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/cloudcafe/analytics-worker.log",
            "log_group_name": "/cloudcafe/analytics-worker",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Enable and start service
echo "Starting analytics worker..."
sudo systemctl daemon-reload
sudo systemctl enable analytics-worker
sudo systemctl start analytics-worker

# Check status
sleep 5
sudo systemctl status analytics-worker

echo "========================================="
echo "✅ Deployment Complete"
echo "========================================="
echo "Service Status: sudo systemctl status analytics-worker"
echo "View Logs: sudo journalctl -u analytics-worker -f"
echo "Trigger Stress: python3.11 worker.py stress 600 90"
echo "========================================="
