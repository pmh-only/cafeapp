#!/bin/bash

# CloudCafe Endpoint Testing Script
# Region: ap-northeast-2 (Seoul)
# Date: February 24, 2026

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print test header
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to test HTTP endpoint
test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=$3
    local method=${4:-GET}
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${YELLOW}Testing: $name${NC}"
    echo "URL: $url"
    echo "Method: $method"
    echo "Expected Status: $expected_status"
    
    # Make request and capture status code
    response=$(curl -s -o /dev/null -w "%{http_code}" -X $method "$url" --connect-timeout 10 --max-time 30 2>&1 || echo "000")
    
    if [ "$response" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} - Status: $response"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - Expected: $expected_status, Got: $response"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Function to test endpoint with detailed response
test_endpoint_detailed() {
    local name=$1
    local url=$2
    local method=${3:-GET}
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${YELLOW}Testing: $name${NC}"
    echo "URL: $url"
    echo "Method: $method"
    
    # Make request and capture full response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}\nTIME_TOTAL:%{time_total}s" -X $method "$url" --connect-timeout 10 --max-time 30 2>&1)
    
    status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    time=$(echo "$response" | grep "TIME_TOTAL:" | cut -d: -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS:/,$d')
    
    echo "Status Code: $status"
    echo "Response Time: $time"
    
    if [ ! -z "$body" ] && [ "$body" != "" ]; then
        echo "Response Body (first 200 chars):"
        echo "$body" | head -c 200
        echo ""
    fi
    
    if [ "$status" != "000" ] && [ ! -z "$status" ]; then
        echo -e "${GREEN}✓ PASS${NC} - Endpoint is accessible"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - Endpoint not accessible"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Function to test DNS resolution
test_dns() {
    local name=$1
    local hostname=$2
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${YELLOW}Testing DNS: $name${NC}"
    echo "Hostname: $hostname"
    
    if host "$hostname" > /dev/null 2>&1; then
        ip=$(host "$hostname" | grep "has address" | head -1 | awk '{print $4}')
        echo -e "${GREEN}✓ PASS${NC} - Resolved to: $ip"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - DNS resolution failed"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Start testing
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         CloudCafe Endpoint Testing Suite                  ║"
echo "║         Region: ap-northeast-2 (Seoul)                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Load endpoints from Terraform outputs
cd infrastructure/terraform
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
API_GW_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url 2>/dev/null || echo "")
NLB_DNS=$(terraform output -raw nlb_dns_name 2>/dev/null || echo "")
cd ../..

# ============================================
# 1. DNS Resolution Tests
# ============================================
print_header "1. DNS RESOLUTION TESTS"

if [ ! -z "$ALB_DNS" ]; then
    test_dns "Application Load Balancer" "$ALB_DNS"
fi

if [ ! -z "$NLB_DNS" ]; then
    test_dns "Network Load Balancer" "$NLB_DNS"
fi

# ============================================
# 2. Load Balancer Tests
# ============================================
print_header "2. LOAD BALANCER TESTS"

if [ ! -z "$ALB_DNS" ]; then
    test_endpoint "ALB Root Path" "http://$ALB_DNS/" "404"
    test_endpoint "ALB Health Check" "http://$ALB_DNS/health" "404"
    test_endpoint "ALB API Path" "http://$ALB_DNS/api" "404"
fi

if [ ! -z "$NLB_DNS" ]; then
    test_endpoint "NLB Connection" "http://$NLB_DNS/" "000"
fi

# ============================================
# 3. API Gateway Tests
# ============================================
print_header "3. API GATEWAY TESTS"

if [ ! -z "$API_GW_URL" ]; then
    test_endpoint_detailed "API Gateway Root" "$API_GW_URL"
    test_endpoint_detailed "API Gateway /api Path" "$API_GW_URL/api"
    test_endpoint_detailed "API Gateway /api/orders" "$API_GW_URL/api/orders"
    
    # Test different HTTP methods
    test_endpoint "API Gateway GET" "$API_GW_URL/api/test" "500" "GET"
    test_endpoint "API Gateway POST" "$API_GW_URL/api/test" "500" "POST"
fi

# ============================================
# 4. CloudFront CDN Tests
# ============================================
print_header "4. CLOUDFRONT CDN TESTS"

if [ ! -z "$CLOUDFRONT_URL" ]; then
    test_endpoint_detailed "CloudFront Root" "$CLOUDFRONT_URL"
    test_endpoint_detailed "CloudFront /api Path" "$CLOUDFRONT_URL/api"
    test_endpoint_detailed "CloudFront /static Path" "$CLOUDFRONT_URL/static"
    
    # Test CloudFront headers
    echo -e "${YELLOW}Testing CloudFront Headers${NC}"
    headers=$(curl -s -I "$CLOUDFRONT_URL" 2>&1 | grep -i "x-cache\|x-amz-cf-id\|via" || echo "")
    if [ ! -z "$headers" ]; then
        echo -e "${GREEN}✓ CloudFront headers detected${NC}"
        echo "$headers"
    else
        echo -e "${YELLOW}⚠ CloudFront headers not found${NC}"
    fi
    echo ""
fi

# ============================================
# 5. Service-Specific Endpoint Tests
# ============================================
print_header "5. SERVICE-SPECIFIC TESTS"

if [ ! -z "$ALB_DNS" ]; then
    # Order Service endpoints
    test_endpoint "Order Service - List Orders" "http://$ALB_DNS/api/orders" "404"
    test_endpoint "Order Service - Create Order" "http://$ALB_DNS/api/orders" "404" "POST"
    
    # Menu Service endpoints
    test_endpoint "Menu Service - List Items" "http://$ALB_DNS/api/menu/items" "404"
    
    # Inventory Service endpoints
    test_endpoint "Inventory Service - Check Stock" "http://$ALB_DNS/api/inventory/check" "404"
    
    # Loyalty Service endpoints
    test_endpoint "Loyalty Service - Get Points" "http://$ALB_DNS/api/loyalty/points/user123" "404"
fi

# ============================================
# 6. HTTPS/TLS Tests
# ============================================
print_header "6. HTTPS/TLS TESTS"

if [ ! -z "$API_GW_URL" ]; then
    echo -e "${YELLOW}Testing API Gateway TLS${NC}"
    tls_info=$(curl -s -v "$API_GW_URL" 2>&1 | grep -i "ssl\|tls" | head -3 || echo "")
    if [ ! -z "$tls_info" ]; then
        echo -e "${GREEN}✓ TLS connection established${NC}"
        echo "$tls_info"
    fi
    echo ""
fi

if [ ! -z "$CLOUDFRONT_URL" ]; then
    echo -e "${YELLOW}Testing CloudFront TLS${NC}"
    tls_info=$(curl -s -v "$CLOUDFRONT_URL" 2>&1 | grep -i "ssl\|tls" | head -3 || echo "")
    if [ ! -z "$tls_info" ]; then
        echo -e "${GREEN}✓ TLS connection established${NC}"
        echo "$tls_info"
    fi
    echo ""
fi

# ============================================
# 7. Performance Tests
# ============================================
print_header "7. PERFORMANCE TESTS"

if [ ! -z "$ALB_DNS" ]; then
    echo -e "${YELLOW}Testing ALB Response Time${NC}"
    for i in {1..5}; do
        time=$(curl -s -o /dev/null -w "%{time_total}s" "http://$ALB_DNS/" --connect-timeout 10)
        echo "Request $i: $time"
    done
    echo ""
fi

if [ ! -z "$CLOUDFRONT_URL" ]; then
    echo -e "${YELLOW}Testing CloudFront Response Time${NC}"
    for i in {1..5}; do
        time=$(curl -s -o /dev/null -w "%{time_total}s" "$CLOUDFRONT_URL" --connect-timeout 10)
        echo "Request $i: $time"
    done
    echo ""
fi

# ============================================
# Test Summary
# ============================================
print_header "TEST SUMMARY"

echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ALL TESTS PASSED SUCCESSFULLY! ✓    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    exit 0
else
    echo -e "\n${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   SOME TESTS FAILED - REVIEW ABOVE    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}\n"
    exit 1
fi
