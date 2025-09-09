#!/bin/bash

set -e

REGION=${AWS_REGION:-ap-east-1}
STACK_NAME="s3-batch-processor"
MAX_WORKERS=${1:-3}
INSTANCE_TYPE=${2:-c5.large}

echo "🚀 Deploying S3 Batch Processor"
echo "Workers: $MAX_WORKERS"
echo "Instance Type: $INSTANCE_TYPE"
echo "Region: $REGION"

# Step 1: Build and push Docker image
echo ""
echo "📦 Step 1: Building and pushing Docker image..."
./build-and-push.sh

# Step 2: Deploy SAM stack
echo ""
echo "🏗️ Step 2: Deploying SAM stack..."
sam build --template template.yaml
sam deploy \
  --template .aws-sam/build/template.yaml \
  --stack-name $STACK_NAME \
  --region $REGION \
  --capabilities CAPABILITY_IAM \
  --resolve-s3 \
  --parameter-overrides \
    MaxWorkers=$MAX_WORKERS \
    InstanceType=$INSTANCE_TYPE

echo ""
echo "✅ Deployment completed!"
echo ""
echo "📋 Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs' \
  --output table

echo ""
echo "🧪 To test the deployment:"
echo "  ./test.sh"
