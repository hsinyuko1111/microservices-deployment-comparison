package rabbitmq

import (
	"errors"
	"fmt"
	"log"
	"sync"

	amqp "github.com/rabbitmq/amqp091-go"
)

type ChannelPool struct {
	conn      *amqp.Connection
	channels  chan *amqp.Channel
	mu        sync.Mutex
	size      int
	queueName string
}

// NewChannelPool creates a new channel pool
func NewChannelPool(rabbitmqURL string, queueName string, size int) (*ChannelPool, error) {
	conn, err := amqp.Dial(rabbitmqURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	pool := &ChannelPool{
		conn:      conn,
		channels:  make(chan *amqp.Channel, size),
		size:      size,
		queueName: queueName,
	}

	// Pre-create channels
	for i := 0; i < size; i++ {
		ch, err := pool.createChannel()
		if err != nil {
			pool.Close()
			return nil, fmt.Errorf("failed to create channel %d: %w", i, err)
		}
		pool.channels <- ch
	}

	log.Printf("Created RabbitMQ channel pool with %d channels", size)
	return pool, nil
}

// createChannel creates and configures a new channel
func (p *ChannelPool) createChannel() (*amqp.Channel, error) {
	ch, err := p.conn.Channel()
	if err != nil {
		return nil, err
	}

	// Declare the queue (idempotent operation)
	_, err = ch.QueueDeclare(
		p.queueName, // name
		true,        // durable
		false,       // delete when unused
		false,       // exclusive
		false,       // no-wait
		nil,         // arguments
	)
	if err != nil {
		ch.Close()
		return nil, fmt.Errorf("failed to declare queue: %w", err)
	}

	return ch, nil
}

// GetChannel retrieves a channel from the pool
func (p *ChannelPool) GetChannel() (*amqp.Channel, error) {
	select {
	case ch := <-p.channels:
		// Check if channel is still open
		if ch.IsClosed() {
			// Try to create a new channel
			newCh, err := p.createChannel()
			if err != nil {
				return nil, err
			}
			return newCh, nil
		}
		return ch, nil
	default:
		return nil, errors.New("no channels available in pool")
	}
}

// ReturnChannel returns a channel to the pool
func (p *ChannelPool) ReturnChannel(ch *amqp.Channel) {
	if ch != nil && !ch.IsClosed() {
		select {
		case p.channels <- ch:
			// Successfully returned to pool
		default:
			// Pool is full, close the channel
			ch.Close()
		}
	}
}

// Close closes all channels and the connection
func (p *ChannelPool) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()

	close(p.channels)
	for ch := range p.channels {
		ch.Close()
	}
	if p.conn != nil {
		p.conn.Close()
	}
	log.Println("Closed RabbitMQ channel pool")
}
