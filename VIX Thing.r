# Establish libraries
import pandas as pd
import numpy as np
import yfinance as yf
import openpyxl
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import streamlit as st
from io import BytesIO
import warnings
warnings.filterwarnings("ignore")

# Page config 
st.set_page_config(page_title="Stock Snapshot", page_icon="📈", layout="wide")
st.title("Stock Technical & Fundamental Snapshot")

# Sidebar inputs
with st.sidebar:
    st.header("Settings")
    ticker_input = st.text_input("Ticker Symbol", value="AAPL").upper().strip()
    period = st.selectbox("istorical Period", ["6mo", "1y", "2y", "5y"], index=1)
    run = st.button("Generate Snapshot", type="primary")

if not run and "ticker" not in st.session_state:
    st.info("Enter a ticker symbol in the sidebar and click Generate Snapshot.")
    st.stop()

if run:
    st.session_state["ticker"] = ticker_input
    st.session_state["period"] = period

ticker = st.session_state["ticker"]
period = st.session_state["period"]

# Data fetch
@st.cache_data(ttl=300)
def fetch_data(ticker, period):
    stock = yf.Ticker(ticker)
    hist = stock.history(period=period)
    info = stock.info
    return hist, info

with st.spinner(f"Fetching data for {ticker}..."):
    hist, info = fetch_data(ticker, period)

if hist.empty:
    st.error(f"No data found for '{ticker}'. Check the symbol and try again.")
    st.stop()

# Technical indicator helpers
def compute_rsi(series, window=14):
    delta = series.diff()
    gain = delta.clip(lower=0).rolling(window).mean()
    loss = (-delta.clip(upper=0)).rolling(window).mean()
    rs = gain / loss
    return 100 - (100 / (1 + rs))

def compute_macd(series, fast=12, slow=26, signal=9):
    ema_fast = series.ewm(span=fast, adjust=False).mean()
    ema_slow = series.ewm(span=slow, adjust=False).mean()
    macd_line = ema_fast - ema_slow
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    return macd_line, signal_line, macd_line - signal_line

def compute_bollinger(series, window=20):
    sma = series.rolling(window).mean()
    std = series.rolling(window).std()
    return sma + 2 * std, sma, sma - 2 * std

close = hist["Close"]
hist["SMA20"]  = close.rolling(20).mean()
hist["SMA50"]  = close.rolling(50).mean()
hist["SMA200"] = close.rolling(200).mean()
hist["RSI"]    = compute_rsi(close)
hist["MACD"], hist["Signal"], hist["Histogram"] = compute_macd(close)
hist["BB_Upper"], hist["BB_Mid"], hist["BB_Lower"] = compute_bollinger(close)

# Stock header
company_name  = info.get("longName", ticker)
current_price = info.get("currentPrice") or float(close.iloc[-1])
prev_close    = info.get("previousClose")
change_pct    = ((current_price - prev_close) / prev_close * 100) if prev_close else None

h1, h2, h3 = st.columns([3, 1, 1])
h1.subheader(f"{company_name} ({ticker})")
h2.metric("Price",
          f"${current_price:.2f}",
          f"{change_pct:+.2f}%" if change_pct is not None else None)
h3.metric("52-Wk Range",
          f"${info.get('fiftyTwoWeekLow', '?')} – ${info.get('fiftyTwoWeekHigh', '?')}")

st.divider()

# Technical charts
st.subheader("Technical Analysis")

BG = "#0e1117"
fig, axes = plt.subplots(3, 1, figsize=(14, 12),
                          gridspec_kw={"height_ratios": [3, 1, 1]})
fig.patch.set_facecolor(BG)
for ax in axes:
    ax.set_facecolor(BG)
    ax.tick_params(colors="white")
    ax.yaxis.label.set_color("white")
    for spine in ax.spines.values():
        spine.set_edgecolor("#333")

# Price + Bollinger Bands + MAs
ax1 = axes[0]
ax1.plot(hist.index, close,           color="#00c4ff", lw=1.5, label="Price")
ax1.plot(hist.index, hist["BB_Upper"], color="#555",   lw=0.8, ls="--")
ax1.plot(hist.index, hist["BB_Mid"],   color="#888",   lw=0.8, ls="--", label="BB Mid / SMA20")
ax1.plot(hist.index, hist["BB_Lower"], color="#555",   lw=0.8, ls="--")
ax1.fill_between(hist.index, hist["BB_Upper"], hist["BB_Lower"],
                 alpha=0.06, color="gray")
