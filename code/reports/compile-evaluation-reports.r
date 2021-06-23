# packages ---------------------------------------------------------------------
library(dplyr)
library(here)
library(readr)
library(scoringutils)
library(rmarkdown)
library(data.table)
library(covidHubUtils)
library(lubridate)
source(here("code", "config_utils", "get_hub_config.R"))
data_types <- get_hub_config("target_variables")

options(knitr.duplicate.label = "allow")

report_date <- today()
wday(report_date) <- get_hub_config("forecast_week_day")

suppressWarnings(dir.create(here::here("html")))

last_forecast_date <- report_date
## load forecasts --------------------------------------------------------------
raw_forecasts <- load_forecasts(
  source = "local_hub_repo",
  hub_repo_path = here(),
  hub = "ECDC"
) %>%
  # set forecast date to corresponding submission date
  mutate(forecast_date = ceiling_date(forecast_date, "week", week_start = 2) - 1) %>%
  filter(between(forecast_date, ymd("2021-03-08"), ymd(report_date))) %>%
  rename(prediction = value)

## load truth data -------------------------------------------------------------
raw_truth <- load_truth(
  truth_source = "JHU",
  target_variable = data_types,
  truth_end_date = report_date,
  hub = "ECDC"
)

# get anomalies
anomalies <- read_csv(here("data-truth", "anomalies", "anomalies.csv"))

truth <- anti_join(raw_truth, anomalies) %>%
  mutate(model = NULL) %>%
  rename(true_value = value)

# remove forecasts made directly after a data anomaly
forecasts <- raw_forecasts %>%
  mutate(previous_end_date = forecast_date - 2) %>%
  left_join(anomalies %>%
            rename(previous_end_date = target_end_date),
            by = c("target_variable",
                   "location", "location_name",
                   "previous_end_date")) %>%
  filter(is.na(anomaly)) %>%
  select(-anomaly, -previous_end_date)

data <- scoringutils::merge_pred_and_obs(forecasts, truth,
                                         join = "full")

for (i in 1:nrow(hub_locations_ecdc)) {
  country_code <- hub_locations_ecdc$location[i]
  country <- hub_locations_ecdc$location_name[i]

  rmarkdown::render(here::here("code", "reports", "evaluation",
                               "evaluation-by-country.Rmd"),
                    output_format = "html_document",
                    params = list(data = data,
                                  location_code = country_code,
                                  location_name = country,
                                  report_date = report_date,
                                  restrict_weeks = 4),
                    output_file =
                      here::here("html",
                                 paste0("evaluation-report-",
                                        country, ".html")),
                    envir = new.env())
}

rmarkdown::render(here::here("code", "reports", "evaluation",
                             "evaluation-report.Rmd"),
                  params = list(data = data,
                                report_date = report_date,
                                restrict_weeks = 4),
                  output_format = "html_document",
                  output_file =
                    here::here("html", paste0("evaluation-report-",
                                              "Overall.html")),
                  envir = new.env())

## to make this generalisable
# allow bits to be turned off and on
# somehow pass down the filtering
