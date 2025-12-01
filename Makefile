# Makefile
# Commands for local and AWS deployment comparison
#
# Usage:
#   make local-up      - Start local environment
#   make local-down    - Stop local environment
#   make local-test    - Run load test against local
#   make aws-test      - Run load test against AWS
#   make compare       - Generate comparison report

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# AWS Configuration (update with your ALB DNS)
AWS_ALB_DNS ?= your-alb-dns.us-east-1.elb.amazonaws.com

# Load Test Configuration
NUM_USERS ?= 100
SPAWN_RATE ?= 10
TEST_DURATION ?= 2m
NUM_INITIAL_PRODUCTS ?= 500
TARGET_CHECKOUTS ?= 10000

# Directories
RESULTS_DIR := ./analysis/results
LOCAL_RESULTS := $(RESULTS_DIR)/local
AWS_RESULTS := $(RESULTS_DIR)/aws

# Timestamp for test runs
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)

# ==============================================================================
# LOCAL ENVIRONMENT (Docker Compose + Nginx - no AWS emulation)
# ==============================================================================

.PHONY: local-up
local-up: ## Start local environment (Nginx + all services, NO LocalStack)
	@echo "🚀 Starting local environment (Docker Compose + Nginx)..."
	@echo "   This is for quick local development without AWS emulation."
	@echo ""
	docker-compose up --build -d
	@echo "⏳ Waiting for services to be healthy..."
	@sleep 10
	@echo ""
	@echo "✅ Local environment is ready!"
	@echo "   - Load Balancer: http://localhost (Nginx)"
	@echo "   - RabbitMQ UI:   http://localhost:15672 (guest/guest)"
	@echo "   - Nginx Status:  http://localhost:8090/nginx_status"
	@echo ""
	@docker-compose ps

.PHONY: local-down
local-down: ## Stop local environment
	@echo "🛑 Stopping local environment..."
	docker-compose down
	@echo "✅ Local environment stopped"

.PHONY: local-logs
local-logs: ## View logs from all services
	docker-compose logs -f

.PHONY: local-status
local-status: ## Check status of local services
	@echo "📊 Service Status:"
	@docker-compose ps
	@echo ""
	@echo "📊 Nginx Status:"
	@curl -s http://localhost:8090/nginx_status || echo "Nginx not running"
	@echo ""
	@echo "📊 RabbitMQ Queues:"
	@curl -s -u guest:guest http://localhost:15672/api/queues | python3 -c "import sys,json; queues=json.load(sys.stdin); [print(f\"  - {q['name']}: {q.get('messages',0)} messages\") for q in queues]" 2>/dev/null || echo "  RabbitMQ not running"

.PHONY: local-health
local-health: ## Check health of all endpoints
	@echo "🏥 Health Check:"
	@echo -n "  Nginx:         "; curl -s -o /dev/null -w "%{http_code}" http://localhost/health && echo " ✅" || echo " ❌"
	@echo -n "  Product:       "; curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost/product -H "Content-Type: application/json" -d '{"sku":"HEALTH","manufacturer":"Test","category_id":1,"weight":100,"some_other_id":1}' && echo " ✅" || echo " ❌"
	@echo -n "  Shopping Cart: "; curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost/shopping-cart -H "Content-Type: application/json" -d '{"customer_id":1}' && echo " ✅" || echo " ❌"
	@echo -n "  RabbitMQ:      "; curl -s -o /dev/null -w "%{http_code}" -u guest:guest http://localhost:15672/api/overview && echo " ✅" || echo " ❌"

# ==============================================================================
# LOAD TESTING
# ==============================================================================

.PHONY: setup-results
setup-results: ## Create results directories
	@mkdir -p $(LOCAL_RESULTS)
	@mkdir -p $(AWS_RESULTS)

