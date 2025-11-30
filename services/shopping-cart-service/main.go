package main

import (
	"log"

	"shopping-cart-service/clients"
	"shopping-cart-service/config"
	"shopping-cart-service/handlers"
	"shopping-cart-service/rabbitmq"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.LoadConfig()

	log.Printf("Starting Shopping Cart Service on port %s", cfg.Port)

	// Set Gin mode
	if cfg.LogLevel == "debug" {
		gin.SetMode(gin.DebugMode)
	} else {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize RabbitMQ channel pool
	channelPool, err := rabbitmq.NewChannelPool(cfg.RabbitMQURL, cfg.RabbitMQQueue, cfg.ChannelPoolSize)
	if err != nil {
		log.Fatalf("Failed to create RabbitMQ channel pool: %v", err)
	}
	defer channelPool.Close()

	// Initialize publisher
	publisher := rabbitmq.NewPublisher(channelPool, cfg.RabbitMQQueue)

	// Initialize CCA client
	ccaClient := clients.NewCCAClient(cfg.CCAServiceURL)

	// Initialize handlers
	cartHandler := handlers.NewCartHandler()
	checkoutHandler := handlers.NewCheckoutHandler(cartHandler, ccaClient, publisher)

	// Setup router
	router := gin.Default()

	// Routes
	router.POST("/shopping-cart", cartHandler.CreateCart)
	router.POST("/shopping-carts/:shoppingCartId/addItem", cartHandler.AddItem)
	router.POST("/shopping-carts/:shoppingCartId/checkout", checkoutHandler.Checkout)

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "OK"})
	})

	log.Fatal(router.Run(":" + cfg.Port))
}
