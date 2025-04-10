# SAFAR: AI-Powered Road Safety System for India 🚦: ANKIT ANAND

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R Version](https://img.shields.io/badge/R-%3E%3D%204.0-blue)](https://www.r-project.org/)

## 📌 Overview

SAFAR (Smart AI for Accident Reduction) is an end-to-end machine learning system built in R that predicts and prevents road accidents through:

1. **Real-time risk prediction** using traffic, weather and road data
2. **Automated safety interventions** (emergency calls, driver alerts)
3. **Policy dashboard** for transportation authorities

## 🛠️ Technical Implementation

### 📂 Data Pipeline

```r
# Load required packages
library(httr)
library(dplyr)
library(imputeTS)

# Fetch and clean MORTH accident data
get_morth_data <- function() {
  GET("https://api.morth.gov.in/accidents") %>% 
    content("parsed") %>%
    mutate(
      fatalities = na_ma(fatalities, k = 4), # Impute missing values
      severity = case_when(
        fatalities > 3 ~ "CRITICAL",
        fatalities > 0 ~ "MAJOR",
        TRUE ~ "MINOR"
      )
    )
}
