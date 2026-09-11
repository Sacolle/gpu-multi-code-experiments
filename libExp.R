library(DoE.base)
library(glue)
library(tidyverse)
library(tidyverse)
library(ggplot2)
library(dplyr)
library(patchwork)
library(stringr)


# function to make the experiments
# Use case
# sf_cpu_factors <- list(
#   WithIO =  c(0, 1),
#   Schedulers = c("random", "ws", "lws", "dm", "dmdar")
# )
#  sf_ex <- generate_experiment(sf_cpu_factors, replications, seed) 
generate_experiment <- function(factors, replications, seed) {
  DoE.base::fac.design(
    nfactors = length(factors),
    replications = replications,
    repeat.only = FALSE,
    randomize = TRUE,
    seed = seed,
    nlevels = sapply(factors, length),
    factor.names = factors
  )
}


machines <- read_csv("./machines.csv")

# Take a table and a row of that table that represents the file to be read for each line and apply the parse_fn
# to it. The parse_fn needs to return a tibble so that it can be unnested
parse_files <- function(tibble, FILE, parse_fn){
  mutate(tibble, Data = map( {{ FILE }} , function(file) {
    if(!dir.exists(dirname(file))){
      return(NULL)
    }
    lines <- tryCatch({
        read_lines(file)
    }, error = function(e){
        message(paste0("Warning: Failed to read file: ", file, ". Skipping..."))
        return(NULL) # Returns NULL instead of breaking the script
    })
    if(is.null(lines)) {
      return(NULL)
    }
    parse_fn(lines)
    })) |>
    filter(lengths(Data) > 0) |>
    unnest(Data)
}
