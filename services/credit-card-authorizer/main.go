package main

import (
	"log"

	"credit-card-authorizer/config"
	"credit-card-authorizer/handlers"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.LoadConfig()

	log.Printf("Starting Credit Card Authorizer Service on port %s", cfg.Port)

	// Set Gin mode based on environment
	if cfg.LogLevel == "debug" {
		gin.SetMode(gin.DebugMode)
	} else {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.Default()
	authorizeHandler := handlers.NewAuthorizeHandler()

	// Routes
	router.POST("/credit-card-authorizer/authorize", authorizeHandler.Authorize)

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "OK"})
	})

	log.Fatal(router.Run(":" + cfg.Port))
}
