package validators

import (
	"regexp"
)

// ValidateCreditCardFormat validates the credit card number format
// Format: 4 groups of 4 digits separated by dashes (e.g., 1234-5678-9012-3456)
func ValidateCreditCardFormat(cardNumber string) bool {
	// Regex pattern: exactly 4 groups of 4 digits separated by dashes
	pattern := `^\d{4}-\d{4}-\d{4}-\d{4}$`
	matched, err := regexp.MatchString(pattern, cardNumber)
	if err != nil {
		return false
	}
	return matched
}
