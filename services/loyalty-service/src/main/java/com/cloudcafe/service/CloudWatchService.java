package com.cloudcafe.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.cloudwatch.CloudWatchClient;
import software.amazon.awssdk.services.cloudwatch.model.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Service for emitting CloudWatch custom metrics
 */
@Service
@Slf4j
public class CloudWatchService {

    private final CloudWatchClient cloudWatchClient;
    private final String environment;

    public CloudWatchService(
        CloudWatchClient cloudWatchClient,
        @Value("${cloudcafe.environment:dev}") String environment
    ) {
        this.cloudWatchClient = cloudWatchClient;
        this.environment = environment;
    }

    /**
     * Emit a single metric to CloudWatch
     */
    public void emitMetric(String metricName, Double value) {
        emitMetric(metricName, value, StandardUnit.COUNT);
    }

    /**
     * Emit a metric with custom unit
     */
    public void emitMetric(String metricName, Double value, StandardUnit unit) {
        try {
            MetricDatum datum = MetricDatum.builder()
                .metricName(metricName)
                .value(value)
                .unit(unit)
                .timestamp(Instant.now())
                .dimensions(
                    Dimension.builder()
                        .name("Environment")
                        .value(environment)
                        .build()
                )
                .build();

            PutMetricDataRequest request = PutMetricDataRequest.builder()
                .namespace("CloudCafe/Loyalty")
                .metricData(datum)
                .build();

            cloudWatchClient.putMetricData(request);

            log.debug("Emitted CloudWatch metric: {} = {} {}", metricName, value, unit);

        } catch (Exception e) {
            log.error("Failed to emit CloudWatch metric: {}", metricName, e);
        }
    }

    /**
     * Emit multiple metrics in a batch
     */
    public void emitMetrics(List<MetricDatum> metrics) {
        if (metrics.isEmpty()) {
            return;
        }

        try {
            PutMetricDataRequest request = PutMetricDataRequest.builder()
                .namespace("CloudCafe/Loyalty")
                .metricData(metrics)
                .build();

            cloudWatchClient.putMetricData(request);

            log.debug("Emitted {} CloudWatch metrics", metrics.size());

        } catch (Exception e) {
            log.error("Failed to emit CloudWatch metrics batch", e);
        }
    }

    /**
     * Create a metric datum builder with common dimensions
     */
    public MetricDatum.Builder createMetricBuilder(String metricName, Double value, StandardUnit unit) {
        return MetricDatum.builder()
            .metricName(metricName)
            .value(value)
            .unit(unit)
            .timestamp(Instant.now())
            .dimensions(
                Dimension.builder()
                    .name("Environment")
                    .value(environment)
                    .build()
            );
    }
}