.PHONY: local-test
local-test: setup-results ## Run load test against local environment
	@echo "🧪 Running load test against LOCAL environment..."
	@echo "   URL: http://localhost"
	@echo "   Users: $(NUM_USERS)"
	@echo "   Duration: $(TEST_DURATION)"
	@echo "   Results: $(LOCAL_RESULTS)/$(TIMESTAMP)"
	@echo ""
	@mkdir -p $(LOCAL_RESULTS)/$(TIMESTAMP)
	SETUP_USERS=50 \
	NUM_INITIAL_PRODUCTS=$(NUM_INITIAL_PRODUCTS) \
	TARGET_CHECKOUTS=$(TARGET_CHECKOUTS) \
	locust -f load-test/locustfile.py \
		--host http://localhost \
		--users $(NUM_USERS) \
		--spawn-rate $(SPAWN_RATE) \
		--run-time $(TEST_DURATION) \
		--headless \
		--html $(LOCAL_RESULTS)/$(TIMESTAMP)/report.html \
		--csv $(LOCAL_RESULTS)/$(TIMESTAMP)/results
	@echo ""
	@echo "✅ Local test complete!"
	@echo "   Report: $(LOCAL_RESULTS)/$(TIMESTAMP)/report.html"

.PHONY: local-test-ui
local-test-ui: ## Run load test with web UI against local
	@echo "🧪 Starting Locust Web UI for LOCAL testing..."
	@echo "   Open: http://localhost:8089"
	@echo "   Host: http://localhost"
	@echo ""
	SETUP_USERS=50 \
	NUM_INITIAL_PRODUCTS=$(NUM_INITIAL_PRODUCTS) \
	TARGET_CHECKOUTS=$(TARGET_CHECKOUTS) \
	locust -f load-test/locustfile.py \
		--host http://localhost

.PHONY: aws-test
aws-test: setup-results ## Run load test against AWS environment
	@if [ "$(AWS_ALB_DNS)" = "your-alb-dns.us-east-1.elb.amazonaws.com" ]; then \
		echo "❌ Error: Please set AWS_ALB_DNS"; \
		echo "   Usage: make aws-test AWS_ALB_DNS=your-actual-alb-dns.com"; \
		exit 1; \
	fi
	@echo "🧪 Running load test against AWS environment..."
	@echo "   URL: http://$(AWS_ALB_DNS)"
	@echo "   Users: $(NUM_USERS)"
	@echo "   Duration: $(TEST_DURATION)"
	@echo "   Results: $(AWS_RESULTS)/$(TIMESTAMP)"
	@echo ""
	@mkdir -p $(AWS_RESULTS)/$(TIMESTAMP)
	SETUP_USERS=50 \
	NUM_INITIAL_PRODUCTS=$(NUM_INITIAL_PRODUCTS) \
	TARGET_CHECKOUTS=$(TARGET_CHECKOUTS) \
	locust -f load-test/locustfile.py \
		--host http://$(AWS_ALB_DNS) \
		--users $(NUM_USERS) \
		--spawn-rate $(SPAWN_RATE) \
		--run-time $(TEST_DURATION) \
		--headless \
		--html $(AWS_RESULTS)/$(TIMESTAMP)/report.html \
		--csv $(AWS_RESULTS)/$(TIMESTAMP)/results
	@echo ""
	@echo "✅ AWS test complete!"
	@echo "   Report: $(AWS_RESULTS)/$(TIMESTAMP)/report.html"

.PHONY: aws-test-ui
aws-test-ui: ## Run load test with web UI against AWS
	@if [ "$(AWS_ALB_DNS)" = "your-alb-dns.us-east-1.elb.amazonaws.com" ]; then \
		echo "❌ Error: Please set AWS_ALB_DNS"; \
		echo "   Usage: make aws-test-ui AWS_ALB_DNS=your-actual-alb-dns.com"; \
		exit 1; \
	fi
	@echo "🧪 Starting Locust Web UI for AWS testing..."
	@echo "   Open: http://localhost:8089"
	@echo "   Host: http://$(AWS_ALB_DNS)"
	@echo ""
	SETUP_USERS=50 \
	NUM_INITIAL_PRODUCTS=$(NUM_INITIAL_PRODUCTS) \
	TARGET_CHECKOUTS=$(TARGET_CHECKOUTS) \
	locust -f load-test/locustfile.py \
		--host http://$(AWS_ALB_DNS)

# ==============================================================================
# COMPARISON LOAD TESTS
# ==============================================================================

