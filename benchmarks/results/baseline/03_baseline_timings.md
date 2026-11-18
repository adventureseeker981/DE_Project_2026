| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Search box: active products whose title contains "wireless", best rated first | READ | | | | |
| R02: Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000 | READ | | | | |
| R03: Product page: rating breakdown (how many 5★, 4★ …) for product 4321 | READ | | | | |
| R04: "Your Orders": customer 1042's orders with the number of items in each | READ | | | | |
| R05: Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026) | READ | | | | |
| R06: Seller Central: seller 217's order lines in June 2026 | READ | | | | |
| R07: Seller Central: seller 217's products that are low on stock | READ | | | | |
| R08: Merchandising: top 5 best-selling products in every sub-category, last 30 days | READ | | | | |
| R09: Prime team: average order value of Prime vs non-Prime customers per month in 2026 | READ | | | | |
| R10: Marketing: carts untouched since May 2026 whose owner has not ordered since then | READ | | | | |
| R11: Product page: "Frequently bought together" with product 4321 | READ | | | | |
| R12: Category managers: return rate per top-level category | READ | | | | |
| R13: Data clean-up: saved addresses that have never been used for any order | READ | | | | |
| R14: Deals page: active products selling at less than half of MRP, biggest discount first | READ | | | | |
| R15: Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026 | READ | | | | |
| R16: Review insights: Electronics reviews that mention the battery | READ | | | | |
| R17: Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer | READ | | | | |
| R18: Customer analytics: Mumbai customers split into 4 spending tiers (2026) | READ | | | | |
| R19: Category report: every Mobile phone with its last sale date and units sold (all time) | READ | | | | |
| R20: Finance: daily sales (GMV) and running total for June 2026 | READ | | | | |
| R21: Logistics: deliveries in June 2026 that took more than 5 days | READ | | | | |
| R22: Admin: "All orders", newest first, page 3,001 (25 rows per page) | READ | | | | |
| R23: Order details page: one order with its lines, products and sellers | READ | | | | |
| R24: Product lookup by ASIN (barcode scanner in the warehouse) | READ | | | | |
| W01: Checkout: create a new order (header row) | WRITE | | | | |
| W02: Checkout: reduce stock of product 4322 after a sale | WRITE | | | | |
| W03: Seller Central: 10% price cut on all of seller 217's Watches | WRITE | | | | |
| W04: Big sale: 5,000 "add to cart" events loaded in one batch | WRITE | | | | |
| W05: Logistics: mark the oldest packed order as shipped | WRITE | | | | |
| W06: Nightly clean-up: remove cart items older than 90 days | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |