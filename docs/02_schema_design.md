3. Detailed Table Design
3.1 CITIES

Purpose: Stores city and state information used by customers and sellers.

Column	Data Type	Constraints	Description
city_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique city identifier
city_name	VARCHAR(100)	NOT NULL	Name of the city
state	VARCHAR(100)	NOT NULL	State name

Primary Key: city_id

Relationships:

One city can have multiple sellers.
One city can have multiple customers.
One city can be associated with multiple delivery addresses.

Business Rules:

City IDs must be positive.
City name and state cannot be NULL.
3.2 CATEGORIES

Purpose: Maintains product categories and their hierarchical relationships.

Column	Data Type	Constraints	Description
category_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique category identifier
category_name	VARCHAR(100)	NOT NULL, UNIQUE	Category name
parent_category_id	INTEGER	FOREIGN KEY	Parent category
is_digital	BOOLEAN	NOT NULL, DEFAULT FALSE	Indicates digital category

Primary Key: category_id

Foreign Key:

parent_category_id references categories(category_id).

Relationships:

A category can contain multiple subcategories.
A category can contain multiple products.
A category may have one parent category.

Business Rules:

Category names must be unique.
Category IDs must be positive.
A category cannot be its own parent.
Parent categories cannot be deleted while referenced by child categories (ON DELETE RESTRICT).
3.3 SELLERS

Purpose: Stores information about businesses selling products on the platform.

Column	Data Type	Constraints	Description
seller_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique seller identifier
business_name	VARCHAR(200)	NOT NULL	Seller business name
gstin	VARCHAR(15)	NOT NULL, UNIQUE	GST identification number
city_id	INTEGER	NOT NULL, FOREIGN KEY	Seller's city
joined_on	DATE	NOT NULL	Seller registration date
seller_rating	NUMERIC(2,1)	CHECK 1.0–5.0	Seller rating
status	VARCHAR(20)	NOT NULL, DEFAULT 'ACTIVE'	Seller account status

Primary Key: seller_id

Foreign Key:

city_id references cities(city_id).

Relationships:

One seller can list multiple products.
One seller can be associated with multiple order items.
Each seller belongs to one city.

Allowed Seller Statuses:

ACTIVE
SUSPENDED
INACTIVE
CLOSED

Business Rules:

GSTIN must follow the specified 15-character format.
Seller ratings must be between 1.0 and 5.0 when provided.
Seller joining date cannot be in the future.
Seller status must belong to the allowed values.
A referenced city cannot be deleted.
3.4 PRODUCTS

Purpose: Stores product listings, pricing, inventory, and product availability information.

Column	Data Type	Constraints	Description
product_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique product identifier
asin	VARCHAR(10)	NOT NULL, UNIQUE	Amazon Standard Identification Number
seller_id	INTEGER	NOT NULL, FOREIGN KEY	Product seller
category_id	INTEGER	NOT NULL, FOREIGN KEY	Product category
title	VARCHAR(500)	NOT NULL	Product title
brand	VARCHAR(100)	NULL	Product brand
mrp	NUMERIC(10,2)	NOT NULL, CHECK > 0	Maximum retail price
price	NUMERIC(10,2)	NOT NULL, CHECK > 0	Selling price
stock_qty	INTEGER	NOT NULL, DEFAULT 0	Available inventory
is_prime_eligible	BOOLEAN	NOT NULL, DEFAULT FALSE	Prime eligibility
avg_rating	NUMERIC(2,1)	CHECK 1.0–5.0	Average product rating
review_count	INTEGER	NOT NULL, DEFAULT 0	Number of reviews
listed_on	DATE	NOT NULL	Product listing date
status	VARCHAR(20)	NOT NULL, DEFAULT 'ACTIVE'	Product status

Primary Key: product_id

Foreign Keys:

seller_id references sellers(seller_id).
category_id references categories(category_id).

Allowed Product Statuses:

ACTIVE
OUT_OF_STOCK
DISCONTINUED
INACTIVE

Business Rules:

ASIN must follow the specified 10-character format.
Selling price must be positive.
Selling price cannot exceed MRP.
Stock quantity cannot be negative.
Product ratings must be between 1.0 and 5.0 when provided.
Review count cannot be negative.
Listing date cannot be in the future.
Every product must belong to an existing seller and category.
3.5 CUSTOMERS

