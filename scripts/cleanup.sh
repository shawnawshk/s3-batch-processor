#!/bin/bash

# S3 Batch Processing PoC - Cleanup Script
set -e

# Configuration
PROJECT_NAME="s3-batch-processor"
ENVIRONMENT="poc"
REGION="ap-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SOURCE_BUCKET="${PROJECT_NAME}-source-${ACCOUNT_ID}"

echo "🧹 Starting cleanup of S3 Batch Processing PoC resources"
echo "Project: ${PROJECT_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Region: ${REGION}"
echo ""

# Step 1: Stop any running ECS tasks
echo "🛑 Stopping running ECS tasks..."
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
RUNNING_TASKS=$(aws ecs list-tasks --cluster ${CLUSTER_NAME} --region ${REGION} --query 'taskArns' --output text 2>/dev/null || echo "")

if [ ! -z "$RUNNING_TASKS" ] && [ "$RUNNING_TASKS" != "None" ]; then
    echo "Stopping tasks: ${RUNNING_TASKS}"
    for task in $RUNNING_TASKS; do
        aws ecs stop-task --cluster ${CLUSTER_NAME} --task ${task} --region ${REGION} || true
    done
    echo "Waiting for tasks to stop..."
    sleep 30
else
    echo "No running tasks found"
fi

# Step 2: Empty and delete S3 bucket
echo "🪣 Cleaning up S3 bucket..."
if aws s3api head-bucket --bucket ${SOURCE_BUCKET} --region ${REGION} 2>/dev/null; then
    echo "Emptying bucket: ${SOURCE_BUCKET}"
    aws s3 rm s3://${SOURCE_BUCKET} --recursive --region ${REGION} || true
    echo "Deleting bucket: ${SOURCE_BUCKET}"
    aws s3 rb s3://${SOURCE_BUCKET} --region ${REGION} || true
else
    echo "Bucket ${SOURCE_BUCKET} not found or already deleted"
fi

# Step 3: Delete CloudFormation stacks
echo "☁️ Deleting CloudFormation stacks..."

# Delete Step Functions stack first (depends on ECS)
echo "Deleting Step Functions stack..."
aws cloudformation delete-stack --stack-name ${PROJECT_NAME}-stepfunctions-${ENVIRONMENT} --region ${REGION} || true

# Wait for Step Functions stack deletion
echo "Waiting for Step Functions stack deletion..."
aws cloudformation wait stack-delete-complete --stack-name ${PROJECT_NAME}-stepfunctions-${ENVIRONMENT} --region ${REGION} || true

# Delete ECS stack
echo "Deleting ECS stack..."
aws cloudformation delete-stack --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} --region ${REGION} || true

# Wait for ECS stack deletion
echo "Waiting for ECS stack deletion..."
aws cloudformation wait stack-delete-complete --stack-name ${PROJECT_NAME}-ecs-${ENVIRONMENT} --region ${REGION} || true

# Step 4: Delete ECR repository
echo "📦 Deleting ECR repository..."
aws ecr delete-repository --repository-name ${PROJECT_NAME} --force --region ${REGION} || true

# Step 5: Clean up CloudWatch logs
echo "📋 Cleaning up CloudWatch logs..."
LOG_GROUP="/ecs/${PROJECT_NAME}"
aws logs delete-log-group --log-group-name ${LOG_GROUP} --region ${REGION} || true

echo ""
echo "✅ Cleanup completed!"
echo ""
echo "🗑️ Resources cleaned up:"
echo "  - ECS tasks stopped"
echo "  - S3 bucket emptied and deleted"
echo "  - CloudFormation stacks deleted"
echo "  - ECR repository deleted"
echo "  - CloudWatch log groups deleted"
echo ""
echo "💡 Note: Some resources may take a few minutes to fully delete."