package clients

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type CCAClient struct {
	baseURL    string
	httpClient *http.Client
}

type AuthorizationRequest struct {
	CreditCardNumber string `json:"credit_card_number"`
}

type AuthorizationResponse struct {
	Status string `json:"status"`
}

func NewCCAClient(baseURL string) *CCAClient {
	return &CCAClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// Authorize calls the Credit Card Authorizer service
func (c *CCAClient) Authorize(creditCardNumber string) (string, error) {
	reqBody := AuthorizationRequest{
		CreditCardNumber: creditCardNumber,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	url := fmt.Sprintf("%s/credit-card-authorizer/authorize", c.baseURL)
	resp, err := c.httpClient.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to call CCA service: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response body: %w", err)
	}

	// Handle different status codes
	switch resp.StatusCode {
	case http.StatusOK:
		var authResp AuthorizationResponse
		if err := json.Unmarshal(body, &authResp); err != nil {
			return "", fmt.Errorf("failed to unmarshal response: %w", err)
		}
		return authResp.Status, nil
	case http.StatusPaymentRequired:
		var authResp AuthorizationResponse
		if err := json.Unmarshal(body, &authResp); err != nil {
			return "", fmt.Errorf("failed to unmarshal response: %w", err)
		}
		return authResp.Status, nil
	case http.StatusBadRequest:
		return "", fmt.Errorf("invalid credit card format: %s", string(body))
	default:
		return "", fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}
}