LOCUST_FILE := load-test/locustfile_comparison.py
TEST_USERS ?= 50
TEST_SPAWN_RATE ?= 5
TEST_DURATION ?= 2m

.PHONY: test-localstack
test-localstack: setup-results ## Run load test against LocalStack
	@echo "🧪 Running load test against LOCALSTACK..."
	@mkdir -p $(LOCAL_RESULTS)/$(TIMESTAMP)
	ENV=localstack \
	NUM_PRODUCTS=100 \
	TARGET_CHECKOUTS=200 \
	locust -f $(LOCUST_FILE) \
		--host http://localhost \
		--headless \
		--users $(TEST_USERS) \
		--spawn-rate $(TEST_SPAWN_RATE) \
		--run-time $(TEST_DURATION) \
		--html $(LOCAL_RESULTS)/$(TIMESTAMP)/report.html \
		--csv $(LOCAL_RESULTS)/$(TIMESTAMP)/results
	@echo "✅ LocalStack test complete: $(LOCAL_RESULTS)/$(TIMESTAMP)/"

.PHONY: test-aws
test-aws: setup-results ## Run load test against AWS
	@if [ -z "$(AWS_ALB_DNS)" ]; then \
		echo "❌ Error: Set AWS_ALB_DNS"; \
		echo "   Usage: make test-aws AWS_ALB_DNS=your-alb.amazonaws.com"; \
		exit 1; \
	fi
	@echo "🧪 Running load test against AWS..."
	@mkdir -p $(AWS_RESULTS)/$(TIMESTAMP)
	ENV=aws \
	NUM_PRODUCTS=100 \
	TARGET_CHECKOUTS=200 \
	locust -f $(LOCUST_FILE) \
		--host http://$(AWS_ALB_DNS) \
		--headless \
		--users $(TEST_USERS) \
		--spawn-rate $(TEST_SPAWN_RATE) \
		--run-time $(TEST_DURATION) \
		--html $(AWS_RESULTS)/$(TIMESTAMP)/report.html \
		--csv $(AWS_RESULTS)/$(TIMESTAMP)/results
	@echo "✅ AWS test complete: $(AWS_RESULTS)/$(TIMESTAMP)/"

.PHONY: test-both
test-both: ## Run tests against both environments
	@echo "🧪 Running comparison tests..."
	@$(MAKE) test-localstack
	@sleep 5
	@$(MAKE) test-aws AWS_ALB_DNS=$(AWS_ALB_DNS)
	@echo ""
	@echo "✅ Both tests complete! Run 'make compare' to generate report."

# ==============================================================================
# COMPARISON & ANALYSIS
# ==============================================================================

.PHONY: compare
compare: ## Generate comparison report from test results
	@echo "📊 Generating comparison report..."
	python3 analysis/compare_results.py
	@echo "✅ Comparison complete! Check analysis/results/comparison/"

.PHONY: list-results
list-results: ## List all test results
	@echo "📁 LocalStack Results:"
	@ls -la $(LOCAL_RESULTS) 2>/dev/null || echo "   No results yet"
	@echo ""
	@echo "📁 AWS Results:"
	@ls -la $(AWS_RESULTS) 2>/dev/null || echo "   No results yet"

# ==============================================================================
# LOCALSTACK DEPLOYMENT
# ==============================================================================

.PHONY: localstack-up
localstack-up: ## Start LocalStack Pro
	@if [ -z "$(LOCALSTACK_AUTH_TOKEN)" ]; then \
		echo "❌ Error: LOCALSTACK_AUTH_TOKEN not set"; \
		echo "   Get your token from: https://app.localstack.cloud"; \
		echo "   Then run: export LOCALSTACK_AUTH_TOKEN=your-token"; \
		exit 1; \
	fi
	@echo "🚀 Starting LocalStack Pro..."
	docker-compose -f docker-compose.localstack.yml up -d
	@echo "⏳ Waiting for LocalStack to be ready..."
	@sleep 15
	@curl -s http://localhost:4566/_localstack/health | python3 -c "import sys,json; h=json.load(sys.stdin); print('✅ LocalStack ready!' if h.get('edition')=='pro' else '⚠️  LocalStack running (check Pro license)')"

