#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="972209100553"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        CloudCafe Frontend Deployment                      ║"
echo "║        Region: ap-northeast-2 (Seoul)                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get CloudFront distribution ID
cd infrastructure/terraform
CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url 2>/dev/null || echo "")
S3_BUCKET=$(terraform output -json | jq -r '.frontend_bucket_name.value' 2>/dev/null || echo "cloudcafe-frontend-dev")
cd ../..

echo "Infrastructure:"
echo "  CloudFront ID: $CLOUDFRONT_ID"
echo "  CloudFront URL: $CLOUDFRONT_URL"
echo "  S3 Bucket: $S3_BUCKET"
echo ""

# Create S3 bucket if it doesn't exist
echo "=== Checking S3 Bucket ==="
if /usr/local/bin/aws s3 ls "s3://$S3_BUCKET" --region $AWS_REGION 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating S3 bucket..."
    /usr/local/bin/aws s3 mb "s3://$S3_BUCKET" --region $AWS_REGION
    
    # Enable static website hosting
    /usr/local/bin/aws s3 website "s3://$S3_BUCKET" \
        --index-document index.html \
        --error-document index.html \
        --region $AWS_REGION
    
    # Set bucket policy for public read
    cat > /tmp/bucket-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$S3_BUCKET/*"
        }
    ]
}
EOF
    
    /usr/local/bin/aws s3api put-bucket-policy \
        --bucket $S3_BUCKET \
        --policy file:///tmp/bucket-policy.json \
        --region $AWS_REGION
    
    echo "✓ Bucket created and configured"
else
    echo "✓ Bucket exists"
fi

echo ""
echo "=== Deploying Frontends ==="

# Function to deploy a frontend
deploy_frontend() {
    local name=$1
    local path=$2
    local s3_path=$3
    
    echo ""
    echo "--- Deploying $name ---"
    
    if [ ! -d "$path" ]; then
        echo "⚠ Directory not found: $path"
        return
    fi
    
    # Sync to S3
    /usr/local/bin/aws s3 sync "$path" "s3://$S3_BUCKET/$s3_path" \
        --region $AWS_REGION \
        --delete \
        --cache-control "max-age=3600" \
        --exclude "*.md" \
        --exclude ".DS_Store"
    
    echo "✓ $name deployed to s3://$S3_BUCKET/$s3_path"
}

# Deploy each frontend
deploy_frontend "Customer Web App" "frontends/customer-web" ""
deploy_frontend "Barista Dashboard" "frontends/barista-dashboard" "barista"
deploy_frontend "Mobile App" "frontends/mobile-app" "mobile"
deploy_frontend "Admin Analytics" "frontends/admin-analytics" "admin"

# Create index page that links to all frontends
echo ""
echo "=== Creating Main Index ==="

cat > /tmp/main-index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CloudCafe - Frontend Applications</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            width: 100%;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 50px;
        }
        
        .header h1 {
            font-size: 3.5em;
            margin-bottom: 15px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        
        .header p {
            font-size: 1.3em;
            opacity: 0.95;
        }
        
        .apps-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 30px;
        }
        
        .app-card {
            background: white;
            border-radius: 20px;
            padding: 40px;
            text-align: center;
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }
        
        .app-card:hover {
            transform: translateY(-10px);
            box-shadow: 0 20px 60px rgba(0,0,0,0.2);
        }
        
        .app-card .icon {
            font-size: 4em;
            margin-bottom: 20px;
        }
        
        .app-card h2 {
            color: #6f4e37;
            font-size: 1.8em;
            margin-bottom: 15px;
        }
        
        .app-card p {
            color: #666;
            line-height: 1.6;
            margin-bottom: 25px;
        }
        
        .app-card a {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px 35px;
            border-radius: 25px;
            text-decoration: none;
            font-weight: bold;
            transition: all 0.3s ease;
        }
        
        .app-card a:hover {
            transform: scale(1.05);
            box-shadow: 0 5px 20px rgba(102, 126, 234, 0.4);
        }
        
        .info-section {
            background: white;
            border-radius: 20px;
            padding: 40px;
            margin-top: 40px;
            text-align: center;
        }
        
        .info-section h2 {
            color: #6f4e37;
            font-size: 2em;
            margin-bottom: 20px;
        }
        
        .info-section p {
            color: #666;
            line-height: 1.8;
            font-size: 1.1em;
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 2em;
            }
            
            .apps-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>☕ CloudCafe</h1>
            <p>Choose Your Experience</p>
        </div>
        
        <div class="apps-grid">
            <div class="app-card">
                <div class="icon">🌐</div>
                <h2>Customer Web</h2>
                <p>Discover your new favorite coffee ritual. Every cup tells a story.</p>
                <a href="/index.html">Explore Menu</a>
            </div>
            
            <div class="app-card">
                <div class="icon">👨‍🍳</div>
                <h2>Barista Dashboard</h2>
                <p>Where art meets craft. Create moments of joy, one cup at a time.</p>
                <a href="/barista/index.html">Start Shift</a>
            </div>
            
            <div class="app-card">
                <div class="icon">📱</div>
                <h2>Mobile App</h2>
                <p>Coffee in your pocket. Order ahead, earn rewards, skip the line.</p>
                <a href="/mobile/index.html">Open App</a>
            </div>
            
            <div class="app-card">
                <div class="icon">📊</div>
                <h2>Admin Analytics</h2>
                <p>The story behind the numbers. Data-driven insights with heart.</p>
                <a href="/admin/index.html">View Dashboard</a>
            </div>
        </div>
        
        <div class="info-section">
            <h2>🚀 Deployed on AWS</h2>
            <p>
                All frontends are deployed on AWS infrastructure in the ap-northeast-2 (Seoul) region.
                <br><br>
                <strong>Infrastructure:</strong> S3 + CloudFront + ECS + EKS
                <br>
                <strong>Status:</strong> Production Ready ✅
                <br><br>
                Built with ☕ and ❤️ by the CloudCafe Team
            </p>
        </div>
    </div>
</body>
</html>
EOF

# Upload main index
/usr/local/bin/aws s3 cp /tmp/main-index.html "s3://$S3_BUCKET/apps.html" \
    --region $AWS_REGION \
    --cache-control "max-age=300" \
    --content-type "text/html"

echo "✓ Main index created at /apps.html"

# Invalidate CloudFront cache if distribution exists
if [ ! -z "$CLOUDFRONT_ID" ] && [ "$CLOUDFRONT_ID" != "None" ]; then
    echo ""
    echo "=== Invalidating CloudFront Cache ==="
    
    INVALIDATION_ID=$(/usr/local/bin/aws cloudfront create-invalidation \
        --distribution-id $CLOUDFRONT_ID \
        --paths "/*" \
        --region us-east-1 \
        --query 'Invalidation.Id' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$INVALIDATION_ID" ]; then
        echo "✓ Cache invalidation created: $INVALIDATION_ID"
    else
        echo "⚠ Could not create cache invalidation"
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Deployment Complete! ✅                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Frontend URLs:"
echo "  Main Portal:      $CLOUDFRONT_URL/apps.html"
echo "  Customer Web:     $CLOUDFRONT_URL/"
echo "  Barista:          $CLOUDFRONT_URL/barista/"
echo "  Mobile:           $CLOUDFRONT_URL/mobile/"
echo "  Admin:            $CLOUDFRONT_URL/admin/"
echo ""
echo "S3 Bucket:"
echo "  Bucket:           s3://$S3_BUCKET"
echo "  Region:           $AWS_REGION"
echo ""
echo "CloudFront:"
echo "  Distribution:     $CLOUDFRONT_ID"
echo "  URL:              $CLOUDFRONT_URL"
echo ""
echo "All frontends are now live! 🚀"
echo ""
