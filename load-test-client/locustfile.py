from locust import HttpUser, task

class ShoppingCartUser(HttpUser):
    def on_start(self):
        # Locust's HttpUser automatically handles cookies!
        # Create cart once
        response = self.client.post("/shopping-cart", 
                                     json={"customer_id": 1})
        self.cart_id = response.json()["shopping_cart_id"]

    
    @task(4)
    def add_item_to_cart(self):
        # This will use the same cookie → goes to same instance
        self.client.post(f"/shopping-carts/{self.cart_id}/addItem",
                        json={"product_id": 100, "quantity": 2})
    

    @task(1)   # Weight 1 → executed ~20% of the time (5× less)
    def checkout(self):
        self.client.post(
            f"/shopping-carts/{self.cart_id}/checkout",
            json={"credit_card_number": "1234-5678-9012-3456"}
        )