ax1.plot(hist.index, hist["SMA50"],  color="#f4a21e", lw=1.2, label="SMA 50")
ax1.plot(hist.index, hist["SMA200"], color="#e84444", lw=1.2, label="SMA 200")
ax1.legend(facecolor="#1a1a2e", labelcolor="white", fontsize=8)
ax1.set_title(f"{ticker} — Price, Bollinger Bands & Moving Averages",
              color="white", fontsize=11)
ax1.xaxis.set_major_formatter(mdates.DateFormatter("%b '%y"))

# RSI
ax2 = axes[1]
ax2.plot(hist.index, hist["RSI"], color="#a78bfa", lw=1.2)
ax2.axhline(70, color="#e84444", lw=0.8, ls="--")
ax2.axhline(30, color="#22c55e", lw=0.8, ls="--")
ax2.fill_between(hist.index, hist["RSI"], 70,
                 where=(hist["RSI"] >= 70), alpha=0.2, color="red")
ax2.fill_between(hist.index, hist["RSI"], 30,
                 where=(hist["RSI"] <= 30), alpha=0.2, color="green")
ax2.set_ylim(0, 100)
ax2.set_ylabel("RSI (14)", fontsize=9)
ax2.xaxis.set_major_formatter(mdates.DateFormatter("%b '%y"))

# MACD
ax3 = axes[2]
ax3.plot(hist.index, hist["MACD"],   color="#00c4ff", lw=1.2, label="MACD")
ax3.plot(hist.index, hist["Signal"], color="#f4a21e", lw=1.2, label="Signal")
bar_colors = ["#22c55e" if v >= 0 else "#e84444" for v in hist["Histogram"]]
ax3.bar(hist.index, hist["Histogram"], color=bar_colors, alpha=0.6, width=1)
ax3.axhline(0, color="#444", lw=0.5)
ax3.set_ylabel("MACD (12/26/9)", fontsize=9)
ax3.legend(facecolor="#1a1a2e", labelcolor="white", fontsize=8)
ax3.xaxis.set_major_formatter(mdates.DateFormatter("%b '%y"))

plt.tight_layout()
st.pyplot(fig)
plt.close(fig)

# Signal summary
st.subheader("Signal Summary")
latest  = hist.iloc[-1]
rsi_val = latest["RSI"]
macd_cross = latest["MACD"] > latest["Signal"]

def rsi_label(r):
    if r > 70:  return "🔴 Overbought"
    if r < 30:  return "🟢 Oversold"
    return "🟡 Neutral"

s1, s2, s3, s4 = st.columns(4)
s1.metric("RSI (14)", f"{rsi_val:.1f}", rsi_label(rsi_val))
s2.metric("MACD Cross", "Bullish" if macd_cross else "Bearish",
          "🟢" if macd_cross else "🔴")
s3.metric("vs SMA 50",
          "Above" if latest["Close"] > latest["SMA50"] else "Below",
          "🟢" if latest["Close"] > latest["SMA50"] else "🔴")
s4.metric("vs SMA 200",
          "Above" if latest["Close"] > latest["SMA200"] else "Below",
          "🟢" if latest["Close"] > latest["SMA200"] else "🔴")

st.divider()

# Fundamental helpers
def fmt_large(val):
    if val is None: return "N/A"
    if val >= 1e12: return f"${val / 1e12:.2f}T"
    if val >= 1e9:  return f"${val / 1e9:.2f}B"
    if val >= 1e6:  return f"${val / 1e6:.2f}M"
    return f"${val:,.0f}"

def fmt_pct(val):
    return f"{val * 100:.2f}%" if val is not None else "N/A"

def fmt_x(val, d=2):
    return f"{val:.{d}f}x" if val is not None else "N/A"

# Fundamental tables
st.subheader("Fundamental Analysis")

valuation = {
    "Market Cap":               fmt_large(info.get("marketCap")),
    "Enterprise Value":         fmt_large(info.get("enterpriseValue")),
    "P/E (TTM)":                fmt_x(info.get("trailingPE")),
    "Forward P/E":              fmt_x(info.get("forwardPE")),
    "P/B Ratio":                fmt_x(info.get("priceToBook")),
    "P/S Ratio":                fmt_x(info.get("priceToSalesTrailing12Months")),
    "EV/EBITDA":                fmt_x(info.get("enterpriseToEbitda")),
    "EPS (TTM)":                f"${info.get('trailingEps', 'N/A')}",
    "Forward EPS":              f"${info.get('forwardEps', 'N/A')}",
    "PEG Ratio":                fmt_x(info.get("pegRatio")),
}

