#' Real-time Pipeline
#'
#' @description Combine fitting a delay distribution, constructing a set of
#' complete sampled linelists, nowcast cases by onset date, and estimate
#' the time-varying effective reproduction number and rate of spread.
#' @param cases A dataframe of cases (`confirm`) by date of confirmation (`date`) and import status (`import_status`)
#' @param linelist A dataframe of of cases (by row) containing the following variables:
#' `import_status` (values "local" and "imported"), `date_onset`, `date_confirm`, `report_delay`.
#' @param target_folder Character string, name of the folder in which to save the results.
#' @param target_date Character string, in the form "2020-01-01". Date to cast.
#' @param delay_cutoff_date Character string, in the form "2020-01-01". Cutoff date to use
#' to estimate the delay distribution.
#' @param predict_lag Numeric, number of days to use as a prediction lag. Defaults to 0.
#' @param samples Numeric, the number of pseudo linelists to generate. Defaults to 1000.
#' @param window Numeric, the window to use to estimate time-varying parameters. Defaults to 7.
#' @param earliest_allowed_onset A character string in the form of a date ("2020-01-01") indiciating the earliest
#' allowed onset.
#' @param start_rate_of_spread_est A character string in the form of a date ("2020-01-01") indicating the start time to
#' estimate the rate of sprea.
#' @param case_only Logical, defaults to `FALSE`. Should estimates also be made based on reported cases.
#' @param serial_intervals A matrix with columns representing samples and rows representing the probability of the serial intervel being on
#' that day. Defaults to `EpiNow::covid_serial_intervals`.
#' @param si_samples Numeric, the number of samples to take from the serial intervals supplied
#' @param rt_samples Numeric, the number of samples to take from the estimated R distribution for each time point.
#' @param rt_prior A list defining the reproduction number prior containing the mean (`mean_prior`) and standard deviation (`std_prior`)
#' @param verbose Logical, defaults to `FALSE`. Should internal nowcasting progress messages be returned.
#' @param save_plots Logical, defaults to code `FALSE`. Should plots be saved.
#' @return NULL
#' @export
#' @importFrom dplyr rename filter mutate count group_by ungroup mutate_at pull select case_when bind_rows left_join bind_rows
#' @importFrom tidyr drop_na unnest
#' @importFrom purrr map
#' @importFrom ggplot2 ggsave theme labs coord_cartesian
#' @importFrom cowplot theme_cowplot
#' @importFrom patchwork plot_layout
#'
#' @examples
#'
rt_pipeline <- function(cases = NULL,
                              imported_cases = NULL,
                              linelist = NULL,
                              target_folder = NULL,
                              target_date = NULL,
                              delay_cutoff_date = NULL,
                              predict_lag = 0,
                              samples = 1000,
                              si_samples = 1,
                              rt_samples = 100,
                              window = 7,
                              earliest_allowed_onset = NULL,
                              start_rate_of_spread_est = NULL,
                              merge_actual_onsets = TRUE,
                              case_only = FALSE,
                              delay_only = FALSE,
                              verbose = FALSE,
                              serial_intervals = NULL,
                              rt_prior = NULL,
                              save_plots = FALSE) {



# Default input -----------------------------------------------------------

  if (is.null(serial_intervals)) {
    message("Using default sample of serial intervals with mean (sd) of 4.7 (2.9)")
    serial_intervals <- EpiNow::covid_serial_intervals
  }


  if (is.null(rt_prior)) {
    message("Using default Rt prior of 2.6 (2)")
    rt_prior <- list(
      mean_prior = 2.6,
      std_prior = 2)
  }


  # Format input ------------------------------------------------------------

  ## Reformat linelist for use in nowcast_pipeline
  formatted_linelist <- linelist %>%
    dplyr::rename(date_onset_symptoms = date_onset,
                  date_confirmation = date_confirm,
                  delay_confirmation = report_delay)

  ##Reformat cases
  cases <- cases %>%
    dplyr::rename(confirm = cases)

  # Run a nowcast -----------------------------------------------------------

  nowcast <- EpiNow::nowcast_pipeline(reported_cases = cases,
                                                 linelist = formatted_linelist,
                                                 date_to_cast = target_date,
                                                 date_to_cutoff_delay = delay_cutoff_date,
                                                 earliest_allowed_onset = earliest_allowed_onset,
                                                 merge_actual_onsets = merge_actual_onsets,
                                                 samples = samples,
                                                 delay_only = delay_only,
                                                 predict_lag = predict_lag,
                                                 verbose = verbose)


  # Save cast ---------------------------------------------------------------

  if (!dir.exists(target_folder)) {
    dir.create(target_folder, recursive = TRUE)
  }

  saveRDS(nowcast,  paste0(target_folder, "/nowcast.rds"))


  # Summarise nowcast -------------------------------------------------------

  summarise_cast <- EpiNow::summarise_cast(nowcast)

  ## Combine nowcast with observed cases by onset and repor
  reported_cases <- cases %>%
    dplyr::count(date, wt = confirm) %>%
    dplyr::select(date, median = n) %>%
    dplyr::mutate(type = "Observed by report date",
                  confidence = 1)


  ## Count cumulative cases
  all_cases <- summarise_cast %>%
    dplyr::bind_rows(reported_cases) %>%
    dplyr::group_by(type) %>%
    dplyr::ungroup()

  ## Save combined data
  saveRDS(all_cases,  paste0(target_folder, "/summarised_nowcast.rds"))

  ## Extract latest cases
  current_cases <- all_cases %>%
    dplyr::filter(type %in% "nowcast") %>%
    dplyr::filter(date == max(date)) %>%
    dplyr::mutate(range = paste0(round(bottom, 0), " -- ", round(top, 0))) %>%
    dplyr::pull(range)

  saveRDS(current_cases,  paste0(target_folder, "/current_cases.rds"))

  ## Plot comparison of cases
  plot_cases <- all_cases %>%
    dplyr::filter(!type %in% "from_delay") %>%
    dplyr::mutate(median = ifelse(type == "nowcast", NA, median)) %>%
    EpiNow::plot_confidence() +
    ggplot2::theme(legend.position = "none") +
    ggplot2::labs(y = "Daily cases", x = "Date")


  if (save_plots) {
    ggplot2::ggsave(paste0(target_folder, "/cases_plot.png"),
                    plot_cases,
                    width = 8,
                    height = 6,
                    dpi = 320)

  }

  saveRDS(plot_cases,  paste0(target_folder, "/plot_cases.rds"))



  # Estimate time-varying parameters ----------------------------------------


  time_varying_params <- nowcast %>%
    dplyr::filter(type %in% "nowcast") %>%
    EpiNow::estimate_time_varying_measures_for_nowcast(start_rate_of_spread_est = start_rate_of_spread_est,
                                                                  serial_intervals = serial_intervals,
                                                                  si_samples = si_samples, rt_samples = rt_samples,
                                                                  window = window, rt_prior = rt_prior)


  saveRDS(time_varying_params,  paste0(target_folder, "/time_varying_params.rds"))


  # Time-varying for observed cases -----------------------------------------
  if (case_only) {
    case_based_time_varying_params <-
      EpiNow::estimate_time_varying_measures_for_cases(reported_cases %>%
                                                                    dplyr::rename(cases = median) %>%
                                                                    dplyr::mutate(import_status = "local"),
                                                                  start_rate_of_spread_est = start_rate_of_spread_est,
                                                                  si_samples = si_samples, rt_samples = rt_samples,
                                                                  serial_intervals = serial_intervals, rt_prior = rt_prior,
                                                                  window = window)



    saveRDS(case_based_time_varying_params,
            paste0(target_folder, "/case_based_time_varying_params.rds"))

  }

  # Munge output ------------------------------------------------------------

  ## Pull out R estimates
  bigr_estimates <- time_varying_params[[1]]

  if (case_only) {
    bigr_estimates <- bigr_estimates %>%
      dplyr::bind_rows(
        case_based_time_varying_params[[1]] %>%
          dplyr::mutate(type = "Cases by report date")
      )
  }

  bigr_estimates <- bigr_estimates %>%
    dplyr::left_join(
      all_cases %>%
        dplyr::select(type, date, confidence),
      by = c("type", "date")
    )


  saveRDS(bigr_estimates,
          paste0(target_folder, "/bigr_estimates.rds"))

  # Pull out and plot big R -------------------------------------------------

  extract_bigr_values <- function(max_var, sel_var) {
    max_var <- dplyr::enquo(max_var)
    sel_var <- dplyr::enquo(sel_var)

    out <- EpiNow::pull_max_var(bigr_estimates, !!max_var,
                                                  !!sel_var,
                                                  type_selected = "nowcast")

    return(out)
  }
  ## Pull summary measures
  R_max_estimate <- extract_bigr_values(median, R0_range)


  saveRDS(R_max_estimate,
          paste0(target_folder, "/bigr_eff_max_estimate.rds"))

  R_latest <- extract_bigr_values(date, R0_range)

  saveRDS(R_latest,
          paste0(target_folder, "/bigr_eff_latest.rds"))

  ## Pull out probability of control
  prob_control <- extract_bigr_values(date, prob_control) %>%
    signif(2)

  saveRDS(prob_control,
          paste0(target_folder, "/prob_control_latest.rds"))

  ## Plot R estimates
  plot_bigr <- bigr_estimates %>%
    dplyr::filter(type %in% "nowcast") %>%
    EpiNow::plot_confidence(plot_median = FALSE) +
    ggplot2::theme(legend.position = "none") +
    ggplot2::labs(y = "Effective Reproduction no.", x = "Date") +
    ggplot2::geom_hline(yintercept = 1, linetype = 2) +
    ggplot2::expand_limits(y = 0)


  if (save_plots) {
    ## Save plot
    ggplot2::ggsave(paste0(target_folder, "/bigr_eff_plot.png"),
                    plot_bigr,
                    width = 8,
                    height = 6,
                    dpi = 320)
  }

  saveRDS(plot_bigr,
          paste0(target_folder, "/bigr_eff_plot.rds"))


  # Pull out and plot little R ----------------------------------------------

  ## Pull out little
  littler_estimates <- time_varying_params[[2]]

  if (case_only) {
    littler_estimates <- littler_estimates %>%
      dplyr::bind_rows(
        case_based_time_varying_params[[2]] %>%
          dplyr::mutate(type = "Cases by report date")
      )
  }

  saveRDS(littler_estimates,
          paste0(target_folder, "/rate_spread_estimates.rds"))

  ## get overall estimates
  report_overall <- littler_estimates %>%
    dplyr::mutate(report_overall = purrr::map(overall_little_r,
                                              ~ purrr::map_dfr(., function(estimate) {
                                                paste0(signif(estimate$bottom, 2), "--", signif(estimate$top, 2))
                                              }))) %>%
    tidyr::unnest("report_overall") %>%
    dplyr::select(Data = type,
                  `Rate of spread` = little_r,
                  `Doubling time (days)` = doubling_time,
                  `Adjusted R-squared` = goodness_of_fit
    )


  saveRDS(report_overall,
          paste0(target_folder, "/rate_spread_overall_summary.rds"))

  clean_double <- function(var) {
    var <- signif(var, 2)
    var[is.infinite(var)] <- "Cases decreasing"
    return(var)
  }

  ## get latest estimates
  report_latest <-  littler_estimates %>%
    dplyr::mutate(report_latest = purrr::map(time_varying_r, function(estimate) {
      estimate <- dplyr::filter(estimate, date == max(date))

      estimate$bottom <- clean_double(estimate$bottom)
      estimate$top <- clean_double(estimate$top)

      out <- tibble::tibble(
        vars = estimate$vars,
        range = paste0(estimate$bottom, " -- ", estimate$top)
      )

      out$range <- ifelse(out$range %in% "Cases decreasing -- Cases decreasing",
                          "Cases decreasing",
                          out$range)

      return(out)
    })) %>%
    tidyr::unnest("report_latest") %>%
    dplyr::select(type, vars, range) %>%
    tidyr::spread(key = "vars", value = "range") %>%
    dplyr::select(Data = type,
                  `Rate of spread` = little_r,
                  `Doubling time (days)` = doubling_time,
                  `Adjusted R-squared` = goodness_of_fit
    )


  saveRDS(report_latest,
          paste0(target_folder, "/rate_spread_latest_summary.rds"))


  ## Get individual estimates
  rate_spread_latest <- report_latest %>%
    dplyr::filter(Data == "nowcast") %>%
    pull(`Rate of spread`)


  saveRDS(rate_spread_latest,
          paste0(target_folder, "/rate_spread_latest.rds"))

  doubling_time_latest <- report_latest %>%
    dplyr::filter(Data == "nowcast") %>%
    pull(`Doubling time (days)`)

  saveRDS(doubling_time_latest,
          paste0(target_folder, "/doubling_time_latest.rds"))

  adjusted_r_latest <- report_latest %>%
    dplyr::filter(Data == "nowcast") %>%
    pull(`Adjusted R-squared`)

  saveRDS(adjusted_r_latest,
          paste0(target_folder, "/adjusted_r_latest.rds"))

  ## Prepare data for plotting
  plot_littler_data <-  littler_estimates %>%
    tidyr::unnest("time_varying_r") %>%
    dplyr::select(-overall_little_r) %>%
    dplyr::mutate(vars = vars %>%
                    factor(levels = c("little_r", "doubling_time", "goodness_of_fit"),
                           labels = c("Rate of spread",
                                      "Doubling time (days)",
                                      "Adjusted R-squared")
                    )) %>%
    dplyr::left_join(
      all_cases %>%
        dplyr::select(type, date, confidence),
      by = c("type", "date")
    ) %>%
    dplyr::filter(type %in% "nowcast")

  ## Define generic plotting function
  plot_littler_fn <- function(littler_df, plot_var = "Rate of spread") {
    plot_littler <- littler_df %>%
      dplyr::filter(vars %in% plot_var) %>%
      EpiNow::plot_confidence(plot_median = FALSE) +
      ggplot2::theme(legend.position = "none") +
      ggplot2::labs(y = "", x = "Date")

    return(plot_littler)
  }

  ## Plot each measure
  plot_littler <- plot_littler_data %>%
    plot_littler_fn(plot_var = "Rate of spread") +
    ggplot2::coord_cartesian(ylim=c(0,2)) +
    ggplot2::labs(tag = "A")

  plot_doublingtime <- plot_littler_data %>%
    plot_littler_fn(plot_var = "Doubling time (days)") +
    ggplot2::coord_cartesian(ylim=c(0, 15)) +
    ggplot2::labs(tag = "B")

  plot_fit <- plot_littler_data %>%
    plot_littler_fn(plot_var = "Adjusted R-squared") +
    ggplot2::labs(tag = "C")

  ## Combine plots
  plot_littler_summary <- plot_littler +
    plot_doublingtime +
    plot_fit +
    patchwork::plot_layout(nrow = 3)


  if (save_plots) {
    ## Save plot
    ggplot2::ggsave(paste0(target_folder, "/rate_spread_plot.png"),
                    plot_littler_summary,
                    width = 8,
                    height = 6,
                    dpi = 320)

  }

  saveRDS(plot_littler_summary,
          paste0(target_folder, "/rate_spread_plot.rds"))


  return(invisible(NULL))
}
