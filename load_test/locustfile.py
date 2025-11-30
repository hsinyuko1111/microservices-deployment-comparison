"""
Locust Load Tester for CS6650 Homework 10 - Option 2: Microservice Extravaganza

GOAL: Send 200k checkout messages as quickly as possible to stress test the system.

DISTRIBUTED MODE: For high user counts (200+), run in distributed mode to avoid
client CPU bottleneck.

IMPORTANT: TARGET_CHECKOUTS is per-worker. For N workers, set:
    TARGET_CHECKOUTS=$((200000 / N))

Examples:
    4 workers → TARGET_CHECKOUTS=50000
    6 workers → TARGET_CHECKOUTS=33333
    8 workers → TARGET_CHECKOUTS=25000

Usage:
    # Master (needs SETUP_USERS for user distribution)
    SETUP_USERS=100 locust -f locustfile.py --master --host https://your-lb.com

    # Workers (need TARGET_CHECKOUTS and NUM_INITIAL_PRODUCTS)
    TARGET_CHECKOUTS=25000 NUM_INITIAL_PRODUCTS=1000 \\
        locust -f locustfile.py --worker --master-host=localhost
"""

import os
import random
import string
import time
import threading
from locust import HttpUser, task, events
from locust.runners import MasterRunner, WorkerRunner

# ============================================================================
# CONFIGURATION
# ============================================================================

NUM_INITIAL_PRODUCTS = int(os.getenv("NUM_INITIAL_PRODUCTS", "1000"))
TARGET_CHECKOUTS = int(os.getenv("TARGET_CHECKOUTS", "200000"))
MIN_ITEMS_PER_CART = int(os.getenv("MIN_ITEMS_PER_CART", "2"))
MAX_ITEMS_PER_CART = int(os.getenv("MAX_ITEMS_PER_CART", "5"))
SETUP_USERS = int(os.getenv("SETUP_USERS", "100"))

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
    "manufacturer": random.choice(
      [
        "Acme Corp",
        "TechGiant Inc",
        "Global Mfg",
        "Premium Products",
        "Budget Brands",
        "Innovation Ltd",
      ]
    ),
    "category_id": random.randint(1, 50),
    "weight": random.randint(10, 5000),
    "some_other_id": random.randint(1, 10000),
  }


# ============================================================================
# USER CLASSES
# ============================================================================


class ProductSetupUser(HttpUser):
  """Creates products then stops. Uses fixed_count for even distribution."""

  fixed_count = SETUP_USERS

  @task
  def create_product(self):
    if shared_state.get_product_count() >= NUM_INITIAL_PRODUCTS:
      self.stop()
      return

    with self.client.post(
      "/product",
      json=generate_product_data(),
      catch_response=True,
      name="POST /product",
    ) as resp:
      if resp.status_code == 201:
        try:
          product_id = resp.json().get("product_id")
          if product_id:
            shared_state.add_product(product_id)
            total = shared_state.get_product_count()

            if total % 100 == 0:
              print(f"[Worker] Products: {total}/{NUM_INITIAL_PRODUCTS}")

            if total >= NUM_INITIAL_PRODUCTS:
              shared_state.mark_setup_complete()
              print(f"[Worker] SETUP COMPLETE: {total} products\n")

            resp.success()
          else:
            resp.failure("No product_id")
        except Exception as e:
          resp.failure(f"Parse error: {e}")
      else:
        resp.failure(f"Status {resp.status_code}")


class ShopperUser(HttpUser):
  """Executes shopping cycles continuously. No wait time for maximum throughput."""

  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)
    self.customer_id = shared_state.get_next_customer_id()

  def on_start(self):
    while not shared_state.is_setup_complete():
      if shared_state.get_product_count() > 0:
        shared_state.mark_setup_complete()
        break
      time.sleep(0.5)

  @task
  def complete_shopping_cycle(self):
    if shared_state.get_checkout_count() >= TARGET_CHECKOUTS:
      return

    cart_id = self._create_cart()
    if not cart_id:
      return

    num_items = random.randint(MIN_ITEMS_PER_CART, MAX_ITEMS_PER_CART)
    items_added = sum(1 for _ in range(num_items) if self._add_item_to_cart(cart_id))

    if items_added > 0:
      self._checkout_cart(cart_id)

  def _create_cart(self) -> int:
    with self.client.post(
      "/shopping-cart",
      json={"customer_id": self.customer_id},
      catch_response=True,
      name="POST /shopping-cart",
    ) as resp:
      if resp.status_code == 201:
        try:
          cart_id = resp.json().get("shopping_cart_id")
          if cart_id:
            resp.success()
            return cart_id
          resp.failure("No shopping_cart_id")
        except Exception as e:
          resp.failure(f"Parse error: {e}")
      else:
        resp.failure(f"Status {resp.status_code}")
      return None

  def _add_item_to_cart(self, cart_id: int) -> bool:
    product_id = shared_state.get_random_product()
    if not product_id:
      return False

    with self.client.post(
      f"/shopping-carts/{cart_id}/addItem",
      json={"product_id": product_id, "quantity": random.randint(1, 3)},
      catch_response=True,
      name="POST /shopping-carts/{id}/addItem",
    ) as resp:
      if resp.status_code == 204:
        resp.success()
        return True
      resp.failure(f"Status {resp.status_code}")
      return False

  def _checkout_cart(self, cart_id: int):
    with self.client.post(
      f"/shopping-carts/{cart_id}/checkout",
      json={"credit_card_number": generate_credit_card()},
      catch_response=True,
      name="POST /shopping-carts/{id}/checkout",
    ) as resp:
      if resp.status_code == 200:
        try:
          if resp.json().get("order_id"):
            checkout_count = shared_state.increment_checkout()

            if checkout_count % 500 == 0:
              declined = shared_state.get_declined_count()
              print(
                f"[Worker] Progress: {checkout_count} checkouts ({declined} declined)"
              )

            if checkout_count >= TARGET_CHECKOUTS:
              print(f"[Worker] TARGET REACHED: {checkout_count} checkouts!\n")

            resp.success()
          else:
            resp.failure("No order_id")
        except Exception as e:
          resp.failure(f"Parse error: {e}")
      elif resp.status_code == 402:
        shared_state.increment_declined()
        resp.success()
      else:
        resp.failure(f"Status {resp.status_code}")


