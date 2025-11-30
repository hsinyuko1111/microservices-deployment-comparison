# ===============================================
# Test System for Microservice Extravaganza
# Compatible with PowerShell 5.1 / 7+
# ===============================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Testing Microservice Extravaganza System" -ForegroundColor Cyan
Write-Host "==========================================`n"

# --- Helper for colored output ---
function Info($msg) { Write-Host $msg -ForegroundColor Yellow }
function Ok($msg) { Write-Host $msg -ForegroundColor Green }
function Fail($msg) { Write-Host $msg -ForegroundColor Red }

# --- Helper to extract JSON field safely ---
function Get-JsonField($json, $field) {
    try {
        $obj = $json | ConvertFrom-Json
        return ($obj.$field)
    } catch {
        return $null
    }
}

# --- Helper to perform safe HTTP request ---
function HttpPost($url, $jsonBody) {
    try {
        return Invoke-RestMethod -Method POST -Uri $url `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $jsonBody -TimeoutSec 10
    } catch {
        return $null
    }
}

# ----------------------------------------------------------
# Test 1: Create Shopping Cart
# ----------------------------------------------------------
Info "Test 1: Creating Shopping Cart"
$cartResponse = HttpPost "http://localhost:8081/shopping-cart" '{"customer_id":42}'

if ($cartResponse -and $cartResponse.shopping_cart_id) {
    $cartId = $cartResponse.shopping_cart_id
    Ok "Created shopping cart with ID: $cartId"
} else {
    Fail "Failed to create shopping cart"
    exit 1
}
Write-Host ""

# ----------------------------------------------------------
# Test 2: Add Items to Cart
# ----------------------------------------------------------
Info "Test 2: Adding Items to Cart"
HttpPost "http://localhost:8081/shopping-carts/$cartId/addItem" '{"product_id":1001,"quantity":5}' | Out-Null
HttpPost "http://localhost:8081/shopping-carts/$cartId/addItem" '{"product_id":1002,"quantity":3}' | Out-Null
Ok "Added items to cart"
Write-Host ""

# ----------------------------------------------------------
# Test 3: Checkout
# ----------------------------------------------------------
Info "Test 3: Checking Out"
$checkoutResponse = HttpPost "http://localhost:8081/shopping-carts/$cartId/checkout" '{"credit_card_number":"1234-5678-9012-3456"}'

if ($checkoutResponse -and $checkoutResponse.order_id) {
    $orderId = $checkoutResponse.order_id
    Ok "Checkout successful! Order ID: $orderId"
} else {
    Fail "Checkout failed (card may have been declined)"
    Write-Host "Response: $checkoutResponse"
}
Write-Host ""

# ----------------------------------------------------------
# Test 4: Create Product
# ----------------------------------------------------------
Info "Test 4: Creating Product"
$productResponse = HttpPost "http://localhost:8080/product" '{
    "sku": "TESTSKU123",
    "manufacturer": "Test Manufacturer",
    "category_id": 100,
    "weight": 1500,
    "some_other_id": 999
}'

if ($productResponse -and $productResponse.product_id) {
    $productId = $productResponse.product_id
    Ok "Created product with ID: $productId"
} else {
    Fail "Failed to create product"
}
Write-Host ""

# ----------------------------------------------------------
# Test 5: Get Product
# ----------------------------------------------------------
Info "Test 5: Retrieving Product"
try {
    $productData = Invoke-RestMethod -Uri "http://localhost:8080/products/$productId"
    if ($productData.sku -eq "TESTSKU123") {
        Ok "Successfully retrieved product"
    } else {
        Fail "Product data mismatch"
    }
} catch {
    Fail "Failed to retrieve product"
}
Write-Host ""

# ----------------------------------------------------------
# Test 6: Bad Product Service (~50% failure rate)
# ----------------------------------------------------------
Info "Test 6: Testing Bad Product Service (expected ~50% failures)"
$successCount = 0
$failureCount = 0

for ($i = 1; $i -le 10; $i++) {
    $body = "{
        `"sku`": `"BAD${i}`",
        `"manufacturer`": `"Test Corp`",
        `"category_id`": 1,
        `"weight`": 500,
        `"some_other_id`": 1
    }"
    try {
        $resp = Invoke-RestMethod -Uri "http://localhost:8083/product" -Method POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $body -SkipHttpErrorCheck
        $successCount++
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 503) {
            $failureCount++
        }
    }
}

Write-Host "Successes: " -NoNewline; Write-Host "$successCount" -ForegroundColor Green -NoNewline
Write-Host " | Failures: " -NoNewline; Write-Host "$failureCount" -ForegroundColor Red

if ($failureCount -ge 3 -and $failureCount -le 7) {
    Ok "Bad service behaving as expected (~50% failure rate)"
} else {
    Info "Failure rate outside expected range (this is random)"
}
Write-Host ""

# ----------------------------------------------------------
# Test 7: Invalid Credit Card Format
# ----------------------------------------------------------
Info "Test 7: Testing Invalid Credit Card Format"
try {
    $invalidResp = HttpPost "http://localhost:8082/credit-card-authorizer/authorize" '{"credit_card_number":"1234567890123456"}'
    if ($invalidResp -and $invalidResp.error -eq "INVALID_CARD_FORMAT") {
        Ok "Invalid card format correctly rejected"
    } else {
        Fail "Invalid card format not rejected"
    }
} catch {
    Fail "Credit Card Authorizer request failed"
}
Write-Host ""

# ----------------------------------------------------------
# Summary
# ----------------------------------------------------------
Write-Host "==========================================" -ForegroundColor Cyan
Ok "Testing Complete!"
Write-Host "=========================================="
Write-Host ""
Write-Host "Check RabbitMQ Management UI at: http://localhost:15672"
Write-Host "Username: guest | Password: guest"