income = {
    "Revenue (TTM)":            fmt_large(info.get("totalRevenue")),
    "Gross Profit":             fmt_large(info.get("grossProfits")),
    "EBITDA":                   fmt_large(info.get("ebitda")),
    "Net Income":               fmt_large(info.get("netIncomeToCommon")),
    "Gross Margin":             fmt_pct(info.get("grossMargins")),
    "Operating Margin":         fmt_pct(info.get("operatingMargins")),
    "Profit Margin":            fmt_pct(info.get("profitMargins")),
    "Revenue Growth (YoY)":     fmt_pct(info.get("revenueGrowth")),
    "Earnings Growth (YoY)":    fmt_pct(info.get("earningsGrowth")),
}

balance = {
    "Total Cash":               fmt_large(info.get("totalCash")),
    "Total Debt":               fmt_large(info.get("totalDebt")),
    "Debt / Equity":            f"{info.get('debtToEquity', 'N/A')}",
    "Current Ratio":            fmt_x(info.get("currentRatio")),
    "Quick Ratio":              fmt_x(info.get("quickRatio")),
    "Return on Equity":         fmt_pct(info.get("returnOnEquity")),
    "Return on Assets":         fmt_pct(info.get("returnOnAssets")),
    "Free Cash Flow":           fmt_large(info.get("freeCashflow")),
    "Dividend Yield":           fmt_pct(info.get("dividendYield")),
    "Payout Ratio":             fmt_pct(info.get("payoutRatio")),
}

col_v, col_i, col_b = st.columns(3)

with col_v:
    st.markdown("**Valuation**")
    st.dataframe(
        pd.DataFrame.from_dict(valuation, orient="index", columns=["Value"]),
        use_container_width=True
    )

with col_i:
    st.markdown("**Income Statement**")
    st.dataframe(
        pd.DataFrame.from_dict(income, orient="index", columns=["Value"]),
        use_container_width=True
    )

with col_b:
    st.markdown("**Balance Sheet & Returns**")
    st.dataframe(
        pd.DataFrame.from_dict(balance, orient="index", columns=["Value"]),
        use_container_width=True
    )

# Company overview
with st.expander("Company Overview"):
    st.write(info.get("longBusinessSummary", "No description available."))
    mc1, mc2, mc3, mc4 = st.columns(4)
    mc1.metric("Sector",    info.get("sector",   "N/A"))
    mc2.metric("Industry",  info.get("industry", "N/A"))
    mc3.metric("Employees",
               f"{info.get('fullTimeEmployees'):,}"
               if info.get("fullTimeEmployees") else "N/A")
    mc4.metric("Country",   info.get("country",  "N/A"))

st.divider()

# DCF Valuation 
st.subheader("DCF Valuation")

_fcf    = info.get("freeCashflow")
_shares = info.get("sharesOutstanding")

