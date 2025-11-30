package consumer

import (
	"fmt"
	"log"
	"strings"
	"sync"
)

type OrderItem struct {
	ProductID int32
	Quantity  int32
}

// OrderTracker tracks total orders and product quantities in a thread-safe manner
type OrderTracker struct {
	mu                sync.Mutex
	totalOrders       int64
	productQuantities map[int32]int64
}

func NewOrderTracker() *OrderTracker {
	return &OrderTracker{
		productQuantities: make(map[int32]int64),
	}
}

// RecordOrder records an order and updates product quantities
func (t *OrderTracker) RecordOrder(orderID int32, items []OrderItem) {
	t.mu.Lock()
	defer t.mu.Unlock()

	// Increment total orders
	t.totalOrders++

	// Update product quantities
	for _, item := range items {
		t.productQuantities[item.ProductID] += int64(item.Quantity)
	}

	log.Printf("Recorded order %d (Total orders: %d)", orderID, t.totalOrders)
}

// PrintSummary prints the final summary when shutting down
func (t *OrderTracker) PrintSummary() {
	t.mu.Lock()
	defer t.mu.Unlock()

	fmt.Println("\n" + strings.Repeat("=", 60))
	fmt.Println("WAREHOUSE SUMMARY")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("Total Orders Processed: %d\n", t.totalOrders)
	fmt.Println(strings.Repeat("=", 60))

	// Optionally print product quantities (commented out for large datasets)
	// fmt.Println("\nProduct Quantities:")
	// for productID, quantity := range t.productQuantities {
	// 	fmt.Printf("  Product %d: %d units\n", productID, quantity)
	// }
	// fmt.Println("="*60)
}

// GetTotalOrders returns the total number of orders (for testing)
func (t *OrderTracker) GetTotalOrders() int64 {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.totalOrders
}

// GetProductQuantity returns the quantity for a specific product (for testing)
func (t *OrderTracker) GetProductQuantity(productID int32) int64 {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.productQuantities[productID]
}
