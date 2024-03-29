#' @title Plotting boxplot time series of the three RCPs scenarios
#' @description A function that receives three netCDF files, and variable name,
#' statistical ensemble member and plot three plots of the three scenarios for
#' each year
#' @param netCDF.files The netCDF files that contain similar simulation
#' variables. They should be provided including the full path to the files
#' @param variable inside these netCDF files, e.g., AET
#' @param region A string referring to the region to plot; "total",
#' "Vogtlandkreis", "Burgenlandkreis", "Greiz", and "Altenburger Land".
#' @param landcover A numeric variable indicating which land cover should be
#' considered. To consider all land cover give 1000.
#' @param stat_var A string referring to the statistical variable to plot in
#' case the file is ensemble file, for example, "mean","sd","median","max"
#' and "min"
#' @param language A character variable either "EN" or "DE", to specify the
#' languages of plots
#' @param run_id A character variable either "2ter", "3ter", or "4ter"
#' specifying the which run is used to produce the ensemble.
#' @param output_path A string pointing to the output directory,
#'  it should end with "/"
#' @param output_csv A string pointing to the output directory for the csv
#' file that is produced by pre-processing netCDF files
#' @author Ahmed Homoudi
#' @return  PNG
#' @import stats
#' @importFrom utils globalVariables write.table
#' @export
ens_yearly_boxplots <- function(netCDF.files,
                                variable,
                                region,
                                landcover,
                                stat_var,
                                language,
                                run_id,
                                output_path,
                                output_csv) {
  # check files
  if (length(netCDF.files) != 3) stop("not all RCPs files has been provided")

  # check Language
  if (language == "DE") {
    message("Producing Plots in German")

    utils::data("standard_output_de",
      envir = environment()
    )
  } else if (language == "EN") {
    message("Producing Plots in English")

    utils::data("standard_output_en",
      envir = environment()
    )
  } else {
    stop("Please select a language, either \"EN\" or \"DE\"")
  }

  netCDF.files <- sort(netCDF.files, decreasing = F)
  # read files
  r.rast <- lapply(X = netCDF.files, FUN = terra::rast, subds = stat_var)

  names(r.rast) <- c("RCP2.6", "RCP4.5", "RCP8.5")

  # load spatial data -------------------------------------------------------

  # spatial data
  utils::data("Bundeslaender", envir = environment())
  utils::data("Landkreise", envir = environment())
  utils::data("land_cover", envir = environment())

  # project shapefiles
  sf::st_crs(Landkreise) <- "+proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs"
  sf::st_crs(Bundeslaender) <- "+proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs"

  # convert land cover to rast
  LC <- terra::rast(x = land_cover, type = "xyz")
  terra::crs(LC) <- terra::crs(r.rast[[1]])

  # terra::plot(LC)

  # get region
  # crop the data to the region
  if (region == "total") {
    message("Producing Plots considering the Whole model region")
  } else if (region != "total") {
    message(paste0("Producing Plots considering only: ", region))

    shp_lk <- Landkreise[Landkreise$Name == region, ]

    shp_ext <- sf::st_bbox(shp_lk)

    r.rast <- lapply(r.rast,
      FUN = terra::mask,
      mask = terra::vect(shp_lk)
    )

    LC <- terra::mask(
      x = LC,
      mask = terra::vect(shp_lk)
    )
  } else {
    stop("Please specifiy a region to analyse! Either \"total\",\"Vogtlandkreis\", \n
         \"Burgenlandkreis\", \"Greiz\", or \"Altenburger Land\" ")
  }

  # checking landcover ------------------------------------------------------

  # check landcover
  if (landcover == 1000) {
    message("Analysis will include all land cover types")

    # assign LC plot caption
    if (language == "DE") {
      LC_name <- paste0(enc2utf8("F\u00FCr"), " alle CORINE-Landbedeckungsklassen")
    } else if (language == "EN") {
      LC_name <- "For all CORINE Land Cover Classes"
    }
  } else {
    message(paste0("Analysis will include only landcover type: ", landcover))

    # for further analysis

    indices <- which(terra::values(LC) != landcover)

    # remove other LC classes
    r.rast <- lapply(r.rast, f1_replace_values_in_SpatRaster_layers, IDs = indices)

    # test
    # terra::plot(r.rast[[1]][[1]])

    # get the name of specific land cover
    utils::data("land_cover_legend", envir = environment())

    if (language == "DE") {
      LC_name <- paste0(
        " ", enc2utf8("F\u00FCr"), " CORINE-LB: ",
        land_cover_legend$LABEL3[which(land_cover_legend$CLC_CODE == landcover)]
      )
    } else if (language == "EN") {
      LC_name <- LC_name <- paste0(
        "For CORINE-LC: ",
        land_cover_legend$LABEL3[which(land_cover_legend$CLC_CODE == landcover)]
      )
    }
  }

  # prepare boxplots data-----------------------------------------------------

  var_plotting <- lapply(r.rast, yearly_boxplot_df) %>%
    purrr::imap(.x = ., ~ purrr::set_names(.x, c("ID", "Period", .y))) %>%
    purrr::reduce(dplyr::left_join, by = c("ID", "Period")) %>%
    tidyr::pivot_longer(
      cols = -c("ID", "Period"),
      names_to = "Scenario",
      values_to = "Kvalue"
    )

  # get decade
  var_plotting$Period <- as.numeric(var_plotting$Period) -
    as.numeric(var_plotting$Period) %% 10

  # clean some memory
  invisible(gc())

  # meta data ---------------------------------------------------------------



  if (language == "DE") {
    # index of the variable in standard output
    variable_index <- which(standard_output_de$variable == variable)
    var_units <- standard_output_de$units[variable_index]
    var_name <- standard_output_de$longname[variable_index]

    if (region == "total") {
      plot.title <- paste0(var_name, " ", enc2utf8("f\u00FCr"), " die Gesamtmodellregion")
    } else {
      plot.title <- paste0(var_name, " f\u00fcr ", region)
    }
    plot.caption <- paste(
      paste0(
        "\u00a9 KlimaKonform ", lubridate::year(Sys.time()),
        ". ",
        LC_name
      ),
      paste0("Quelle: Ensemble no. ", run_id),
      sep = "\n"
    )
  } else if (language == "EN") {
    # index of the variable in standard output
    variable_index <- which(standard_output_en$variable == variable)
    var_units <- standard_output_en$units[variable_index]
    var_name <- standard_output_en$longname[variable_index]

    if (region == "total") {
      plot.title <- paste0(var_name, " for the Total Model Region")
    } else {
      plot.title <- paste0(var_name, " for ", region)
    }
    plot.caption <- paste(
      paste0(
        "\u00a9 KlimaKonform ", lubridate::year(Sys.time()),
        ". ",
        LC_name
      ),
      paste0("Source: Ensemble no.", run_id),
      sep = "\n"
    )
  }


  # change name of stat_var -------------------------------------------------

  # english,"mean","sd","median","max" and "min"
  if (language == "EN") {
    if (stat_var == "mean") {
      plot.title <- paste0(
        plot.title,
        "\n (Mean Ensemble)"
      )
    }
    if (stat_var == "sd") {
      plot.title <- paste0(
        plot.title,
        "\n ( Standard deviation Ensemble)"
      )
    }
    if (stat_var == "max") {
      plot.title <- paste0(
        plot.title,
        "\n ( Maximum Ensemble)"
      )
    }
    if (stat_var == "min") {
      plot.title <- paste0(
        plot.title,
        "\n (Minimum Ensemble)"
      )
    }
    if (stat_var == "median") {
      plot.title <- paste0(
        plot.title,
        "\n (Median Ensemble)"
      )
    }

    # deutsch
  } else if (language == "DE") {
    if (stat_var == "mean") {
      plot.title <- paste0(
        plot.title,
        "\n (Mittelwert Ensemble)"
      )
    }
    if (stat_var == "sd") {
      plot.title <- paste0(
        plot.title,
        "\n (Standardabweichung Ensemble)"
      )
    }
    if (stat_var == "max") {
      plot.title <- paste0(
        plot.title,
        "\n (Maximum Ensemble)"
      )
    }
    if (stat_var == "min") {
      plot.title <- paste0(
        plot.title,
        "\n (Minimum Ensemble)"
      )
    }
    if (stat_var == "median") {
      plot.title <- paste0(
        plot.title,
        "\n (Zentralwert Ensemble)"
      )
    }
  }

  if (language == "DE") {
    legend.title <- "Szenario"
  }

  if (language == "EN") {
    legend.title <- "Scenario"
  }

  #
  # plots and csv name  -----------------------------------------------------

  # define plot name
  if (exists("output_path")) {
    plot_name <- paste0(
      output_path,
      variable, "_",
      "ensemble_",
      run_id, "_lauf_",
      "3XRCPs_yearly_BP_.png"
    )
  } else {
    plot_name <- paste0(
      variable, "_",
      "ensemble_",
      run_id, "_lauf_",
      "3XRCPs_yearly_BP_.png"
    )
  }
  # define csv name
  if (exists("output_csv")) {
    csv_name <- paste0(
      output_csv,
      variable, "_",
      "ensemble_",
      run_id, "_lauf_",
      "3XRCPs_yearly_BP_.csv.gz"
    )
  } else {
    csv_name <- paste0(
      variable, "_",
      "ensemble_",
      run_id, "_lauf_",
      "3XRCPs_yearly_BP_.csv.gz"
    )
  }

  # pre-plot --------------------------------------------------------------------
  # read logo
  # KlimaKonform_img <- project_logo()
  # grid::rasterGrob(KlimaKonform_img)

  # y axis

  y.axis.max <- max(var_plotting$Kvalue, na.rm = T)
  y.axis.min <- min(var_plotting$Kvalue, na.rm = T)

  y.limits <- setting_nice_limits(y.axis.min, y.axis.max)

  y.axis.max <- y.limits[2]
  y.axis.min <- y.limits[1]

  # colors
  rcps_colours <- c("#003466", "#70A0CD", "#990002")

  # plot --------------------------------------------------------------------
  figure <- ggplot2::ggplot(
    data = var_plotting,
    mapping = ggplot2::aes(
      x = Period,
      y = Kvalue,
      color = Scenario,
      group = Period
    )
  ) +
    ggplot2::geom_boxplot(
      outlier.shape = 4,
      outlier.size = 0.05,
      outlier.alpha = 0.5,
      fatten = 0.3, size = 0.2
    ) +
    ggplot2::stat_boxplot(
      geom = "errorbar",
      size = 0.2
    ) +
    ggplot2::facet_wrap(~Scenario,
      nrow = 3
    ) +
    ggplot2::scale_color_manual(values = rcps_colours) +
    ggplot2::theme_bw(base_size = 6) +

    # add axis title
    ggplot2::ylab(paste0(
      var_name,
      " [", var_units, "]"
    )) +
    ggplot2::xlab("") +
    # set axis breaks
    ggplot2::scale_y_continuous(
      limits = c(y.axis.min, y.axis.max),
      expand = c(0, 0)
    ) +
    ggplot2::scale_x_continuous(
      limits = c(1960, 2100),
      expand = c(0, 0),
      breaks = seq(1960, 2100, 10)
    ) +
    ggplot2::labs(
      title = plot.title,
      caption = plot.caption,
    ) +
    ggplot2::theme(
      legend.position = "none",
      plot.title = ggplot2::element_text(
        hjust = 0.5,
        size = 6
      ),
      axis.title = ggplot2::element_text(
        hjust = 0.5,
        size = 5,
        margin = ggplot2::margin(rep(2, 4), unit = "mm")
      ),
      axis.text = ggplot2::element_text(
        hjust = 0.5,
        size = 5,
        colour = "black"
      ),
      panel.spacing = ggplot2::unit(2, "mm"),
      plot.caption = ggplot2::element_text(
        hjust = c(0),
        size = 4,
        colour = "blue",
        margin = ggplot2::margin(2, 0, 0, 0, unit = "mm")
      ),
      plot.margin = ggplot2::margin(rep(2, 4), unit = "mm")
    )

  # # add logo
  # ggplot2::annotation_custom(KlimaKonform_img
  # )

  # post-plot ---------------------------------------------------------------

  ggplot2::ggsave(
    plot = figure,
    filename = plot_name,
    units = "mm",
    width = 100,
    height = 100,
    dpi = 300,
    device = "png"
  )

  # write csv to disk
  # no need boxplots csv files works as well

  # End ---------------------------------------------------------------------
  # clean
  rm(list = ls())
  invisible(gc())
}