.PHONY: localstack-down
localstack-down: ## Stop LocalStack
	@echo "🛑 Stopping LocalStack..."
	docker-compose -f docker-compose.localstack.yml down
	@echo "✅ LocalStack stopped"

.PHONY: localstack-status
localstack-status: ## Check LocalStack status
	@echo "📊 LocalStack Status:"
	@curl -s http://localhost:4566/_localstack/health | python3 -m json.tool || echo "LocalStack not running"

.PHONY: localstack-deploy
localstack-deploy: ## Deploy infrastructure to LocalStack
	@echo "🚀 Deploying to LocalStack..."
	cd terraform && terraform init && terraform apply -var-file="localstack.tfvars" -auto-approve
	@echo "✅ Deployed to LocalStack!"

.PHONY: localstack-destroy
localstack-destroy: ## Destroy LocalStack infrastructure
	@echo "💥 Destroying LocalStack infrastructure..."
	cd terraform && terraform destroy -var-file="localstack.tfvars" -auto-approve

.PHONY: localstack-test
localstack-test: setup-results ## Run load test against LocalStack
	@echo "🧪 Running load test against LOCALSTACK environment..."
	@LOCALSTACK_ALB=$(cd terraform && terraform output -var-file="localstack.tfvars" -raw alb_dns_name 2>/dev/null || echo "localhost:4566"); \
	echo "   URL: http://$LOCALSTACK_ALB"; \
	echo "   Users: $(NUM_USERS)"; \
	echo "   Duration: $(TEST_DURATION)"; \
	mkdir -p $(LOCAL_RESULTS)/$(TIMESTAMP); \
	SETUP_USERS=50 \
	NUM_INITIAL_PRODUCTS=$(NUM_INITIAL_PRODUCTS) \
	TARGET_CHECKOUTS=$(TARGET_CHECKOUTS) \
	locust -f load-test/locustfile.py \
		--host http://$LOCALSTACK_ALB \
		--users $(NUM_USERS) \
		--spawn-rate $(SPAWN_RATE) \
		--run-time $(TEST_DURATION) \
		--headless \
		--html $(LOCAL_RESULTS)/$(TIMESTAMP)/report.html \
		--csv $(LOCAL_RESULTS)/$(TIMESTAMP)/results
	@echo "✅ LocalStack test complete!"

# ==============================================================================
# AWS DEPLOYMENT
# ==============================================================================

.PHONY: aws-deploy
aws-deploy: ## Deploy infrastructure to AWS
	@echo "🚀 Deploying to AWS..."
	cd terraform && terraform init && terraform apply

.PHONY: aws-destroy
aws-destroy: ## Destroy AWS infrastructure
	@echo "💥 Destroying AWS infrastructure..."
	cd terraform && terraform destroy

.PHONY: aws-output
aws-output: ## Show AWS deployment outputs (including ALB DNS)
	@echo "📋 AWS Deployment Outputs:"
	@cd terraform && terraform output

# ==============================================================================
# UTILITIES
# ==============================================================================

.PHONY: clean
clean: ## Clean up results and temporary files
	@echo "🧹 Cleaning up..."
	rm -rf $(RESULTS_DIR)
	docker-compose down -v --remove-orphans
	@echo "✅ Cleaned"

.PHONY: rebuild
rebuild: ## Rebuild all Docker images
	@echo "🔨 Rebuilding all images..."
	docker-compose build --no-cache
	@echo "✅ Rebuild complete"

.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration (override with VAR=value):"
	@echo "  AWS_ALB_DNS          $(AWS_ALB_DNS)"
	@echo "  NUM_USERS            $(NUM_USERS)"
	@echo "  SPAWN_RATE           $(SPAWN_RATE)"
	@echo "  TEST_DURATION        $(TEST_DURATION)"
	@echo "  NUM_INITIAL_PRODUCTS $(NUM_INITIAL_PRODUCTS)"
	@echo "  TARGET_CHECKOUTS     $(TARGET_CHECKOUTS)"

.DEFAULT_GOAL := help