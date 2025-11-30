package handlers

import (
	"log"
	"net/http"
	"strconv"
	"sync"

	"shopping-cart-service/models"

	"github.com/gin-gonic/gin"
)

type CartHandler struct {
	mu         sync.RWMutex
	carts      map[int32]*models.ShoppingCart
	nextCartID int32
}

func NewCartHandler() *CartHandler {
	return &CartHandler{
		carts:      make(map[int32]*models.ShoppingCart),
		nextCartID: 1,
	}
}

// CreateCart handles POST /shopping-cart
func (h *CartHandler) CreateCart(c *gin.Context) {
	var req models.CreateCartRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid request body",
			Details: err.Error(),
		})
		return
	}

	h.mu.Lock()
	cartID := h.nextCartID
	h.nextCartID++

	cart := &models.ShoppingCart{
		ShoppingCartID: cartID,
		CustomerID:     req.CustomerID,
		Items:          []models.CartItem{},
	}
	h.carts[cartID] = cart
	h.mu.Unlock()

	log.Printf("Created shopping cart %d for customer %d", cartID, req.CustomerID)

	c.JSON(http.StatusCreated, models.CreateCartResponse{
		ShoppingCartID: cartID,
	})
}

// AddItem handles POST /shopping-carts/{shoppingCartId}/addItem
func (h *CartHandler) AddItem(c *gin.Context) {
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

	var req models.AddItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid request body",
			Details: err.Error(),
		})
		return
	}

	h.mu.Lock()
	cart, exists := h.carts[int32(cartID)]
	if !exists {
		h.mu.Unlock()
		c.JSON(http.StatusNotFound, models.ErrorResponse{
			Error:   "NOT_FOUND",
			Message: "Shopping cart not found",
		})
		return
	}

	// Add or update item in cart
	found := false
	for i, item := range cart.Items {
		if item.ProductID == req.ProductID {
			cart.Items[i].Quantity += req.Quantity
			found = true
			break
		}
	}
	if !found {
		cart.Items = append(cart.Items, models.CartItem{
			ProductID: req.ProductID,
			Quantity:  req.Quantity,
		})
	}
	h.mu.Unlock()

	log.Printf("Added %d of product %d to cart %d", req.Quantity, req.ProductID, cartID)

	c.Status(http.StatusNoContent)
}

// GetCart returns a cart (helper method for checkout)
func (h *CartHandler) GetCart(cartID int32) (*models.ShoppingCart, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	cart, exists := h.carts[cartID]
	return cart, exists
}