# ============================================================================
# EVENT HANDLERS
# ============================================================================


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
  mode = (
    "MASTER"
    if isinstance(environment.runner, MasterRunner)
    else "WORKER"
    if isinstance(environment.runner, WorkerRunner)
    else "SINGLE"
  )

  print(f"\n{'=' * 70}")
  print(f"  E-COMMERCE LOAD TEST [{mode}]")
  print(f"{'=' * 70}")
  print(f"  Target (per worker):  {TARGET_CHECKOUTS:,} checkouts")
  print(f"  Setup users:          {SETUP_USERS} (distributed evenly)")
  print(f"  Products per worker:  {NUM_INITIAL_PRODUCTS:,}")
  print(f"  Items per cart:       {MIN_ITEMS_PER_CART}-{MAX_ITEMS_PER_CART}")
  print(f"{'=' * 70}\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
  checkouts = shared_state.get_checkout_count()
  declined = shared_state.get_declined_count()
  total = checkouts + declined
  success_rate = (checkouts / total * 100) if total > 0 else 0

  mode = (
    "MASTER"
    if isinstance(environment.runner, MasterRunner)
    else "WORKER"
    if isinstance(environment.runner, WorkerRunner)
    else "SINGLE"
  )

  print(f"\n{'=' * 70}")
  print(f"  TEST COMPLETED [{mode}]")
  print(f"{'=' * 70}")
  print(f"  Checkouts:    {checkouts:,}")
  print(f"  Declined:     {declined:,}")
  print(f"  Success rate: {success_rate:.1f}%")
  print(f"  Products:     {shared_state.get_product_count():,}")
  print(f"{'=' * 70}\n")


# ============================================================================
# USAGE INSTRUCTIONS
# ============================================================================

"""
================================================================================
DISTRIBUTED MODE SETUP
================================================================================

CRITICAL: Set TARGET_CHECKOUTS per worker based on number of workers!
    For N workers: TARGET_CHECKOUTS=$((200000 / N))

Variable Distribution:
  - SETUP_USERS: Set on MASTER (controls user distribution via fixed_count)
  - TARGET_CHECKOUTS: Set on WORKERS (per-worker checkout limit)
  - NUM_INITIAL_PRODUCTS: Set on WORKERS (per-worker product creation)

Step 1: Start Master (Terminal 1)
----------------------------------
SETUP_USERS=100 locust -f locustfile.py --master --host https://your-lb.com

Web UI: http://localhost:8089

Step 2: Verify Workers Connected
---------------------------------
In Master UI, click "Workers" tab → should show "N workers connected"

Step 3: Start Workers (Terminals 2-N) - BEFORE Starting Test!
--------------------------------------------------------------
For 8 workers with 200k total target:

TARGET_CHECKOUTS=25000 NUM_INITIAL_PRODUCTS=1000 \\
    locust -f locustfile.py --worker --master-host=localhost

Repeat this command in 8 separate terminals.

Step 4: Start Test in Master UI
--------------------------------
Total users: 600 (example)
Spawn rate: 10/sec
Click "Start"

With 8 workers and 600 users:
- 100 ProductSetupUsers → ~12 per worker (distributed by fixed_count)
- 500 ShopperUsers → ~62 per worker

All workers should show product creation logs!

HEADLESS MODE
-------------
Master (Terminal 1):
SETUP_USERS=100 locust -f locustfile.py --master --headless \\
    --users 600 --spawn-rate 10 --run-time 30m \\
    --host https://your-lb.com --html report.html --csv results

Workers (Terminals 2-N):
TARGET_CHECKOUTS=25000 NUM_INITIAL_PRODUCTS=1000 \\
    locust -f locustfile.py --worker --master-host=localhost

SINGLE MACHINE MODE (< 200 users)
----------------------------------
SETUP_USERS=100 NUM_INITIAL_PRODUCTS=1000 TARGET_CHECKOUTS=200000 \\
    locust -f locustfile.py --headless --users 150 --spawn-rate 10 \\
    --run-time 30m --host https://your-lb.com \\
    --html report.html --csv results

FINDING OPTIMAL CONFIGURATION
------------------------------
Goal: Maximize RPS while keeping RabbitMQ queue < 1000

Test progression (4-8 workers):
  200 users → Monitor metrics
  400 users → Monitor metrics
  600 users → Monitor metrics
  800 users → Monitor metrics

Monitor:
- Locust Master UI: Total RPS, P50/P95/P99, failure rate
- RabbitMQ console: Queue depth, publish/consumer rates
- Worker terminals: All should show product creation and progress
- Client: CPU per worker should stay < 80%

Stop increasing users when:
- RPS plateaus (diminishing returns)
- P95 response time > 5 seconds
- RabbitMQ queue depth > 1000
- Failure rate > 5%

================================================================================
"""
