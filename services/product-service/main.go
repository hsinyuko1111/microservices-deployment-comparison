package main

import (
	"log"
	"product-service/config"
	"product-service/handlers"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.LoadConfig()

	log.Printf("Starting Product Service on port %s", cfg.Port)

	// Set Gin mode based on environment
	if cfg.LogLevel == "debug" {
		gin.SetMode(gin.DebugMode)
	} else {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.Default()
	productHandler := handlers.NewProductHandler()

	// Routes
	router.POST("/product", productHandler.CreateProduct)
	router.GET("/products/:productId", productHandler.GetProduct)

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "OK"})
	})

	log.Fatal(router.Run(":" + cfg.Port))
}
