package main

import (
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"warehouse-consumer/config"
	"warehouse-consumer/consumer"

	amqp "github.com/rabbitmq/amqp091-go"
)

func main() {
	cfg := config.LoadConfig()

	log.Printf("Starting Warehouse Consumer with %d workers", cfg.NumWorkers)
	log.Printf("Connecting to RabbitMQ at %s", cfg.RabbitMQURL)

	// Connect to RabbitMQ
	conn, err := amqp.Dial(cfg.RabbitMQURL)
	if err != nil {
		log.Fatalf("Failed to connect to RabbitMQ: %v", err)
	}
	defer conn.Close()

	// Declare the queue (ensure it exists)
	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("Failed to open a channel: %v", err)
	}

	_, err = ch.QueueDeclare(
		cfg.RabbitMQQueue, // name
		true,              // durable
		false,             // delete when unused
		false,             // exclusive
		false,             // no-wait
		nil,               // arguments
	)
	if err != nil {
		log.Fatalf("Failed to declare queue: %v", err)
	}
	ch.Close()

	log.Printf("Connected to queue: %s", cfg.RabbitMQQueue)

	// Create order tracker
	tracker := consumer.NewOrderTracker()

	// Create workers
	var wg sync.WaitGroup
	workers := make([]*consumer.Worker, cfg.NumWorkers)

	for i := 0; i < cfg.NumWorkers; i++ {
		worker, err := consumer.NewWorker(i+1, conn, cfg.RabbitMQQueue, tracker)
		if err != nil {
			log.Fatalf("Failed to create worker %d: %v", i+1, err)
		}
		workers[i] = worker

		wg.Add(1)
		go worker.Start(&wg)
	}

	log.Printf("All %d workers started successfully", cfg.NumWorkers)

	// Wait for interrupt signal to gracefully shut down
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	<-sigChan
	log.Println("\nReceived shutdown signal, stopping workers...")

	// Close connection (this will close all channels and stop workers)
	conn.Close()

	// Wait for all workers to finish
	wg.Wait()

	// Print final summary
	tracker.PrintSummary()

	log.Println("Warehouse Consumer shut down gracefully")
}
