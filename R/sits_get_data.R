#' @title Get time series from data cubes and cloud services
#' @name sits_get_data
#' @author Gilberto Camara
#'
#' @description Retrieve a set of time series from a data cube or from
#' a time series service. Data cubes and puts it in a "sits tibble".
#' Sits tibbles are the main structures of sits package.
#' They contain both the satellite image time series and their metadata.
#' There are four ways of specifying data to be retrieved:
#' \itemize{
#' \item{CSV file:}{Provide a CSV file with columns
#' "longitude", "latitude", "start_date", "end_date" and "label" for
#' each sample}
#' \item{SHP file:}{Provide a shapefile in POINT or POLYGON geometry
#' containing the location of the samples and an attribute to be
#' used as label. Also, provide start and end date for the time series.}
#' \item{samples:}{A data.frame with with columns
#' "longitude", "latitude", "start_date", "end_date" and "label" for
#' each sample}
#' \item{single point:}{Provide the values
#' "longitude", "latitude", "start_date", "end_date" and "label" to
#' obtain a time series for a spacetime location}
#' }
#
#' @param cube            Data cube from where data is to be retrieved.
#' @param file            File with information on the data to be retrieved.
#' @param samples         Data.frame with samples location in spacetime.
#' @param multicores      Number of threads to process the time series.
#' @param longitude       Longitude of the chosen location.
#' @param latitude        Latitude of the chosen location.
#' @param start_date      Start of the interval for the time series
#'                        in "YYYY-MM-DD" format (optional).
#' @param end_date        End of the interval for the time series in
#'                        "YYYY-MM-DD" format (optional).
#' @param label           Label to be assigned to the time series (optional).
#' @param bands           Bands to be retrieved (optional).
#' @param impute_fn       Imputation function for NA values.
#' @param shp_attr        Attribute in the shapefile to be used
#'                        as a polygon label.
#' @param .n_pts_csv      Number of points from CSV file to be retrieved.
#' @param .n_shp_pol      Number of samples per polygon to be read
#'                        (for POLYGON or MULTIPOLYGON shapefile).
#'
#' @return A tibble with the metadata and data for each time series
#' <longitude, latitude, start_date, end_date, label, cube, time_series>.
#'
#' @examples
#' \donttest{
#' # -- Read a point in a raster data cube
#'
#' # Create a data cube based on files
#' data_dir <- system.file("extdata/raster/mod13q1", package = "sits")
#' raster_cube <- sits_cube(
#'     source = "BDC",
#'     collection = "MOD13Q1-6",
#'     data_dir = data_dir,
#'     delim = "_",
#'     parse_info = c("X1", "X2", "tile", "band", "date")
#' )
#'
#' # read the time series of the point from the raster
#' point_ts <- sits_get_data(raster_cube,
#'     longitude = -55.554,
#'     latitude = -11.525
#' )
#'
#' # --- Read a set of points described by a CSV file
#'
#' # read data from a CSV file
#' csv_file <- system.file("extdata/samples/samples_sinop_crop.csv",
#'     package = "sits"
#' )
#' points_csv <- sits_get_data(raster_cube, file = csv_file)
#' }
#' @export
#'
sits_get_data <- function(cube,
                          file = NULL,
                          samples = NULL,
                          longitude = NULL,
                          latitude  = NULL,
                          start_date = NULL,
                          end_date = NULL,
                          label = "NoClass",
                          bands = NULL,
                          impute_fn = sits_impute_linear(),
                          shp_attr = NULL,
                          .n_pts_csv = NULL,
                          .n_shp_pol = 30,
                          multicores = 1) {

    # set caller to show in errors
    .check_set_caller("sits_get_data")

    # pre-condition - file parameter
    .check_chr(file, allow_empty = FALSE, len_min = 1, len_max = 1,
               allow_null = TRUE, msg = "invalid 'file' parameter")

    # no start or end date? get them from the timeline
    timeline <- sits_timeline(cube)
    if (purrr::is_null(start_date))
        start_date <- as.Date(timeline[1])
    if (purrr::is_null(end_date))
        end_date <- as.Date(timeline[length(timeline)])

    # is there a shapefile or a CSV file?
    if (!purrr::is_null(file)) {
        # get the file extension
        file_ext <- tolower(tools::file_ext(file))
        # sits only accepts "csv" or "shp" files
        .check_chr_within(
            x = file_ext,
            within = .config_get("sample_file_formats"),
            msg = paste0("samples should be of type ",
                         paste(.config_get("sample_file_formats"),
                               collapse = " or "))
        )
        if (file_ext == "csv")
            samples <- .sits_get_samples_from_csv(
                csv_file   = file,
                .n_pts_csv = .n_pts_csv
            )

        if (file_ext == "shp")
            samples <- .sits_get_samples_from_shp(
                shp_file = file,
                label = label,
                shp_attr = shp_attr,
                start_date = start_date,
                end_date = end_date,
                .n_shp_pol = .n_shp_pol
            )
    } else {
        if (!purrr::is_null(samples)) {
            # check if samples are a data.frame
            .check_chr_contains(
                x = class(samples),
                contains = "data.frame",
                case_sensitive = TRUE,
                discriminator = "any_of",
                can_repeat = TRUE,
                msg = "samples should be of type data.frame"
            )
        } else {
            if (!purrr::is_null(latitude) &&
                !purrr::is_null(longitude)) {
                samples <- tibble::tibble(
                    longitude  = longitude,
                    latitude   = latitude,
                    start_date = as.Date(start_date),
                    end_date   = as.Date(end_date),
                    label      = label
                )
            } else {
                stop("no valid information about samples")
            }
        }
    }
    # post-condition
    # check if samples contains all the required columns
    .check_chr_contains(
        x = colnames(samples),
        contains = .config_get("df_sample_columns"),
        discriminator = "all_of",
        msg = "data input is not valid"
    )

    data <-  .sits_get_ts(
        cube       = cube,
        samples    = samples,
        bands      = bands,
        impute_fn  = impute_fn,
        multicores = multicores
    )
    return(data)
}

