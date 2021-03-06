##' @name calc_metrics
##' @title calc_metrics
##' @export
##' @param model.calc
##' @param obvs.calc
##' @param var
##' @param metrics
##' @param start_year
##' @param end_year
##' @param bm
##' @param ensemble.id
##' @param model_run
##' 
##' 
##' @author Betsy Cowdery
calc_metrics <- function(model.calc, obvs.calc, var, metrics, start_year, end_year, bm, ensemble.id, model_run) {
  
  dat <- align_data(model.calc, obvs.calc, var, start_year, end_year, 
                    align_method = "mean_over_larger_timestep")
  
  results <- as.data.frame(matrix(NA, nrow = length(metrics$name), ncol = 3))
  colnames(results) <- c("metric", "variable", "score")
  results$metric <- metrics$name
  
  metric_dat <- dat[, c(paste(var, c("m", "o"), sep = "."), "posix")]
  colnames(metric_dat) <- c("model", "obvs", "time")
  
  for (m in seq_along(metrics$name)) {
    
    fcn <- paste0("metric_", metrics$name[m])
    results[m,"metric"] <- metrics$name[m]
    results[m,"variable"] <- var
    
    if (tail(unlist(strsplit(fcn, "_")), 1) == "plot") {
      filename <- file.path(dirname(dirname(model_run)), 
                            paste("benchmark", metrics$name[m], var, ensemble.id, "pdf", sep = "."))
      do.call(fcn, args <- list(metric_dat, var, filename))
      results[m,"score"] <- filename
    } else {
      results[m,"score"] <- as.character(do.call(fcn, args <- list(metric_dat, var)))
    }
    
  }  #end loop over metrics

  return(list(benchmarks = results, dat = dat))
} # calc_metrics
