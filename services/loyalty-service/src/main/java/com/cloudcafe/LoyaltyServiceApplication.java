package com.cloudcafe;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * CloudCafe Loyalty Service
 *
 * Manages customer loyalty points, tier calculations, and rewards.
 * Deployed on EC2 with Auto Scaling for variable workloads.
 */
@SpringBootApplication
@EnableScheduling
public class LoyaltyServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(LoyaltyServiceApplication.class, args);
    }
}