#' @title Dispatch function to get time series from data cubes and cloud services
#' @name .sits_get_ts
#' @author Gilberto Camara
#' @keywords internal
#' @param cube            Data cube from where data is to be retrieved.
#' @param samples         Samples to be retrieved.
#' @param bands           Bands to be retrieved (optional).
#' @param impute_fn       Imputation function for NA values.
#' @param multicores      Number of threads to process the time series.
.sits_get_ts <- function(cube,
                         samples,
                         ...,
                         bands = NULL,
                         impute_fn,
                         multicores) {

    # Dispatch
    UseMethod(".sits_get_ts", cube)
}

#' @keywords internal
#' @export
#'
.sits_get_ts.wtss_cube <- function(cube,
                                   samples,
                                   ...,
                                   bands,
                                   impute_fn) {

    # pre-condition - check bands
    if (is.null(bands))
        bands <- .cube_bands(cube)
    .cube_bands_check(cube, bands = bands)

    # for each row of the input, retrieve the time series
    data <- slider::slide_dfr(samples, function(row){
            row_ts <- .sits_get_data_from_wtss(
                cube = cube,
                longitude  = row[["longitude"]],
                latitude   = row[["latitude"]],
                start_date = lubridate::as_date(row[["start_date"]]),
                end_date   = lubridate::as_date(row[["end_date"]]),
                label      = row[["label"]],
                bands      = bands,
                impute_fn  = impute_fn
            )
            return(row_ts)
        }
    )
    # check if data has been retrieved
    .sits_get_data_check(nrow(samples), nrow(data))

    if (!inherits(data, "sits")) {
        class(data) <- c("sits", class(data))
    }
    return(data)
}

