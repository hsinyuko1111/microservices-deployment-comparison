#!/bin/bash

# Configuration
AWS_ACCOUNT_ID=782389663648
AWS_REGION=us-west-2
ECR_BASE=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting build and push for all services...${NC}\n"

# Function to build and push
build_and_push() {
    local SERVICE_DIR=$1
    local ECR_REPO=$2
    
    echo -e "${GREEN}Building $SERVICE_DIR...${NC}"
    docker build -t $ECR_REPO:latest ./services/$SERVICE_DIR/
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Pushing $SERVICE_DIR to ECR...${NC}"
        docker push $ECR_REPO:latest
        echo -e "${GREEN}✓ Successfully pushed $SERVICE_DIR${NC}\n"
    else
        echo -e "${RED}✗ Failed to build $SERVICE_DIR${NC}\n"
        exit 1
    fi
}

# Build and push all services
build_and_push "product-service" "$ECR_BASE/product-service"
build_and_push "product-service-bad" "$ECR_BASE/product-service-bad"
build_and_push "credit-card-authorizer" "$ECR_BASE/credit-card-authorizer"
build_and_push "shopping-cart-service" "$ECR_BASE/shopping-cart-service"
build_and_push "warehouse-consumer" "$ECR_BASE/warehouse-consumer"

echo -e "${GREEN}All services built and pushed successfully!${NC}"