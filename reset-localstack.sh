#!/bin/bash
# scripts/reset-localstack.sh
# Completely reset LocalStack and Terraform state
#
# Usage:
#   ./scripts/reset-localstack.sh

set -e

echo "=========================================="
echo "  Resetting LocalStack Environment"
echo "=========================================="

# Get project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo ""
echo "🛑 Stopping LocalStack..."
docker-compose -f docker-compose.localstack.yml down -v 2>/dev/null || true

echo ""
echo "🧹 Removing LocalStack data..."
rm -rf localstack-data

echo ""
echo "🧹 Removing Terraform state..."
rm -f terraform-localstack/terraform.tfstate
rm -f terraform-localstack/terraform.tfstate.backup
rm -rf terraform-localstack/.terraform

echo ""
echo "🚀 Starting fresh LocalStack..."
if [ -z "$LOCALSTACK_AUTH_TOKEN" ]; then
  echo "⚠️  Warning: LOCALSTACK_AUTH_TOKEN not set"
  echo "   Set it with: export LOCALSTACK_AUTH_TOKEN=your-token"
fi

docker-compose -f docker-compose.localstack.yml up -d

echo ""
echo "⏳ Waiting for LocalStack to be ready (30 seconds)..."
sleep 30

echo ""
echo "🔍 Checking LocalStack health..."
curl -s http://localhost:4566/_localstack/health | python3 -c "
import sys, json
try:
    h = json.load(sys.stdin)
    print(f\"   Edition: {h.get('edition', 'unknown')}\")
    print(f\"   Version: {h.get('version', 'unknown')}\")
    services = h.get('services', {})
    running = [k for k, v in services.items() if v == 'running' or v == 'available']
    print(f\"   Services: {', '.join(running[:5])}...\")
except:
    print('   Could not parse health response')
"

echo ""
echo "🏗️  Initializing Terraform..."
cd terraform-localstack
terraform init

echo ""
echo "🚀 Applying Terraform..."
terraform apply -auto-approve

echo ""
echo "📦 Building and pushing Docker images..."
cd "$PROJECT_ROOT"
./scripts/push-to-localstack.sh

echo ""
echo "=========================================="
echo "  ✅ LocalStack Reset Complete!"
echo "=========================================="
echo ""
echo "Outputs:"
cd terraform-localstack
terraform output
echo ""
echo "Test with:"
echo "  curl http://localstack-alb.elb.localhost.localstack.cloud/product"