package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/go-redis/redis/v8"
	"github.com/gorilla/mux"

	"github.com/cloudcafe/inventory-service/pkg/stress"
)

var (
	dynamoClient    *dynamodb.Client
	cloudwatchClient *cloudwatch.Client
	redisClient     *redis.Client
	tableName       string
)

type InventoryItem struct {
	StoreID  string `json:"store_id" dynamodbav:"store_id"`
	SKU      string `json:"sku" dynamodbav:"sku"`
	Quantity int    `json:"quantity" dynamodbav:"quantity"`
	UpdatedAt string `json:"updated_at" dynamodbav:"updated_at"`
}

type HealthResponse struct {
	Status    string `json:"status"`
	Service   string `json:"service"`
	Timestamp string `json:"timestamp"`
}

type StressRequest struct {
	DurationSeconds int `json:"duration_seconds"`
	TargetCPU       int `json:"target_cpu"`
}

func init() {
	// Initialize AWS SDK
	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(getEnv("AWS_REGION", "us-east-1")),
	)
	if err != nil {
		log.Fatalf("unable to load SDK config, %v", err)
	}

	dynamoClient = dynamodb.NewFromConfig(cfg)
	cloudwatchClient = cloudwatch.NewFromConfig(cfg)
	tableName = getEnv("DYNAMODB_TABLE", "cloudcafe-store-inventory-dev")

	// Initialize Redis
	redisEndpoint := os.Getenv("MEMORYDB_ENDPOINT")
	if redisEndpoint != "" {
		redisClient = redis.NewClient(&redis.Options{
			Addr: redisEndpoint + ":6379",
		})
	}
}

func main() {
	router := mux.NewRouter()

	// Routes
	router.HandleFunc("/health", healthHandler).Methods("GET")
	router.HandleFunc("/inventory/store/{storeId}", getStoreInventoryHandler).Methods("GET")
	router.HandleFunc("/inventory/update", updateInventoryHandler).Methods("POST")
	router.HandleFunc("/stress/restock", restockStressHandler).Methods("POST")

	port := getEnv("PORT", "8080")
	log.Printf("Inventory Service starting on port %s", port)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	log.Fatal(srv.ListenAndServe())
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	response := HealthResponse{
		Status:    "healthy",
		Service:   "inventory-service",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func getStoreInventoryHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	storeID := vars["storeId"]

	startTime := time.Now()

	// Try Redis cache first
	if redisClient != nil {
		cacheKey := fmt.Sprintf("inventory:store:%s", storeID)
		cached, err := redisClient.Get(context.TODO(), cacheKey).Result()
		if err == nil {
			// Cache hit
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("X-Cache", "HIT")
			w.Write([]byte(cached))

			emitMetric("CacheHit", 1)
			return
		}
	}

	// Cache miss, query DynamoDB
	input := &dynamodb.QueryInput{
		TableName:              aws.String(tableName),
		KeyConditionExpression: aws.String("store_id = :storeId"),
		ExpressionAttributeValues: map[string]dynamodb.AttributeValue{
			":storeId": &dynamodb.AttributeValueMemberS{Value: storeID},
		},
	}

	result, err := dynamoClient.Query(context.TODO(), input)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		emitMetric("QueryError", 1)
		return
	}

	var items []InventoryItem
	err = attributevalue.UnmarshalListOfMaps(result.Items, &items)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	responseJSON, _ := json.Marshal(items)

	// Cache in Redis for 5 minutes
	if redisClient != nil {
		cacheKey := fmt.Sprintf("inventory:store:%s", storeID)
		redisClient.Set(context.TODO(), cacheKey, responseJSON, 5*time.Minute)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Cache", "MISS")
	w.Write(responseJSON)

	// Emit metrics
	duration := time.Since(startTime).Milliseconds()
	emitMetric("QueryDuration", float64(duration))
	emitMetric("CacheMiss", 1)
}

func updateInventoryHandler(w http.ResponseWriter, r *http.Request) {
	var item InventoryItem
	if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	item.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	// Update DynamoDB
	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	input := &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      av,
	}

	_, err = dynamoClient.PutItem(context.TODO(), input)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		emitMetric("UpdateError", 1)
		return
	}

	// Invalidate cache
	if redisClient != nil {
		cacheKey := fmt.Sprintf("inventory:store:%s", item.StoreID)
		redisClient.Del(context.TODO(), cacheKey)
	}

	// Update atomic counter in MemoryDB
	if redisClient != nil {
		counterKey := fmt.Sprintf("inventory:counter:%s:%s", item.StoreID, item.SKU)
		redisClient.Set(context.TODO(), counterKey, item.Quantity, 0)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"store_id": item.StoreID,
		"sku":     item.SKU,
	})

	emitMetric("InventoryUpdated", 1)
}

func restockStressHandler(w http.ResponseWriter, r *http.Request) {
	var req StressRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		// Use defaults
		req.DurationSeconds = 180
		req.TargetCPU = 80
	}

	log.Printf("Starting Restock Storm stress scenario: %ds, target CPU %d%%",
		req.DurationSeconds, req.TargetCPU)

	// Run stress in background goroutine
	go stress.SimulateRestockStorm(
		time.Duration(req.DurationSeconds)*time.Second,
		req.TargetCPU,
		cloudwatchClient,
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":           "stress_started",
		"scenario":         "restock_storm",
		"duration_seconds": req.DurationSeconds,
		"target_cpu":       req.TargetCPU,
	})
}

func emitMetric(metricName string, value float64) {
	if cloudwatchClient == nil {
		return
	}

	input := &cloudwatch.PutMetricDataInput{
		Namespace: aws.String("CloudCafe/Inventory"),
		MetricData: []types.MetricDatum{
			{
				MetricName: aws.String(metricName),
				Value:      aws.Float64(value),
				Timestamp:  aws.Time(time.Now()),
				Unit:       types.StandardUnitCount,
			},
		},
	}

	cloudwatchClient.PutMetricData(context.TODO(), input)
}

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}
