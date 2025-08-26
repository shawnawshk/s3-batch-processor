#!/bin/bash
set -e

# Configuration
PROJECT_NAME="s3-batch-processor"
ENVIRONMENT="poc"
REGION="ap-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Get Step Functions ARN
get_state_machine_arn() {
    aws cloudformation describe-stacks \
        --stack-name $PROJECT_NAME-stepfunctions-$ENVIRONMENT \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text --region $REGION
}

# Start execution
start_execution() {
    local state_machine_arn=$1
    local execution_name="test-execution-$(date +%s)"
    
    log "Starting Step Functions execution..."
    info "State Machine: $state_machine_arn"
    info "Execution Name: $execution_name"
    
    local execution_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$state_machine_arn" \
        --name "$execution_name" \
        --region $REGION \
        --query 'executionArn' --output text)
    
    log "Execution started: $execution_arn"
    echo "$execution_arn"
}

# Monitor execution
monitor_execution() {
    local execution_arn=$1
    local start_time=$(date +%s)
    
    log "Monitoring execution progress..."
    info "Execution ARN: $execution_arn"
    
    while true; do
        local status=$(aws stepfunctions describe-execution \
            --execution-arn "$execution_arn" \
            --region $REGION \
            --query 'status' --output text)
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        case $status in
            "RUNNING")
                info "Status: RUNNING (${elapsed}s elapsed)"
                sleep 10
                ;;
            "SUCCEEDED")
                log "Execution completed successfully in ${elapsed}s"
                break
                ;;
            "FAILED"|"TIMED_OUT"|"ABORTED")
                error "Execution failed with status: $status (${elapsed}s elapsed)"
                ;;
            *)
                warn "Unknown status: $status"
                sleep 5
                ;;
        esac
    done
}

# Get execution results
get_execution_results() {
    local execution_arn=$1
    
    log "Retrieving execution results..."
    
    # Get execution details
    local execution_details=$(aws stepfunctions describe-execution \
        --execution-arn "$execution_arn" \
        --region $REGION)
    
    echo "$execution_details" | jq '.'
    
    # Get execution history (last 10 events)
    log "Recent execution events:"
    aws stepfunctions get-execution-history \
        --execution-arn "$execution_arn" \
        --region $REGION \
        --max-items 10 \
        --query 'events[*].[timestamp,type,id]' \
        --output table
}

# Check processing results in S3
check_s3_results() {
    local bucket_name="$PROJECT_NAME-source-$AWS_ACCOUNT_ID"
    
    log "Checking processing results in S3..."
    info "Bucket: $bucket_name"
    
    # List processing results
    local result_count=$(aws s3 ls "s3://$bucket_name/processing-results/" --region $REGION | wc -l)
    
    if [ "$result_count" -gt 0 ]; then
        log "Found $result_count processing result files"
        
        # Show first few results
        info "Sample results:"
        aws s3 ls "s3://$bucket_name/processing-results/" --region $REGION | head -5
        
        # Download and show a sample result
        local sample_file=$(aws s3 ls "s3://$bucket_name/processing-results/" --region $REGION | head -1 | awk '{print $4}')
        if [ -n "$sample_file" ]; then
            info "Sample result content:"
            aws s3 cp "s3://$bucket_name/processing-results/$sample_file" - --region $REGION | jq '.'
        fi
    else
        warn "No processing results found"
    fi
}

# Get CloudWatch logs
get_logs() {
    local log_group="/ecs/$PROJECT_NAME"
    local start_time=$(($(date +%s) - 3600))000  # Last hour in milliseconds
    
    log "Retrieving CloudWatch logs..."
    info "Log Group: $log_group"
    
    # Get recent log streams
    local log_streams=$(aws logs describe-log-streams \
        --log-group-name "$log_group" \
        --order-by LastEventTime \
        --descending \
        --max-items 5 \
        --region $REGION \
        --query 'logStreams[*].logStreamName' --output text)
    
    if [ -n "$log_streams" ]; then
        info "Recent log streams:"
        echo "$log_streams" | tr '\t' '\n'
        
        # Get logs from the most recent stream
        local latest_stream=$(echo "$log_streams" | cut -f1)
        if [ -n "$latest_stream" ]; then
            info "Latest logs from: $latest_stream"
            aws logs get-log-events \
                --log-group-name "$log_group" \
                --log-stream-name "$latest_stream" \
                --start-time $start_time \
                --region $REGION \
                --query 'events[*].message' \
                --output text | tail -10
        fi
    else
        warn "No log streams found"
    fi
}

# Performance analysis
analyze_performance() {
    local execution_arn=$1
    
    log "Analyzing performance..."
    
    # Get Map Run details if available
    local map_runs=$(aws stepfunctions list-map-runs \
        --execution-arn "$execution_arn" \
        --region $REGION \
        --query 'mapRuns[*].mapRunArn' --output text 2>/dev/null || echo "")
    
    if [ -n "$map_runs" ]; then
        info "Found Map Runs:"
        for map_run in $map_runs; do
            info "Map Run: $map_run"
            aws stepfunctions describe-map-run \
                --map-run-arn "$map_run" \
                --region $REGION \
                --query '{Status:status,ItemCounts:itemCounts,ExecutionCounts:executionCounts}' \
                --output table
        done
    else
        info "No Map Runs found (execution may still be running)"
    fi
}

# Main test function
main() {
    log "Starting Step Functions execution test"
    log "Project: $PROJECT_NAME"
    log "Environment: $ENVIRONMENT"
    log "Region: $REGION"
    
    # Get state machine ARN
    local state_machine_arn=$(get_state_machine_arn)
    if [ -z "$state_machine_arn" ]; then
        error "Could not find Step Functions state machine. Make sure deployment completed successfully."
    fi
    
    # Start execution
    local execution_arn=$(start_execution "$state_machine_arn")
    
    # Monitor execution
    monitor_execution "$execution_arn"
    
    # Get results
    get_execution_results "$execution_arn"
    
    # Check S3 results
    check_s3_results
    
    # Get logs
    get_logs
    
    # Analyze performance
    analyze_performance "$execution_arn"
    
    log "Test execution completed!"
    log ""
    log "Next steps:"
    log "1. Review the execution results above"
    log "2. Check CloudWatch logs for detailed processing information"
    log "3. Examine S3 processing results"
    log "4. Scale up by adding more test objects to S3"
    log ""
    log "To run another test:"
    log "./scripts/test-execution.sh"
}

# Run main function
main "$@"