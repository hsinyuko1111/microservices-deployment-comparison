package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"shopping-cart-service/models"

	amqp "github.com/rabbitmq/amqp091-go"
)

type Publisher struct {
	pool      *ChannelPool
	queueName string
}

func NewPublisher(pool *ChannelPool, queueName string) *Publisher {
	return &Publisher{
		pool:      pool,
		queueName: queueName,
	}
}

// PublishOrder publishes an order to the warehouse queue
func (p *Publisher) PublishOrder(order models.Order) error {
	ch, err := p.pool.GetChannel()
	if err != nil {
		return fmt.Errorf("failed to get channel from pool: %w", err)
	}
	defer p.pool.ReturnChannel(ch)

	// Convert order to JSON
	body, err := json.Marshal(order)
	if err != nil {
		return fmt.Errorf("failed to marshal order: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Publish message with confirmation
	err = ch.PublishWithContext(ctx,
		"",          // exchange
		p.queueName, // routing key (queue name)
		false,       // mandatory
		false,       // immediate
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  "application/json",
			Body:         body,
		})

	if err != nil {
		return fmt.Errorf("failed to publish order: %w", err)
	}

	log.Printf("Published order %d to warehouse queue", order.OrderID)
	return nil
}
