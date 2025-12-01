#!/bin/bash
# scripts/push-to-localstack.sh
# Build and push Docker images to LocalStack ECR
#
# Usage:
#   ./scripts/push-to-localstack.sh

set -e

# LocalStack ECR endpoint
LOCALSTACK_ECR="localhost.localstack.cloud:4566"
ACCOUNT_ID="000000000000"
REGION="us-east-1"

SERVICES=(
  "product-service"
  "product-service-bad"
  "shopping-cart-service"
  "credit-card-authorizer"
  "warehouse-consumer"
)

echo "=========================================="
echo "  Pushing images to LocalStack ECR"
echo "=========================================="

# For LocalStack, we don't need real authentication
# Just configure Docker to allow insecure registry
echo ""
echo "🔐 Configuring Docker for LocalStack ECR..."

# Create ECR URL base
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.localhost.localstack.cloud:4566"

for SERVICE in "${SERVICES[@]}"; do
  echo ""
  echo "========================================"
  echo "📦 Processing ${SERVICE}..."
  echo "========================================"
  
  # Build the image
  echo "🔨 Building image..."
  docker build -t ${SERVICE}:latest ./services/${SERVICE}
  
  # Tag for LocalStack ECR
  ECR_URL="${ECR_BASE}/${SERVICE}"
  echo "🏷️  Tagging as ${ECR_URL}:latest..."
  docker tag ${SERVICE}:latest ${ECR_URL}:latest
  
  # Push to LocalStack ECR
  # LocalStack ECR accepts pushes without authentication
  echo "⬆️  Pushing to LocalStack ECR..."
  docker push ${ECR_URL}:latest || {
    echo "⚠️  Direct push failed, trying with localhost..."
    # Alternative: try with localhost directly
    ALT_ECR_URL="localhost:4566/${SERVICE}"
    docker tag ${SERVICE}:latest ${ALT_ECR_URL}:latest
    docker push ${ALT_ECR_URL}:latest
  }
  
  echo "✅ ${SERVICE} pushed successfully!"
done

echo ""
echo "=========================================="
echo "  All images pushed to LocalStack ECR!"
echo "=========================================="
echo ""
echo "ECR Repository URLs:"
for SERVICE in "${SERVICES[@]}"; do
  echo "  - ${SERVICE}: ${ECR_BASE}/${SERVICE}:latest"
done
echo ""
echo "Next: The ECS services should now be able to pull these images."
echo "Check service status with: aws --endpoint-url=http://localhost:4566 ecs list-services --cluster localstack-cluster"