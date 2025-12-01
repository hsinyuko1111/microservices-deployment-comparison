"""
Locust Load Tester for LocalStack vs AWS Comparison

This file supports both environments:
- LocalStack: Uses split endpoints (product via ALB, cart via direct)
- AWS: Uses single ALB endpoint

Usage:
  # LocalStack
  locust -f locustfile_comparison.py --host http://localhost --env localstack

  # AWS
  locust -f locustfile_comparison.py --host http://your-alb-dns.amazonaws.com --env aws
  
  # Headless mode (for automated testing)
  locust -f locustfile_comparison.py \
    --host http://localhost \
    --env localstack \
    --headless \
    --users 50 \
    --spawn-rate 5 \
    --run-time 2m \
    --html results.html \
    --csv results
"""

import os
import random
import string
import time
import threading
from locust import HttpUser, task, events, between
from locust.runners import MasterRunner, WorkerRunner

# ============================================================================
# CONFIGURATION
# ============================================================================

# Environment: "localstack" or "aws"
ENVIRONMENT = os.getenv("ENV", "aws")

# LocalStack specific endpoints
LOCALSTACK_PRODUCT_HOST = os.getenv("LOCALSTACK_PRODUCT_HOST", "http://localhost:4566")
LOCALSTACK_CART_HOST = os.getenv("LOCALSTACK_CART_HOST", "http://localhost:8081")
LOCALSTACK_ALB_HEADER = "localstack-alb.elb.localhost.localstack.cloud"

# Test configuration
NUM_PRODUCTS = int(os.getenv("NUM_PRODUCTS", "100"))
TARGET_CHECKOUTS = int(os.getenv("TARGET_CHECKOUTS", "500"))
SETUP_USERS = int(os.getenv("SETUP_USERS", "10"))

# ============================================================================
# SHARED STATE
# ============================================================================

class SharedState:
    def __init__(self):
        self._lock = threading.Lock()
        self._product_ids = []
        self._cart_ids = []
        self._setup_complete = False
        self._checkout_count = 0
        self._metrics = {
            "product_create": [],
            "cart_create": [],
            "cart_add_item": [],
            "checkout": [],
        }

    def add_product(self, product_id):
        with self._lock:
            self._product_ids.append(product_id)

    def get_random_product(self):
        with self._lock:
            return random.choice(self._product_ids) if self._product_ids else None

    def get_product_count(self):
        with self._lock:
            return len(self._product_ids)

    def mark_setup_complete(self):
        with self._lock:
            self._setup_complete = True

    def is_setup_complete(self):
        with self._lock:
            return self._setup_complete

    def increment_checkout(self):
        with self._lock:
            self._checkout_count += 1
            return self._checkout_count

    def get_checkout_count(self):
        with self._lock:
            return self._checkout_count

    def add_metric(self, metric_type, value):
        with self._lock:
            self._metrics[metric_type].append(value)

    def get_metrics(self):
        with self._lock:
            return self._metrics.copy()


shared_state = SharedState()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def generate_sku():
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=10))

def generate_credit_card():
    parts = ["".join([str(random.randint(0, 9)) for _ in range(4)]) for _ in range(4)]
    return "-".join(parts)

def generate_product_data():
    return {
        "sku": generate_sku(),
        "manufacturer": random.choice(["Acme", "TechCorp", "GlobalMfg"]),
        "category_id": random.randint(1, 50),
        "weight": random.randint(10, 5000),
        "some_other_id": random.randint(1, 10000),
    }

# ============================================================================
# LOCALSTACK USER (Split endpoints)
# ============================================================================

