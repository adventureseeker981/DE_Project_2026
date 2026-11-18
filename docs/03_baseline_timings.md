| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Search box: active products whose title contains "wireless", best rated first | READ | 26.952 | 25.022 | 25.002 | 25.659 |
| R02: Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000 | READ | 5.871 | 5.714 | 5.540 | 5.708 |
| R03: Product page: rating breakdown (how many 5★, 4★ …) for product 4321 | READ | 4.242 | 2.305 | 2.246 | 2.931 |
| R04: "Your Orders": customer 1042's orders with the number of items in each | READ | 10.723 | 6.168 | 6.084 | 7.658 |
| R05: Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026) | READ | 9.153 | 9.525 | 9.534 | 9.404 |
| R06: Seller Central: seller 217's order lines in June 2026 | READ | 18.880 | 9.050 | 8.995 | 12.308 |
| R07: Seller Central: seller 217's products that are low on stock | READ | 3.592 | 3.702 | 3.586 | 3.627 |
| R08: Merchandising: top 5 best-selling products in every sub-category, last 30 days | READ | 46.805 | 46.327 | 46.823 | 46.652 |
| R09: Prime team: average order value of Prime vs non-Prime customers per month in 2026 | READ | 46.532 | 45.879 | 45.779 | 46.063 |
| R10: Marketing: carts untouched since May 2026 whose owner has not ordered since then | READ | 31.821 | 32.045 | 30.686 | 31.517 |
| R11: Product page: "Frequently bought together" with product 4321 | READ | 10.057 | 8.421 | 8.463 | 8.980 |
| R12: Category managers: return rate per top-level category | READ | 122.245 | 115.268 | 117.178 | 118.230 |
| R13: Data clean-up: saved addresses that have never been used for any order | READ | 29.606 | 31.690 | 28.543 | 29.946 |
| R14: Deals page: active products selling at less than half of MRP, biggest discount first | READ | 7.752 | 7.530 | 7.606 | 7.629 |
| R15: Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026 | READ | 42.414 | 42.309 | 42.800 | 42.508 |
| R16: Review insights: Electronics reviews that mention the battery | READ | 24.278 | 25.081 | 24.098 | 24.486 |
| R17: Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer | READ | 99.484 | 101.706 | 100.817 | 100.669 |
| R18: Customer analytics: Mumbai customers split into 4 spending tiers (2026) | READ | 18.309 | 18.949 | 18.317 | 18.525 |
| R19: Category report: every Mobile phone with its last sale date and units sold (all time) | READ | 17596.902 | 17752.086 | 18319.363 | 17889.450 |
| R20: Finance: daily sales (GMV) and running total for June 2026 | READ | 11.526 | 11.414 | 11.750 | 11.563 |
| R21: Logistics: deliveries in June 2026 that took more than 5 days | READ | 9.441 | 9.460 | 9.565 | 9.489 |
| R22: Admin: "All orders", newest first, page 3,001 (25 rows per page) | READ | 46.849 | 46.061 | 46.202 | 46.371 |
| R23: Order details page: one order with its lines, products and sellers | READ | 0.973 | 0.121 | 0.117 | 0.404 |
| R24: Product lookup by ASIN (barcode scanner in the warehouse) | READ | 0.457 | 0.048 | 0.054 | 0.186 |
| W01: Checkout: create a new order (header row) | WRITE | 3.036 | 1.040 | 1.004 | 1.693 |
| W02: Checkout: reduce stock of product 4322 after a sale | WRITE | 2.582 | 0.467 | 0.427 | 1.159 |
| W03: Seller Central: 10% price cut on all of seller 217's Watches | WRITE | 2.345 | 2.356 | 2.235 | 2.312 |
| W04: Big sale: 5,000 "add to cart" events loaded in one batch | WRITE | 87.679 | 60.856 | 56.776 | 68.437 |
| W05: Logistics: mark the oldest packed order as shipped | WRITE | 14.544 | 16.530 | 14.320 | 15.131 |
| W06: Nightly clean-up: remove cart items older than 90 days | WRITE | 12.420 | 10.736 | 10.999 | 11.385 |
| **Total (sum of all 30)** | | **18,297.47** | **18,457.87** | **19,004.91** | **18,586.75** |
