#!/bin/bash
# Deploy Loyalty Service to EC2 instances
# This script should be added to EC2 User Data or run via Systems Manager

set -e

echo "========================================="
echo "CloudCafe Loyalty Service - EC2 Deployment"
echo "========================================="

# Install Java 17
echo "Installing Java 17..."
sudo yum install -y java-17-amazon-corretto-devel

# Verify Java installation
java -version

# Install Maven
echo "Installing Maven..."
sudo wget https://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo \
  -O /etc/yum.repos.d/epel-apache-maven.repo
sudo sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
sudo yum install -y apache-maven
mvn -version

# Create application directory
APP_DIR="/opt/cloudcafe/loyalty-service"
sudo mkdir -p $APP_DIR
cd $APP_DIR

# Clone source code (adjust with your repo URL)
# git clone https://github.com/yourorg/cloudcafe.git .
# For now, assuming code is already present

# Build application
echo "Building application..."
mvn clean package -DskipTests

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/loyalty-service.service > /dev/null <<EOF
[Unit]
Description=CloudCafe Loyalty Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/java -jar $APP_DIR/target/loyalty-service.jar
Restart=always
RestartSec=10

# Environment variables
Environment="SERVER_PORT=8080"
Environment="DB_HOST=\${DB_HOST}"
Environment="DB_NAME=cloudcafe"
Environment="DB_USER=\${DB_USER}"
Environment="DB_PASSWORD=\${DB_PASSWORD}"
Environment="ENVIRONMENT=\${ENVIRONMENT}"
Environment="REDSHIFT_CLUSTER_ID=\${REDSHIFT_CLUSTER_ID}"
Environment="AWS_REGION=us-east-1"

# JVM Options
Environment="JAVA_OPTS=-Xms512m -Xmx2g -XX:+UseG1GC"

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
    "namespace": "CloudCafe/Loyalty",
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
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/cloudcafe/loyalty-service.log",
            "log_group_name": "/cloudcafe/loyalty-service",
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
echo "Starting loyalty service..."
sudo systemctl daemon-reload
sudo systemctl enable loyalty-service
sudo systemctl start loyalty-service

# Check status
sleep 5
sudo systemctl status loyalty-service

echo "========================================="
echo "✅ Deployment Complete"
echo "========================================="
echo "Service Status: sudo systemctl status loyalty-service"
echo "View Logs: sudo journalctl -u loyalty-service -f"
echo "Health Check: curl http://localhost:8080/loyalty/health"
echo "========================================="
