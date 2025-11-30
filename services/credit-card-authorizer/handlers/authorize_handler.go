package handlers

import (
	"log"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"credit-card-authorizer/models"
	"credit-card-authorizer/validators"

	"github.com/gin-gonic/gin"
)

type AuthorizeHandler struct {
	mu  sync.Mutex
	rng *rand.Rand
}

func NewAuthorizeHandler() *AuthorizeHandler {
	return &AuthorizeHandler{
		rng: rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

// Authorize handles POST /credit-card-authorizer/authorize
func (h *AuthorizeHandler) Authorize(c *gin.Context) {
	var req models.AuthorizationRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_INPUT",
			Message: "Invalid request body",
			Details: err.Error(),
		})
		return
	}

	// Validate credit card format
	if !validators.ValidateCreditCardFormat(req.CreditCardNumber) {
		log.Printf("Invalid credit card format: %s", req.CreditCardNumber)
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_CARD_FORMAT",
			Message: "Invalid credit card number format",
			Details: "Credit card must be in format: XXXX-XXXX-XXXX-XXXX (4 groups of 4 digits separated by dashes)",
		})
		return
	}

	// Simulate authorization logic: 90% authorized, 10% declined
	if h.shouldAuthorize() {
		log.Printf("Credit card authorized: %s", maskCardNumber(req.CreditCardNumber))
		c.JSON(http.StatusOK, models.AuthorizationResponse{
			Status: "Authorized",
		})
	} else {
		log.Printf("Credit card declined: %s", maskCardNumber(req.CreditCardNumber))
		c.JSON(http.StatusPaymentRequired, models.AuthorizationResponse{
			Status: "Declined",
		})
	}
}

// shouldAuthorize returns true 90% of the time
func (h *AuthorizeHandler) shouldAuthorize() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.rng.Float32() < 0.9
}

// maskCardNumber masks all but the last 4 digits for logging
func maskCardNumber(cardNumber string) string {
	if len(cardNumber) < 4 {
		return "****"
	}
	return "****-****-****-" + cardNumber[len(cardNumber)-4:]
}
