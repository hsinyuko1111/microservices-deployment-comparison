#!/usr/bin/env python3
"""
Locust Load Tester for AWS Environment

Matches the LocalStack test for fair comparison.
All requests go through the ALB.

Usage:
    cd load-test
    NUM_INITIAL_PRODUCTS=100 TARGET_CHECKOUTS=500 \
    locust -f locustfile_aws.py \
      --host http://microservices-alb-XXXXX.us-west-2.elb.amazonaws.com \
      --headless \
      --users 50 \
      --spawn-rate 5 \
      --run-time 2m \
      --html ../analysis/results/aws/report.html \
      --csv ../analysis/results/aws/results
"""

import os
import random
import string
import time
import threading
from locust import HttpUser, task, events, between

# ============================================================================
# CONFIGURATION (same as LocalStack version)
# ============================================================================

NUM_INITIAL_PRODUCTS = int(os.getenv("NUM_INITIAL_PRODUCTS", "100"))
TARGET_CHECKOUTS = int(os.getenv("TARGET_CHECKOUTS", "500"))
MIN_ITEMS_PER_CART = int(os.getenv("MIN_ITEMS_PER_CART", "1"))
MAX_ITEMS_PER_CART = int(os.getenv("MAX_ITEMS_PER_CART", "3"))

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
# USER CLASS
# ============================================================================

class AWSUser(HttpUser):
    """
    User for AWS testing - all requests through ALB.
    Matches LocalStack test behavior.
    """
    wait_time = between(0.1, 0.5)
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.customer_id = shared_state.get_next_customer_id()

    def on_start(self):
        """Create products at startup"""
        while shared_state.get_product_count() < NUM_INITIAL_PRODUCTS:
            if self._create_product():
                count = shared_state.get_product_count()
                if count % 20 == 0:
                    print(f"[AWS] Products: {count}/{NUM_INITIAL_PRODUCTS}")
                if count >= NUM_INITIAL_PRODUCTS:
                    shared_state.mark_setup_complete()
                    print(f"[AWS] Setup complete: {count} products")
                    break

    def _create_product(self) -> bool:
        """Create a product"""
        with self.client.post(
            "/product",
            json=generate_product_data(),
            catch_response=True,
            name="POST /product"
        ) as resp:
            if resp.status_code in [200, 201]:
                try:
                    product_id = resp.json().get("product_id")
                    if product_id:
                        shared_state.add_product(product_id)
                        resp.success()
                        return True
                except:
                    pass
            # 503 from bad service is expected (~25%)
            if resp.status_code == 503:
                resp.success()  # Count as success for metrics (expected behavior)
            else:
                resp.failure(f"Status {resp.status_code}")
        return False

    @task(10)
    def shopping_flow(self):
        """Complete shopping flow: create cart -> add items -> checkout"""
        if shared_state.get_checkout_count() >= TARGET_CHECKOUTS:
            return

        # Ensure we have products
        if not shared_state.is_setup_complete():
            self._create_product()
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

    @task(2)
    def create_product_task(self):
        """Occasionally create more products"""
        self._create_product()

    def _create_cart(self) -> int | None:
        """Create shopping cart"""
        with self.client.post(
            "/shopping-cart",
            json={"customer_id": self.customer_id},
            catch_response=True,
            name="POST /shopping-cart"
        ) as resp:
            if resp.status_code in [200, 201]:
                try:
                    cart_id = resp.json().get("shopping_cart_id")
                    if cart_id:
                        resp.success()
                        return cart_id
                except:
                    pass
                resp.failure("No cart_id in response")
            else:
                resp.failure(f"Status {resp.status_code}")
        return None

    def _add_item(self, cart_id: int) -> bool:
        """Add item to cart"""
        product_id = shared_state.get_random_product()
        if not product_id:
            return False

        with self.client.post(
            f"/shopping-carts/{cart_id}/addItem",
            json={"product_id": product_id, "quantity": random.randint(1, 3)},
            catch_response=True,
            name="POST /shopping-carts/{id}/addItem"
        ) as resp:
            if resp.status_code in [200, 201, 204]:
                resp.success()
                return True
            resp.failure(f"Status {resp.status_code}")
        return False

    def _checkout(self, cart_id: int) -> bool:
        """Checkout cart"""
        with self.client.post(
            f"/shopping-carts/{cart_id}/checkout",
            json={"credit_card_number": generate_credit_card()},
            catch_response=True,
            name="POST /shopping-carts/{id}/checkout"
        ) as resp:
            if resp.status_code == 200:
                try:
                    if resp.json().get("order_id"):
                        count = shared_state.increment_checkout()
                        if count % 50 == 0:
                            print(f"[AWS] Checkouts: {count}/{TARGET_CHECKOUTS}")
                        resp.success()
                        return True
                except:
                    pass
                resp.failure("No order_id")
            elif resp.status_code == 402:
                # Declined - expected ~10%
                shared_state.increment_declined()
                resp.success()
                return True
            else:
                resp.failure(f"Status {resp.status_code}")
        return False


# ============================================================================
# EVENT HANDLERS
# ============================================================================

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print(f"\n{'=' * 60}")
    print(f"  AWS LOAD TEST")
    print(f"{'=' * 60}")
    print(f"  Host:           {environment.host}")
    print(f"  Target:         {TARGET_CHECKOUTS} checkouts")
    print(f"  Products:       {NUM_INITIAL_PRODUCTS}")
    print(f"  Items per cart: {MIN_ITEMS_PER_CART}-{MAX_ITEMS_PER_CART}")
    print(f"{'=' * 60}\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    checkouts = shared_state.get_checkout_count()
    declined = shared_state.get_declined_count()
    total = checkouts + declined
    success_rate = (checkouts / total * 100) if total > 0 else 0

    print(f"\n{'=' * 60}")
    print(f"  AWS TEST COMPLETED")
    print(f"{'=' * 60}")
    print(f"  Checkouts:    {checkouts:,}")
    print(f"  Declined:     {declined:,}")
    print(f"  Success rate: {success_rate:.1f}%")
    print(f"  Products:     {shared_state.get_product_count():,}")
    print(f"{'=' * 60}\n")