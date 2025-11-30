package consumer

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"warehouse-consumer/models"

	amqp "github.com/rabbitmq/amqp091-go"
)

type Worker struct {
	workerID     int
	channel      *amqp.Channel
	queueName    string
	orderTracker *OrderTracker
}

func NewWorker(workerID int, conn *amqp.Connection, queueName string, tracker *OrderTracker) (*Worker, error) {
	// Each worker gets its own channel
	ch, err := conn.Channel()
	if err != nil {
		return nil, fmt.Errorf("failed to open channel for worker %d: %w", workerID, err)
	}

	// Set QoS (prefetch count) - each worker processes one message at a time
	err = ch.Qos(
		1,     // prefetch count
		0,     // prefetch size
		false, // global
	)
	if err != nil {
		ch.Close()
		return nil, fmt.Errorf("failed to set QoS for worker %d: %w", workerID, err)
	}

	return &Worker{
		workerID:     workerID,
		channel:      ch,
		queueName:    queueName,
		orderTracker: tracker,
	}, nil
}

// Start begins consuming messages
func (w *Worker) Start(wg *sync.WaitGroup) {
	defer wg.Done()
	defer w.channel.Close()

	// Register as a consumer
	msgs, err := w.channel.Consume(
		w.queueName,                          // queue
		fmt.Sprintf("worker-%d", w.workerID), // consumer tag
		false,                                // auto-ack (we want manual acknowledgements)
		false,                                // exclusive
		false,                                // no-local
		false,                                // no-wait
		nil,                                  // args
	)
	if err != nil {
		log.Printf("Worker %d failed to register consumer: %v", w.workerID, err)
		return
	}

	log.Printf("Worker %d started and waiting for messages", w.workerID)

	// Process messages
	for msg := range msgs {
		w.processMessage(msg)
	}

	log.Printf("Worker %d stopped", w.workerID)
}

// processMessage processes a single message
func (w *Worker) processMessage(msg amqp.Delivery) {
	var order models.Order

	// Parse the order
	if err := json.Unmarshal(msg.Body, &order); err != nil {
		log.Printf("Worker %d: Failed to unmarshal order: %v", w.workerID, err)
		// Reject the message (don't requeue - it's malformed)
		msg.Nack(false, false)
		return
	}

	// Convert items to the format expected by OrderTracker
	type Item struct {
		ProductID int32
		Quantity  int32
	}
	// Convert items to the format expected by OrderTracker
	items := make([]OrderItem, len(order.Items))
	for i, item := range order.Items {
		items[i] = OrderItem{
			ProductID: item.ProductID,
			Quantity:  item.Quantity,
		}
	}

	// Record the order (thread-safe)
	w.orderTracker.RecordOrder(order.OrderID, items)

	// Acknowledge the message (manual acknowledgement)
	if err := msg.Ack(false); err != nil {
		log.Printf("Worker %d: Failed to acknowledge message: %v", w.workerID, err)
	} else {
		log.Printf("Worker %d: Processed and acknowledged order %d", w.workerID, order.OrderID)
	}
}

// Stop gracefully stops the worker
func (w *Worker) Stop() {
	if w.channel != nil {
		w.channel.Close()
	}
}
