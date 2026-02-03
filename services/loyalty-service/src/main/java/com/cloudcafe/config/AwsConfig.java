package com.cloudcafe.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudwatch.CloudWatchClient;
import software.amazon.awssdk.services.redshiftdata.RedshiftDataClient;

/**
 * AWS SDK configuration
 */
@Configuration
public class AwsConfig {

    @Bean
    public CloudWatchClient cloudWatchClient() {
        return CloudWatchClient.builder()
            .region(Region.US_EAST_1)
            .credentialsProvider(DefaultCredentialsProvider.create())
            .build();
    }

    @Bean
    public RedshiftDataClient redshiftDataClient() {
        return RedshiftDataClient.builder()
            .region(Region.US_EAST_1)
            .credentialsProvider(DefaultCredentialsProvider.create())
            .build();
    }
}
