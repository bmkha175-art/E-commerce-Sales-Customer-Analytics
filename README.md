# E-commerce Sales & Customer Analytics

SQL and Excel analysis of about 51,000 order lines and 17,400 customers, answering business questions on profit, discounting, market growth and customer retention.

**Data source:** [Xóm Dataset](https://dataset.xomdata.com/) (e-commerce, 4 tables: sales, customer, product, region). The company and stakeholders in the brief are fictional framing.

| Table | Rows | One row is |
|---|---|---|
| ecom_sales | ~51,300 | one order line |
| customer | ~17,400 | one customer profile |
| product | ~28,400 | one product record |
| region | ~3,800 | one shipping destination |

## Key findings

- Revenue grew 23.8% year over year, but profit fell 12.2%, mainly because of heavy discounting.
- In Body care, profit turns negative at roughly a 31% discount.
- Only 15.9% of customers reorder, and 2,960 customers ($1.22M in revenue) are at high churn risk.
- Corporate accounts earn about 3× a Consumer account and drive 57% of total profit.

## Recommendations

- Require manager sign-off for discounts above 15% and cap Body care discounts (about $164k profit recovered).
- Launch a win-back offer for high-risk customers.
- Focus expansion on Europe, USCA and Africa.

## Limitations

- No ship date or return flag, so delivery time and returns cannot be measured.
- The discount analysis shows correlation, not causation.
