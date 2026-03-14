# ---------------------------------------------------------
# PROJECT: QUANTITATIVE SEASONALITY & VOLATILITY DIVERGENCE
# GOAL: IDENTIFY "SUMMER CREEP" & OPTION MISPRICING
# ---------------------------------------------------------

# 1. LOAD REQUIRED LIBRARIES
if (!require("patchwork")) install.packages("patchwork")
library(tidyquant)
library(tidyverse)
library(lubridate)
library(patchwork)

# 2. DATA ENGINE
symbols <- c("^VIX", "^VVIX")
raw_data <- tq_get(symbols, from = today() - years(10), to = today()) %>%
  select(symbol, date, close) %>%
  pivot_wider(names_from = symbol, values_from = close) %>%
  rename(vix = `^VIX`, vvix = `^VVIX`) %>%
  mutate(month = month(date, label = TRUE, abbr = TRUE),
         year = year(date))

# 3. STATISTICAL CALCULATIONS
monthly_stats <- raw_data %>%
  group_by(month) %>%
  summarise(
    avg_vix = mean(vix, na.rm = TRUE),
    sd_vix  = sd(vix, na.rm = TRUE),
    avg_vvix = mean(vvix, na.rm = TRUE),
    sd_vvix  = sd(vvix, na.rm = TRUE),
    .groups = 'drop'
  )

final_data <- raw_data %>%
  left_join(monthly_stats, by = "month") %>%
  mutate(
    vix_z_score = (vix - avg_vix) / sd_vix,
    vix_upper_1sd = avg_vix + sd_vix,
    vix_lower_1sd = avg_vix - sd_vix
  )

# 4. GENERATE TANGIBLE DELIVERABLES (Files)

# A. Visual: 10-Year Macro Dashboard
# Top Pane: VIX Price vs Seasonal Normal
p1 <- ggplot(final_data, aes(x = date)) +
  geom_ribbon(aes(ymin = vix_lower_1sd, ymax = vix_upper_1sd), fill = "blue", alpha = 0.1) +
  geom_line(aes(y = vix), color = "steelblue", size = 0.5) +
  geom_line(aes(y = avg_vix), color = "black", linetype = "dashed", alpha = 0.5) +
  labs(title = "10-Year VIX Seasonality Analysis", 
       subtitle = "Shaded area represents 1-Standard Deviation from Monthly Mean",
       y = "VIX Price (Raw)") +
  theme_minimal()

# Bottom Pane: VVIX (The Panic Filter)
p2 <- ggplot(final_data, aes(x = date)) +
  geom_line(aes(y = vvix), color = "purple", size = 0.5) +
  labs(title = "VVIX (Volatility of Volatility)", y = "VVIX Price",
       caption = "Data Source: Yahoo Finance via Tidyquant") +
  theme_minimal()

# Combine Panes
macro_dashboard <- p1 / p2
ggsave("LinkedIn_Macro_Volatility.png", macro_dashboard, width = 12, height = 8, dpi = 300)

# B. Data: Professional Excel Exports
write.csv(final_data, "VIX_Daily_Analysis_Full.csv", row.names = FALSE)
write.csv(monthly_stats, "VIX_Monthly_Benchmarks.csv", row.names = FALSE)

# 5. CONSOLE REPORT (Executive Summary)
cat("\n--- PROJECT EXPORT COMPLETE ---\n")
cat("Generated: LinkedIn_Macro_Volatility.png (Visual Evidence)\n")
cat("Generated: VIX_Monthly_Benchmarks.csv (Data Evidence)\n")
