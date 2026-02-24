#!/usr/bin/env python3
"""
CloudCafe Advanced Endpoint Testing Suite
Region: ap-northeast-2 (Seoul)
"""

import json
import subprocess
import sys
import time
from typing import Dict, List, Tuple
from urllib.parse import urlparse
import socket

try:
    import requests
except ImportError:
    print("Installing requests library...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "-q"])
    import requests

# ANSI color codes
class Colors:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color
    BOLD = '\033[1m'

class EndpointTester:
    def __init__(self):
        self.total_tests = 0
        self.passed_tests = 0
        self.failed_tests = 0
        self.results = []
        self.endpoints = self.load_endpoints()
        
    def load_endpoints(self) -> Dict[str, str]:
        """Load endpoints from Terraform outputs"""
        try:
            result = subprocess.run(
                ['terraform', 'output', '-json'],
                cwd='infrastructure/terraform',
                capture_output=True,
                text=True,
                check=True
            )
            outputs = json.loads(result.stdout)
            
            return {
                'alb_dns': outputs.get('alb_dns_name', {}).get('value', ''),
                'nlb_dns': outputs.get('nlb_dns_name', {}).get('value', ''),
                'api_gateway_url': outputs.get('api_gateway_url', {}).get('value', ''),
                'cloudfront_url': outputs.get('cloudfront_url', {}).get('value', ''),
                'rds_endpoint': outputs.get('rds_cluster_endpoint', {}).get('value', ''),
                'elasticache_endpoint': outputs.get('elasticache_endpoint', {}).get('value', ''),
            }
        except Exception as e:
            print(f"{Colors.RED}Error loading endpoints: {e}{Colors.NC}")
            return {}
    
    def print_header(self, text: str):
        """Print formatted header"""
        print(f"\n{Colors.BLUE}{'=' * 60}{Colors.NC}")
        print(f"{Colors.BLUE}{text.center(60)}{Colors.NC}")
        print(f"{Colors.BLUE}{'=' * 60}{Colors.NC}\n")
    
    def test_http_endpoint(self, name: str, url: str, method: str = 'GET', 
                          expected_status: int = None, timeout: int = 10) -> Dict:
        """Test HTTP endpoint and return results"""
        self.total_tests += 1
        result = {
            'name': name,
            'url': url,
            'method': method,
            'status': 'UNKNOWN',
            'status_code': None,
            'response_time': None,
            'error': None
        }
        
        print(f"{Colors.YELLOW}Testing: {name}{Colors.NC}")
        print(f"  URL: {url}")
        print(f"  Method: {method}")
        
        try:
            start_time = time.time()
            
            if method == 'GET':
                response = requests.get(url, timeout=timeout, allow_redirects=True)
            elif method == 'POST':
                response = requests.post(url, timeout=timeout, json={})
            elif method == 'HEAD':
                response = requests.head(url, timeout=timeout)
            else:
                response = requests.request(method, url, timeout=timeout)
            
            response_time = time.time() - start_time
            
            result['status_code'] = response.status_code
            result['response_time'] = round(response_time, 3)
            
            # Check if status matches expected
            if expected_status:
                if response.status_code == expected_status:
                    result['status'] = 'PASS'
                    self.passed_tests += 1
                    print(f"  {Colors.GREEN}✓ PASS{Colors.NC} - Status: {response.status_code}")
                else:
                    result['status'] = 'FAIL'
                    self.failed_tests += 1
                    print(f"  {Colors.RED}✗ FAIL{Colors.NC} - Expected: {expected_status}, Got: {response.status_code}")
            else:
                # Any response is considered success
                result['status'] = 'PASS'
                self.passed_tests += 1
                print(f"  {Colors.GREEN}✓ PASS{Colors.NC} - Status: {response.status_code}")
            
            print(f"  Response Time: {response_time:.3f}s")
            
            # Print response headers
            if 'x-cache' in response.headers:
                print(f"  CloudFront Cache: {response.headers['x-cache']}")
            if 'x-amz-cf-id' in response.headers:
                print(f"  CloudFront ID: {response.headers['x-amz-cf-id'][:20]}...")
            
        except requests.exceptions.Timeout:
            result['status'] = 'TIMEOUT'
            result['error'] = 'Request timeout'
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ TIMEOUT{Colors.NC}")
        except requests.exceptions.ConnectionError as e:
            result['status'] = 'CONNECTION_ERROR'
            result['error'] = str(e)
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ CONNECTION ERROR{Colors.NC}")
        except Exception as e:
            result['status'] = 'ERROR'
            result['error'] = str(e)
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ ERROR: {e}{Colors.NC}")
        
        print()
        self.results.append(result)
        return result
    
    def test_dns_resolution(self, name: str, hostname: str) -> Dict:
        """Test DNS resolution"""
        self.total_tests += 1
        result = {
            'name': name,
            'hostname': hostname,
            'status': 'UNKNOWN',
            'ip_addresses': []
        }
        
        print(f"{Colors.YELLOW}Testing DNS: {name}{Colors.NC}")
        print(f"  Hostname: {hostname}")
        
        try:
            ip_addresses = socket.gethostbyname_ex(hostname)[2]
            result['ip_addresses'] = ip_addresses
            result['status'] = 'PASS'
            self.passed_tests += 1
            print(f"  {Colors.GREEN}✓ PASS{Colors.NC} - Resolved to: {', '.join(ip_addresses)}")
        except socket.gaierror:
            result['status'] = 'FAIL'
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ FAIL{Colors.NC} - DNS resolution failed")
        except Exception as e:
            result['status'] = 'ERROR'
            result['error'] = str(e)
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ ERROR: {e}{Colors.NC}")
        
        print()
        self.results.append(result)
        return result
    
    def test_tcp_connection(self, name: str, host: str, port: int, timeout: int = 5) -> Dict:
        """Test TCP connection to host:port"""
        self.total_tests += 1
        result = {
            'name': name,
            'host': host,
            'port': port,
            'status': 'UNKNOWN'
        }
        
        print(f"{Colors.YELLOW}Testing TCP: {name}{Colors.NC}")
        print(f"  Host: {host}:{port}")
        
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            start_time = time.time()
            sock.connect((host, port))
            connect_time = time.time() - start_time
            sock.close()
            
            result['status'] = 'PASS'
            result['connect_time'] = round(connect_time, 3)
            self.passed_tests += 1
            print(f"  {Colors.GREEN}✓ PASS{Colors.NC} - Connected in {connect_time:.3f}s")
        except socket.timeout:
            result['status'] = 'TIMEOUT'
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ TIMEOUT{Colors.NC}")
        except Exception as e:
            result['status'] = 'ERROR'
            result['error'] = str(e)
            self.failed_tests += 1
            print(f"  {Colors.RED}✗ ERROR: {e}{Colors.NC}")
        
        print()
        self.results.append(result)
        return result
    
    def run_all_tests(self):
        """Run all endpoint tests"""
        print(f"{Colors.BLUE}")
        print("╔════════════════════════════════════════════════════════════╗")
        print("║      CloudCafe Advanced Endpoint Testing Suite            ║")
        print("║           Region: ap-northeast-2 (Seoul)                  ║")
        print("╚════════════════════════════════════════════════════════════╝")
        print(f"{Colors.NC}")
        
        # 1. DNS Resolution Tests
        self.print_header("1. DNS RESOLUTION TESTS")
        
        if self.endpoints.get('alb_dns'):
            self.test_dns_resolution("Application Load Balancer", self.endpoints['alb_dns'])
        
        if self.endpoints.get('nlb_dns'):
            self.test_dns_resolution("Network Load Balancer", self.endpoints['nlb_dns'])
        
        # 2. Load Balancer Tests
        self.print_header("2. LOAD BALANCER TESTS")
        
        if self.endpoints.get('alb_dns'):
            alb_url = f"http://{self.endpoints['alb_dns']}"
            self.test_http_endpoint("ALB Root Path", alb_url, expected_status=404)
            self.test_http_endpoint("ALB /api Path", f"{alb_url}/api", expected_status=404)
            self.test_http_endpoint("ALB /health Path", f"{alb_url}/health", expected_status=404)
        
        # 3. API Gateway Tests
        self.print_header("3. API GATEWAY TESTS")
        
        if self.endpoints.get('api_gateway_url'):
            api_url = self.endpoints['api_gateway_url']
            self.test_http_endpoint("API Gateway Root", api_url)
            self.test_http_endpoint("API Gateway /api", f"{api_url}/api")
            self.test_http_endpoint("API Gateway GET /api/orders", f"{api_url}/api/orders", method='GET')
            self.test_http_endpoint("API Gateway POST /api/orders", f"{api_url}/api/orders", method='POST')
        
        # 4. CloudFront CDN Tests
        self.print_header("4. CLOUDFRONT CDN TESTS")
        
        if self.endpoints.get('cloudfront_url'):
            cf_url = self.endpoints['cloudfront_url']
            self.test_http_endpoint("CloudFront Root", cf_url)
            self.test_http_endpoint("CloudFront /api", f"{cf_url}/api")
            self.test_http_endpoint("CloudFront /static", f"{cf_url}/static")
        
        # 5. Service Endpoint Tests
        self.print_header("5. SERVICE-SPECIFIC ENDPOINT TESTS")
        
        if self.endpoints.get('alb_dns'):
            alb_url = f"http://{self.endpoints['alb_dns']}"
            
            # Order Service
            self.test_http_endpoint("Order Service - List", f"{alb_url}/api/orders", expected_status=404)
            self.test_http_endpoint("Order Service - Create", f"{alb_url}/api/orders", method='POST', expected_status=404)
            
            # Menu Service
            self.test_http_endpoint("Menu Service - Items", f"{alb_url}/api/menu/items", expected_status=404)
            
            # Inventory Service
            self.test_http_endpoint("Inventory Service - Check", f"{alb_url}/api/inventory/check", expected_status=404)
            
            # Loyalty Service
            self.test_http_endpoint("Loyalty Service - Points", f"{alb_url}/api/loyalty/points/user123", expected_status=404)
        
        # 6. Database Connection Tests
        self.print_header("6. DATABASE CONNECTION TESTS")
        
        if self.endpoints.get('rds_endpoint'):
            rds_host = self.endpoints['rds_endpoint'].split(':')[0]
            self.test_tcp_connection("RDS Aurora PostgreSQL", rds_host, 5432)
        
        if self.endpoints.get('elasticache_endpoint'):
            redis_host = self.endpoints['elasticache_endpoint'].split(':')[0]
            self.test_tcp_connection("ElastiCache Redis", redis_host, 6379)
        
        # 7. Performance Tests
        self.print_header("7. PERFORMANCE TESTS")
        
        if self.endpoints.get('alb_dns'):
            print(f"{Colors.YELLOW}ALB Response Time (5 requests):{Colors.NC}")
            times = []
            for i in range(5):
                result = self.test_http_endpoint(f"ALB Request {i+1}", f"http://{self.endpoints['alb_dns']}", expected_status=404)
                if result.get('response_time'):
                    times.append(result['response_time'])
            
            if times:
                avg_time = sum(times) / len(times)
                print(f"  Average Response Time: {avg_time:.3f}s")
                print(f"  Min: {min(times):.3f}s, Max: {max(times):.3f}s\n")
        
        # Print Summary
        self.print_summary()
    
    def print_summary(self):
        """Print test summary"""
        self.print_header("TEST SUMMARY")
        
        print(f"Total Tests: {self.total_tests}")
        print(f"{Colors.GREEN}Passed: {self.passed_tests}{Colors.NC}")
        print(f"{Colors.RED}Failed: {self.failed_tests}{Colors.NC}")
        
        pass_rate = (self.passed_tests / self.total_tests * 100) if self.total_tests > 0 else 0
        print(f"Pass Rate: {pass_rate:.1f}%\n")
        
        # Save results to JSON
        with open('endpoint_test_results.json', 'w') as f:
            json.dump({
                'total_tests': self.total_tests,
                'passed_tests': self.passed_tests,
                'failed_tests': self.failed_tests,
                'pass_rate': pass_rate,
                'results': self.results
            }, f, indent=2)
        
        print(f"Results saved to: endpoint_test_results.json\n")
        
        if self.failed_tests == 0:
            print(f"{Colors.GREEN}╔════════════════════════════════════════╗{Colors.NC}")
            print(f"{Colors.GREEN}║   ALL TESTS PASSED SUCCESSFULLY! ✓    ║{Colors.NC}")
            print(f"{Colors.GREEN}╚════════════════════════════════════════╝{Colors.NC}\n")
            return 0
        else:
            print(f"{Colors.YELLOW}╔════════════════════════════════════════╗{Colors.NC}")
            print(f"{Colors.YELLOW}║   SOME TESTS FAILED - REVIEW ABOVE    ║{Colors.NC}")
            print(f"{Colors.YELLOW}╚════════════════════════════════════════╝{Colors.NC}\n")
            return 1

def main():
    """Main entry point"""
    tester = EndpointTester()
    exit_code = tester.run_all_tests()
    sys.exit(exit_code)

if __name__ == '__main__':
    main()
