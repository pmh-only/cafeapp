# CloudCafe Staff Portal - Complete Guide

## Overview

Comprehensive staff management system for CloudCafe operations, providing inventory management, staff scheduling, sales reporting, and menu administration.

**URL**: https://d11kzx6ndq7xox.cloudfront.net/staff/

---

## Features

### 1. Dashboard 📊

Real-time operational overview with key metrics:

- **Today's Sales**: Total revenue for current day
- **Orders**: Number of orders processed
- **Active Staff**: Currently on-duty employees
- **Low Stock Alerts**: Items requiring reorder

**Recent Activity Feed**:
- Inventory updates
- Staff changes
- System alerts
- Report generation

**Backend Integration**:
```
GET /staff/dashboard
Response: {
  todaySales: 2847.50,
  todayOrders: 156,
  activeStaff: 8,
  lowStockItems: 3
}
```

---

### 2. Inventory Management 📦

Complete inventory tracking and management system.

**Features**:
- View all inventory items from DynamoDB `store_inventory` table
- Real-time stock levels
- Low stock warnings (< minimum threshold)
- Last updated timestamps
- Quick update functionality
- Automated reorder system

**Inventory Items**:
- Coffee Beans (Arabica, Robusta)
- Dairy Products (Milk, Oat Milk, Almond Milk)
- Syrups (Caramel, Vanilla, Hazelnut)
- Supplies (Cups, Lids, Napkins)
- Condiments (Sugar, Sweeteners)

**Stock Status Indicators**:
- 🟢 **Good**: Stock > 1.5x minimum
- 🟡 **Warning**: Stock between minimum and 1.5x minimum
- 🔴 **Low Stock**: Stock < minimum threshold

**Actions**:
1. **Update Stock**: Manually adjust inventory levels
2. **Reorder**: Trigger automated reorder via SQS queue

**Backend Integration**:
```
GET  /inventory
Response: [
  {
    id: "1",
    name: "Coffee Beans (Arabica)",
    category: "Ingredients",
    stock: 45,
    minStock: 50,
    unit: "kg",
    lastUpdated: "2026-02-24T01:00:00Z"
  }
]

PUT  /inventory/{itemId}
Body: { stock: 100 }
Response: { success: true, updated: true }

POST /inventory/reorder
Body: { itemId: "1", quantity: 100 }
Response: { orderId: "PO-12345", status: "pending" }
```

**Data Flow**:
1. Staff views inventory → API Gateway → Lambda → DynamoDB
2. Low stock detected → Automatic alert
3. Staff clicks reorder → SQS message sent to supplier system
4. Supplier confirms → Inventory updated

---

### 3. Staff Management 👥

Employee scheduling and performance tracking.

**Features**:
- View all staff members
- Role assignments (Barista, Cashier, Supervisor)
- Shift schedules (Morning 6AM-2PM, Afternoon 2PM-10PM)
- Status tracking (On Duty, Off Duty)
- Performance ratings (1-5 stars)
- Schedule management

**Staff Roles**:
- **Barista**: Coffee preparation
- **Senior Barista**: Advanced drinks, training
- **Cashier**: Order taking, payments
- **Shift Supervisor**: Team management
- **Manager**: Overall operations

**Performance Metrics**:
- Customer ratings
- Order completion time
- Accuracy rate
- Attendance record

**Actions**:
1. **Edit Staff**: Update role, shift, contact info
2. **View Schedule**: See weekly schedule
3. **Add Staff**: Onboard new employees

**Backend Integration**:
```
GET  /staff
Response: [
  {
    id: "1",
    name: "Alex Chen",
    role: "Barista",
    shift: "Morning (6AM-2PM)",
    status: "active",
    performance: 4.9
  }
]

PUT  /staff/{staffId}
Body: { shift: "Afternoon (2PM-10PM)" }

GET  /staff/{staffId}/schedule
Response: {
  week: [
    { day: "Mon", shift: "Morning", hours: 8 },
    { day: "Tue", shift: "Morning", hours: 8 }
  ]
}
```

---

### 4. Menu Management ☕

Product catalog administration.

**Features**:
- View all menu items from DynamoDB `menu_catalog`
- Edit prices
- Enable/disable items
- Category organization
- Status management

**Menu Categories**:
- Coffee (Espresso, Latte, Cappuccino)
- Iced Coffee (Cold Brew, Iced Latte)
- Tea (Matcha, Chai, Herbal)
- Pastries (Croissants, Muffins, Cookies)
- Sandwiches
- Seasonal Specials

**Actions**:
1. **Edit Item**: Update price, description
2. **Toggle Status**: Enable/disable availability
3. **Add Item**: Create new menu item

**Backend Integration**:
```
GET  /menu
Response: [
  {
    id: "1",
    name: "Espresso",
    category: "Coffee",
    price: 3.50,
    status: "active",
    description: "Bold, intense coffee"
  }
]

PUT  /menu/{itemId}
Body: { price: 3.75 }

POST /menu
Body: {
  name: "Pumpkin Spice Latte",
  category: "Seasonal",
  price: 5.50,
  description: "Fall favorite"
}
```

---

### 5. Sales Reports 📈

Business intelligence and analytics.

**Features**:
- Date range selection
- Total sales calculation
- Order count
- Average order value
- Top selling items
- Export to CSV

**Report Metrics**:
- **Total Sales**: Revenue for period
- **Total Orders**: Number of transactions
- **Avg Order Value**: Sales / Orders
- **Top Items**: Best sellers by revenue
- **Peak Hours**: Busiest times
- **Staff Performance**: Sales by employee

