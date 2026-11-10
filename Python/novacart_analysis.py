"""
NovaCart: E-commerce Profitability, Marketing & Customer Retention (Jan 2025 - Jun 2026)

What this script does, end to end:
  1. Reads the 6 raw CSV files from Data/raw/
  2. Cleans them with the same rules as Sql/02_data_cleaning.sql
     and checks the row counts against the data quality log
  3. Answers the 5 management questions (P&L, categories, channels,
     cohort retention, Black Friday)
  4. Saves cleaned data, result tables and charts

Run from the main project folder:   python Python/novacart_analysis.py
Libraries needed:                    pip install pandas matplotlib
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# ---------------------------------------------------------------
# 0. Folders and settings
# ---------------------------------------------------------------
PROJECT_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_DIR / "Data" / "raw"
CLEAN_DIR = PROJECT_DIR / "Data" / "cleaned"
OUT_DIR = PROJECT_DIR / "Python" / "outputs"
CLEAN_DIR.mkdir(parents=True, exist_ok=True)
OUT_DIR.mkdir(parents=True, exist_ok=True)

PERIOD_START, PERIOD_END = "2025-01-01", "2026-06-30"
BF_START, BF_END = "2025-11-20", "2025-11-30"          # Black Friday campaign
EXPECTED_ROWS = {"products": 40, "customers": 1718, "orders": 2460,
                 "order_items": 4134, "returns": 354, "marketing_spend": 72}

CATEGORIES = {"electronics": "Electronics", "home & kitchen": "Home & Kitchen",
              "fashion": "Fashion", "beauty": "Beauty", "sports": "Sports"}
CHANNELS = {"facebook ads": "Facebook Ads", "fb ads": "Facebook Ads", "facebook": "Facebook Ads",
            "google ads": "Google Ads", "organic": "Organic",
            "referral": "Referral", "email": "Email"}


def read_raw(name):
    """Read a raw CSV as text, so nothing is changed before we clean it."""
    return pd.read_csv(RAW_DIR / f"{name}.csv", dtype=str, keep_default_na=False)


def clean_text(series):
    """Lower-case and remove spaces at the start and end."""
    return series.str.strip().str.lower()


# ---------------------------------------------------------------
# 1. Load raw data
# ---------------------------------------------------------------
raw = {name: read_raw(name) for name in EXPECTED_ROWS}

# ---------------------------------------------------------------
# 2. Clean (same rules as Sql/02_data_cleaning.sql)
# ---------------------------------------------------------------
# Products: drop duplicate row, standardize category, '$96.73' -> 96.73
products = raw["products"].drop_duplicates().copy()
products["category"] = clean_text(products["category"]).str.replace(" and ", " & ").map(CATEGORIES)
products["unit_price"] = products["unit_price"].str.replace("[$,]", "", regex=True).astype(float)
products["unit_cost"] = products["unit_cost"].astype(float)

# Customers: drop duplicates and test accounts, fix dates, city, channel
customers = raw["customers"].drop_duplicates().copy()
test_ids = set(customers.loc[customers["email"].str.endswith("@novacart.com"), "customer_id"])
customers = customers[~customers["customer_id"].isin(test_ids)].copy()
is_ddmm = customers["signup_date"].str.contains("/")
customers["signup_date"] = pd.to_datetime(
    np.where(is_ddmm,
             pd.to_datetime(customers["signup_date"], format="%d/%m/%Y", errors="coerce").dt.strftime("%Y-%m-%d"),
             customers["signup_date"].str.strip()))
customers["city"] = customers["city"].str.strip().replace("", "Unknown")
customers["acquisition_channel"] = clean_text(customers["acquisition_channel"]).map(CHANNELS)
customers["email"] = clean_text(customers["email"])

# Orders: drop duplicates, impossible dates and test orders; '10%' -> 0.10
orders = raw["orders"].drop_duplicates().copy()
orders = orders[orders["order_date"].between(PERIOD_START, PERIOD_END)]
orders = orders[~orders["customer_id"].isin(test_ids)].copy()
pct = orders["discount_pct"].str.contains("%")
orders["discount_pct"] = np.where(pct,
                                  orders["discount_pct"].str.replace("%", "").astype(float) / 100,
                                  pd.to_numeric(orders["discount_pct"], errors="coerce"))
orders["order_date"] = pd.to_datetime(orders["order_date"])
orders["shipping_cost"] = orders["shipping_cost"].astype(float)

# Order items: keep known products and kept orders, quantity > 0, fix 10x prices
items = raw["order_items"].copy()
items["quantity"] = items["quantity"].astype(int)
items["unit_price"] = items["unit_price"].astype(float)
items = items.merge(products[["product_id", "unit_price"]].rename(columns={"unit_price": "list_price"}),
                    on="product_id")                                  # inner join drops PR999
items = items[items["order_id"].isin(orders["order_id"]) & (items["quantity"] > 0)].copy()
too_high = items["unit_price"] > items["list_price"] * 5
items.loc[too_high, "unit_price"] = items.loc[too_high, "list_price"]
items = items.drop(columns="list_price")

# Returns: drop duplicates, drop returns for unknown items, cap refund at item value
returns = raw["returns"].drop_duplicates().copy()
returns["refund_amount"] = returns["refund_amount"].astype(float)
returns["return_date"] = pd.to_datetime(returns["return_date"])
item_value = items.merge(orders[["order_id", "discount_pct"]], on="order_id")
item_value["value"] = (item_value["quantity"] * item_value["unit_price"]
                       * (1 - item_value["discount_pct"])).round(2)
returns = returns.merge(item_value[["order_item_id", "value"]], on="order_item_id")
returns["refund_amount"] = returns[["refund_amount", "value"]].min(axis=1)
returns = returns.drop(columns="value")

# Marketing: 'Jan-2025' -> '2025-01', standardize channel, drop duplicate
marketing = raw["marketing_spend"].drop_duplicates().copy()
mon = marketing["month"].str.match(r"^[A-Za-z]{3}-\d{4}$")
marketing.loc[mon, "month"] = pd.to_datetime(marketing.loc[mon, "month"], format="%b-%Y").dt.strftime("%Y-%m")
marketing["channel"] = clean_text(marketing["channel"]).map(CHANNELS)
marketing["spend_usd"] = marketing["spend_usd"].astype(float)

clean = {"products": products, "customers": customers, "orders": orders,
         "order_items": items, "returns": returns, "marketing_spend": marketing}

print("=== DATA CLEANING ===")
for name, df in clean.items():
    status = "OK" if len(df) == EXPECTED_ROWS[name] else "CHECK!"
    print(f"{name:16} raw {len(raw[name]):5}  ->  clean {len(df):5}   expected {EXPECTED_ROWS[name]:5}  {status}")
    df.to_csv(CLEAN_DIR / f"{name}.csv", index=False, date_format="%Y-%m-%d")
missing = [n for n, d in [("category", products["category"]), ("channel", customers["acquisition_channel"]),
                          ("marketing channel", marketing["channel"])] if d.isna().any()]
if missing:
    print("WARNING: unmapped values in", missing)

# ---------------------------------------------------------------
# 3. One row per delivered order line, with every measure we need
# ---------------------------------------------------------------
lines = (items
         .merge(orders, on="order_id")
         .merge(products[["product_id", "product_name", "category", "unit_cost"]], on="product_id")
         .merge(returns[["order_item_id", "refund_amount"]], on="order_item_id", how="left")
         .merge(customers[["customer_id", "acquisition_channel", "signup_date"]], on="customer_id", how="left"))
lines = lines[lines["status"] == "Delivered"].copy()
lines["refund_amount"] = lines["refund_amount"].fillna(0)
lines["net_sales"] = lines["quantity"] * lines["unit_price"] * (1 - lines["discount_pct"])
lines["net_revenue"] = lines["net_sales"] - lines["refund_amount"]
lines["cogs"] = lines["quantity"] * lines["unit_cost"]
lines["gross_profit"] = lines["net_revenue"] - lines["cogs"]
lines["month"] = lines["order_date"].dt.strftime("%Y-%m")
delivered = orders[orders["status"] == "Delivered"].copy()
delivered["month"] = delivered["order_date"].dt.strftime("%Y-%m")

# ---------------------------------------------------------------
# Q1. Monthly P&L
# ---------------------------------------------------------------
pnl = lines.groupby("month").agg(net_revenue=("net_revenue", "sum"), gross_profit=("gross_profit", "sum"))
pnl["shipping"] = delivered.groupby("month")["shipping_cost"].sum()   # order level: no double counting
pnl["marketing"] = marketing.groupby("month")["spend_usd"].sum()
pnl["operating_profit"] = pnl["gross_profit"] - pnl["shipping"] - pnl["marketing"]
pnl["gross_margin_pct"] = pnl["gross_profit"] / pnl["net_revenue"] * 100
pnl["revenue_growth_pct"] = pnl["net_revenue"].pct_change() * 100     # pandas version of SQL LAG
pnl = pnl.fillna({"shipping": 0, "marketing": 0})

print("\n=== Q1. MONTHLY P&L ===")
print(pnl.round(1).to_string())
total = pnl[["net_revenue", "gross_profit", "shipping", "marketing", "operating_profit"]].sum()
print(f"\nTotal net revenue ${total.net_revenue:,.0f} | gross profit ${total.gross_profit:,.0f} | "
      f"marketing ${total.marketing:,.0f} | operating profit ${total.operating_profit:,.0f}")
print(f"Months with an operating loss: {(pnl['operating_profit'] < 0).sum()} of {len(pnl)}")

# ---------------------------------------------------------------
# Q2. Category and product profitability
# ---------------------------------------------------------------
cat = lines.groupby("category").agg(net_sales=("net_sales", "sum"), refunds=("refund_amount", "sum"),
                                    net_revenue=("net_revenue", "sum"), gross_profit=("gross_profit", "sum"))
cat["refund_rate_pct"] = cat["refunds"] / cat["net_sales"] * 100
cat["gross_margin_pct"] = cat["gross_profit"] / cat["net_revenue"] * 100
cat = cat.sort_values("gross_profit", ascending=False)

prod = lines.groupby(["category", "product_name"]).agg(net_revenue=("net_revenue", "sum"),
                                                       gross_profit=("gross_profit", "sum")).reset_index()
prod["rank_in_category"] = prod.groupby("category")["gross_profit"].rank(ascending=False, method="min").astype(int)
top3 = prod[prod["rank_in_category"] <= 3].sort_values(["category", "rank_in_category"])

reasons = (lines[lines["refund_amount"] > 0]
           .merge(returns[["order_item_id", "reason"]], on="order_item_id")
           .groupby(["category", "reason"]).size().unstack(fill_value=0))

print("\n=== Q2. CATEGORIES ===")
print(cat.round(1).to_string())
print("\nTop 3 products per category:")
print(top3.round(0).to_string(index=False))
print("\nReturn reasons by category (count):")
print(reasons.to_string())

# ---------------------------------------------------------------
# Q3. Marketing channels
# ---------------------------------------------------------------
cust_orders = delivered.groupby("customer_id")["order_id"].nunique()
cust_profit = lines.groupby("customer_id")["gross_profit"].sum()
cust = customers.set_index("customer_id")[["acquisition_channel", "signup_date"]].copy()
cust["delivered_orders"] = cust_orders.reindex(cust.index).fillna(0)
cust["gross_profit"] = cust_profit.reindex(cust.index).fillna(0)

chan = cust.groupby("acquisition_channel").agg(customers=("gross_profit", "size"),
                                               repeat_rate=("delivered_orders", lambda s: (s >= 2).mean() * 100),
                                               gross_profit=("gross_profit", "sum"))
chan["spend"] = marketing.groupby("channel")["spend_usd"].sum().reindex(chan.index).fillna(0)
chan["cac"] = (chan["spend"] / chan["customers"]).replace(0, np.nan)
chan["profit_per_customer"] = chan["gross_profit"] / chan["customers"]
chan["profit_after_ads_per_customer"] = (chan["gross_profit"] - chan["spend"]) / chan["customers"]
chan = chan.sort_values("profit_after_ads_per_customer", ascending=False)

print("\n=== Q3. CHANNELS ===")
print(chan.round(2).to_string())

# ---------------------------------------------------------------
# Q4. Cohort retention (cohort = month of first delivered order)
# ---------------------------------------------------------------
known = delivered[delivered["customer_id"].isin(customers["customer_id"])].copy()
known["order_period"] = known["order_date"].dt.to_period("M")
known["cohort"] = known.groupby("customer_id")["order_period"].transform("min")
known["month_number"] = (known["order_period"] - known["cohort"]).apply(lambda d: d.n)
active = known.groupby(["cohort", "month_number"])["customer_id"].nunique().unstack()
cohort_size = active[0]
retention = active.divide(cohort_size, axis=0) * 100

last_month = known["order_period"].max()
for cohort in retention.index:                     # months not reached yet -> NaN, not 0
    months_available = (last_month - cohort).n
    retention.loc[cohort, retention.columns > months_available] = np.nan
for cohort in retention.index:                     # reached but nobody came back -> 0
    months_available = (last_month - cohort).n
    cols = [c for c in retention.columns if c <= months_available]
    retention.loc[cohort, cols] = retention.loc[cohort, cols].fillna(0)

once_only = (cust.loc[cust.index.isin(known["customer_id"]), "delivered_orders"] == 1).mean() * 100
print("\n=== Q4. COHORT RETENTION (% active, months 0-6) ===")
print(retention.iloc[:, :7].round(1).to_string())
print(f"\nCustomers who ordered only once: {once_only:.1f}%")

# ---------------------------------------------------------------
# Q5. Black Friday 2025
# ---------------------------------------------------------------
lines["period"] = np.where(lines["order_date"].between(BF_START, BF_END), "Black Friday", "Other days")
bf = lines.groupby("period").agg(days=("order_date", "nunique"), orders=("order_id", "nunique"),
                                 net_revenue=("net_revenue", "sum"), gross_profit=("gross_profit", "sum"))
bf["orders_per_day"] = bf["orders"] / bf["days"]
bf["gross_profit_per_day"] = bf["gross_profit"] / bf["days"]
bf["gross_margin_pct"] = bf["gross_profit"] / bf["net_revenue"] * 100

season = cust[cust["signup_date"].between("2025-09-01", "2026-01-31")].copy()
season["group"] = np.where(season["signup_date"].between(BF_START, BF_END),
                           "Signed up on Black Friday", "Same season, other days")
bf_cust = season.groupby("group").agg(customers=("gross_profit", "size"),
                                      facebook_share=("acquisition_channel", lambda s: (s == "Facebook Ads").mean() * 100),
                                      repeat_rate=("delivered_orders", lambda s: (s >= 2).mean() * 100),
                                      profit_per_customer=("gross_profit", "mean"))

print("\n=== Q5. BLACK FRIDAY 2025 ===")
print(bf.round(1).to_string())
print(bf_cust.round(1).to_string())

# Save result tables
for name, df in [("q1_monthly_pnl", pnl), ("q2_categories", cat), ("q2_top3_products", top3),
                 ("q3_channels", chan), ("q4_cohort_retention", retention), ("q5_black_friday", bf),
                 ("q5_black_friday_customers", bf_cust)]:
    df.round(2).to_csv(OUT_DIR / f"{name}.csv")

# ---------------------------------------------------------------
# 4. Charts
# ---------------------------------------------------------------
PERIOD = "(Jan 2025 - Jun 2026)"

# Chart 1: revenue vs operating profit
fig, ax = plt.subplots(figsize=(11, 5))
ax.plot(pnl.index, pnl["net_revenue"], marker="o", label="Net revenue", color="#2E86AB")
ax.plot(pnl.index, pnl["operating_profit"], marker="o", label="Operating profit", color="#E07A5F")
ax.axhline(0, color="black", linewidth=0.8)
ax.annotate("Black Friday", xy=("2025-11", pnl.loc["2025-11", "operating_profit"]),
            xytext=(-60, -30), textcoords="offset points", arrowprops=dict(arrowstyle="->"))
ax.set_title(f"Revenue grew, profit did not {PERIOD}")
ax.set_ylabel("USD"); ax.legend(); ax.tick_params(axis="x", rotation=45)
plt.tight_layout(); plt.savefig(OUT_DIR / "q1_revenue_vs_profit.png", dpi=150); plt.close()

# Chart 2: category revenue vs gross margin
fig, ax1 = plt.subplots(figsize=(9, 5))
ax1.bar(cat.index, cat["net_revenue"], color="#2E86AB", label="Net revenue")
ax1.set_ylabel("Net revenue (USD)")
ax2 = ax1.twinx()
ax2.plot(cat.index, cat["gross_margin_pct"], color="#E07A5F", marker="o", linewidth=2, label="Gross margin %")
ax2.set_ylabel("Gross margin (%)"); ax2.set_ylim(0, 70)
ax1.set_title(f"Biggest category, smallest margin {PERIOD}")
fig.legend(loc="upper right", bbox_to_anchor=(0.88, 0.88))
plt.tight_layout(); plt.savefig(OUT_DIR / "q2_category_revenue_margin.png", dpi=150); plt.close()

# Chart 3: profit after ads per customer, by channel
colors = ["#D62828" if v < 0 else "#2A9D8F" for v in chan["profit_after_ads_per_customer"]]
fig, ax = plt.subplots(figsize=(8, 4.5))
ax.barh(chan.index, chan["profit_after_ads_per_customer"], color=colors)
ax.axvline(0, color="black", linewidth=0.8); ax.invert_yaxis()
for i, v in enumerate(chan["profit_after_ads_per_customer"]):
    ax.text(v, i, f" ${v:,.0f} ", va="center", ha="left" if v >= 0 else "right")
ax.set_title(f"Profit after ad cost, per customer {PERIOD}")
ax.set_xlabel("USD per customer")
plt.tight_layout(); plt.savefig(OUT_DIR / "q3_channel_profit_after_ads.png", dpi=150); plt.close()

# Chart 4: cohort retention heatmap (months 1-6; month 0 is always 100%)
heat = retention.iloc[:, 1:7]
fig, ax = plt.subplots(figsize=(8, 7))
im = ax.imshow(heat.values, cmap="Greens", aspect="auto", vmin=0, vmax=np.nanmax(heat.values))
ax.set_xticks(range(heat.shape[1])); ax.set_xticklabels([f"M{c}" for c in heat.columns])
ax.set_yticks(range(heat.shape[0])); ax.set_yticklabels([str(p) for p in heat.index])
for r in range(heat.shape[0]):
    for c in range(heat.shape[1]):
        v = heat.values[r, c]
        if not np.isnan(v):
            ax.text(c, r, f"{v:.0f}%", ha="center", va="center", fontsize=8)
ax.set_title("Cohort retention: % of customers ordering again")
ax.set_xlabel("Months after first order"); ax.set_ylabel("Cohort (month of first order)")
fig.colorbar(im, ax=ax, label="% of cohort")
plt.tight_layout(); plt.savefig(OUT_DIR / "q4_cohort_heatmap.png", dpi=150); plt.close()

# Chart 5: Black Friday per day vs other days
fig, axes = plt.subplots(1, 2, figsize=(10, 4))
axes[0].bar(bf.index, bf["orders_per_day"], color=["#E07A5F", "#2E86AB"])
axes[0].set_title("Orders per day")
axes[1].bar(bf.index, bf["gross_profit_per_day"], color=["#D62828", "#2A9D8F"])
axes[1].axhline(0, color="black", linewidth=0.8)
axes[1].set_title("Gross profit per day (USD)")
fig.suptitle("Black Friday 2025: more orders, negative profit")
plt.tight_layout(); plt.savefig(OUT_DIR / "q5_black_friday.png", dpi=150); plt.close()

print(f"\nDone! Cleaned data in {CLEAN_DIR}\nResults and charts in {OUT_DIR}")
