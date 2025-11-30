package handlers

import (
	"log"
	"net/http"
	"strconv"
	"sync"

	"shopping-cart-service/clients"
	"shopping-cart-service/models"
	"shopping-cart-service/rabbitmq"

	"github.com/gin-gonic/gin"
)

type CheckoutHandler struct {
	cartHandler *CartHandler
	ccaClient   *clients.CCAClient
	mqPublisher *rabbitmq.Publisher
	mu          sync.Mutex
	nextOrderID int32
}

func NewCheckoutHandler(cartHandler *CartHandler, ccaClient *clients.CCAClient, mqPublisher *rabbitmq.Publisher) *CheckoutHandler {
	return &CheckoutHandler{
		cartHandler: cartHandler,
		ccaClient:   ccaClient,
		mqPublisher: mqPublisher,
		nextOrderID: 1,
	}
}

// Checkout handles POST /shopping-carts/{shoppingCartId}/checkout
func (h *CheckoutHandler) Checkout(c *gin.Context) {
	cartIDStr := c.Param("shoppingCartId")
	cartID, err := strconv.ParseInt(cartIDStr, 10, 32)
	if err != nil || cartID <= 0 {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid shopping cart ID",
			Details: "Shopping cart ID must be a positive integer",
		})
		return
	}

	var req models.CheckoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid request body",
			Details: err.Error(),
		})
		return
	}

	// Get the shopping cart
	cart, exists := h.cartHandler.GetCart(int32(cartID))
	if !exists {
		c.JSON(http.StatusNotFound, models.ErrorResponse{
			Error:   "NOT_FOUND",
			Message: "Shopping cart not found",
		})
		return
	}

	// Check if cart has items
	if len(cart.Items) == 0 {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "EMPTY_CART",
			Message: "Cannot checkout an empty shopping cart",
		})
		return
	}

	// Step 1: Authorize credit card
	log.Printf("Authorizing credit card for cart %d", cartID)
	authStatus, err := h.ccaClient.Authorize(req.CreditCardNumber)
	if err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "AUTHORIZATION_ERROR",
			Message: "Failed to authorize credit card",
			Details: err.Error(),
		})
		return
	}

	if authStatus != "Authorized" {
		c.JSON(http.StatusPaymentRequired, models.ErrorResponse{
			Error:   "PAYMENT_DECLINED",
			Message: "Credit card payment was declined",
		})
		return
	}

	log.Printf("Credit card authorized for cart %d", cartID)

	// Step 2: Generate order ID
	h.mu.Lock()
	orderID := h.nextOrderID
	h.nextOrderID++
	h.mu.Unlock()

	// Step 3: Publish to RabbitMQ
	order := models.Order{
		OrderID:        orderID,
		ShoppingCartID: cart.ShoppingCartID,
		CustomerID:     cart.CustomerID,
		Items:          cart.Items,
	}

	if err := h.mqPublisher.PublishOrder(order); err != nil {
		log.Printf("Failed to publish order to warehouse: %v", err)
		c.JSON(http.StatusInternalServerError, models.ErrorResponse{
			Error:   "ORDER_PROCESSING_ERROR",
			Message: "Failed to send order to warehouse",
			Details: err.Error(),
		})
		return
	}

	log.Printf("Successfully checked out cart %d, created order %d", cartID, orderID)

	c.JSON(http.StatusOK, models.CheckoutResponse{
		OrderID: orderID,
	})
}
