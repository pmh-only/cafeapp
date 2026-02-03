#!/bin/bash
# Deploy Payment Processor Lambda Function

set -e

FUNCTION_NAME="cloudcafe-payment-processor-dev"
AWS_REGION=${AWS_REGION:-us-east-1}

echo "🚀 Deploying Payment Processor Lambda..."

# Create deployment package directory
rm -rf package
mkdir -p package

# Install dependencies
echo "📦 Installing dependencies..."
pip install -r requirements.txt -t package/ -q

# Copy handler
echo "📄 Copying handler..."
cp handler.py package/

# Create ZIP
echo "📦 Creating deployment package..."
cd package
zip -r ../payment-processor.zip . > /dev/null
cd ..

echo "✅ Deployment package created: payment-processor.zip"

# Check if function exists
if aws lambda get-function --function-name $FUNCTION_NAME --region $AWS_REGION > /dev/null 2>&1; then
    echo "🔄 Updating existing Lambda function..."

    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://payment-processor.zip \
        --region $AWS_REGION \
        --output json > /dev/null

    echo "✅ Lambda function updated"
else
    echo "❌ Lambda function $FUNCTION_NAME not found"
    echo "💡 Create the function first using Terraform"
    exit 1
fi

# Cleanup
echo "🧹 Cleaning up..."
rm -rf package
rm payment-processor.zip

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Check function: aws lambda get-function --function-name $FUNCTION_NAME"
echo "  2. View logs: aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
echo "  3. Test function: Send message to SQS queue"
echo ""
