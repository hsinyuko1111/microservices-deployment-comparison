package models

type Order struct {
	OrderID        int32      `json:"order_id"`
	ShoppingCartID int32      `json:"shopping_cart_id"`
	CustomerID     int32      `json:"customer_id"`
	Items          []CartItem `json:"items"`
}

type CartItem struct {
	ProductID int32 `json:"product_id"`
	Quantity  int32 `json:"quantity"`
}
