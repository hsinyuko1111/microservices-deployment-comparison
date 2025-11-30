package models

// Order represents an order to be sent to the warehouse
type Order struct {
	OrderID        int32      `json:"order_id"`
	ShoppingCartID int32      `json:"shopping_cart_id"`
	CustomerID     int32      `json:"customer_id"`
	Items          []CartItem `json:"items"`
}
