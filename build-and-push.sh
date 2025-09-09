#!/bin/bash

set -e

REGION=${AWS_REGION:-ap-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="s3-batch-processor"
IMAGE_TAG="latest"

echo "🐳 Building and pushing Docker image..."
echo "Account: $ACCOUNT_ID"
echo "Region: $REGION"
echo "Repository: $REPO_NAME"

# Create ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION 2>/dev/null || \
aws ecr create-repository --repository-name $REPO_NAME --region $REGION

# Get ECR login token
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build the image
echo "Building Docker image..."
cd application
docker build -t $REPO_NAME:$IMAGE_TAG .

# Tag for ECR
docker tag $REPO_NAME:$IMAGE_TAG $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

# Push to ECR
echo "Pushing to ECR..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

echo "✅ Image pushed successfully!"
echo "Image URI: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG"
