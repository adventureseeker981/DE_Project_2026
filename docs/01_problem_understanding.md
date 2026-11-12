# Phase 1: Problem Understanding

## Business Problems Analysis

### P1: Search and Category Pages Performance
**Stakeholders:** Customers, Category Managers  
**Business Need:** Fast product discovery through search and browsing across nested categories  
**Classification:** Customer-facing / Real-time  
**Affected Queries:** R01, R02, R14  
**Issue:** Recursive category traversal and text search without proper indexing causes sluggish page loads, impacting customer experience and conversion rates.

### P2: Product Page Load Times
**Stakeholders:** Customers  
**Business Need:** Quick access to product ratings breakdown and related product recommendations  
**Classification:** Customer-facing / Real-time  
**Affected Queries:** R03, R11, R24  
**Issue:** Aggregating reviews and finding frequently bought together items for popular products requires scanning large datasets, causing delays on high-traffic product pages.

### P3: Order History Performance
**Stakeholders:** Customers  
**Business Need:** Fast access to personal order history and order details  
**Classification:** Customer-facing / Real-time  
**Affected Queries:** R04, R23  
**Issue:** Joining orders with order items without proper indexing on customer_id causes slow "Your Orders" page loads, frustrating customers checking order status.

### P4: Seller Dashboard Delays
**Stakeholders:** Sellers  
**Business Need:** Real-time access to sales data, inventory status, and pricing tools  
**Classification:** Reporting / Analytics (with some real-time elements)  
**Affected Queries:** R06, R07, R15, W02, W03  
**Issue:** Sellers cannot efficiently monitor their business metrics, manage inventory, or adjust pricing due to slow dashboard queries.

### P5: Logistics Operations Bottlenecks
**Stakeholders:** Logistics Team  
**Business Need:** Identify delayed shipments and manage packing queue efficiently  
**Classification:** Reporting / Analytics (time-sensitive)  
**Affected Queries:** R05, R21, W05  
**Issue:** Without indexed status and date fields, finding stuck shipments requires full table scans, delaying response to delivery issues.

### P6: Data Quality Issues
**Stakeholders:** Admin, Data Quality Team  
**Business Need:** Identify unused addresses for database cleanup  
**Classification:** Reporting / Analytics  
**Affected Queries:** R13  
**Issue:** The query likely returns no results due to NULL handling in NOT IN clause, masking actual unused addresses and preventing proper data cleanup.

### P7: Marketing Campaign Performance
**Stakeholders:** Marketing Team  
**Business Need:** Identify abandoned carts for re-engagement campaigns and perform cart cleanup  
**Classification:** Reporting / Analytics  
**Affected Queries:** R10, W04, W06  
**Issue:** Correlating cart data with order history without proper indexing causes long-running batch jobs, delaying marketing campaigns.

### P8: Trust & Safety Review Analysis
**Stakeholders:** Trust & Safety Team  
**Business Need:** Detect fraudulent reviews and analyze review sentiment  
**Classification:** Reporting / Analytics  
**Affected Queries:** R16, R17  
**Issue:** Text searches in reviews and complex verification logic run slowly, limiting the team's ability to quickly identify and remove fake reviews.

### P9: Business Analytics and Reporting
**Stakeholders:** Analytics Team, Finance Team, Category Managers, Prime Team  
**Business Need:** Generate comprehensive reports on returns, sales trends, customer segments, and Prime metrics  
**Classification:** Reporting / Analytics  
**Affected Queries:** R08, R09, R12, R18, R19, R20, R22, W01  
**Issue:** Complex aggregations, window functions, and cross-table analytics without optimization cause timeouts. With 20× growth expected, these will become completely unusable.

## Performance Targets by Query Type

Based on the business classification:

| Query Type | Target Performance | Justification |
|------------|-------------------|---------------|
| Customer-facing / Real-time | < 50ms | Direct impact on user experience; every 100ms delay costs conversion |
| Seller Tools (Interactive) | < 500ms | Used frequently during business hours; impacts seller satisfaction |
| Reports / Analytics | < 5 seconds | Run less frequently; can tolerate some delay but must complete |
| Batch Operations | < 30 seconds | Run off-hours; optimization focused on resource efficiency |

## Key Assumptions

1. **Data Growth:** The 20× growth will be proportional across all tables
2. **Query Patterns:** The 30 queries represent the actual production workload distribution
3. **Hardware:** Optimization focuses on query structure and indexing, not hardware upgrades
4. **Data Integrity:** Current seed data is clean and represents real production data patterns
5. **Prime Delivery:** Digital products (is_digital=true) don't require shipping addresses
6. **Timestamps:** All timestamps use IST (UTC+5:30) consistently
7. **Status Flow:** Orders follow a logical status progression (PLACED → PACKED → SHIPPED → DELIVERED)
8. **Returns:** Only delivered orders can be returned; refund_amount is populated only after approval
9. **Reviews:** verified_purchase flag should correlate with actual delivered orders
10. **Cart Cleanup:** Items older than 90 days are safe to delete per business policy
