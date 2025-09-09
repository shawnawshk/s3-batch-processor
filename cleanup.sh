#!/bin/bash

set -e

REGION=${AWS_REGION:-ap-east-1}
STACK_NAME="s3-batch-processor"

echo "🧹 Cleaning up S3 Batch Processor resources..."

# Delete CloudFormation stack
echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION

echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION

# Clean up S3 bucket contents (bucket will be deleted by stack)
BUCKET_NAME="s3-batch-processor-$(aws sts get-caller-identity --query Account --output text)"
echo "Cleaning up S3 bucket contents..."
aws s3 rm "s3://$BUCKET_NAME" --recursive --region $REGION 2>/dev/null || true

# Clean up ECR repository
echo "Cleaning up ECR repository..."
aws ecr delete-repository --repository-name s3-batch-processor --force --region $REGION 2>/dev/null || true

echo "✅ Cleanup completed!"
