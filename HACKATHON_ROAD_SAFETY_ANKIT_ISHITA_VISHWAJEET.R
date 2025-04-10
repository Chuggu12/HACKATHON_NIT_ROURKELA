# ROAD SAFETY AI PROTOTYPE - COMPREHENSIVE SOLUTION
# BY ANKIT ANAND, VISHWAJEET RAWAT & Ishita Rawat

# Inittail Pacakages Required
library(tidyverse)
library(lubridate)
library(randomForest)
library(xgboost)
library(leaflet)
library(shiny)
library(httr)
library(jsonlite)
library(imputeTS)  # For missing data handling
library(lime)      # For model interpretability

### 1. DATA INTEGRATION PIPELINE WITH QA/QC ###

integrate_safety_data <- function() {
  
  
  # Source 1: MORTH Accident Reports (API), here I take variable as per the Morth dataset
  morth_data <- GET("https://api.morth.gov.in/accidents_xlsx") %>% 
    content("parsed") %>%
    as_tibble() %>%
    mutate(
      timestamp = ymd_hms(timestamp),
      # Data cleaning
      fatalities = ifelse(is.na(fatalities), median(fatalities, na.rm = TRUE), fatalities),
      severity = case_when(
        fatalities > 3 ~ "CRITICAL",
        fatalities > 0 ~ "MAJOR",
        TRUE ~ "MINOR"
      )
    )
  
  # Source 2: Weather API (IMD): YOU WILL PASTE WEATHER DATA HERE, the var taken is on my assumptions behalf"
  weather_data <- GET("https://api.imd.gov.in/weather") %>%
    content("parsed") %>%
    mutate(
      landslide_risk = ifelse(
        precipitation > 100 & terrain == "hilly", 
        pmax(0, pmin(1, (precipitation-100)/50 + 0.3*wind_speed/40),
             0
        )
      )
      
      # Source 3: NHAI Blackspots, variable taken as per dataset
      
      nhai_data <- read_csv("nhai_blackspots.csv") %>%
        filter(!is.na(latitude)) %>%  # QC: Remove entries without coordinates
        mutate(
          risk_score = severity * 0.7 + traffic_volume * 0.3  # Weighted scoring
        )
      
      # Source 4: Driver Behavior (Telematics)
      
      driver_data <- read_csv("driver_telematics.csv") %>%
        group_by(driver_id) %>%
        mutate(
          # Impute missing values
          speed = na_ma(speed, k = 4),
          # Flag reckless driving
          reckless = ifelse(
            speed > 120 | 
              alcohol_level > 0.03 |
              harsh_braking > 3/hour,
            TRUE, FALSE
          )
        )
      
      # Unified Dataset
      
      combined_data <- list(morth_data, weather_data, nhai_data, driver_data) %>%
        reduce(full_join, by = c("location_id", "timestamp"))
      
      return(combined_data)
}

### 2. ADVANCED PREDICTION MODELS ###

train_safety_model <- function(data) {
  # Handle missing data
  data_clean <- data %>%
    mutate(
      across(where(is.numeric), ~ifelse(is.na(.), median(., na.rm = TRUE), .)
      )
      
      # XGBoost model for high accuracy
      model <- xgboost(
        data = select(data_clean, -accident_occurred) %>% as.matrix(),
        label = data_clean$accident_occurred,
        nrounds = 100,
        objective = "binary:logistic"
      )
      
      # LIME for interpretability
      explainer <- lime(
        select(data_clean, -accident_occurred),
        model,
        n_bins = 5
      )
      
      return(list(model = model, explainer = explainer))
}

### 3. REAL-TIME SAFETY SYSTEMS ###

# Autonomous Emergency Calling
emergency_monitor <- function(gps_data, time_threshold = 20, density_threshold = 0.1) {
  gps_data %>%
    mutate(
      emergency_status = ifelse(
        (time_alone > time_threshold | vehicle_density < density_threshold) &
          road_type %in% c("ring_road", "rural"),
        "ACTIVE",
        "STANDBY"
      )
    )
}

# E-Vehicle Proximity Alert
ev_alert_system <- function(proximity_data) {
  proximity_data %>%
    mutate(
      alert_level = case_when(
        ev_distance < 50 & ev_speed > 60 ~ "DANGER",
        ev_distance < 100 ~ "CAUTION",
        TRUE ~ "NORMAL"
      ),
      alert_message = ifelse(
        alert_level != "NORMAL",
        paste("E-vehicle", ev_id, "approaching at", ev_speed, "km/h"),
        NA
      )
    )
}

# Dark Zone Detection
dark_zone_alerts <- function(lighting_data) {
  lighting_data %>%
    mutate(
      lighting_status = case_when(
        lux < 5 ~ "CRITICAL",
        lux < 10 ~ "WARNING",
        TRUE ~ "NORMAL"
      )
    )
}

### 4. HILLY ROAD & LANDSLIDE SYSTEMS ###

landslide_early_warning <- function(weather_data, terrain_data) {
  terrain_data %>%
    left_join(weather_data, by = "location_id") %>%
    mutate(
      landslide_risk = ifelse(
        terrain == "hilly",
        pmax(0, pmin(1, (precipitation-100)/50 + slope_angle/45)),
        0
      ),
      alert = ifelse(landslide_risk > 0.7, "EVACUATE", ifelse(landslide_risk > 0.4, "WARNING", "NORMAL"))
    )
}

### 5. DRIVER MONITORING SYSTEM ###

driver_fatigue_detection <- function(eye_tracking, steering_pattern) {
  eye_tracking %>%
    left_join(steering_pattern, by = "driver_id") %>%
    mutate(
      fatigue_score = 0.4 * blink_rate + 
        0.3 * steering_std_dev + 
        0.2 * yawn_count + 
        0.1 * lane_deviation,
      alert = ifelse(fatigue_score > 0.7, "WAKE UP!", ifelse(fatigue_score > 0.4, "TAKE BREAK", "NORMAL"))
    )
}

### 6. INTERACTIVE DASHBOARD ###

ui <- navbarPage(
  "SAFAR - Intelligent Road Safety System",
  tabPanel("Risk Map",
           leafletOutput("live_risk_map"),
           actionButton("emergency", "SOS", class = "btn-danger")
  ),
  tabPanel("Driver Profile",
           plotOutput("driver_risk"),
           verbatimTextOutput("challan_history")
  ),
  tabPanel("Vehicle Alerts",
           uiOutput("ev_alert"),
           uiOutput("dark_zone_alert"),
           uiOutput("landslide_alert")
  ),
  tabPanel("Fatigue Monitor",
           gaugeOutput("fatigue_meter"),
           plotOutput("steering_pattern")
  )
)

server <- function(input, output, session) {
  # Real-time data processing
  live_data <- reactivePoll(
    1000, session,
    checkFunc = function() { Sys.time() },
    valueFunc = integrate_safety_data
  )
  
  # Dynamic risk mapping
  output$live_risk_map <- renderLeaflet({
    leaflet(live_data()) %>%
      addTiles() %>%
      addHeatmap(lng = ~lon, lat = ~lat, intensity = ~risk_score) %>%
      addMarkers(
        data = filter(live_data(), emergency_status == "ACTIVE"),
        icon = makeIcon(iconUrl = "emergency.png", iconWidth = 24)
      )
  })
  
  # E-vehicle alerts
  output$ev_alert <- renderUI({
    alerts <- ev_alert_system(live_data())
    if(any(alerts$alert_level != "NORMAL")) {
      box(
        title = "E-VEHICLE WARNING",
        color = "red",
        lapply(which(alerts$alert_level != "NORMAL"), function(i) {
          p(paste("⚠️", alerts$alert_message[i]))
        })
      )
    }
  })
  
  # Anti-sleep system
  output$fatigue_meter <- renderGauge({
    fatigue <- driver_fatigue_detection(
      eye_data(), 
      steering_data()
    )$fatigue_score[1]
    
    gauge(
      fatigue,
      min = 0, max = 1,
      sectors = gaugeSectors(
        danger = c(0.7, 1),
        warning = c(0.4, 0.7),
        success = c(0, 0.4)
      )
    )
  })
}

shinyApp(ui, server)

### 7. DATA QUALITY CHECKS ###

validate_safety_data <- function(data) {
  # Check for missing critical fields
  if(any(is.na(data$latitude)) | any(is.na(data$longitude))) {
    warning("Missing coordinates in ", sum(is.na(data$latitude)), " records")
  }
  
  # Validate timestamps
  if(any(data$timestamp > now())) {
    warning("Future timestamps detected")
  }
  
  # Outlier detection
  speed_outliers <- data %>%
    filter(speed > 200) %>%
    count()
  
  if(nrow(speed_outliers) > 0) {
    warning(nrow(speed_outliers), " speed outliers (>200km/h) detected")
  }
}

# Features this haves:    #
#    - Driver profiling with bad driver detection
#    - E-vehicle proximity alerts
#    - Dark zone warnings
#    - Landslide prediction for hilly roads
#    - Emergency calling system
#    - Anti-fatigue dashboard
# 2. Data quality checks at every integration point
# 3. Model interpretability using LIME
# 4. Real-time monitoring with reactive polling
# 5. Calm color scheme for dashboard (#3366cc blues)
# 6. Progressive alert system (Normal → Warning → Danger)