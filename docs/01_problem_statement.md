# Phase 1: Problem Understanding

Amazon India is a marketplace where customers shop across a hierarchy of product categories, sellers manage listings and stock, and logistics teams fulfill orders. The existing database has no documented schema, and teams report slow customer workflows, operational tools, and business reports. This phase identifies the needs behind those reports and groups the related workload queries before schema design and performance testing.

## Business problems and stakeholders

| Problem | Business need | Stakeholder(s) affected | Classification | Related queries |
|---|---|---|---|---|
| **P1 — Search and category browsing** | Find active products and browse all levels of a category tree quickly, including when a category has many descendants. | Customers; Search / Browse team | Customer-facing / real-time | R01, R02, R14 |
| **P2 — Product details** | Load product ratings and related-product recommendations promptly, including for popular products with many reviews or sales. | Customers; Product page team | Customer-facing / real-time | R03, R11, R24 |
| **P3 — Orders and order details** | Let customers open their order history and inspect an order's items without long waits. | Customers; Customer app team | Customer-facing / real-time | R04, R23 |
| **P4 — Seller Central** | Provide sellers with responsive sales, stock, price, and revenue information and allow timely inventory and price updates. | Sellers; Seller Central team | Operational / real-time | R06, R07, R15, W02, W03 |
| **P5 — Shipping and fulfillment** | Quickly identify shipments that are stuck or late and keep the packing-to-shipping queue moving. | Logistics and fulfillment teams | Operational / real-time | R05, R21, W05 |
| **P6 — Unused addresses** | Find saved addresses that have not been used by any order so support and data teams can investigate or clean them up. | Customer support; Data quality team | Reporting / analytics | R13 |
| **P7 — Abandoned carts** | Identify eligible abandoned carts for campaigns and remove expired cart entries efficiently. | Marketing; Customers; Operations | Batch / operational analytics | R10, W04, W06 |
| **P8 — Review integrity and insights** | Flag potentially unsubstantiated verified-purchase reviews and search review text for product feedback themes. | Trust & Safety; Product teams | Reporting / analytics | R16, R17 |
| **P9 — Business reporting at growth** | Produce category, Prime, finance, returns, and customer-spend reports reliably as data volume and traffic grow by an expected 20×. | Category managers; Prime team; Finance; Analytics | Reporting / analytics | R08, R09, R12, R18, R19, R20 |

## Assumptions

- “Real-time” means a customer or operational workflow needs a prompt response; it does not imply a specific latency target until the project’s benchmark targets are applied.
- Seller and logistics queries are classified as operational / real-time because they support active business workflows, even though they are not customer-facing.
- Reports that aggregate or rank data across many records are classified as reporting / analytics. Cart cleanup and bulk cart loading are batch operations, while abandoned-cart selection supports marketing analysis.
- The 20× growth estimate is a planning assumption supplied in the project brief; actual performance must be measured on the faculty-provided large dataset.
- Query results must remain correct during optimization. Any discovered data-quality or SQL correctness issue should be documented rather than hidden by changing the underlying data.

## Phase 1 outcome

The project will reconstruct a constrained schema from the supplied CSV exports, establish baseline performance for all 30 workload queries, optimize without changing intended results, and evaluate whether the design can handle the larger dataset.
