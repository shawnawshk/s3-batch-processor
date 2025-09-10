#!/bin/bash

set -e

REGION=${AWS_REGION:-ap-east-1}
STACK_NAME="s3-batch-processor"
WORKER_COUNT=${1:-3}

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <worker_count> [prefix]"
    echo "Example: $0 5 input/"
    echo "Example: $0 10 data/"
    exit 1
fi

PREFIX=${2:-input/}

echo "🚀 Executing S3 Batch Processing with $WORKER_COUNT workers"

# Get stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
  --output text)

echo "📋 Using:"
echo "  Bucket: $BUCKET_NAME"
echo "  Prefix: $PREFIX"
echo "  Workers: $WORKER_COUNT"

# Get objects to process
OBJECTS=$(aws s3api list-objects-v2 \
  --bucket $BUCKET_NAME \
  --prefix $PREFIX \
  --region $REGION \
  --query 'Contents[].{Key: Key}')

OBJECT_COUNT=$(echo "$OBJECTS" | jq length)
echo "  Objects: $OBJECT_COUNT"

if [ "$OBJECT_COUNT" -eq 0 ]; then
    echo "❌ No objects found with prefix '$PREFIX'"
    exit 1
fi

# Create execution input
EXECUTION_INPUT=$(echo "$OBJECTS" | jq --argjson workers "$WORKER_COUNT" '{objects: ., worker_count: $workers}')

# Execute workflow
echo ""
echo "🚀 Starting Step Functions execution..."
EXECUTION_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --input "$EXECUTION_INPUT" \
  --region $REGION \
  --query 'executionArn' \
  --output text)

echo "✅ Execution started: $EXECUTION_ARN"
echo "📊 Monitor at: https://$REGION.console.aws.amazon.com/states/home?region=$REGION#/executions/details/$EXECUTION_ARN"
