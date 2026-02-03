package com.cloudcafe.controller;

import com.cloudcafe.model.LoyaltyAccount;
import com.cloudcafe.model.LoyaltyAccount.LoyaltyTier;
import com.cloudcafe.repository.LoyaltyAccountRepository;
import com.cloudcafe.service.CloudWatchService;
import com.cloudcafe.service.RedshiftService;
import com.cloudcafe.service.StressScenarioService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * REST controller for loyalty operations
 */
@RestController
@RequestMapping("/loyalty")
@RequiredArgsConstructor
@Slf4j
public class LoyaltyController {

    private final LoyaltyAccountRepository accountRepository;
    private final CloudWatchService cloudWatchService;
    private final RedshiftService redshiftService;
    private final StressScenarioService stressScenarioService;

    /**
     * Health check endpoint
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "healthy");
        health.put("service", "loyalty-service");
        health.put("timestamp", Instant.now().toString());

        // Check database connectivity
        try {
            long accountCount = accountRepository.count();
            health.put("database", Map.of(
                "connected", true,
                "account_count", accountCount
            ));
        } catch (Exception e) {
            health.put("database", Map.of(
                "connected", false,
                "error", e.getMessage()
            ));
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(health);
        }

        return ResponseEntity.ok(health);
    }

    /**
     * Get loyalty account by customer ID
     */
    @GetMapping("/points/{customerId}")
    public ResponseEntity<Map<String, Object>> getPoints(@PathVariable String customerId) {
        long startTime = System.currentTimeMillis();

        try {
            Optional<LoyaltyAccount> accountOpt = accountRepository.findByCustomerId(customerId);

            if (accountOpt.isEmpty()) {
                cloudWatchService.emitMetric("AccountNotFound", 1.0);
                return ResponseEntity.notFound().build();
            }

            LoyaltyAccount account = accountOpt.get();
            long duration = System.currentTimeMillis() - startTime;

            cloudWatchService.emitMetric("QueryDuration", (double) duration);
            cloudWatchService.emitMetric("PointsRetrieved", 1.0);

            Map<String, Object> response = new HashMap<>();
            response.put("customer_id", account.getCustomerId());
            response.put("points_balance", account.getPointsBalance());
            response.put("lifetime_points", account.getLifetimePoints());
            response.put("tier", account.getTier().name());
            response.put("tier_multiplier", account.getTierMultiplier());
            response.put("last_purchase_date", account.getLastPurchaseDate());
            response.put("duration_ms", duration);

            log.info("Retrieved points for customer: {} - Balance: {}, Tier: {}",
                customerId, account.getPointsBalance(), account.getTier());

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Error retrieving points for customer: {}", customerId, e);
            cloudWatchService.emitMetric("QueryError", 1.0);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Accrue loyalty points from an order
     */
    @PostMapping("/accrue")
    public ResponseEntity<Map<String, Object>> accruePoints(@RequestBody Map<String, Object> request) {
        long startTime = System.currentTimeMillis();

        try {
            String customerId = (String) request.get("customer_id");
            Double orderAmount = ((Number) request.get("order_amount")).doubleValue();
            String orderId = (String) request.get("order_id");

            // Get or create account
            LoyaltyAccount account = accountRepository.findByCustomerId(customerId)
                .orElseGet(() -> {
                    LoyaltyAccount newAccount = new LoyaltyAccount();
                    newAccount.setCustomerId(customerId);
                    return newAccount;
                });

            // Calculate base points (1 point per dollar)
            int basePoints = (int) Math.floor(orderAmount);

            // Apply tier multiplier
            int earnedPoints = (int) Math.floor(basePoints * account.getTierMultiplier());

            // Update account
            account.setPointsBalance(account.getPointsBalance() + earnedPoints);
            account.setLifetimePoints(account.getLifetimePoints() + earnedPoints);
            account.setLastPurchaseDate(Instant.now());

            // Recalculate tier
            LoyaltyTier newTier = LoyaltyTier.fromLifetimePoints(account.getLifetimePoints());
            boolean tierChanged = !newTier.equals(account.getTier());

            if (tierChanged) {
                log.info("Customer {} upgraded from {} to {}",
                    customerId, account.getTier(), newTier);
                account.setTier(newTier);
                account.setTierMultiplier(newTier.getMultiplier());
                cloudWatchService.emitMetric("TierUpgrade", 1.0);
            }

            // Save to RDS
            account = accountRepository.save(account);

            // Write analytics to Redshift (async)
            redshiftService.writePointsTransaction(customerId, orderId, earnedPoints, newTier);

            long duration = System.currentTimeMillis() - startTime;

            cloudWatchService.emitMetric("PointsAccrued", (double) earnedPoints);
            cloudWatchService.emitMetric("AccrualDuration", (double) duration);

            Map<String, Object> response = new HashMap<>();
            response.put("customer_id", customerId);
            response.put("points_earned", earnedPoints);
            response.put("new_balance", account.getPointsBalance());
            response.put("lifetime_points", account.getLifetimePoints());
            response.put("tier", account.getTier().name());
            response.put("tier_changed", tierChanged);
            response.put("duration_ms", duration);

            log.info("Accrued {} points for customer: {} (Order: {})",
                earnedPoints, customerId, orderId);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Error accruing points", e);
            cloudWatchService.emitMetric("AccrualError", 1.0);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Redeem loyalty points
     */
    @PostMapping("/redeem")
    public ResponseEntity<Map<String, Object>> redeemPoints(@RequestBody Map<String, Object> request) {
        try {
            String customerId = (String) request.get("customer_id");
            Integer pointsToRedeem = ((Number) request.get("points")).intValue();

            Optional<LoyaltyAccount> accountOpt = accountRepository.findByCustomerId(customerId);

            if (accountOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }

            LoyaltyAccount account = accountOpt.get();

            if (account.getPointsBalance() < pointsToRedeem) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "Insufficient points balance"));
            }

            account.setPointsBalance(account.getPointsBalance() - pointsToRedeem);
            account = accountRepository.save(account);

            cloudWatchService.emitMetric("PointsRedeemed", (double) pointsToRedeem);

            log.info("Redeemed {} points for customer: {}", pointsToRedeem, customerId);

            return ResponseEntity.ok(Map.of(
                "customer_id", customerId,
                "points_redeemed", pointsToRedeem,
                "new_balance", account.getPointsBalance()
            ));

        } catch (Exception e) {
            log.error("Error redeeming points", e);
            cloudWatchService.emitMetric("RedemptionError", 1.0);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get tier statistics
     */
    @GetMapping("/stats/tiers")
    public ResponseEntity<Map<String, Object>> getTierStats() {
        try {
            Map<String, Object> stats = new HashMap<>();

            for (LoyaltyTier tier : LoyaltyTier.values()) {
                long count = accountRepository.countByTier(tier);
                Double avgPoints = accountRepository.averagePointsByTier(tier);

                stats.put(tier.name(), Map.of(
                    "count", count,
                    "average_points", avgPoints != null ? avgPoints : 0.0
                ));
            }

            Long totalPoints = accountRepository.sumAllPoints();
            stats.put("total_points_outstanding", totalPoints != null ? totalPoints : 0L);

            return ResponseEntity.ok(stats);

        } catch (Exception e) {
            log.error("Error retrieving tier stats", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Trigger CPU stress scenario: Loyalty Batch Calculation
     */
    @PostMapping("/stress/batch-calculation")
    public ResponseEntity<Map<String, Object>> triggerStressScenario(@RequestBody Map<String, Object> request) {
        try {
            Integer durationSeconds = request.containsKey("duration_seconds") ?
                ((Number) request.get("duration_seconds")).intValue() : 720; // 12 minutes default
            Integer targetCpu = request.containsKey("target_cpu") ?
                ((Number) request.get("target_cpu")).intValue() : 100;

            log.info("========================================");
            log.info("STRESS SCENARIO TRIGGERED: Loyalty Batch Calculation");
            log.info("Duration: {} seconds, Target CPU: {}%", durationSeconds, targetCpu);
            log.info("========================================");

            // Run stress scenario in background thread
            new Thread(() -> {
                stressScenarioService.simulateBatchCalculation(durationSeconds, targetCpu);
            }).start();

            return ResponseEntity.ok(Map.of(
                "status", "stress_scenario_started",
                "scenario", "loyalty_batch_calculation",
                "duration_seconds", durationSeconds,
                "target_cpu", targetCpu,
                "story", "Hourly recalculation for 10M customers. EC2 hits 100% CPU."
            ));

        } catch (Exception e) {
            log.error("Error triggering stress scenario", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", e.getMessage()));
        }
    }
}
