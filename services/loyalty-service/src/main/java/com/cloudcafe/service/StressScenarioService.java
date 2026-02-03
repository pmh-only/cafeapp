package com.cloudcafe.service;

import com.sun.management.OperatingSystemMXBean;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.codec.digest.DigestUtils;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.cloudwatch.model.StandardUnit;

import java.lang.management.ManagementFactory;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.Random;

/**
 * Stress Scenario: Loyalty Batch Calculation
 *
 * Story: Every hour, the loyalty service recalculates points, tiers, and rewards
 * for all 10 million customers. This CPU-intensive batch job processes complex
 * tier multipliers, purchase history analysis, and fraud detection scoring.
 *
 * Expected Impact:
 * - EC2 CPU → 100%
 * - RDS read IOPS spike
 * - Redshift concurrent queries increase
 * - EC2 Auto Scaling triggers (adds instances)
 * - NLB connection count increases
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class StressScenarioService {

    private final CloudWatchService cloudWatchService;
    private volatile boolean stressRunning = false;

    /**
     * Simulate hourly batch loyalty calculation for millions of customers
     */
    public void simulateBatchCalculation(int durationSeconds, int targetCpu) {
        if (stressRunning) {
            log.warn("Stress scenario already running, ignoring new request");
            return;
        }

        stressRunning = true;

        log.info("========================================");
        log.info("🔥 STRESS SCENARIO: LOYALTY BATCH CALCULATION");
        log.info("========================================");
        log.info("Story: Hourly recalculation for 10M customers. EC2 hits 100% CPU.");
        log.info("Duration: {}s", durationSeconds);
        log.info("Target CPU: {}%", targetCpu);
        log.info("========================================");

        long startTime = System.currentTimeMillis();
        long endTime = startTime + (durationSeconds * 1000L);

        int iteration = 0;
        int availableProcessors = Runtime.getRuntime().availableProcessors();
        ExecutorService executorService = Executors.newFixedThreadPool(availableProcessors);

        try {
            while (System.currentTimeMillis() < endTime) {
                long iterationStart = System.currentTimeMillis();

                // Create CPU-intensive tasks for each core
                List<CompletableFuture<Void>> futures = new ArrayList<>();

                for (int i = 0; i < availableProcessors; i++) {
                    final int threadNum = i;
                    CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                        processBatchOfCustomers(threadNum, 1000);
                    }, executorService);
                    futures.add(future);
                }

                // Wait for all threads to complete
                CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

                iteration++;

                // Emit metrics every 10 iterations
                if (iteration % 10 == 0) {
                    double cpuUsage = getCpuUsage();
                    long elapsed = (System.currentTimeMillis() - startTime) / 1000;

                    cloudWatchService.emitMetric("BatchJobCPU", cpuUsage, StandardUnit.PERCENT);
                    cloudWatchService.emitMetric("BatchJobIterations", (double) iteration, StandardUnit.COUNT);

                    log.info("[{}s] CPU: {:.1f}% | Iterations: {} | Customers processed: {}",
                        elapsed, cpuUsage, iteration, iteration * availableProcessors * 1000);
                }

                // Adaptive delay to hit target CPU
                double currentCpu = getCpuUsage();
                long delay = calculateDelay(currentCpu, targetCpu);

                if (delay > 0) {
                    Thread.sleep(delay);
                }
            }

            long totalTime = (System.currentTimeMillis() - startTime) / 1000;
            int totalCustomers = iteration * availableProcessors * 1000;

            log.info("========================================");
            log.info("✅ STRESS COMPLETE");
            log.info("Total time: {}s", totalTime);
            log.info("Total iterations: {}", iteration);
            log.info("Total customers processed: {}", totalCustomers);
            log.info("========================================");

            cloudWatchService.emitMetric("BatchJobCompleted", 1.0, StandardUnit.COUNT);

        } catch (Exception e) {
            log.error("Error during stress scenario", e);
            cloudWatchService.emitMetric("BatchJobError", 1.0, StandardUnit.COUNT);

        } finally {
            executorService.shutdown();
            stressRunning = false;
        }
    }

    /**
     * Process a batch of customers with CPU-intensive operations
     */
    private void processBatchOfCustomers(int threadNum, int batchSize) {
        Random random = new Random(threadNum);

        for (int i = 0; i < batchSize; i++) {
            String customerId = String.format("customer-%d-%d", threadNum, i);

            // 1. Complex tier multiplier calculation (floating point ops)
            double tierMultiplier = calculateTierMultiplier(customerId, random);

            // 2. Purchase bonus calculation with exponential decay
            double purchaseBonus = calculatePurchaseBonus(random);

            // 3. Fraud scoring with hash operations
            double fraudScore = calculateFraudScore(customerId, random);

            // 4. Final points calculation
            double points = tierMultiplier * purchaseBonus * (1.0 - fraudScore);

            // 5. Hash the result for "data integrity"
            String pointsStr = String.valueOf(points);
            String hash = DigestUtils.sha256Hex(pointsStr);

            // 6. More crypto operations
            for (int j = 0; j < 10; j++) {
                DigestUtils.sha256Hex(hash + j);
            }
        }
    }

    /**
     * CPU-intensive tier multiplier calculation
     */
    private double calculateTierMultiplier(String customerId, Random random) {
        double multiplier = 1.0;

        // Hash-based computation
        String hash = DigestUtils.sha256Hex(customerId);

        for (int i = 0; i < 1000; i++) {
            hash = DigestUtils.sha256Hex(hash + i);
            multiplier += (hash.hashCode() % 100) / 10000.0;
        }

        // Fibonacci calculation
        multiplier += fibonacci(20) / 10000.0;

        return multiplier;
    }

    /**
     * Purchase bonus with exponential calculations
     */
    private double calculatePurchaseBonus(Random random) {
        double bonus = 1.0;

        for (int i = 0; i < 5000; i++) {
            double purchaseAmount = random.nextDouble() * 100;
            bonus += Math.exp(purchaseAmount / 1000) * 0.001;
            bonus = bonus / 1.0001; // Keep it bounded
        }

        return bonus;
    }

    /**
     * Fraud scoring with extensive hash operations
     */
    private double calculateFraudScore(String customerId, Random random) {
        String data = customerId + random.nextInt(1000);

        // Multiple rounds of hashing
        for (int i = 0; i < 500; i++) {
            data = DigestUtils.sha256Hex(data);
            data = DigestUtils.md5Hex(data);
        }

        // Convert to score
        return (Math.abs(data.hashCode()) % 100) / 100.0;
    }

    /**
     * Recursive Fibonacci (CPU-intensive)
     */
    private long fibonacci(int n) {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }

    /**
     * Get current CPU usage percentage
     */
    private double getCpuUsage() {
        try {
            OperatingSystemMXBean osBean = (OperatingSystemMXBean)
                ManagementFactory.getOperatingSystemMXBean();
            double cpuUsage = osBean.getProcessCpuLoad() * 100;
            return cpuUsage >= 0 ? cpuUsage : 0.0;
        } catch (Exception e) {
            log.debug("Failed to get CPU usage", e);
            return 0.0;
        }
    }

    /**
     * Calculate adaptive delay to hit target CPU
     */
    private long calculateDelay(double currentCpu, int targetCpu) {
        if (currentCpu < targetCpu - 10) {
            return 1; // Too low, work harder
        } else if (currentCpu > targetCpu + 10) {
            return 100; // Too high, back off
        } else {
            return 10; // Just right
        }
    }
}
