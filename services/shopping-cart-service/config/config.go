package config

import (
	"os"
	"strconv"
)

type Config struct {
	Port            string
	LogLevel        string
	CCAServiceURL   string
	RabbitMQURL     string
	RabbitMQQueue   string
	ChannelPoolSize int
}

func LoadConfig() *Config {
	return &Config{
		Port:            getEnv("PORT", "8081"),
		LogLevel:        getEnv("LOG_LEVEL", "info"),
		CCAServiceURL:   getEnv("CCA_SERVICE_URL", "/cca"),
		RabbitMQURL:     getEnv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/"),
		RabbitMQQueue:   getEnv("RABBITMQ_QUEUE", "warehouse_orders"),
		ChannelPoolSize: getEnvAsInt("CHANNEL_POOL_SIZE", 10),
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
