# Regional Delivery & Review Performance Analysis — Olist E-Commerce

**Business question:** Why do some Brazilian states consistently show lower customer
review scores — is it a product/seller quality problem, or something else? What should
the business fix first?

**Dataset:** [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/olistbr/brazilian-ecommerce)
— ~99,000 real, anonymized orders (2016–2018) across orders, customers, order items,
payments, reviews, products, and sellers.

**Tools:** SQL (SQLite — CTEs, window functions), Python (pandas), Power BI (dashboard).

---

## 1. The Naive Answer

A first pass ranks average review score by customer state:

| State | Orders | Avg Review Score |
|---|---|---|
| AL | 397 | 3.82 |
| MA | 717 | 3.82 |
| PA | 946 | 3.89 |
| SE | 335 | 3.90 |
| BA | 3,256 | 3.91 |
| ... | ... | ... |
| SP | 40,501 | 4.23 |

**The obvious read:** customers in AL, MA, PA, SE, BA are less satisfied — looks like a
product quality or seller service problem concentrated in those states. A less careful
analysis would stop here and recommend a seller-quality audit in those regions.

## 2. Why That's Wrong

Adding delivery-time data to the same ranking tells a different story:

- Correlation between **average delivery time** and **average review score** across
  states: **-0.78** (strong negative)
- Correlation between **days late vs. the promised date** and review score: **-0.51**
  (weaker — most orders arrive before the promised date everywhere, so "lateness vs.
  promise" isn't the real driver)

A cleaner test — bucketing **all orders nationally** by delivery speed, independent of
state — confirms it's a delivery-time effect, not a state-specific artifact:

| Delivery time | Orders | Avg Review Score |
|---|---|---|
| 0–7 days | 26,046 | 4.41 |
| 8–14 days | 40,212 | 4.30 |
| 15–21 days | 17,713 | 4.13 |
| 22–30 days | 7,949 | 3.59 |
| 30+ days | 4,550 | **2.24** |

A clean, monotonic drop — strong evidence this is a real driver, not a coincidence.

**Root cause:** the lowest-review states (AL, PA, MA, SE, CE) are concentrated in
Brazil's North/Northeast — geographically farthest from São Paulo, where most Olist
sellers are based. This is a **logistics/distance problem**, not a seller-quality
problem. Auditing seller quality in those states would have addressed the wrong lever
entirely.

## 3. Checking the Assumption Before Building a Recommendation on It

Before turning this into a "fix delivery to protect revenue" pitch, I tested the
underlying assumption: *does a bad review actually cost the business repeat customers?*

| Review bucket | Customers | Repeat Purchase Rate |
|---|---|---|
| 1–2 (Bad) | 12,322 | 2.88% |
| 3 (Neutral) | 7,762 | 3.05% |
| 4–5 (Good) | 73,274 | 3.01% |

**It doesn't hold.** Repeat purchase rate is flat (~3%) regardless of review score.
Olist is a low-repeat marketplace — most customers buy once across many independent
sellers — so a "bad reviews kill retention" argument would be wrong here, even though
it's the assumption most people would reach for by default.

This mattered: it changed what number belongs in the recommendation. The real,
defensible business case isn't retention — it's **direct revenue exposure on the order
itself** (returns, support costs, and platform reputation), which the data does
support directly:

| Delivery status | Orders | % of orders | Avg Review | Revenue |
|---|---|---|---|---|
| Late | 7,826 | 8.1% | 2.55 | $1,351,625 |
| On-time/Early | 88,644 | 91.9% | 4.28 | $14,066,770 |

## 4. The Real Answer & Recommendation

Late deliveries are concentrated in specific, geographically explainable states, cut
review scores by ~40% (4.28 → 2.55), and touch **$1.35M in order revenue (8.8% of
analyzed revenue)** — even though they're only 8.1% of order volume.

**Recommendation:** prioritize logistics/carrier investment (regional fulfillment
partners or adjusted delivery-time promises) for the AL/PA/MA/SE/CE corridor before any
seller-quality initiative. This is a distance-and-logistics fix, not a
merchant-management fix — and it's where the revenue risk is concentrated.

---

## Repo structure



## Dashboard (Power BI)
Build 2 pages from the exports above:
1. **Executive summary:** KPI cards (total revenue, % late orders, avg review score,
   revenue at risk) + monthly revenue trend line (rolling 3-month avg)
2. **Regional drill-down:** state map or bar chart (avg delivery days vs. avg review
   score, dual axis) + the delivery-speed-vs-review bucket chart as the callout insight

## Suggested resume bullet
> Analyzed 99K+ e-commerce orders (SQL, Python) to test whether low regional review
> scores reflected a seller-quality problem; identified delivery time as the actual
> driver (r = -0.78) and geographic distance from the seller hub as the root cause —
> redirecting the fix from merchandising to logistics for $1.35M in exposed revenue.