#' @keywords internal
#' @export
#'
.sits_get_ts.satveg_cube <- function(cube, samples, ...) {

    # Precondition - is the SATVEG cube available?
    # Retrieve the URL to test for SATVEG access
    url <- .source_url(source = .cube_source(cube = cube))

    # get the cube timeline
    timeline <- sits_timeline(cube)
    start_date_cube <- timeline[1]
    end_date_cube <- timeline[length(timeline)]

    # for each row of the input, retrieve the time series
    data <- slider::slide_dfr(samples, function(row){
            row_ts <- .sits_get_data_from_satveg(
                cube = cube,
                longitude  = row[["longitude"]],
                latitude   = row[["latitude"]],
                start_date = row[["start_date"]],
                end_date   = row[["end_date"]],
                label      = row[["label"]]
            )
            return(row_ts)
        }
    )
    # check if data has been retrieved
    .sits_get_data_check(nrow(samples), nrow(data))

    if (!inherits(data, "sits")) {
        class(data) <- c("sits", class(data))
    }
    return(data)
}


#' @keywords internal
#' @export
.sits_get_ts.raster_cube <- function(cube,
                                     samples,
                                     ...,
                                     bands,
                                     impute_fn,
                                     multicores) {

    # pre-condition - check bands
    if (is.null(bands))
        bands <- .cube_bands(cube)
    .cube_bands_check(cube, bands = bands)

    # is the cloud band available?
    cld_band <- .source_cloud()
    if (cld_band %in% bands) {
        bands <- bands[bands != cld_band]
    } else {
        cld_band <- NULL
    }

    # prepare parallelization
    .sits_parallel_start(workers = multicores, log = FALSE)
    on.exit(.sits_parallel_stop(), add = TRUE)

    data <- slider::slide_dfr(cube, function(tile) {
        # get the data
        ts <- .sits_raster_data_get_ts(
            tile = tile,
            points = samples,
            bands = bands,
            cld_band = cld_band,
            impute_fn = impute_fn
        )
        return(ts)
    })
    # check if data has been retrieved
    .sits_get_data_check(nrow(samples), nrow(data))

    if (!inherits(data, "sits")) {
        class(data) <- c("sits", class(data))
    }
    return(data)
}

#' @title check if all points have been retrieved
#' @name .sits_get_data_check
#' @keywords internal
#' @param n_rows_input     Number of rows in input
#' @param n_rows_output    Number of rows in output
#'
#' @return A logical value
#'
.sits_get_data_check <- function(n_rows_input, n_rows_output) {

    # Have all input rows being read?
    if (n_rows_output == 0) {
        message("No points have been retrieved")
        return(invisible(FALSE))
    }

    if (n_rows_output < n_rows_input) {
        message("Some points could not be retrieved")
    } else {
        message("All points have been retrieved")
    }

    return(invisible(TRUE))
}
#' @title Obtain one timeSeries from the EMBRAPA SATVEG server
#' @name .sits_get_data_from_satveg
#' @keywords internal
#' @author Julio Esquerdo, \email{julio.esquerdo@@embrapa.br}
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Returns one set of MODIS time series provided by the EMBRAPA
#' Given a location (lat/long), retrieve the "ndvi" and "evi" bands from SATVEG
#' If start and end date are given, the function
#' filters the data to limit the temporal interval.
#'
#' @param cube            The data cube metadata that describes the SATVEG data.
#' @param longitude       Longitude of the chosen location.
#' @param latitude        Latitude of the chosen location.
#' @param start_date      The start date of the period.
#' @param end_date        The end date of the period.
#' @param label           Label to attach to the time series (optional).
#' @return A sits tibble.
.sits_get_data_from_satveg <- function(cube,
                                       longitude,
                                       latitude,
                                       start_date,
                                       end_date,
                                       label) {

    # set caller to show in errors
    .check_set_caller(".sits_get_data_from_satveg")

    # retrieve the time series
    ts <- .sits_satveg_ts_from_txt(longitude = longitude,
                                   latitude = latitude,
                                   cube = cube)

    # filter the dates
    ts <- dplyr::filter(ts, dplyr::between(
        ts$Index,
        start_date, end_date
    ))
    # create a tibble to store the SATVEG data
    data <- .sits_tibble()
    # add one row to the tibble
    data <- tibble::add_row(data,
                            longitude = longitude,
                            latitude = latitude,
                            start_date = start_date,
                            end_date = end_date,
                            label = label,
                            cube = cube$collection,
                            time_series = list(ts)
    )
    return(data)
}

