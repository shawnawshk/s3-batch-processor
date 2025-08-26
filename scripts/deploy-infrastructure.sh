#!/bin/bash

# S3 Batch Processing PoC - Infrastructure Deployment Script
set -e

# Configuration
PROJECT_NAME="s3-batch-processor"
ENVIRONMENT="poc"
REGION="ap-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SOURCE_BUCKET="${PROJECT_NAME}-source-${ACCOUNT_ID}"
WORKER_COUNT=${1:-2}  # Default to 2 workers if not specified
LAUNCH_TYPE=${2:-FARGATE}  # Default to FARGATE if not specified
INSTANCE_TYPE=${3:-t3.medium}  # Default to t3.medium if not specified

echo "🚀 Starting S3 Batch Processing PoC Deployment"
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Worker Count: ${WORKER_COUNT}"
echo "Launch Type: ${LAUNCH_TYPE}"
echo "Instance Type: ${INSTANCE_TYPE}"
echo "Region: ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo "Source Bucket: ${SOURCE_BUCKET}"
echo ""

# Step 1: Create ECR repository if it doesn't exist
echo "📦 Setting up ECR repository..."
aws ecr describe-repositories --repository-names ${PROJECT_NAME} --region ${REGION} 2>/dev/null || \
aws ecr create-repository --repository-name ${PROJECT_NAME} --region ${REGION}

# Step 2: Build and push Docker image
echo "🐳 Building and pushing Docker image..."
cd application/
docker build -t ${PROJECT_NAME}:latest .
docker tag ${PROJECT_NAME}:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}:latest

# Login to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Push image
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}:latest
cd ..

# Step 3: Create S3 bucket if it doesn't exist
echo "🪣 Setting up S3 source bucket..."
aws s3api head-bucket --bucket ${SOURCE_BUCKET} --region ${REGION} 2>/dev/null || \
aws s3 mb s3://${SOURCE_BUCKET} --region ${REGION}

# Step 4: Get network configuration
echo "🌐 Getting network configuration..."
if [ "${LAUNCH_TYPE}" = "FARGATE" ]; then
    # For Fargate, use default VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region ${REGION})
    SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[0].SubnetId' --output text --region ${REGION})
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region ${REGION})
    
    echo "VPC ID: ${VPC_ID}"
    echo "Subnet ID: ${SUBNET_ID}"
    echo "Security Group ID: ${SECURITY_GROUP_ID}"
else
    # For EC2, network configuration will be created by the ECS stack
    echo "Using EC2 launch type - network configuration will be created by ECS stack"
    SUBNET_ID="placeholder"
    SECURITY_GROUP_ID="placeholder"
fi

# Step 5: Deploy ECS infrastructure
echo "🏗️ Deploying ECS infrastructure..."
aws cloudformation deploy \
  --template-file infrastructure/ecs-cluster.yaml \
  --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} \
  --parameter-overrides \
    ProjectName=${PROJECT_NAME} \
    Environment=${ENVIRONMENT} \
    LaunchType=${LAUNCH_TYPE} \
    InstanceType=${INSTANCE_TYPE} \
  --capabilities CAPABILITY_IAM \
  --region ${REGION}

# Get ECS outputs
CLUSTER_ARN=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`ClusterArn`].OutputValue' --output text --region ${REGION})
TASK_DEFINITION_ARN=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text --region ${REGION})

# Get network configuration from ECS stack if using EC2
if [ "${LAUNCH_TYPE}" = "EC2" ]; then
    SUBNET_ID=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`SubnetId`].OutputValue' --output text --region ${REGION})
    SECURITY_GROUP_ID=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' --output text --region ${REGION})
fi

echo "Cluster ARN: ${CLUSTER_ARN}"
echo "Task Definition ARN: ${TASK_DEFINITION_ARN}"
echo "Subnet ID: ${SUBNET_ID}"
echo "Security Group ID: ${SECURITY_GROUP_ID}"

# Step 6: Deploy Step Functions infrastructure
echo "⚡ Deploying Step Functions infrastructure..."
aws cloudformation deploy \
  --template-file infrastructure/step-functions.yaml \
  --stack-name ${PROJECT_NAME}-stepfunctions-${ENVIRONMENT} \
  --parameter-overrides \
    ProjectName=${PROJECT_NAME} \
    Environment=${ENVIRONMENT} \
    SourceBucket=${SOURCE_BUCKET} \
    ClusterArn=${CLUSTER_ARN} \
    TaskDefinitionArn=${TASK_DEFINITION_ARN} \
    SubnetId=${SUBNET_ID} \
    SecurityGroupId=${SECURITY_GROUP_ID} \
    WorkerCount=${WORKER_COUNT} \
    LaunchType=${LAUNCH_TYPE} \
  --capabilities CAPABILITY_IAM \
  --region ${REGION}

# Get Step Functions outputs
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-stepfunctions-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' --output text --region ${REGION})
ACTIVITY_ARN=$(aws cloudformation describe-stacks --stack-name ${PROJECT_NAME}-stepfunctions-${ENVIRONMENT} --query 'Stacks[0].Outputs[?OutputKey==`ActivityArn`].OutputValue' --output text --region ${REGION})

echo "State Machine ARN: ${STATE_MACHINE_ARN}"
echo "Activity ARN: ${ACTIVITY_ARN}"

echo ""
echo "✅ Infrastructure deployment completed successfully!"
echo ""
echo "📋 Deployment Summary:"
echo "  - ECR Repository: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}"
echo "  - S3 Source Bucket: ${SOURCE_BUCKET}"
echo "  - ECS Cluster: ${CLUSTER_ARN}"
echo "  - Task Definition: ${TASK_DEFINITION_ARN}"
echo "  - State Machine: ${STATE_MACHINE_ARN}"
echo "  - Activity: ${ACTIVITY_ARN}"
echo ""
echo "🧪 Ready for testing! Use scripts/test-end-to-end.sh to run tests."
echo ""
echo "💡 Usage: $0 [worker_count] [launch_type] [instance_type]"
echo "   worker_count: Number of workers (default: 2, max: 100)"
echo "   launch_type: FARGATE or EC2 (default: FARGATE)"
echo "   instance_type: EC2 instance type (default: t3.medium, only used with EC2)"
echo ""
echo "   Examples:"
echo "   $0 5                    # Deploy with 5 Fargate workers"
echo "   $0 10 EC2              # Deploy with 10 EC2 workers (t3.medium)"
echo "   $0 20 EC2 c5.large     # Deploy with 20 EC2 workers (c5.large)"