class LocalStackUser(HttpUser):
    """User for LocalStack environment with split endpoints."""
    
    wait_time = between(0.1, 0.5)
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.customer_id = random.randint(1, 100000)
        self.product_host = LOCALSTACK_PRODUCT_HOST
        self.cart_host = LOCALSTACK_CART_HOST

    def on_start(self):
        # Wait for products to be created
        while not shared_state.is_setup_complete():
            if shared_state.get_product_count() >= 10:
                shared_state.mark_setup_complete()
                break
            time.sleep(0.5)

    @task(3)
    def create_product(self):
        """Create a product via LocalStack ALB."""
        if shared_state.get_product_count() >= NUM_PRODUCTS:
            return
            
        import requests
        start = time.time()
        try:
            resp = requests.post(
                f"{self.product_host}/product",
                json=generate_product_data(),
                headers={
                    "Host": LOCALSTACK_ALB_HEADER,
                    "Content-Type": "application/json"
                },
                timeout=10
            )
            latency = time.time() - start
            
            if resp.status_code in [200, 201]:
                data = resp.json()
                if "product_id" in data:
                    shared_state.add_product(data["product_id"])
                    shared_state.add_metric("product_create", latency)
                    # Log to Locust
                    events.request.fire(
                        request_type="POST",
                        name="/product",
                        response_time=latency * 1000,
                        response_length=len(resp.content),
                        exception=None,
                        context={}
                    )
            else:
                events.request.fire(
                    request_type="POST",
                    name="/product",
                    response_time=latency * 1000,
                    response_length=0,
                    exception=Exception(f"Status {resp.status_code}"),
                    context={}
                )
        except Exception as e:
            events.request.fire(
                request_type="POST",
                name="/product",
                response_time=(time.time() - start) * 1000,
                response_length=0,
                exception=e,
                context={}
            )

    @task(5)
    def shopping_flow(self):
        """Complete a shopping flow: create cart, add item, checkout."""
        if shared_state.get_checkout_count() >= TARGET_CHECKOUTS:
            return
            
        product_id = shared_state.get_random_product()
        if not product_id:
            return

        import requests
        
        # Create cart
        start = time.time()
        try:
            resp = requests.post(
                f"{self.cart_host}/shopping-cart",
                json={"customer_id": self.customer_id},
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            latency = time.time() - start
            
            if resp.status_code in [200, 201]:
                cart_id = resp.json().get("shopping_cart_id")
                shared_state.add_metric("cart_create", latency)
                events.request.fire(
                    request_type="POST",
                    name="/shopping-cart",
                    response_time=latency * 1000,
                    response_length=len(resp.content),
                    exception=None,
                    context={}
                )
                
                if cart_id:
                    # Add item
                    start = time.time()
                    resp = requests.post(
                        f"{self.cart_host}/shopping-carts/{cart_id}/addItem",
                        json={"product_id": product_id, "quantity": 1},
                        headers={"Content-Type": "application/json"},
                        timeout=10
                    )
                    latency = time.time() - start
                    shared_state.add_metric("cart_add_item", latency)
                    events.request.fire(
                        request_type="POST",
                        name="/shopping-carts/{id}/addItem",
                        response_time=latency * 1000,
                        response_length=len(resp.content) if resp.content else 0,
                        exception=None if resp.status_code in [200, 204] else Exception(f"Status {resp.status_code}"),
                        context={}
                    )
                    
                    # Checkout
                    start = time.time()
                    resp = requests.post(
                        f"{self.cart_host}/shopping-carts/{cart_id}/checkout",
                        json={"credit_card_number": generate_credit_card()},
                        headers={"Content-Type": "application/json"},
                        timeout=10
                    )
                    latency = time.time() - start
                    
                    if resp.status_code in [200, 402]:  # 402 = declined (still valid)
                        shared_state.add_metric("checkout", latency)
                        shared_state.increment_checkout()
                        events.request.fire(
                            request_type="POST",
                            name="/shopping-carts/{id}/checkout",
                            response_time=latency * 1000,
                            response_length=len(resp.content),
                            exception=None,
                            context={}
                        )
                    else:
                        events.request.fire(
                            request_type="POST",
                            name="/shopping-carts/{id}/checkout",
                            response_time=latency * 1000,
                            response_length=0,
                            exception=Exception(f"Status {resp.status_code}"),
                            context={}
                        )
        except Exception as e:
            events.request.fire(
                request_type="POST",
                name="/shopping-cart",
                response_time=(time.time() - start) * 1000,
                response_length=0,
                exception=e,
                context={}
            )


# ============================================================================
# AWS USER (Single ALB endpoint)
# ============================================================================

class AWSUser(HttpUser):
    """User for AWS environment with single ALB endpoint."""
    
    wait_time = between(0.1, 0.5)
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.customer_id = random.randint(1, 100000)

    def on_start(self):
        while not shared_state.is_setup_complete():
            if shared_state.get_product_count() >= 10:
                shared_state.mark_setup_complete()
                break
            time.sleep(0.5)

    @task(3)
    def create_product(self):
        """Create a product."""
        if shared_state.get_product_count() >= NUM_PRODUCTS:
            return
            
        start = time.time()
        with self.client.post(
            "/product",
            json=generate_product_data(),
            catch_response=True
        ) as resp:
            latency = time.time() - start
            if resp.status_code in [200, 201]:
                try:
                    product_id = resp.json().get("product_id")
                    if product_id:
                        shared_state.add_product(product_id)
                        shared_state.add_metric("product_create", latency)
                        resp.success()
                    else:
                        resp.failure("No product_id")
                except:
                    resp.failure("Parse error")
            else:
                resp.failure(f"Status {resp.status_code}")

    @task(5)
    def shopping_flow(self):
        """Complete a shopping flow."""
        if shared_state.get_checkout_count() >= TARGET_CHECKOUTS:
            return
            
        product_id = shared_state.get_random_product()
        if not product_id:
            return

        # Create cart
        start = time.time()
        with self.client.post(
            "/shopping-cart",
            json={"customer_id": self.customer_id},
            catch_response=True
        ) as resp:
            latency = time.time() - start
            if resp.status_code in [200, 201]:
                try:
                    cart_id = resp.json().get("shopping_cart_id")
                    shared_state.add_metric("cart_create", latency)
                    resp.success()
                except:
                    resp.failure("Parse error")
                    return
            else:
                resp.failure(f"Status {resp.status_code}")
                return

        if not cart_id:
            return

        # Add item
        start = time.time()
        with self.client.post(
            f"/shopping-carts/{cart_id}/addItem",
            json={"product_id": product_id, "quantity": 1},
            catch_response=True
        ) as resp:
            latency = time.time() - start
            shared_state.add_metric("cart_add_item", latency)
            if resp.status_code in [200, 204]:
                resp.success()
            else:
                resp.failure(f"Status {resp.status_code}")
                return

        # Checkout
        start = time.time()
        with self.client.post(
            f"/shopping-carts/{cart_id}/checkout",
            json={"credit_card_number": generate_credit_card()},
            catch_response=True
        ) as resp:
            latency = time.time() - start
            if resp.status_code in [200, 402]:
                shared_state.add_metric("checkout", latency)
                shared_state.increment_checkout()
                resp.success()
            else:
                resp.failure(f"Status {resp.status_code}")


# ============================================================================
# DYNAMIC USER CLASS SELECTION
# ============================================================================

# Select user class based on environment
if ENVIRONMENT.lower() == "localstack":
    class User(LocalStackUser):
        pass
else:
    class User(AWSUser):
        pass


# ============================================================================
# EVENT HANDLERS
# ============================================================================

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print(f"\n{'=' * 60}")
    print(f"  LOAD TEST - Environment: {ENVIRONMENT.upper()}")
    print(f"{'=' * 60}")
    print(f"  Target Products: {NUM_PRODUCTS}")
    print(f"  Target Checkouts: {TARGET_CHECKOUTS}")
    print(f"{'=' * 60}\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    metrics = shared_state.get_metrics()
    
    print(f"\n{'=' * 60}")
    print(f"  TEST COMPLETED - {ENVIRONMENT.upper()}")
    print(f"{'=' * 60}")
    print(f"  Products created: {shared_state.get_product_count()}")
    print(f"  Checkouts completed: {shared_state.get_checkout_count()}")
    print(f"{'=' * 60}")
    
    # Print latency summary
    for metric_name, values in metrics.items():
        if values:
            avg = sum(values) / len(values) * 1000  # Convert to ms
            sorted_vals = sorted(values)
            p50 = sorted_vals[len(values) // 2] * 1000
            p95 = sorted_vals[int(len(values) * 0.95)] * 1000 if len(values) > 20 else avg
            print(f"  {metric_name}: avg={avg:.1f}ms, p50={p50:.1f}ms, p95={p95:.1f}ms")
    
    print(f"{'=' * 60}\n")