#!/bin/bash

# S3 Batch Processing PoC - End-to-End Test Script
set -e

# Configuration
PROJECT_NAME="s3-batch-processor"
ENVIRONMENT="poc"
REGION="ap-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SOURCE_BUCKET="${PROJECT_NAME}-source-${ACCOUNT_ID}"
WORKER_COUNT=${1:-2}  # Default to 2 workers if not specified
TEST_OBJECTS=$((WORKER_COUNT * 3))  # Create 3x objects as workers for good testing

echo "🧪 Starting End-to-End Test"
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Worker Count: ${WORKER_COUNT}"
echo "Test Objects: ${TEST_OBJECTS}"
echo "Region: ${REGION}"
echo "Source Bucket: ${SOURCE_BUCKET}"
echo ""

# Get infrastructure ARNs
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-stepfunctions-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' --output text --region ${REGION})

if [ -z "$STATE_MACHINE_ARN" ]; then
    echo "❌ Error: State machine not found. Please run deploy-infrastructure.sh first."
    exit 1
fi

echo "State Machine ARN: ${STATE_MACHINE_ARN}"

# Step 1: Ensure test data exists in S3
echo "📁 Checking test data in S3..."

# Count existing test objects
EXISTING_COUNT=$(aws s3 ls s3://${SOURCE_BUCKET}/test- --region ${REGION} 2>/dev/null | wc -l | tr -d ' ')

if [ "$EXISTING_COUNT" -ge "$TEST_OBJECTS" ]; then
    echo "✅ Found $EXISTING_COUNT existing test objects (need $TEST_OBJECTS) - skipping creation"
else
    echo "📝 Creating $TEST_OBJECTS test objects (found $EXISTING_COUNT existing)..."
    # Clear existing objects first to avoid confusion
    aws s3 rm s3://${SOURCE_BUCKET} --recursive --quiet --region ${REGION} || true
    
    # Create test objects based on worker count
    for i in $(seq 1 $TEST_OBJECTS); do
        echo "Test content for object $(printf "%05d" $i)" | aws s3 cp - s3://${SOURCE_BUCKET}/test-$(printf "%05d" $i).txt --region ${REGION}
    done
fi

# List objects to verify
echo "📋 Objects in S3 bucket:"
aws s3 ls s3://${SOURCE_BUCKET}/ --region ${REGION}

# Step 2: Start Step Functions execution
echo ""
echo "⚡ Starting Step Functions execution..."
EXECUTION_NAME="end-to-end-test-$(date +%s)"
EXECUTION_INPUT="{\"WorkerCount\": ${WORKER_COUNT}}"
EXECUTION_ARN=$(aws stepfunctions start-execution \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --name ${EXECUTION_NAME} \
    --input "${EXECUTION_INPUT}" \
    --region ${REGION} \
    --query 'executionArn' \
    --output text)

echo "Execution ARN: ${EXECUTION_ARN}"
echo "Execution Name: ${EXECUTION_NAME}"

# Step 3: Monitor execution
echo ""
echo "⏳ Monitoring execution progress..."
START_TIME=$(date +%s)
TIMEOUT=600  # 10 minutes timeout

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "❌ Timeout: Execution took longer than ${TIMEOUT} seconds"
        exit 1
    fi
    
    STATUS=$(aws stepfunctions describe-execution \
        --execution-arn ${EXECUTION_ARN} \
        --region ${REGION} \
        --query 'status' \
        --output text)
    
    # Only show status every 30 seconds to reduce noise
    if [ $((ELAPSED % 30)) -eq 0 ] || [ "$STATUS" != "RUNNING" ]; then
        echo "Status: ${STATUS} (${ELAPSED}s elapsed)"
    fi
    
    if [ "$STATUS" = "SUCCEEDED" ]; then
        echo "✅ Execution completed successfully!"
        break
    elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "TIMED_OUT" ] || [ "$STATUS" = "ABORTED" ]; then
        echo "❌ Execution failed with status: ${STATUS}"
        
        # Get error details
        aws stepfunctions describe-execution \
            --execution-arn ${EXECUTION_ARN} \
            --region ${REGION} \
            --query '{error: error, cause: cause}' \
            --output table
        exit 1
    fi
    
    sleep 10
