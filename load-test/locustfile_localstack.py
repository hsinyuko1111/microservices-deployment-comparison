"""
Locust Load Tester for LocalStack Environment

This version handles LocalStack's split endpoints:
- Product Service: localhost:4566 (via ALB with Host header)
- Shopping Cart: localhost:8081 (direct)

Usage:
    cd load-test
    locust -f locustfile_localstack.py --host http://localhost --headless \
        --users 50 --spawn-rate 5 --run-time 2m \
        --html ../analysis/results/local/report.html \
        --csv ../analysis/results/local/results
"""

import os
import random
import string
import time
import threading
import requests
from locust import HttpUser, task, events, between
from locust.runners import MasterRunner, WorkerRunner

# ============================================================================
# CONFIGURATION
# ============================================================================

NUM_INITIAL_PRODUCTS = int(os.getenv("NUM_INITIAL_PRODUCTS", "100"))
TARGET_CHECKOUTS = int(os.getenv("TARGET_CHECKOUTS", "1000"))
MIN_ITEMS_PER_CART = int(os.getenv("MIN_ITEMS_PER_CART", "1"))
MAX_ITEMS_PER_CART = int(os.getenv("MAX_ITEMS_PER_CART", "3"))
SETUP_USERS = int(os.getenv("SETUP_USERS", "10"))

# LocalStack endpoints
PRODUCT_HOST = os.getenv("PRODUCT_HOST", "http://localhost:4566")
CART_HOST = os.getenv("CART_HOST", "http://localhost:8081")
ALB_HOST_HEADER = "localstack-alb.elb.localhost.localstack.cloud"

# ============================================================================
# SHARED STATE
# ============================================================================

class SharedState:
    def __init__(self):
        self._lock = threading.Lock()
        self._product_ids = []
        self._setup_complete = False
        self._checkout_count = 0
        self._declined_count = 0
        self._customer_id_counter = 1

    def add_product(self, product_id: int):
        with self._lock:
            self._product_ids.append(product_id)

    def get_random_product(self):
        with self._lock:
            return random.choice(self._product_ids) if self._product_ids else None

    def mark_setup_complete(self):
        with self._lock:
            self._setup_complete = True

    def is_setup_complete(self) -> bool:
        with self._lock:
            return self._setup_complete

    def increment_checkout(self) -> int:
        with self._lock:
            self._checkout_count += 1
            return self._checkout_count

    def increment_declined(self) -> int:
        with self._lock:
            self._declined_count += 1
            return self._declined_count

    def get_checkout_count(self) -> int:
        with self._lock:
            return self._checkout_count

    def get_declined_count(self) -> int:
        with self._lock:
            return self._declined_count

    def get_next_customer_id(self) -> int:
        with self._lock:
            customer_id = self._customer_id_counter
            self._customer_id_counter += 1
            return customer_id

    def get_product_count(self) -> int:
        with self._lock:
            return len(self._product_ids)


shared_state = SharedState()

# ============================================================================
# DATA GENERATORS
# ============================================================================

def generate_credit_card() -> str:
    parts = ["".join([str(random.randint(0, 9)) for _ in range(4)]) for _ in range(4)]
    return "-".join(parts)

def generate_sku() -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=10))

def generate_product_data() -> dict:
    return {
        "sku": generate_sku(),
        "manufacturer": random.choice(["Acme Corp", "TechGiant Inc", "Global Mfg"]),
        "category_id": random.randint(1, 50),
        "weight": random.randint(10, 5000),
        "some_other_id": random.randint(1, 10000),
    }

# ============================================================================
# USER CLASS - Combined for LocalStack
# ============================================================================

