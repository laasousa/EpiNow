#' Estimate time varying measures for nowcast
#'
#' @param nowcast A nowcast as produced by `nowcast_pipeline`
#' @param window Numeric, the time window over which to vary the parameters.
#' @param start_rate_of_spread_est A character string in the form of a date ("2020-01-01")
#' @inheritParams estimate_R0
#' @return
#' @export
#' @importFrom tidyr gather nest unnest drop_na
#' @importFrom dplyr filter group_by ungroup mutate select summarise n group_split bind_rows arrange
#' @importFrom purrr safely compact
#' @importFrom furrr future_map
#' @importFrom data.table setDT
#' @examples
#'
estimate_time_varying_measures_for_nowcast <- function(nowcast = NULL,
                                                       serial_intervals = NULL,
                                                       start_rate_of_spread_est = NULL,
                                                       si_samples = NULL, rt_samples = NULL,
                                                       window = 7, rt_prior = NULL) {

  ## Estimate time-varying R0
  safe_R0 <- purrr::safely(EpiNow::estimate_R0)

  message("Estimate time-varying R0")
  data_list <-  dplyr::group_split(nowcast, type, sample, keep = TRUE)


  R0_estimates <- furrr::future_map(data_list, function(data) {
    R0 <- safe_R0(cases = data,
            serial_intervals = serial_intervals,
            rt_prior = rt_prior,
            si_samples = si_samples,
            rt_samples = rt_samples,
            window = window)[[1]]

    if (!is.null(R0)) {
     R0 <-  dplyr::mutate(R0, type = data$type[1],
                    sample = data$sample[1])
    }

    return(R0)
    }, .progress = TRUE)

  R0_estimates <- purrr::compact(R0_estimates)
  R0_estimates <- purrr::map(R0_estimates, ~ tidyr::unnest(., R))
  R0_estimates <- dplyr::bind_rows(R0_estimates)


  message("Summarising time-varying R0")

  R0_estimates_sum <- data.table::setDT(R0_estimates)[, .(
    bottom = quantile(R, 0.025, na.rm = TRUE),
    top = quantile(R, 0.975, na.rm = TRUE),
    lower = quantile(R, 0.25, na.rm = TRUE),
    upper = quantile(R, 0.75, na.rm = TRUE),
    median = median(R, na.rm = TRUE),
    mean = mean(R, na.rm = TRUE),
    std = sd(R, na.rm = TRUE),
    prob_control = (sum(R < 1) / .N)),
    by = .(type, date)
    ][, R0_range := paste(round(bottom, 1),
                          round(top, 1),
                          sep = " -- "),]


  R0_estimates_sum <- dplyr::arrange(R0_estimates_sum, date)

  ## Estimate time-varying little r
  message("Estimate time-varying rate of growth")

  if (!is.null(start_rate_of_spread_est)) {
    little_r_estimates <- nowcast %>%
      dplyr::filter(date >= as.Date(start_rate_of_spread_est))
  }else{
    little_r_estimates <- nowcast
  }

  ## Sum across cases and imports
  little_r_estimates <- little_r_estimates %>%
    group_by(type, sample, date) %>%
    dplyr::summarise(cases = sum(cases, na.rm  = TRUE)) %>%
    dplyr::ungroup() %>%
    tidyr::drop_na()

  ## Nest by type and sample then split by type only
  little_r_estimates_list <- little_r_estimates %>%
    dplyr::group_by(type, sample) %>%
    tidyr::nest() %>%
    dplyr::ungroup() %>%
    dplyr::group_split(type, keep = TRUE)

  ## Pull out unique list
  little_r_estimates_res <- little_r_estimates %>%
    dplyr::select(type) %>%
    unique()

  ## Estimate overall
  little_r_estimates_res$overall_little_r <- furrr::future_map(little_r_estimates_list,
                                                        ~ EpiNow::estimate_r_in_window(.$data), 
                                                        .progress = TRUE)

  ## Estimate time-varying
  little_r_estimates_res$time_varying_r <- furrr::future_map(little_r_estimates_list,
                                                             ~ EpiNow::estimate_time_varying_r(.$data,
                                                                                                    window = window),
                                                             .progress = TRUE)


  out <- list(R0_estimates_sum, little_r_estimates_res)

  return(out)
}

