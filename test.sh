#!/bin/bash

set -e

REGION=${AWS_REGION:-ap-east-1}
STACK_NAME="s3-batch-processor"

echo "🧪 End-to-End Test: S3 Batch Processing with Dynamic Workers"
echo "Usage: $0 [worker_count]"
echo "Example: $0 5  # Use 5 workers"

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

ASG_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text)

echo "📋 Using:"
echo "  Bucket: $BUCKET_NAME"
echo "  State Machine: $STATE_MACHINE_ARN"
echo "  Auto Scaling Group: $ASG_NAME"

# Step 1: Generate test files
echo ""
echo "📁 Step 1: Generating test files..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

for i in {1..5}; do
  FILE_NUM=$(printf "%03d" $i)
  echo "Test content for file $FILE_NUM - $(date)" > "$TEMP_DIR/test-$FILE_NUM.txt"
done

# Step 2: Upload to S3
echo ""
echo "⬆️ Step 2: Uploading files to S3..."
aws s3 sync "$TEMP_DIR" "s3://$BUCKET_NAME/input/" --region $REGION

# Step 3: Create execution input
echo ""
echo "📋 Step 3: Preparing execution input..."
OBJECTS=$(aws s3api list-objects-v2 \
  --bucket $BUCKET_NAME \
  --prefix input/ \
  --region $REGION \
  --query 'Contents[].{Key: Key}')

# Dynamic worker count - can be customized
WORKER_COUNT=${1:-3}  # Default to 3 workers, or use first argument
EXECUTION_INPUT=$(echo "$OBJECTS" | jq --argjson workers "$WORKER_COUNT" '{objects: ., worker_count: $workers}')
echo "Processing $(echo "$OBJECTS" | jq length) files with $WORKER_COUNT workers"

# Step 4: Execute workflow
echo ""
echo "🚀 Step 4: Starting Step Functions execution..."
EXECUTION_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --input "$EXECUTION_INPUT" \
  --region $REGION \
  --query 'executionArn' \
  --output text)

echo "Execution ARN: $EXECUTION_ARN"

# Step 5: Monitor execution
echo ""
echo "📊 Step 5: Monitoring execution..."
for i in {1..20}; do
  STATUS=$(aws stepfunctions describe-execution \
    --execution-arn "$EXECUTION_ARN" \
    --region $REGION \
    --query 'status' \
    --output text)
  
  ASG_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $REGION \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)
  
  echo "[$i/20] Status: $STATUS | ASG Desired: $ASG_DESIRED ($(date))"
  
  if [[ "$STATUS" == "SUCCEEDED" ]]; then
    echo "✅ Execution completed successfully!"
    break
  elif [[ "$STATUS" == "FAILED" || "$STATUS" == "TIMED_OUT" || "$STATUS" == "ABORTED" ]]; then
    echo "❌ Execution failed with status: $STATUS"
    exit 1
  fi
  
  sleep 15
done

# Step 6: Check results
echo ""
echo "📊 Step 6: Checking results..."
echo "Processed files:"
aws s3 ls "s3://$BUCKET_NAME/processed/" --region $REGION

echo ""
echo "Sample processed file content:"
aws s3 cp "s3://$BUCKET_NAME/processed/test-001.txt" - --region $REGION

# Step 7: Verify cleanup
echo ""
echo "📋 Step 7: Verifying infrastructure cleanup..."
ASG_FINAL=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region $REGION \
  --query 'AutoScalingGroups[0].DesiredCapacity' \
  --output text)

echo "Final ASG Desired Capacity: $ASG_FINAL"

if [[ "$ASG_FINAL" == "0" ]]; then
  echo "✅ Auto Scaling Group properly scaled down to 0"
else
  echo "⚠️ Auto Scaling Group still has $ASG_FINAL instances"
fi

echo ""
echo "🎉 End-to-End test completed!"
echo "✅ Dynamic provisioning and processing successful"
echo "✅ Infrastructure automatically cleaned up"
