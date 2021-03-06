% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/nowcast_pipeline.R
\name{nowcast_pipeline}
\alias{nowcast_pipeline}
\title{Run a complete nowcast}
\usage{
nowcast_pipeline(
  reported_cases = NULL,
  linelist = NULL,
  date_to_cast = NULL,
  date_to_cutoff_delay = NULL,
  earliest_allowed_onset = NULL,
  merge_actual_onsets = TRUE,
  delay_only = FALSE,
  verbose = FALSE,
  samples = 1,
  predict_lag = 0
)
}
\arguments{
\item{reported_cases}{A dataframe of reported cases}

\item{linelist}{A linelist of report dates and onset dates}

\item{date_to_cutoff_delay}{A character}

\item{earliest_allowed_onset}{A character string in the form of a date ("2020-01-01") indiciating the earliest
allowed onset.}

\item{merge_actual_onsets}{Logical, defaults to \code{TRUE}.
Should linelist onset dates be used where available?}

\item{delay_only}{Logical, defaults to \code{FALSE}. Should estimates be made based on estimated onset dates without nowcasting.}

\item{verbose}{Logical, defaults to \code{FALSE}. Should internal nowcasting progress messages be returned.}

\item{samples}{Numeric, the number of samples to take.}

\item{date_to_case}{A data indicating when to cast up to.}
}
\value{

}
\description{
Run a complete nowcast
}
\examples{


}