**Export Options**:
- CSV format
- PDF report
- Email delivery
- Scheduled reports

**Backend Integration**:
```
GET  /reports/sales?start=2026-02-17&end=2026-02-24
Response: {
  totalSales: 19847.50,
  totalOrders: 1247,
  avgOrderValue: 15.91,
  topItems: [
    {
      name: "Caramel Macchiato",
      orders: 342,
      revenue: 1795.50
    }
  ],
  peakHours: [
    { hour: 8, orders: 156 },
    { hour: 9, orders: 142 }
  ]
}

POST /reports/export
Body: { format: "csv", dateRange: "..." }
Response: { downloadUrl: "s3://..." }
```

**Data Source**: Redshift data warehouse
- Historical order data
- Aggregated metrics
- Trend analysis
- Predictive analytics

---

## User Interface

### Navigation Tabs
- 📊 Dashboard
- 📦 Inventory
- 👥 Staff
- 📈 Reports
- ☕ Menu Management

### Design Features
- Responsive layout (desktop, tablet, mobile)
- Color-coded status indicators
- Real-time updates
- Modal dialogs for actions
- Loading states
- Error handling

### Color Scheme
- Primary: Purple gradient (#667eea → #764ba2)
- Secondary: Brown (#6f4e37)
- Success: Green (#27ae60)
- Warning: Orange (#f39c12)
- Danger: Red (#e74c3c)

---

## Backend Integration

### API Endpoints

#### Dashboard
```
GET /staff/dashboard
```

#### Inventory
```
GET  /inventory
GET  /inventory/{itemId}
PUT  /inventory/{itemId}
POST /inventory/reorder
```

#### Staff
```
GET  /staff
GET  /staff/{staffId}
PUT  /staff/{staffId}
POST /staff
GET  /staff/{staffId}/schedule
```

#### Menu
```
GET  /menu
GET  /menu/{itemId}
PUT  /menu/{itemId}
POST /menu
DELETE /menu/{itemId}
```

#### Reports
```
GET  /reports/sales
GET  /reports/inventory
GET  /reports/staff
POST /reports/export
```

### Data Sources

1. **DynamoDB Tables**:
   - `store_inventory`: Real-time stock levels
   - `menu_catalog`: Product information
   - `active_orders`: Current orders

2. **RDS Aurora**:
   - `staff`: Employee records
   - `schedules`: Shift assignments
   - `performance`: Ratings and metrics

3. **Redshift**:
   - Historical sales data
   - Aggregated analytics
   - Business intelligence

4. **SQS Queues**:
   - `inventory-reorder`: Supplier orders
   - `staff-notifications`: Employee alerts

5. **ElastiCache**:
   - Dashboard metrics caching
   - Session management

---

## Security

### Access Control
- Manager-level access required
- Role-based permissions
- Session management
- Audit logging

### Authentication (Planned)
- Cognito user pools
- JWT tokens
- Multi-factor authentication
- Password policies

### Data Protection
- HTTPS-only access
- Encrypted data at rest
- Secure API calls
- Input validation

---

## Usage Examples

### Update Inventory
1. Navigate to Inventory tab
2. Find item with low stock
3. Click "Update" button
4. Enter new stock quantity
5. Confirm update
6. System updates DynamoDB
7. Alert cleared if stock sufficient

### Generate Sales Report
1. Navigate to Reports tab
2. Select date range
3. Click "Generate Report"
4. View metrics and top items
5. Click "Export to CSV"
6. Download report file

### Manage Staff Schedule
1. Navigate to Staff tab
2. Find staff member
3. Click "Schedule" button
4. View weekly schedule
5. Make adjustments
6. Save changes

---

## Mobile Responsiveness

The staff portal is fully responsive:

- **Desktop** (>1200px): Full layout with all features
- **Tablet** (768px-1200px): Optimized grid layout
- **Mobile** (<768px): Stacked layout, touch-friendly

---

## Performance

### Optimization
- CloudFront CDN caching (5 min TTL)
- Lazy loading for large tables
- Pagination for inventory/staff lists
- Debounced search inputs
- Optimistic UI updates

### Monitoring
- CloudWatch metrics
- Error tracking
- Performance monitoring
- User analytics

---

## Future Enhancements

### Planned Features
1. **Advanced Analytics**:
   - Predictive inventory
   - Sales forecasting
   - Staff optimization

2. **Automation**:
   - Auto-reorder triggers
   - Smart scheduling
   - Price optimization

3. **Mobile App**:
   - Native iOS/Android
   - Push notifications
   - Offline mode

4. **Integrations**:
   - Accounting software
   - Payroll systems
   - Supplier portals

---

## Troubleshooting

### Common Issues

**Inventory not loading**:
- Check DynamoDB connection
- Verify IAM permissions
- Check CloudWatch logs

**Reports timing out**:
- Reduce date range
- Check Redshift cluster status
- Optimize queries

**Staff updates failing**:
- Verify RDS connection
- Check input validation
- Review error messages

---

## Support

For technical support:
- Check CloudWatch logs
- Review API Gateway metrics
- Contact system administrator

---

**Deployment**: ✅ Live at https://d11kzx6ndq7xox.cloudfront.net/staff/
**Status**: Operational
**Region**: ap-northeast-2 (Seoul)
**Last Updated**: February 24, 2026
