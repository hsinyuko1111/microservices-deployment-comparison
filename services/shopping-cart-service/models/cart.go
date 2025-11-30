package models

type ShoppingCart struct {
	ShoppingCartID int32      `json:"shopping_cart_id"`
	CustomerID     int32      `json:"customer_id"`
	Items          []CartItem `json:"items"`
}

type CartItem struct {
	ProductID int32 `json:"product_id"`
	Quantity  int32 `json:"quantity"`
}

type CreateCartRequest struct {
	CustomerID int32 `json:"customer_id" binding:"required,min=1"`
}

type CreateCartResponse struct {
	ShoppingCartID int32 `json:"shopping_cart_id"`
}

type AddItemRequest struct {
	ProductID int32 `json:"product_id" binding:"required,min=1"`
	Quantity  int32 `json:"quantity" binding:"required,min=1"`
}

type CheckoutRequest struct {
	CreditCardNumber string `json:"credit_card_number" binding:"required"`
}

type CheckoutResponse struct {
	OrderID int32 `json:"order_id"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
	Details string `json:"details,omitempty"`
}