if _fcf and _shares and _fcf > 0:
    with st.expander("Customize DCF Assumptions", expanded=True):
        da1, da2, da3 = st.columns(3)
        _g1 = da1.slider("Near-Term Growth Rate — Yrs 1–5 (%)", -20, 60, 10) / 100
        _g2 = da2.slider("Terminal Growth Rate (%)",               0,  5,  3) / 100
        _dr = da3.slider("Discount Rate / WACC (%)",               5, 20, 10) / 100

        if _dr <= _g2:
            st.warning("Discount rate must exceed terminal growth rate for a valid DCF.")
        else:
            _n   = 10
            _cfs = []
            for _yr in range(1, _n + 1):
                if _yr <= 5:
                    _cfs.append(_fcf * (1 + _g1) ** _yr)
                else:
                    _faded = _g1 + (_g2 - _g1) * ((_yr - 5) / 5)
                    _cfs.append(_fcf * (1 + _g1) ** 5 * (1 + _faded) ** (_yr - 5))

            _pv_cfs   = [cf / (1 + _dr) ** (i + 1) for i, cf in enumerate(_cfs)]
            _term_val  = _cfs[-1] * (1 + _g2) / (_dr - _g2)
            _pv_term   = _term_val / (1 + _dr) ** _n
            _iv_share  = (sum(_pv_cfs) + _pv_term) / _shares
            _mos       = (_iv_share - current_price) / _iv_share * 100

            dc1, dc2, dc3 = st.columns(3)
            dc1.metric("Intrinsic Value (DCF)", f"${_iv_share:.2f}")
            dc2.metric("Current Price",          f"${current_price:.2f}")
            dc3.metric("Margin of Safety",       f"{_mos:+.1f}%",
                       "Undervalued" if _mos > 0 else "Overvalued")

            _yrs = list(range(1, _n + 1))
            fig_d, ax_d = plt.subplots(figsize=(12, 4))
            fig_d.patch.set_facecolor(BG)
            ax_d.set_facecolor(BG)
            ax_d.tick_params(colors="white")
            ax_d.yaxis.label.set_color("white")
            for _sp in ax_d.spines.values():
                _sp.set_edgecolor("#333")
            ax_d.bar(_yrs, [cf / 1e9 for cf in _cfs],     color="#00c4ff", alpha=0.6, label="Projected FCF")
            ax_d.plot(_yrs, [pv / 1e9 for pv in _pv_cfs], color="#f4a21e", marker="o", lw=1.5, label="PV of FCF")
            ax_d.set_xlabel("Year", color="white")
            ax_d.set_ylabel("FCF ($B)", color="white")
            ax_d.set_title("10-Year Projected Free Cash Flows", color="white")
            ax_d.legend(facecolor="#1a1a2e", labelcolor="white", fontsize=9)
            ax_d.xaxis.set_major_locator(plt.MaxNLocator(integer=True))
            st.pyplot(fig_d)
            plt.close(fig_d)
            st.caption("⚠️ DCF valuations are highly sensitive to assumptions. For educational use only, not investment advice.")
else:
    st.info("DCF analysis unavailable — requires positive Free Cash Flow data.")

st.divider()

# Sector Ratio Comparison
st.subheader("Sector Ratio Comparison")

