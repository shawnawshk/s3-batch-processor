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
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
    
    # Verify region
    if [ "$(aws configure get region)" != "$REGION" ]; then
        warn "AWS CLI region is not set to $REGION. Using --region flag."
    fi
    
    log "Prerequisites check passed"
}

# Create ECR repository
create_ecr_repo() {
    log "Creating ECR repository..."
    
    if aws ecr describe-repositories --repository-names $PROJECT_NAME --region $REGION &> /dev/null; then
        log "ECR repository already exists"
    else
        aws ecr create-repository \
            --repository-name $PROJECT_NAME \
            --region $REGION \
            --image-scanning-configuration scanOnPush=true
        log "ECR repository created"
    fi
}

# Build and push Docker image
build_and_push_image() {
    log "Building and pushing Docker image..."
    
    # Get ECR login token
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
    
    # Build image
    docker build -t $PROJECT_NAME:latest ./application/
    
    # Tag image
    docker tag $PROJECT_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME:latest
    
    # Push image
    docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME:latest
    
    log "Docker image built and pushed successfully"
}

# Deploy infrastructure
deploy_infrastructure() {
    log "Deploying infrastructure..."
    
    # Deploy ECS cluster
    aws cloudformation deploy \
        --template-file infrastructure/ecs-cluster.yaml \
        --stack-name $PROJECT_NAME-ecs-$ENVIRONMENT \
        --parameter-overrides \
            ProjectName=$PROJECT_NAME \
            Environment=$ENVIRONMENT \
        --capabilities CAPABILITY_IAM \
        --region $REGION
    
    log "ECS infrastructure deployed"
    
    # Get VPC and subnet information (assuming default VPC for PoC)
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)
    SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text --region $REGION)
    
    # Create security group for ECS tasks
    SG_ID=$(aws ec2 create-security-group \
        --group-name $PROJECT_NAME-ecs-tasks \
        --description "Security group for ECS tasks" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --query 'GroupId' --output text 2>/dev/null || \
        aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$PROJECT_NAME-ecs-tasks" \
        --query 'SecurityGroups[0].GroupId' --output text --region $REGION)
    
    # Allow outbound HTTPS for ECR and S3
    aws ec2 authorize-security-group-egress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region $REGION 2>/dev/null || true
    
    # Get cluster and task definition ARNs
    CLUSTER_ARN=$(aws cloudformation describe-stacks \
        --stack-name $PROJECT_NAME-ecs-$ENVIRONMENT \
        --query 'Stacks[0].Outputs[?OutputKey==`ClusterArn`].OutputValue' \
        --output text --region $REGION)
    
    TASK_DEF_ARN=$(aws cloudformation describe-stacks \
        --stack-name $PROJECT_NAME-ecs-$ENVIRONMENT \
        --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' \
        --output text --region $REGION)
    
    # Deploy Step Functions
    aws cloudformation deploy \
        --template-file infrastructure/step-functions.yaml \
        --stack-name $PROJECT_NAME-stepfunctions-$ENVIRONMENT \
        --parameter-overrides \
            ProjectName=$PROJECT_NAME \
            Environment=$ENVIRONMENT \
            SourceBucket=$PROJECT_NAME-source-$AWS_ACCOUNT_ID \
            ClusterArn=$CLUSTER_ARN \
            TaskDefinitionArn=$TASK_DEF_ARN \
            SubnetId=$SUBNET_ID \
            SecurityGroupId=$SG_ID \
        --capabilities CAPABILITY_IAM \
        --region $REGION
    
    log "Step Functions deployed"
}

# Create test S3 bucket
create_test_bucket() {
    log "Creating test S3 bucket..."
    
    BUCKET_NAME="$PROJECT_NAME-source-$AWS_ACCOUNT_ID"
    
    # Create bucket
    if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://$BUCKET_NAME" --region $REGION
        log "Created S3 bucket: $BUCKET_NAME"
    else
        log "S3 bucket already exists: $BUCKET_NAME"
    fi
    
    log "S3 bucket ready: $BUCKET_NAME"
    log "Use './scripts/generate-test-files.sh' to create test files"
}

# Main deployment function
main() {
    log "Starting deployment of S3 Batch Processing PoC"
    log "Project: $PROJECT_NAME"
    log "Environment: $ENVIRONMENT"
    log "Region: $REGION"
    log "Account: $AWS_ACCOUNT_ID"
    
    check_prerequisites
    create_ecr_repo
    build_and_push_image
    deploy_infrastructure
    create_test_bucket
    
    # Get Step Functions ARN
    STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
        --stack-name $PROJECT_NAME-stepfunctions-$ENVIRONMENT \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text --region $REGION)
    
    log "Deployment completed successfully!"
    log ""
    log "Resources created:"
    log "- ECR Repository: $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME"
    log "- ECS Cluster: $PROJECT_NAME-$ENVIRONMENT"
    log "- Step Functions: $STATE_MACHINE_ARN"
    log "- S3 Bucket: $PROJECT_NAME-source-$AWS_ACCOUNT_ID"
    log ""
    log "Next steps:"
    log "1. Generate test files (00001.txt to NNNNN.txt):"
    log "   ./scripts/generate-test-files.sh           # Generate 150 files (PoC default)"
    log "   ./scripts/generate-test-files.sh -n 1000   # Generate 1000 files for stress testing"
    log ""
    log "2. Run the processing:"
    log "   ./scripts/test-execution.sh"
}

# Run main function
main "$@"