package models

type AuthorizationRequest struct {
	CreditCardNumber string `json:"credit_card_number" binding:"required"`
}

type AuthorizationResponse struct {
	Status string `json:"status"` // "Authorized" or "Declined"
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
	Details string `json:"details,omitempty"`
}