# Tuples: (sector_low, sector_high, higher_is_better)
# D/E uses yfinance scale (already in % form, e.g. 150 = 1.5x)
# Margin / ROE / ROA are stored here as %-points (0-100 scale)
SECTOR_BENCHMARKS = {
    "Technology": {
        "P/E (TTM)":     (15,   35,  False), "P/B Ratio":     (3,    10,  False),
        "P/S Ratio":     (3,    9,   False),  "EV/EBITDA":     (12,   25,  False),
        "Profit Margin": (10,   28,  True),   "ROE":           (15,   35,  True),
        "ROA":           (8,    18,  True),   "Debt/Equity":   (0,    150, False),
        "Current Ratio": (1.5,  3.5, True),
    },
    "Healthcare": {
        "P/E (TTM)":     (14,   28,  False), "P/B Ratio":     (2,    6,   False),
        "P/S Ratio":     (2,    5,   False),  "EV/EBITDA":     (10,   20,  False),
        "Profit Margin": (8,    20,  True),   "ROE":           (10,   22,  True),
        "ROA":           (5,    12,  True),   "Debt/Equity":   (20,   200, False),
        "Current Ratio": (1.5,  2.5, True),
    },
    "Financial Services": {
        "P/E (TTM)":     (10,   18,  False), "P/B Ratio":     (1,    2.5, False),
        "P/S Ratio":     (1,    3,   False),  "EV/EBITDA":     (8,    15,  False),
        "Profit Margin": (15,   35,  True),   "ROE":           (10,   18,  True),
        "ROA":           (1,    2,   True),   "Debt/Equity":   (200,  500, False),
        "Current Ratio": (1.0,  2.0, True),
    },
    "Consumer Cyclical": {
        "P/E (TTM)":     (12,   25,  False), "P/B Ratio":     (2,    5,   False),
        "P/S Ratio":     (0.5,  2,   False),  "EV/EBITDA":     (8,    15,  False),
        "Profit Margin": (4,    10,  True),   "ROE":           (12,   22,  True),
        "ROA":           (4,    10,  True),   "Debt/Equity":   (50,   200, False),
        "Current Ratio": (1.2,  2.0, True),
    },
    "Consumer Defensive": {
        "P/E (TTM)":     (14,   22,  False), "P/B Ratio":     (2,    5,   False),
        "P/S Ratio":     (0.5,  1.5, False),  "EV/EBITDA":     (10,   16,  False),
        "Profit Margin": (5,    12,  True),   "ROE":           (15,   25,  True),
        "ROA":           (6,    12,  True),   "Debt/Equity":   (40,   150, False),
        "Current Ratio": (1.0,  2.0, True),
    },
    "Energy": {
        "P/E (TTM)":     (8,    18,  False), "P/B Ratio":     (1,    3,   False),
        "P/S Ratio":     (0.5,  1.5, False),  "EV/EBITDA":     (5,    10,  False),
        "Profit Margin": (5,    15,  True),   "ROE":           (10,   20,  True),
        "ROA":           (4,    10,  True),   "Debt/Equity":   (30,   150, False),
        "Current Ratio": (1.0,  1.8, True),
    },
    "Utilities": {
        "P/E (TTM)":     (14,   22,  False), "P/B Ratio":     (1.5,  3,   False),
        "P/S Ratio":     (1.5,  3,   False),  "EV/EBITDA":     (9,    14,  False),
        "Profit Margin": (10,   20,  True),   "ROE":           (10,   16,  True),
        "ROA":           (3,    7,   True),   "Debt/Equity":   (100,  300, False),
        "Current Ratio": (0.6,  1.2, True),
    },
    "Industrials": {
        "P/E (TTM)":     (14,   22,  False), "P/B Ratio":     (2,    5,   False),
        "P/S Ratio":     (1,    2.5, False),  "EV/EBITDA":     (10,   16,  False),
        "Profit Margin": (6,    12,  True),   "ROE":           (12,   22,  True),
        "ROA":           (5,    10,  True),   "Debt/Equity":   (40,   150, False),
        "Current Ratio": (1.2,  2.0, True),
    },
    "Basic Materials": {
        "P/E (TTM)":     (10,   20,  False), "P/B Ratio":     (1.5,  3.5, False),
        "P/S Ratio":     (0.5,  2,   False),  "EV/EBITDA":     (6,    12,  False),
        "Profit Margin": (5,    15,  True),   "ROE":           (10,   20,  True),
        "ROA":           (5,    10,  True),   "Debt/Equity":   (25,   120, False),
        "Current Ratio": (1.2,  2.0, True),
    },
    "Real Estate": {
        "P/E (TTM)":     (20,   40,  False), "P/B Ratio":     (1,    2.5, False),
        "P/S Ratio":     (3,    8,   False),  "EV/EBITDA":     (15,   25,  False),
        "Profit Margin": (20,   40,  True),   "ROE":           (6,    12,  True),
        "ROA":           (2,    5,   True),   "Debt/Equity":   (100,  300, False),
        "Current Ratio": (0.5,  1.5, True),
    },
    "Communication Services": {
        "P/E (TTM)":     (14,   28,  False), "P/B Ratio":     (2,    6,   False),
        "P/S Ratio":     (1.5,  4,   False),  "EV/EBITDA":     (8,    18,  False),
        "Profit Margin": (8,    20,  True),   "ROE":           (12,   25,  True),
        "ROA":           (5,    12,  True),   "Debt/Equity":   (40,   150, False),
        "Current Ratio": (1.0,  2.0, True),
    },
}

_sector     = info.get("sector", "")
_benchmarks = SECTOR_BENCHMARKS.get(_sector)

