package stress

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"runtime"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	"github.com/shirou/gopsutil/v3/cpu"
)

// SimulateRestockStorm simulates the weekly inventory restock scenario
//
// Story: Every Sunday at 3 AM, all 30,000 stores simultaneously sync their
// inventory with the central warehouse system. Each store updates 5000+ SKUs,
// causing massive DynamoDB write traffic and CPU-intensive hash calculations
// for data integrity checks.
//
// Expected Impact:
// - EKS pod CPU → 80%
// - DynamoDB write capacity consumed
// - MemoryDB atomic counter updates
// - Pod restart count may increase if resource limits exceeded
func SimulateRestockStorm(duration time.Duration, targetCPU int, cwClient *cloudwatch.Client) {
	log.Println("========================================")
	log.Println("🔥 STRESS SCENARIO: INVENTORY RESTOCK STORM")
	log.Println("========================================")
	log.Printf("Story: Sunday 3 AM. All stores syncing 5000+ SKUs.")
	log.Printf("Duration: %v", duration)
	log.Printf("Target CPU: %d%%", targetCPU)
	log.Println("========================================")

	startTime := time.Now()
	iteration := 0

	// Use all available CPUs
	numWorkers := runtime.NumCPU()
	var wg sync.WaitGroup

	// Start worker goroutines
	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()

			for time.Since(startTime) < duration {
				// Simulate processing multiple stores
				for storeNum := 0; storeNum < 100; storeNum++ {
					storeID := fmt.Sprintf("store-%d", rand.Intn(30000))

					// Process 100 SKUs per store
					for skuNum := 0; skuNum < 100; skuNum++ {
						sku := fmt.Sprintf("SKU-%d", rand.Intn(10000))

						// CPU-intensive operations
						inventoryItem := map[string]interface{}{
							"store_id": storeID,
							"sku":      sku,
							"quantity": rand.Intn(1000),
							"timestamp": time.Now().Unix(),
						}

						// JSON marshaling (CPU-intensive)
						jsonData, _ := json.Marshal(inventoryItem)

						// SHA256 hash for data integrity (CPU-intensive)
						hash := sha256.Sum256(jsonData)
						hashHex := hex.EncodeToString(hash[:])

						// More JSON processing
						json.Unmarshal(jsonData, &inventoryItem)

						// Simulate validation logic
						_ = validateInventory(inventoryItem, hashHex)
					}
				}

				iteration++

				// Adaptive sleep based on CPU usage
				if iteration%10 == 0 {
					currentCPU, _ := cpu.Percent(100*time.Millisecond, false)
					if len(currentCPU) > 0 {
						if currentCPU[0] < float64(targetCPU-10) {
							time.Sleep(1 * time.Millisecond)
						} else if currentCPU[0] > float64(targetCPU+10) {
							time.Sleep(50 * time.Millisecond)
						}
					}
				}
			}
		}(i)
	}

	// Metrics reporter goroutine
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				if time.Since(startTime) >= duration {
					return
				}

				// Get CPU usage
				currentCPU, err := cpu.Percent(time.Second, false)
				if err != nil || len(currentCPU) == 0 {
					continue
				}

				cpuPercent := currentCPU[0]

				// Emit CloudWatch metrics
				if cwClient != nil {
					input := &cloudwatch.PutMetricDataInput{
						Namespace: aws.String("CloudCafe/Inventory"),
						MetricData: []types.MetricDatum{
							{
								MetricName: aws.String("RestockCPU"),
								Value:      aws.Float64(cpuPercent),
								Unit:       types.StandardUnitPercent,
								Timestamp:  aws.Time(time.Now()),
								Dimensions: []types.Dimension{
									{
										Name:  aws.String("Scenario"),
										Value: aws.String("RestockStorm"),
									},
								},
							},
							{
								MetricName: aws.String("RestockIterations"),
								Value:      aws.Float64(float64(iteration)),
								Unit:       types.StandardUnitCount,
								Timestamp:  aws.Time(time.Now()),
								Dimensions: []types.Dimension{
									{
										Name:  aws.String("Scenario"),
										Value: aws.String("RestockStorm"),
									},
								},
							},
						},
					}

					cwClient.PutMetricData(context.TODO(), input)
				}

				elapsed := time.Since(startTime).Seconds()
				log.Printf("[%.0fs] CPU: %.1f%% | Iterations: %d | Workers: %d",
					elapsed, cpuPercent, iteration, numWorkers)
			}
		}
	}()

	// Wait for all workers to complete
	wg.Wait()

	elapsed := time.Since(startTime)
	log.Println("========================================")
	log.Println("✅ STRESS COMPLETE")
	log.Printf("Total time: %.1fs", elapsed.Seconds())
	log.Printf("Total iterations: %d", iteration)
	log.Printf("Throughput: %.0f iterations/sec", float64(iteration)/elapsed.Seconds())
	log.Println("========================================")

	// Final metric
	if cwClient != nil {
		input := &cloudwatch.PutMetricDataInput{
			Namespace: aws.String("CloudCafe/Inventory"),
			MetricData: []types.MetricDatum{
				{
					MetricName: aws.String("RestockCompleted"),
					Value:      aws.Float64(1),
					Unit:       types.StandardUnitCount,
					Timestamp:  aws.Time(time.Now()),
					Dimensions: []types.Dimension{
						{
							Name:  aws.String("Scenario"),
							Value: aws.String("RestockStorm"),
						},
					},
				},
			},
		}

		cwClient.PutMetricData(context.TODO(), input)
	}
}

func validateInventory(item map[string]interface{}, hash string) bool {
	// Simulate complex validation logic (CPU-intensive)
	quantity, ok := item["quantity"].(int)
	if !ok {
		return false
	}

	// Fibonacci calculation for complexity scoring
	complexity := fibonacci(20 + (quantity % 10))

	// More hashing
	validationString := fmt.Sprintf("%v-%s-%d", item, hash, complexity)
	validationHash := sha256.Sum256([]byte(validationString))

	return len(hex.EncodeToString(validationHash[:])) > 0
}

func fibonacci(n int) int {
	if n <= 1 {
		return n
	}
	return fibonacci(n-1) + fibonacci(n-2)
}
