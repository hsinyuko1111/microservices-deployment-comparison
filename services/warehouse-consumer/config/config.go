package config

import (
	"os"
	"strconv"
)

type Config struct {
	RabbitMQURL   string
	RabbitMQQueue string
	NumWorkers    int
	LogLevel      string
}

func LoadConfig() *Config {
	return &Config{
		RabbitMQURL:   getEnv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/"),
		RabbitMQQueue: getEnv("RABBITMQ_QUEUE", "warehouse_orders"),
		NumWorkers:    getEnvAsInt("NUM_WORKERS", 5),
		LogLevel:      getEnv("LOG_LEVEL", "info"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	valueStr := getEnv(key, "")
	if valueStr == "" {
		return defaultValue
	}
	value, err := strconv.Atoi(valueStr)
	if err != nil {
		return defaultValue
	}
	return value
}