if _benchmarks:
    _pm  = info.get("profitMargins")
    _roe = info.get("returnOnEquity")
    _roa = info.get("returnOnAssets")
    _ratio_map = {
        "P/E (TTM)":     info.get("trailingPE"),
        "P/B Ratio":     info.get("priceToBook"),
        "P/S Ratio":     info.get("priceToSalesTrailing12Months"),
        "EV/EBITDA":     info.get("enterpriseToEbitda"),
        "Profit Margin": _pm  * 100 if _pm  is not None else None,
        "ROE":           _roe * 100 if _roe is not None else None,
        "ROA":           _roa * 100 if _roa is not None else None,
        "Debt/Equity":   info.get("debtToEquity"),
        "Current Ratio": info.get("currentRatio"),
    }

    _rows = []
    for _metric, (_lo, _hi, _hb) in _benchmarks.items():
        _val = _ratio_map.get(_metric)
        if _val is None:
            _flag, _lbl = "⬜", "N/A"
        elif _hb:
            if _val >= _hi:   _flag, _lbl = "🟢", "Above Average"
            elif _val >= _lo: _flag, _lbl = "🟡", "Average"
            else:             _flag, _lbl = "🔴", "Below Average"
        else:
            if _val <= _lo:   _flag, _lbl = "🟢", "Favorable"
            elif _val <= _hi: _flag, _lbl = "🟡", "Typical"
            else:             _flag, _lbl = "🔴", "Elevated"
        _rows.append({
            "Metric":      _metric,
            "Company":     f"{_val:.2f}" if _val is not None else "N/A",
            "Sector Low":  f"{_lo:.2f}",
            "Sector High": f"{_hi:.2f}",
            "Assessment":  f"{_flag} {_lbl}",
        })

    st.markdown(f"**Sector: {_sector}** — benchmarks reflect typical S&P 500 ranges by sector.")
    st.dataframe(pd.DataFrame(_rows).set_index("Metric"), use_container_width=True)

    # Radar chart — outer edge = more favorable regardless of metric direction
    _radar_keys = ["P/E (TTM)", "P/B Ratio", "EV/EBITDA", "Profit Margin", "ROE", "Current Ratio"]
    _radar_vals = []
    for _m in _radar_keys:
        _v = _ratio_map.get(_m)
        _lo, _hi, _hb = _benchmarks[_m]
        if _v is None or _hi == _lo:
            _radar_vals.append(0.5)
        else:
            _norm = max(0.0, min(1.0, (_v - _lo) / (_hi - _lo)))
            _radar_vals.append(_norm if _hb else 1.0 - _norm)

    _angles  = np.linspace(0, 2 * np.pi, len(_radar_keys), endpoint=False).tolist()
    _rv_plot = _radar_vals + [_radar_vals[0]]
    _ag_plot = _angles    + [_angles[0]]

    fig_r, ax_r = plt.subplots(figsize=(6, 6), subplot_kw=dict(polar=True))
    fig_r.patch.set_facecolor(BG)
    ax_r.set_facecolor(BG)
    ax_r.plot(_ag_plot, _rv_plot, color="#00c4ff", lw=2)
    ax_r.fill(_ag_plot, _rv_plot, color="#00c4ff", alpha=0.25)
    ax_r.set_xticks(_angles)
    ax_r.set_xticklabels(_radar_keys, color="white", size=9)
    ax_r.set_yticks([0.25, 0.5, 0.75, 1.0])
    ax_r.set_yticklabels(["25%", "50%", "75%", "100%"], color="#888", size=7)
    ax_r.set_ylim(0, 1)
    ax_r.set_title(f"{ticker} vs {_sector} Benchmarks", color="white", pad=20)
    ax_r.grid(color="#333")
    ax_r.spines["polar"].set_edgecolor("#444")

    _, _rc2, _ = st.columns([1, 2, 1])
    with _rc2:
        st.pyplot(fig_r)
    plt.close(fig_r)
    st.caption("Radar shows normalized score vs. sector range — outer edge = more favorable. Based on typical S&P 500 sector medians.")

elif _sector:
    st.info(f"Sector benchmarks not available for '{_sector}'.")
else:
    st.info("Sector information not available for this ticker.")

st.divider()

# Excel export
st.subheader("Export to Excel")

@st.cache_data(ttl=300)
def build_excel(ticker, hist_json, valuation, income, balance):
    hist_df = pd.read_json(hist_json)
    buf = BytesIO()
    with pd.ExcelWriter(buf, engine="openpyxl") as writer:
        hist_df.reset_index().to_excel(writer,
                                       sheet_name="Price & Indicators",
                                       index=False)
        rows = max(len(valuation), len(income), len(balance))
        val_keys   = list(valuation.keys())   + [""] * (rows - len(valuation))
        val_vals   = list(valuation.values()) + [""] * (rows - len(valuation))
        inc_keys   = list(income.keys())      + [""] * (rows - len(income))
        inc_vals   = list(income.values())    + [""] * (rows - len(income))
        bal_keys   = list(balance.keys())     + [""] * (rows - len(balance))
        bal_vals   = list(balance.values())   + [""] * (rows - len(balance))
        fund_df = pd.DataFrame({
            "Valuation Metric":    val_keys,
            "Valuation Value":     val_vals,
            "Income Metric":       inc_keys,
            "Income Value":        inc_vals,
            "Balance Metric":      bal_keys,
            "Balance Value":       bal_vals,
        })
        fund_df.to_excel(writer, sheet_name="Fundamentals", index=False)
    return buf.getvalue()

excel_bytes = build_excel(ticker, hist.to_json(), valuation, income, balance)

st.download_button(
    label=f"Download {ticker} Snapshot (.xlsx)",
    data=excel_bytes,
    file_name=f"{ticker}_snapshot.xlsx",
    mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
)
