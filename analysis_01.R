# Run a Two-one-sided-test on Liv's data

library(dplyr)
library(TOSTER)
library(ggplot2)

# Deal with density data seperately as very different structure
# and needs several calculations

liv_density <- readxl::read_xlsx(here::here("data", "density.xlsx"),
                                 range = cell_cols("A:K"))
# Specification from Dunlop, in kg/m3
density_spec <- tibble::tribble(
  ~foam, ~min, ~max,
  "VF",       58.0, 62.0,
  "EN40-230", 39.0, 42.0,
  "EN50-250", 49.0, 53.5
)

# Calculate various volumes in mm3
liv_density <- liv_density %>%
  mutate(t_mean = rowMeans(across(starts_with("T"))),
         vf_vol = length * width * vf_thickness,
         sag_vol = (sag_height * sag_width * length), # cutout for seat sag
         hr_vol = length * width * t_mean - vf_vol - sag_vol
        ) %>%
# The mass of VF is unknown, but can be estimated from the density_spec
  mutate(
    vf_min_mass = (vf_vol / 1E9) * filter(density_spec, foam == "VF")$max * 1000,
    vf_max_mass = (vf_vol / 1E9) * filter(density_spec, foam == "VF")$min * 1000,
    hr_max_mass = mass - vf_min_mass, # grams
    hr_min_mass = mass - vf_max_mass,
    hr_min = 1E6 * hr_min_mass / hr_vol,  # Convert back to kg/m3
    hr_max = 1E6 * hr_max_mass / hr_vol
  )


# Read the testing results
data_file <- here::here("data", "results.xlsx")

# Display sheet names
sheet_names <- readxl::excel_sheets(data_file)
print(sheet_names)

# Read the two sheets constructed from Liv's data & name them
# Convert to long form for easier analysis,
# then combine both data sets by row and
# group by foam type, variable and the load level for each result
liv_data <- sheet_names %>%                  # Take the named sheets
  purrr::set_names() %>%                     # make them a named list
  purrr::map(                                # apply a function to each element
    function(x) {
      readxl::read_excel(data_file, x) %>%   # read the named sheet
      tidyr::pivot_longer(cols = where(is.numeric), # use the results columns
                   names_to = "level",       # column names to 'level'
                   values_to = "value"       # each value to 'value'
                  )
    }
  ) %>%
  bind_rows(.id = "var") %>%      # combine by rows, put original names in 'var'
  group_by(foam, var, level)      # make groups for each independent measurement

# liv_data is now a list with columns named
# var = lcdod or hysteresis
# cushion = cushion ID number
# foam = EN40-230 or EN50-250
# level = load level for measurement
# value = measurement

# Define a function to calculate the span of the given percentile
# percentile defaults to 95% (0.95)
CI = function(sd, percentile = 0.95) {
  interval = (percentile + 1)/2
  qnorm(p = interval, mean = 0, sd = sd)
}

# Show the Summary stats for each variable,including the 95% CI
liv_summary <- liv_data %>%
  summarise(avg = mean(value), sd = sd(value), n = n()) %>%
  mutate(delta = CI(sd, 0.95), lo_95 = avg - delta, hi_95 = avg + delta) %>%
  select(-delta) %>%
  arrange(var, level, foam)

print(liv_summary)

# Make some simple box plots to show the spread of the data
plots <- list()
for (var_name in unique(liv_data$var)) {
  plots[[var_name]] <- liv_data %>%
    filter(var == var_name) %>%
    ggplot() +
    aes(y = value, x = foam, colour = foam) +
    geom_boxplot() +
    geom_jitter(colour = "black", width = 0.25) +
    labs(title = var_name, y = var_name) +
    facet_wrap(~level)
}
print(plots)

# Notice an issue with one result - check if the density or mass is related
density_plot <- liv_data %>%
  filter(var == "hysteresis", foam == "EN40-230") |>
  left_join(liv_density, by = "cushion") |>
  ggplot() +
  aes(x=hr_max, y = value, colour = level, label = cushion) +
  geom_point() +
  geom_label(hjust = "left", alpha = 0.5, position = "dodge")

print(density_plot)

liv_data %>% ungroup() %>% group_by(var, level) %>%
  group_walk(\(group_data, keys) {
    print(names(group_data));
    print(names(keys));
    TOSTER::dataTOSTtwo(group_data, deps = value, group = foam)
    }
    )




