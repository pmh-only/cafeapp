package com.cloudcafe.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

/**
 * Loyalty account entity representing a customer's points and tier status
 */
@Entity
@Table(name = "loyalty_accounts", indexes = {
    @Index(name = "idx_customer_id", columnList = "customer_id"),
    @Index(name = "idx_tier", columnList = "tier")
})
@Data
@NoArgsConstructor
@AllArgsConstructor
public class LoyaltyAccount {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "customer_id", nullable = false, unique = true, length = 100)
    private String customerId;

    @Column(name = "points_balance", nullable = false)
    private Integer pointsBalance = 0;

    @Column(name = "lifetime_points", nullable = false)
    private Integer lifetimePoints = 0;

    @Enumerated(EnumType.STRING)
    @Column(name = "tier", nullable = false, length = 20)
    private LoyaltyTier tier = LoyaltyTier.BRONZE;

    @Column(name = "tier_multiplier", nullable = false)
    private Double tierMultiplier = 1.0;

    @Column(name = "last_purchase_date")
    private Instant lastPurchaseDate;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @PreUpdate
    public void preUpdate() {
        updatedAt = Instant.now();
    }

    public enum LoyaltyTier {
        BRONZE(1.0),
        SILVER(1.5),
        GOLD(2.0),
        PLATINUM(2.5);

        private final double multiplier;

        LoyaltyTier(double multiplier) {
            this.multiplier = multiplier;
        }

        public double getMultiplier() {
            return multiplier;
        }

        /**
         * Calculate tier based on lifetime points
         */
        public static LoyaltyTier fromLifetimePoints(int points) {
            if (points >= 10000) return PLATINUM;
            if (points >= 5000) return GOLD;
            if (points >= 1000) return SILVER;
            return BRONZE;
        }
    }
}
