% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/estimate_time_varying_measures_for_nowcast.R
\name{estimate_time_varying_measures_for_nowcast}
\alias{estimate_time_varying_measures_for_nowcast}
\title{Estimate time varying measures for nowcast}
\usage{
estimate_time_varying_measures_for_nowcast(
  nowcast = NULL,
  serial_intervals = NULL,
  start_rate_of_spread_est = NULL,
  si_samples = NULL,
  rt_samples = NULL,
  window = 7,
  rt_prior = NULL
)
}
\arguments{
\item{nowcast}{A nowcast as produced by \code{nowcast_pipeline}}

\item{serial_intervals}{A matrix with columns representing samples and rows representing the probability of the serial intervel being on
that day.}

\item{start_rate_of_spread_est}{A character string in the form of a date ("2020-01-01")}

\item{si_samples}{Numeric, the number of samples to take from the serial intervals supplied}

\item{rt_samples}{Numeric, the number of samples to take from the estimated R distribution for each time point.}

\item{window}{Numeric, the time window over which to vary the parameters.}

\item{rt_prior}{A list defining the reproduction number prior containing the mean (\code{mean_prior}) and standard deviation (\code{std_prior})}
}
\value{

}
\description{
Estimate time varying measures for nowcast
}
\examples{

}