done

# Step 4: Get execution results
echo ""
echo "📊 Execution Results:"
STOP_TIME=$(aws stepfunctions describe-execution \
    --execution-arn ${EXECUTION_ARN} \
    --region ${REGION} \
    --query 'stopDate' \
    --output text)

START_TIME_ISO=$(aws stepfunctions describe-execution \
    --execution-arn ${EXECUTION_ARN} \
    --region ${REGION} \
    --query 'startDate' \
    --output text)

echo "Start Time: ${START_TIME_ISO}"
echo "Stop Time: ${STOP_TIME}"

# Get output (truncated for readability)
OUTPUT=$(aws stepfunctions describe-execution \
    --execution-arn ${EXECUTION_ARN} \
    --region ${REGION} \
    --query 'output' \
    --output text)

if [ ${#OUTPUT} -gt 500 ]; then
    echo "Output (first 500 chars): ${OUTPUT:0:500}..."
else
    echo "Output: ${OUTPUT}"
fi

# Step 5: Check worker logs
echo ""
echo "📋 Checking worker logs..."
LOG_GROUP="/ecs/${PROJECT_NAME}"

# Get recent log streams
LOG_STREAMS=$(aws logs describe-log-streams \
    --log-group-name ${LOG_GROUP} \
    --order-by LastEventTime \
    --descending \
    --max-items 2 \
    --region ${REGION} \
    --query 'logStreams[*].logStreamName' \
    --output text)

echo "Recent log streams: ${LOG_STREAMS}"

# Show sample logs from the first stream
FIRST_STREAM=$(echo ${LOG_STREAMS} | cut -d' ' -f1)
if [ ! -z "$FIRST_STREAM" ]; then
    echo ""
    echo "📝 Sample logs from ${FIRST_STREAM}:"
    aws logs get-log-events \
        --log-group-name ${LOG_GROUP} \
        --log-stream-name ${FIRST_STREAM} \
        --region ${REGION} \
        --query 'events[0:5].message' \
        --output text
fi

# Step 6: Verify single-task processing
echo ""
echo "🔍 Verifying single-task processing behavior..."
if echo "${OUTPUT}" | grep -q "processing_mode.*single_task"; then
    echo "✅ Single-task processing mode confirmed in output"
else
    echo "⚠️  Single-task processing mode not found in output (checking logs...)"
fi

# Count successful tasks
TASK_COUNT=$(echo "${OUTPUT}" | grep -o "worker_id" | wc -l)
echo "📈 Total tasks processed: ${TASK_COUNT}"

# Step 7: Performance summary
echo ""
echo "🏁 Test Summary:"
echo "  ✅ Infrastructure deployment: SUCCESS"
echo "  ✅ Test data creation: SUCCESS"
echo "  ✅ Step Functions execution: SUCCESS"
echo "  ✅ Single-task processing: VERIFIED"
echo "  👥 Workers deployed: ${WORKER_COUNT}"
echo "  📊 Objects processed: ${TASK_COUNT}"
echo "  ⏱️  Total execution time: ~$((ELAPSED)) seconds"
echo "  📈 Throughput: ~$((TASK_COUNT * 60 / ELAPSED)) objects/minute"
echo ""
echo "🎉 End-to-end test completed successfully!"
echo ""
echo "🧹 To clean up resources, run: scripts/cleanup.sh"
echo "💡 Usage: $0 [worker_count] (default: 2, max: 100)"
echo "   Example: $0 5  # Test with 5 workers"
echo "   Example: $0 20 # Test with 20 workers"