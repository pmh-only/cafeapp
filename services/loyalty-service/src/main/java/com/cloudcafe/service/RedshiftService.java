package com.cloudcafe.service;

import com.cloudcafe.model.LoyaltyAccount.LoyaltyTier;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.redshiftdata.RedshiftDataClient;
import software.amazon.awssdk.services.redshiftdata.model.ExecuteStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.ExecuteStatementResponse;

import java.time.Instant;

/**
 * Service for writing analytics data to Redshift
 */
@Service
@Slf4j
public class RedshiftService {

    private final RedshiftDataClient redshiftDataClient;
    private final String clusterIdentifier;
    private final String database;
    private final String dbUser;

    public RedshiftService(
        RedshiftDataClient redshiftDataClient,
        @Value("${redshift.cluster-identifier:cloudcafe-redshift-dev}") String clusterIdentifier,
        @Value("${redshift.database:analytics}") String database,
        @Value("${redshift.db-user:admin}") String dbUser
    ) {
        this.redshiftDataClient = redshiftDataClient;
        this.clusterIdentifier = clusterIdentifier;
        this.database = database;
        this.dbUser = dbUser;
    }

    /**
     * Write points transaction to Redshift analytics table (async)
     */
    @Async
    public void writePointsTransaction(String customerId, String orderId, int pointsEarned, LoyaltyTier tier) {
        try {
            String sql = String.format(
                "INSERT INTO fact_loyalty_transactions " +
                "(customer_id, order_id, points_earned, tier, transaction_date) " +
                "VALUES ('%s', '%s', %d, '%s', '%s')",
                customerId.replace("'", "''"),
                orderId.replace("'", "''"),
                pointsEarned,
                tier.name(),
                Instant.now().toString()
            );

            ExecuteStatementRequest request = ExecuteStatementRequest.builder()
                .clusterIdentifier(clusterIdentifier)
                .database(database)
                .dbUser(dbUser)
                .sql(sql)
                .build();

            ExecuteStatementResponse response = redshiftDataClient.executeStatement(request);

            log.debug("Wrote loyalty transaction to Redshift: {} (Statement ID: {})",
                orderId, response.id());

        } catch (Exception e) {
            log.error("Failed to write loyalty transaction to Redshift: {}", orderId, e);
            // Don't throw - this is async analytics, shouldn't fail main request
        }
    }

    /**
     * Write tier change event to Redshift
     */
    @Async
    public void writeTierChange(String customerId, LoyaltyTier oldTier, LoyaltyTier newTier, int lifetimePoints) {
        try {
            String sql = String.format(
                "INSERT INTO fact_tier_changes " +
                "(customer_id, old_tier, new_tier, lifetime_points, change_date) " +
                "VALUES ('%s', '%s', '%s', %d, '%s')",
                customerId.replace("'", "''"),
                oldTier.name(),
                newTier.name(),
                lifetimePoints,
                Instant.now().toString()
            );

            ExecuteStatementRequest request = ExecuteStatementRequest.builder()
                .clusterIdentifier(clusterIdentifier)
                .database(database)
                .dbUser(dbUser)
                .sql(sql)
                .build();

            ExecuteStatementResponse response = redshiftDataClient.executeStatement(request);

            log.debug("Wrote tier change to Redshift for customer {} (Statement ID: {})",
                customerId, response.id());

        } catch (Exception e) {
            log.error("Failed to write tier change to Redshift for customer: {}", customerId, e);
        }
    }

    /**
     * Execute custom analytics query
     */
    public String executeQuery(String sql) {
        try {
            ExecuteStatementRequest request = ExecuteStatementRequest.builder()
                .clusterIdentifier(clusterIdentifier)
                .database(database)
                .dbUser(dbUser)
                .sql(sql)
                .build();

            ExecuteStatementResponse response = redshiftDataClient.executeStatement(request);

            log.info("Executed Redshift query, Statement ID: {}", response.id());
            return response.id();

        } catch (Exception e) {
            log.error("Failed to execute Redshift query", e);
            throw new RuntimeException("Redshift query execution failed", e);
        }
    }
}
