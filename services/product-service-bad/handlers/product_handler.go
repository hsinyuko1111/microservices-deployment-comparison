package handlers

import (
	"log"
	"math/rand"
	"net/http"
	"strconv"
	"sync"
	"time"

	"product-service/models"

	"github.com/gin-gonic/gin"
)

type ProductHandler struct {
	mu            sync.RWMutex
	products      map[int32]*models.Product
	nextProductID int32
	rng           *rand.Rand
}

func NewProductHandler() *ProductHandler {
	return &ProductHandler{
		products:      make(map[int32]*models.Product),
		nextProductID: 1,
		rng:           rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

// CreateProduct handles POST /product with 50% chance of 503 error
func (h *ProductHandler) CreateProduct(c *gin.Context) {
	// Simulate 50% failure rate with 503 Service Unavailable
	if h.shouldFail() {
		log.Printf("Simulating 503 failure for product creation")
		c.JSON(http.StatusServiceUnavailable, models.ErrorResponse{
			Error:   "SERVICE_UNAVAILABLE",
			Message: "Service temporarily unavailable",
			Details: "This is a simulated failure for testing load balancer behavior",
		})
		return
	}

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

	log.Printf("Created product with ID: %d (SUCCESS)", productID)

	c.JSON(http.StatusCreated, models.CreateProductResponse{ProductID: productID})
}

// GetProduct handles GET /products/{productId} with 50% chance of 503 error
func (h *ProductHandler) GetProduct(c *gin.Context) {
	// Simulate 50% failure rate
	if h.shouldFail() {
		log.Printf("Simulating 503 failure for product retrieval")
		c.JSON(http.StatusServiceUnavailable, models.ErrorResponse{
			Error:   "SERVICE_UNAVAILABLE",
			Message: "Service temporarily unavailable",
			Details: "This is a simulated failure for testing load balancer behavior",
		})
		return
	}

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

	log.Printf("Retrieved product with ID: %d (SUCCESS)", productID)
	c.JSON(http.StatusOK, product)
}

// shouldFail returns true 50% of the time
func (h *ProductHandler) shouldFail() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.rng.Float32() < 0.5
}