Purpose: Stores registered shopper information and Amazon Prime membership details.

Column	Data Type	Constraints	Description
customer_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique customer identifier
full_name	VARCHAR(200)	NOT NULL	Customer's full name
email	VARCHAR(255)	NOT NULL, UNIQUE	Customer email
phone	VARCHAR(10)	NOT NULL, UNIQUE	Customer phone number
city_id	INTEGER	NOT NULL, FOREIGN KEY	Customer's city
signup_date	DATE	NOT NULL	Registration date
is_prime	BOOLEAN	NOT NULL, DEFAULT FALSE	Prime membership status
prime_since	DATE	NULL	Prime membership start date

Primary Key: customer_id

Foreign Key:

city_id references cities(city_id).

Business Rules:

Email addresses must follow the specified email format.
Phone numbers must contain exactly 10 digits and begin with 6, 7, 8, or 9.
Email and phone numbers must be unique.
Signup date cannot be in the future.
Non-Prime customers must have prime_since as NULL.
Prime customers must have a non-NULL prime_since.
Prime membership cannot begin before customer registration.
3.6 ADDRESSES

Purpose: Stores customer delivery addresses.

Column	Data Type	Constraints	Description
address_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique address identifier
customer_id	INTEGER	NOT NULL, FOREIGN KEY	Address owner
label	VARCHAR(20)	NOT NULL	Address type
line1	VARCHAR(500)	NOT NULL	Address details
city_id	INTEGER	NOT NULL, FOREIGN KEY	Delivery city
pincode	VARCHAR(6)	NOT NULL	Postal PIN code
is_default	BOOLEAN	NOT NULL, DEFAULT FALSE	Default address indicator

Primary Key: address_id

Foreign Keys:

customer_id references customers(customer_id).
city_id references cities(city_id).

Allowed Address Labels:

HOME
WORK
OTHER

Indexes:

sql
CREATE UNIQUE INDEX idx_one_default_address_per_customer
ON addresses(customer_id)
WHERE is_default = TRUE;


Business Rules:

Every address must belong to an existing customer.
Each customer can have multiple delivery addresses.
Each customer can have at most one default address.
PIN codes must contain exactly six digits and cannot start with zero.
Deleting a customer deletes their associated addresses (ON DELETE CASCADE).
3.7 ORDERS

Purpose: Stores order-level information, including customer details, payment method, total amount, and delivery status.

Column	Data Type	Constraints	Description
order_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique order identifier
customer_id	INTEGER	NOT NULL, FOREIGN KEY	Customer placing the order
address_id	INTEGER	NULL, FOREIGN KEY	Delivery address
ordered_at	TIMESTAMPTZ	NOT NULL	Order placement timestamp
payment_method	VARCHAR(20)	NOT NULL	Payment method
total_amount	NUMERIC(10,2)	NOT NULL, CHECK > 0	Total order amount
status	VARCHAR(20)	NOT NULL, DEFAULT 'PLACED'	Order status
shipped_at	TIMESTAMPTZ	NULL	Shipment timestamp
delivered_at	TIMESTAMPTZ	NULL	Delivery timestamp

Primary Key: order_id

Foreign Keys:

customer_id references customers(customer_id).
address_id references addresses(address_id).

Allowed Payment Methods:

CARD
UPI
NET_BANKING
NETBANKING
COD
WALLET
GIFT_CARD
EMI

Allowed Order Statuses:

PLACED
PACKED
SHIPPED
OUT_FOR_DELIVERY
DELIVERED
CANCELLED
RETURNED

Business Rules:

Every order must belong to an existing customer.
Delivery address is optional.
Total amount must be positive.
Shipment timestamp cannot precede order placement.
Delivery timestamp cannot precede order placement.
Orders with DELIVERED or RETURNED status must have a delivery timestamp.
Deleting a customer with existing orders is restricted.
Deleting an address sets the corresponding order's address_id to NULL.
3.8 ORDER_ITEMS

Purpose: Stores individual product line items belonging to an order.

