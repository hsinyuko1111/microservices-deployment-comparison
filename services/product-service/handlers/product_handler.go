package handlers

import (
	"log"
	"net/http"
	"strconv"
	"sync"

	"product-service/models"

	"github.com/gin-gonic/gin"
)

type ProductHandler struct {
	mu            sync.RWMutex
	products      map[int32]*models.Product
	nextProductID int32
}

func NewProductHandler() *ProductHandler {
	return &ProductHandler{
		products:      make(map[int32]*models.Product),
		nextProductID: 1,
	}
}

// CreateProduct handles POST /product
func (h *ProductHandler) CreateProduct(c *gin.Context) {
	var req models.CreateProductRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid request body",
			Details: err.Error(),
		})
		return
	}

	// Validate input
	if req.SKU == "" || req.Manufacturer == "" {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "SKU and Manufacturer are required",
		})
		return
	}

	if req.CategoryID <= 0 || req.Weight < 0 || req.SomeOtherID <= 0 {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid product fields",
			Details: "CategoryID, Weight, and SomeOtherID must be valid positive numbers",
		})
		return
	}

	h.mu.Lock()
	productID := h.nextProductID
	h.nextProductID++

	product := &models.Product{
		ProductID:    productID,
		SKU:          req.SKU,
		Manufacturer: req.Manufacturer,
		CategoryID:   req.CategoryID,
		Weight:       req.Weight,
		SomeOtherID:  req.SomeOtherID,
	}
	h.products[productID] = product
	h.mu.Unlock()

	log.Printf("Created product with ID: %d", productID)

	c.JSON(http.StatusCreated, models.CreateProductResponse{ProductID: productID})
}

// GetProduct handles GET /products/{productId}
func (h *ProductHandler) GetProduct(c *gin.Context) {
	productIDStr := c.Param("productId")

	productID, err := strconv.ParseInt(productIDStr, 10, 32)
	if err != nil || productID <= 0 {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid product ID",
			Details: "Product ID must be a positive integer",
		})
		return
	}

	h.mu.RLock()
	product, exists := h.products[int32(productID)]
	h.mu.RUnlock()

	if !exists {
		c.JSON(http.StatusNotFound, models.ErrorResponse{
			Error:   "NOT_FOUND",
			Message: "Product not found",
		})
		return
	}

	c.JSON(http.StatusOK, product)
}
