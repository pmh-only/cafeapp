package com.cloudcafe.repository;

import com.cloudcafe.model.LoyaltyAccount;
import com.cloudcafe.model.LoyaltyAccount.LoyaltyTier;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * Repository for loyalty account persistence
 */
@Repository
public interface LoyaltyAccountRepository extends JpaRepository<LoyaltyAccount, Long> {

    /**
     * Find account by customer ID
     */
    Optional<LoyaltyAccount> findByCustomerId(String customerId);

    /**
     * Find all accounts by tier
     */
    List<LoyaltyAccount> findByTier(LoyaltyTier tier);

    /**
     * Count accounts by tier
     */
    long countByTier(LoyaltyTier tier);

    /**
     * Find accounts with points balance above threshold
     */
    List<LoyaltyAccount> findByPointsBalanceGreaterThan(Integer threshold);

    /**
     * Get total points across all accounts
     */
    @Query("SELECT SUM(a.pointsBalance) FROM LoyaltyAccount a")
    Long sumAllPoints();

    /**
     * Get average points by tier
     */
    @Query("SELECT AVG(a.pointsBalance) FROM LoyaltyAccount a WHERE a.tier = ?1")
    Double averagePointsByTier(LoyaltyTier tier);
}