#' @title Obtain one time series from WTSS server and load it on a sits tibble
#' @name .sits_get_data_from_wtss
#' @keywords internal
#'
#' @description Returns one set of time series provided by a WTSS server
#' Given a location (lat/long), and start/end period, and WTSS server info,
#' retrieve a time series and include it on a stis tibble.
#' A Web Time Series Service (WTSS) is a light-weight service that
#' retrieves one or more time series in JSON format from a data base.
#' @references
#' Lubia Vinhas, Gilberto Queiroz, Karine Ferreira, Gilberto Camara,
#' Web Services for Big Earth Observation Data.
#' In: XVII Brazilian Symposium on Geoinformatics, 2016, Campos do Jordao.
#' Proceedings of GeoInfo 2016. Sao Jose dos Campos: INPE/SBC, 2016, p.166-177.
#'
#' @param cube            Metadata about the cube associated to the WTSS.
#' @param longitude       The longitude of the chosen location.
#' @param latitude        The latitude of the chosen location.
#' @param start_date      Date with the start of the period.
#' @param end_date        Date with the end of the period.
#' @param label           Label to attach to the time series (optional).
#' @param bands           Names of the bands of the cube.
#' @param impute_fn       Function to impute NA values
#' @return                A sits tibble.
.sits_get_data_from_wtss <- function(cube,
                                     longitude,
                                     latitude,
                                     start_date,
                                     end_date,
                                     label,
                                     bands = NULL,
                                     impute_fn) {

    # verifies if wtss package is installed
    if (!requireNamespace("Rwtss", quietly = TRUE)) {
        stop("Please install package Rwtss.", call. = FALSE)
    }

    # Try to find the access key as an environment variable
    bdc_access_key <- Sys.getenv("BDC_ACCESS_KEY")
    .check_that(
        x = nzchar(bdc_access_key),
        msg = "BDC_ACCESS_KEY needs to be provided"
    )

    # converts bands to corresponding names used by SITS
    bands <- .source_bands_to_source(source = .cube_source(cube = cube),
                                     collection = .cube_collection(cube = cube),
                                     bands = bands)

    # retrieve the time series from the service
    tryCatch({
        ts <- Rwtss::time_series(URL = .file_info_path(cube),
                                 name = cube$collection,
                                 attributes = bands,
                                 longitude = longitude,
                                 latitude = latitude,
                                 start_date = start_date,
                                 end_date = end_date,
                                 token = bdc_access_key
        )
    },
    warning = function(e) {
        paste(e)
    },
    error = function(e) {
        message(e)
    })

    # interpolate clouds
    cld_band <- .source_bands_band_name(source = "WTSS",
                                        collection = cube$collection,
                                        bands = .source_cloud())

    # retrieve values for the cloud band (if available)
    if (cld_band %in% bands) {

        bands <- bands[bands != cld_band]

        # retrieve values that indicate clouds
        cld_index <- .source_cloud_interp_values(
            source = .cube_source(cube = cube),
            collection = .cube_collection(cube = cube)
        )

        # get the values of the time series (terra object)
        cld_values <- as.integer(ts$time_series[[1]][[cld_band]])

        # get information about cloud bitmask
        if (.source_cloud_bit_mask(
            source = .cube_source(cube = cube),
            collection = .cube_collection(cube = cube))) {

            cld_values <- as.matrix(cld_values)
            cld_rows <- nrow(cld_values)
            cld_values <- matrix(bitwAnd(cld_values, sum(2 ^ cld_index)),
                                 nrow = cld_rows)
        }
    }

    # Retrieve values on a band by band basis
    ts_bands <- lapply(bands, function(band) {

        # get the values of the time series as matrix
        values_band <- ts$time_series[[1]][[band]]

        # convert to sits band
        band_sits <- .source_bands_to_sits(source = cube$source[[1]],
                                           collection = cube$collection[[1]],
                                           bands = band)

        if (!purrr::is_null(impute_fn)) {

            # get the scale factors, max, min and missing values
            missing_value <- .cube_band_missing_value(
                cube = cube,
                band = band_sits
            )
            minimum_value <- .cube_band_minimum_value(
                cube = cube,
                band = band_sits
            )
            maximum_value <- .cube_band_maximum_value(
                cube = cube,
                band = band_sits
            )
            scale_factor <- .cube_band_scale_factor(
                cube = cube,
                band = band_sits
            )

            # include information from cloud band
            if (!purrr::is_null(cld_band)) {
                if (.source_cloud_bit_mask(
                    source = .cube_source(cube = cube),
                    collection = .cube_collection(cube = cube)))
                    values_band[cld_values > 0] <- NA
                else
                    values_band[cld_values %in% cld_index] <- NA
            }

            # adjust maximum and minimum values
            values_band[values_band < minimum_value * scale_factor] <- NA
            values_band[values_band > maximum_value * scale_factor] <- NA

            # are there NA values? interpolate them
            if (any(is.na(values_band))) {
                values_band <- impute_fn(as.integer(values_band / scale_factor))
            }
        }

        # return the values
        return(values_band * scale_factor)
    })

    # rename bands to sits band names
    bands_sits <- .source_bands_to_sits(source = cube$source[[1]],
                                        collection = cube$collection[[1]],
                                        bands = bands)

    # now we have to transpose the data
    ts_samples <- ts_bands %>%
        purrr::set_names(bands_sits) %>%
        tibble::as_tibble()

    ts_samples <- dplyr::bind_cols(ts$time_series[[1]]["Index"], ts_samples)

    ts$time_series[[1]] <- ts_samples

    # change the class of the data
    # before - class "wtss"
    # now - class "sits"
    if (!purrr::is_null(ts)) {
        class(ts) <- setdiff(class(ts), "wtss")
        class(ts) <- c("sits", class(ts))
        # add a label column
        if (label != "NoClass") {
            ts$label <- label
        }
    }

    # return the tibble with the time series
    return(ts)
}
#' @title Transform a shapefile into a samples file
#' @name .sits_get_samples_from_shp
#' @author Gilberto Camara
#' @keywords internal
#' @param shp_file        Shapefile that describes the data to be retrieved.
#' @param label           Default label for samples.
#' @param shp_attr        Shapefile attribute that describes the label
#' @param start_date      Start date for the data set
#' @param end_date        End date for the data set
#' @param .n_shp_pol      Number of samples per polygon to be read
#'                        (for POLYGON or MULTIPOLYGON shapefile).
#' @return                A tibble with information the samples to be retrieved
#'
.sits_get_samples_from_shp <- function(shp_file,
                                       label,
                                       shp_attr,
                                       start_date,
                                       end_date,
                                       .n_shp_pol){

    # pre-condition - check the shape file and its attribute
    sf_shape <- .sits_shp_check_validity(
        shp_file = shp_file,
        shp_attr = shp_attr,
        label = label
    )
    # get the points to be read
    samples <- .sits_shp_to_tibble(
        sf_shape = sf_shape,
        shp_attr = shp_attr,
        label = label,
        .n_shp_pol = .n_shp_pol
    )
    samples$start_date <- as.Date(start_date)
    samples$end_date   <- as.Date(end_date)

    return(samples)
}

#' @title Transform a shapefile into a samples file
#' @name .sits_get_samples_from_csv
#' @author Gilberto Camara
#' @keywords internal
#' @param csv_file        CSV that describes the data to be retrieved.
#' @param .n_pts_csv      number of points to be retrived
#' @return                A tibble with information the samples to be retrieved
#'
.sits_get_samples_from_csv <- function(csv_file,
                                       .n_pts_csv){

    # read sample information from CSV file and put it in a tibble
    samples <- tibble::as_tibble(utils::read.csv(csv_file))

    # pre-condition - check if CSV file is correct
    .sits_csv_check(samples)

    if (!purrr::is_null(.n_pts_csv) &&
        .n_pts_csv > 1 && .n_pts_csv < nrow(samples))
        samples <- samples[1:.n_pts_csv,]

    samples$start_date <- as.Date(samples$start_date)
    samples$end_date   <- as.Date(samples$end_date)

    return(samples)

}