Column	Data Type	Constraints	Description
order_id	INTEGER	PRIMARY KEY, FOREIGN KEY	Associated order
line_no	INTEGER	PRIMARY KEY, CHECK > 0	Line item number
product_id	INTEGER	NOT NULL, FOREIGN KEY	Ordered product
seller_id	INTEGER	NOT NULL, FOREIGN KEY	Seller of the product
quantity	INTEGER	NOT NULL, CHECK > 0	Ordered quantity
unit_price	NUMERIC(10,2)	NOT NULL, CHECK > 0	Product price at purchase

Composite Primary Key: (order_id, line_no)

Foreign Keys:

order_id references orders(order_id).
product_id references products(product_id).
seller_id references sellers(seller_id).

Business Rules:

Every order item must belong to an existing order.
Each order can contain multiple line items.
Line numbers must be positive and unique within an order.
Quantity and unit price must be positive.
Deleting an order deletes its associated order items (ON DELETE CASCADE).
Products and sellers referenced by order items cannot be deleted.

Design Note: unit_price preserves the product's purchase-time price, even if its current selling price changes.

3.9 RETURNS

Purpose: Stores return requests for individual products purchased by customers.

Column	Data Type	Constraints	Description
return_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique return identifier
order_id	INTEGER	NOT NULL, FOREIGN KEY	Associated order
line_no	INTEGER	NOT NULL, FOREIGN KEY	Associated order line
reason	VARCHAR(50)	NOT NULL	Return reason
requested_at	TIMESTAMPTZ	NOT NULL	Return request timestamp
status	VARCHAR(20)	NOT NULL, DEFAULT 'REQUESTED'	Return status
refund_amount	NUMERIC(10,2)	NULL	Refund amount

Primary Key: return_id

Composite Foreign Key:

(order_id, line_no) references order_items(order_id, line_no).

Allowed Return Reasons:

QUALITY_ISSUE
WRONG_ITEM
NOT_NEEDED
DAMAGED
DEFECTIVE
OTHER
NO_LONGER_NEEDED
NOT_AS_DESCRIBED
SIZE_ISSUE

Allowed Return Statuses:

REQUESTED
APPROVED
REJECTED
REFUNDED
PICKED_UP

Business Rules:

Every return must refer to an existing order item.
Refund amount must be positive when the return status is REFUNDED.
Refund amount must be NULL for all other return statuses.
Deleting an order item deletes its associated return records.
3.10 PRODUCT_REVIEWS

Purpose: Stores customer feedback and ratings for products.

Column	Data Type	Constraints	Description
review_id	INTEGER	PRIMARY KEY, CHECK > 0	Unique review identifier
product_id	INTEGER	NOT NULL, FOREIGN KEY	Reviewed product
customer_id	INTEGER	NOT NULL, FOREIGN KEY	Reviewing customer
rating	INTEGER	NOT NULL, CHECK 1–5	Product rating
title	VARCHAR(200)	NULL	Review title
body	TEXT	NULL	Review content
verified_purchase	BOOLEAN	NOT NULL, DEFAULT FALSE	Purchase verification
helpful_votes	INTEGER	NOT NULL, DEFAULT 0	Helpful vote count
created_at	TIMESTAMPTZ	NOT NULL	Review timestamp

Primary Key: review_id

Foreign Keys:

product_id references products(product_id).
customer_id references customers(customer_id).

Business Rules:

Each review must belong to an existing product and customer.
Ratings must be between 1 and 5.
Helpful vote count cannot be negative.
Deleting a product or customer deletes associated reviews (ON DELETE CASCADE).
3.11 CART_ITEMS

Purpose: Stores products currently added to customer shopping carts.

Column	Data Type	Constraints	Description
customer_id	INTEGER	PRIMARY KEY, FOREIGN KEY	Cart owner
product_id	INTEGER	PRIMARY KEY, FOREIGN KEY	Added product
quantity	INTEGER	NOT NULL, CHECK > 0	Cart quantity
added_at	TIMESTAMPTZ	NOT NULL	Timestamp when added

Composite Primary Key: (customer_id, product_id)

Foreign Keys:

customer_id references customers(customer_id).
product_id references products(product_id).

Business Rules:

Each customer can add multiple products to their cart.
A product can appear only once per customer's cart.
Quantity must be positive.
Deleting a customer or product deletes the associated cart entries (ON DELETE CASCADE).