class LocalStackUser(HttpUser):
    """
    User that handles LocalStack's split endpoints.
    Uses requests library directly for different hosts.
    """
    wait_time = between(0.1, 0.5)
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.customer_id = shared_state.get_next_customer_id()
        self.products_created = 0

    def on_start(self):
        # Create some products first
        while shared_state.get_product_count() < NUM_INITIAL_PRODUCTS:
            self._create_product()
            if shared_state.get_product_count() >= NUM_INITIAL_PRODUCTS:
                shared_state.mark_setup_complete()
                break

    def _create_product(self):
        """Create product via LocalStack ALB"""
        start_time = time.time()
        try:
            resp = requests.post(
                f"{PRODUCT_HOST}/product",
                json=generate_product_data(),
                headers={
                    "Host": ALB_HOST_HEADER,
                    "Content-Type": "application/json"
                },
                timeout=10
            )
            elapsed = (time.time() - start_time) * 1000
            
            if resp.status_code in [200, 201]:
                product_id = resp.json().get("product_id")
                if product_id:
                    shared_state.add_product(product_id)
                    self.products_created += 1
                    
                    # Report to Locust
                    events.request.fire(
                        request_type="POST",
                        name="POST /product",
                        response_time=elapsed,
                        response_length=len(resp.content),
                        exception=None,
                        context={}
                    )
                    return True
            
            # Report failure
            events.request.fire(
                request_type="POST",
                name="POST /product",
                response_time=elapsed,
                response_length=0,
                exception=Exception(f"Status {resp.status_code}"),
                context={}
            )
        except Exception as e:
            elapsed = (time.time() - start_time) * 1000
            events.request.fire(
                request_type="POST",
                name="POST /product",
                response_time=elapsed,
                response_length=0,
                exception=e,
                context={}
            )
        return False

    @task(10)
    def shopping_flow(self):
        """Complete shopping flow: create cart -> add items -> checkout"""
        if shared_state.get_checkout_count() >= TARGET_CHECKOUTS:
            return

        # 1. Create cart
        cart_id = self._create_cart()
        if not cart_id:
            return

        # 2. Add items
        num_items = random.randint(MIN_ITEMS_PER_CART, MAX_ITEMS_PER_CART)
        items_added = 0
        for _ in range(num_items):
            if self._add_item(cart_id):
                items_added += 1

        # 3. Checkout
        if items_added > 0:
            self._checkout(cart_id)

    def _create_cart(self):
        """Create shopping cart"""
        start_time = time.time()
        try:
            resp = requests.post(
                f"{CART_HOST}/shopping-cart",
                json={"customer_id": self.customer_id},
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            elapsed = (time.time() - start_time) * 1000
            
            if resp.status_code in [200, 201]:
                cart_id = resp.json().get("shopping_cart_id")
                events.request.fire(
                    request_type="POST",
                    name="POST /shopping-cart",
                    response_time=elapsed,
                    response_length=len(resp.content),
                    exception=None,
                    context={}
                )
                return cart_id
            
            events.request.fire(
                request_type="POST",
                name="POST /shopping-cart",
                response_time=elapsed,
                response_length=0,
                exception=Exception(f"Status {resp.status_code}"),
                context={}
            )
        except Exception as e:
            elapsed = (time.time() - start_time) * 1000
            events.request.fire(
                request_type="POST",
                name="POST /shopping-cart",
                response_time=elapsed,
                response_length=0,
                exception=e,
                context={}
            )
        return None

    def _add_item(self, cart_id):
        """Add item to cart"""
        product_id = shared_state.get_random_product()
        if not product_id:
            return False

        start_time = time.time()
        try:
            resp = requests.post(
                f"{CART_HOST}/shopping-carts/{cart_id}/addItem",
                json={"product_id": product_id, "quantity": random.randint(1, 3)},
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            elapsed = (time.time() - start_time) * 1000
            
            success = resp.status_code in [200, 201, 204]
            events.request.fire(
                request_type="POST",
                name="POST /shopping-carts/{id}/addItem",
                response_time=elapsed,
                response_length=len(resp.content) if resp.content else 0,
                exception=None if success else Exception(f"Status {resp.status_code}"),
                context={}
            )
            return success
        except Exception as e:
            elapsed = (time.time() - start_time) * 1000
            events.request.fire(
                request_type="POST",
                name="POST /shopping-carts/{id}/addItem",
                response_time=elapsed,
                response_length=0,
                exception=e,
                context={}
            )
        return False

    def _checkout(self, cart_id):
        """Checkout cart"""
        start_time = time.time()
        try:
            resp = requests.post(
                f"{CART_HOST}/shopping-carts/{cart_id}/checkout",
                json={"credit_card_number": generate_credit_card()},
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            elapsed = (time.time() - start_time) * 1000
            
            if resp.status_code == 200:
                shared_state.increment_checkout()
                events.request.fire(
                    request_type="POST",
                    name="POST /shopping-carts/{id}/checkout",
                    response_time=elapsed,
                    response_length=len(resp.content),
                    exception=None,
                    context={}
                )
                
                count = shared_state.get_checkout_count()
                if count % 100 == 0:
                    print(f"[LocalStack] Checkouts: {count}/{TARGET_CHECKOUTS}")
                return True
            elif resp.status_code == 402:
                shared_state.increment_declined()
                events.request.fire(
                    request_type="POST",
                    name="POST /shopping-carts/{id}/checkout",
                    response_time=elapsed,
                    response_length=len(resp.content),
                    exception=None,
                    context={}
                )
                return True
            else:
                events.request.fire(
                    request_type="POST",
                    name="POST /shopping-carts/{id}/checkout",
                    response_time=elapsed,
                    response_length=0,
                    exception=Exception(f"Status {resp.status_code}"),
                    context={}
                )
        except Exception as e:
            elapsed = (time.time() - start_time) * 1000
            events.request.fire(
                request_type="POST",
                name="POST /shopping-carts/{id}/checkout",
                response_time=elapsed,
                response_length=0,
                exception=e,
                context={}
            )
        return False


# ============================================================================
# EVENT HANDLERS
# ============================================================================

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print(f"\n{'=' * 60}")
    print(f"  LOCALSTACK LOAD TEST")
    print(f"{'=' * 60}")
    print(f"  Product Host:   {PRODUCT_HOST}")
    print(f"  Cart Host:      {CART_HOST}")
    print(f"  Target:         {TARGET_CHECKOUTS} checkouts")
    print(f"  Products:       {NUM_INITIAL_PRODUCTS}")
    print(f"{'=' * 60}\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    checkouts = shared_state.get_checkout_count()
    declined = shared_state.get_declined_count()
    total = checkouts + declined
    success_rate = (checkouts / total * 100) if total > 0 else 0

    print(f"\n{'=' * 60}")
    print(f"  LOCALSTACK TEST COMPLETED")
    print(f"{'=' * 60}")
    print(f"  Checkouts:    {checkouts:,}")
    print(f"  Declined:     {declined:,}")
    print(f"  Success rate: {success_rate:.1f}%")
    print(f"  Products:     {shared_state.get_product_count():,}")
    print(f"{'=' * 60}\n")