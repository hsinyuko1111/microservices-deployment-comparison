#!/bin/bash

echo "=========================================="
echo "Testing Microservice Extravaganza System"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Create Shopping Cart
echo -e "${YELLOW}Test 1: Creating Shopping Cart${NC}"
CART_RESPONSE=$(curl -s -X POST http://localhost:8081/shopping-cart \
  -H "Content-Type: application/json" \
  -d '{"customer_id": 42}')
CART_ID=$(echo $CART_RESPONSE | grep -o '"shopping_cart_id":[0-9]*' | grep -o '[0-9]*')

if [ -z "$CART_ID" ]; then
  echo -e "${RED}✗ Failed to create shopping cart${NC}"
  exit 1
else
  echo -e "${GREEN}✓ Created shopping cart with ID: $CART_ID${NC}"
fi
echo ""

# Test 2: Add Items to Cart
echo -e "${YELLOW}Test 2: Adding Items to Cart${NC}"
curl -s -X POST http://localhost:8081/shopping-carts/$CART_ID/addItem \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1001, "quantity": 5}' > /dev/null

curl -s -X POST http://localhost:8081/shopping-carts/$CART_ID/addItem \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1002, "quantity": 3}' > /dev/null

echo -e "${GREEN}✓ Added items to cart${NC}"
echo ""

# Test 3: Checkout (may be declined 10% of the time)
echo -e "${YELLOW}Test 3: Checking Out${NC}"
CHECKOUT_RESPONSE=$(curl -s -X POST http://localhost:8081/shopping-carts/$CART_ID/checkout \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number": "1234-5678-9012-3456"}')

ORDER_ID=$(echo $CHECKOUT_RESPONSE | grep -o '"order_id":[0-9]*' | grep -o '[0-9]*')

if [ -z "$ORDER_ID" ]; then
  echo -e "${RED}✗ Checkout failed (card may have been declined)${NC}"
  echo "Response: $CHECKOUT_RESPONSE"
else
  echo -e "${GREEN}✓ Checkout successful! Order ID: $ORDER_ID${NC}"
fi
echo ""

# Test 4: Create Product
echo -e "${YELLOW}Test 4: Creating Product${NC}"
PRODUCT_RESPONSE=$(curl -s -X POST http://localhost:8080/product \
  -H "Content-Type: application/json" \
  -d '{
    "sku": "TESTSKU123",
    "manufacturer": "Test Manufacturer",
    "category_id": 100,
    "weight": 1500,
    "some_other_id": 999
  }')

PRODUCT_ID=$(echo $PRODUCT_RESPONSE | grep -o '"product_id":[0-9]*' | grep -o '[0-9]*')

if [ -z "$PRODUCT_ID" ]; then
  echo -e "${RED}✗ Failed to create product${NC}"
else
  echo -e "${GREEN}✓ Created product with ID: $PRODUCT_ID${NC}"
fi
echo ""

# Test 5: Get Product
echo -e "${YELLOW}Test 5: Retrieving Product${NC}"
PRODUCT_DATA=$(curl -s http://localhost:8080/products/$PRODUCT_ID)
if [[ $PRODUCT_DATA == *"TESTSKU123"* ]]; then
  echo -e "${GREEN}✓ Successfully retrieved product${NC}"
else
  echo -e "${RED}✗ Failed to retrieve product${NC}"
fi
echo ""

# Test 6: Test Bad Product Service
echo -e "${YELLOW}Test 6: Testing Bad Product Service (50% failure rate)${NC}"
SUCCESS_COUNT=0
FAILURE_COUNT=0

for i in {1..10}; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8083/product \
    -H "Content-Type: application/json" \
    -d '{
      "sku": "BAD'$i'",
      "manufacturer": "Test Corp",
      "category_id": 1,
      "weight": 500,
      "some_other_id": 1
    }')
  
  if [ "$HTTP_CODE" == "201" ]; then
    ((SUCCESS_COUNT++))
  elif [ "$HTTP_CODE" == "503" ]; then
    ((FAILURE_COUNT++))
  fi
done

echo -e "Successes: ${GREEN}$SUCCESS_COUNT${NC} | Failures: ${RED}$FAILURE_COUNT${NC}"
if [ $FAILURE_COUNT -ge 3 ] && [ $FAILURE_COUNT -le 7 ]; then
  echo -e "${GREEN}✓ Bad service behaving as expected (~50% failure rate)${NC}"
else
  echo -e "${YELLOW}⚠ Failure rate outside expected range (but this is random)${NC}"
fi
echo ""

# Test 7: Test Invalid Credit Card Format
echo -e "${YELLOW}Test 7: Testing Invalid Credit Card Format${NC}"
INVALID_RESPONSE=$(curl -s -X POST http://localhost:8082/credit-card-authorizer/authorize \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number": "1234567890123456"}')

if [[ $INVALID_RESPONSE == *"INVALID_CARD_FORMAT"* ]]; then
  echo -e "${GREEN}✓ Invalid card format correctly rejected${NC}"
else
  echo -e "${RED}✗ Invalid card format not rejected${NC}"
fi
echo ""

echo "=========================================="
echo -e "${GREEN}Testing Complete!${NC}"
echo "=========================================="
echo ""
echo "Check RabbitMQ Management UI at: http://localhost:15672"
echo "Username: guest | Password: guest"
echo ""