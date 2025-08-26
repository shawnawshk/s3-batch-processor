#!/bin/bash
set -e

# Configuration
PROJECT_NAME="s3-batch-processor"
REGION="ap-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="$PROJECT_NAME-source-$AWS_ACCOUNT_ID"

# Default number of files
NUM_FILES=150

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-files)
            NUM_FILES="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Generate test files for S3 batch processing"
            echo ""
            echo "Options:"
            echo "  -n, --num-files NUM    Number of files to generate (default: 150)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     # Generate 150 test files (PoC default)"
            echo "  $0 -n 1000            # Generate 1000 test files"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate inputs
if ! [[ "$NUM_FILES" =~ ^[0-9]+$ ]] || [ "$NUM_FILES" -lt 1 ]; then
    error "Number of files must be a positive integer"
fi

# Check if bucket exists
check_bucket() {
    log "Checking if S3 bucket exists: $BUCKET_NAME"
    
    if ! aws s3 ls "s3://$BUCKET_NAME" --region $REGION &>/dev/null; then
        error "S3 bucket does not exist: $BUCKET_NAME. Please run ./scripts/deploy.sh first."
    fi
    
    log "S3 bucket confirmed: $BUCKET_NAME"
}

# Generate test files
generate_files() {
    local temp_dir="/tmp/s3-test-files"
    
    log "Generating $NUM_FILES test files..."
    info "Format: 00001.txt to $(printf "%05d" $NUM_FILES).txt"
    info "Content: 'this is 00001.txt' etc."
    
    # Clean and create temporary directory
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Generate files using a simple loop
    info "Creating files in $temp_dir..."
    for i in $(seq 1 $NUM_FILES); do
        local file_num=$(printf "%05d" $i)
        local filename="${file_num}.txt"
        local content="this is ${file_num}.txt"
        
        echo "$content" > "$temp_dir/$filename"
        
        # Progress indicator for large numbers
        if [ $((i % 1000)) -eq 0 ] || [ $i -eq $NUM_FILES ]; then
            info "Generated $i/$NUM_FILES files..."
        fi
    done
    
    # Verify files were created
    local actual_count=$(ls "$temp_dir" | wc -l)
    if [ "$actual_count" -ne "$NUM_FILES" ]; then
        error "Expected $NUM_FILES files, but found $actual_count"
    fi
    
    log "Successfully generated $NUM_FILES files in $temp_dir"
    
    # Show sample files
    info "Sample files created:"
    ls "$temp_dir" | head -3
    info "..."
    ls "$temp_dir" | tail -3
    
    # Show sample content
    info "Sample content:"
    cat "$temp_dir/$(ls "$temp_dir" | head -1)"
}

# Upload files to S3
upload_files() {
    local temp_dir="/tmp/s3-test-files"
    
    log "Uploading $NUM_FILES files to S3..."
    info "Source: $temp_dir"
    info "Destination: s3://$BUCKET_NAME/"
    
    # Use aws s3 sync for efficient upload
    aws s3 sync "$temp_dir/" "s3://$BUCKET_NAME/" --region $REGION --quiet
    
    log "Upload completed"
}

# Verify uploads
verify_uploads() {
    log "Verifying uploads..."
    
    local s3_count=$(aws s3 ls "s3://$BUCKET_NAME/" --region $REGION | grep -E "\.txt$" | wc -l)
    
    info "Files in S3 bucket: $s3_count"
    info "Expected files: $NUM_FILES"
    
    if [ "$s3_count" -ge "$NUM_FILES" ]; then
        log "Upload verification successful!"
    else
        warn "Upload verification failed. Expected $NUM_FILES, found $s3_count"
        return 1
    fi
    
    # Show sample files in S3
    info "Sample files in S3:"
    aws s3 ls "s3://$BUCKET_NAME/" --region $REGION | head -3
    info "..."
    aws s3 ls "s3://$BUCKET_NAME/" --region $REGION | tail -3
    
    # Verify content of a sample file
    info "Sample file content from S3:"
    aws s3 cp "s3://$BUCKET_NAME/00001.txt" - --region $REGION
}

# Clean up temporary files
cleanup() {
    local temp_dir="/tmp/s3-test-files"
    
    if [ -d "$temp_dir" ]; then
        log "Cleaning up temporary files..."
        rm -rf "$temp_dir"
        log "Cleanup completed"
    fi
}

# Main function
main() {
    log "Starting test file generation"
    log "Project: $PROJECT_NAME"
    log "Region: $REGION"
    log "Bucket: $BUCKET_NAME"
    log "Number of files: $NUM_FILES"
    
    check_bucket
    generate_files
    upload_files
    verify_uploads
    cleanup
    
    log "Test file generation completed successfully!"
    log ""
    log "Next steps:"
    log "1. Run the Step Functions execution:"
    log "   ./scripts/test-execution.sh"
    log ""
    log "2. Monitor the processing of $NUM_FILES files"
    log ""
    log "3. Check results in CloudWatch logs for worker activity"
    
    if [ "$NUM_FILES" -lt 1000 ]; then
        log ""
        log "To generate more files for stress testing:"
        log "$0 -n 1000"
    fi
}

# Run main function
main "$@"