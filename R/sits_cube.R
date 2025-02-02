#' @title Create data cubes from image collections
#' @name sits_cube
#'
#' @references `rstac` package (https://github.com/brazil-data-cube/rstac)
#'
#' @description Creates a data cube based on spatial and temporal restrictions
#' on a collection available in repositories such as AWS, Brazil Data Cube
#' (BDC), and Digital Earth Africa (DEA) using information provided by STAC
#' endpoints. Users can also create data cubes from local files.
#'
#' A data cube does not contain actual data; it points to the files where the
#' required data is archived. Other functions (e.g. `sits_classify`) use
#' that information to retrieve and process data.
#'
#' Currently, users can create data cube from the following sources:
#' \itemize{
#'  \item{"BDC": }{Brazil Data Cube (BDC),
#'   see also https://brazil-data-cube.github.io/applications/stac.html}
#'   \item{"WTSS": }{Web Time Series Service from BDC,
#'    see also https://brazil-data-cube.github.io/applications/wtss.html}
#'  \item{"DEAFRICA": }{Digital Earth Africa,
#'   see also https://www.digitalearthafrica.org/}
#'  \item{"AWS": }{Amazon Web Services (AWS),
#'   see also https://earth-search.aws.element84.com/v0/ }
#'  \item{"USGS":}{USGS LANDSAT collection}
#'  \item{"SATVEG": }{Defines a cube to use the SATVEG web service,
#'   see also https://www.satveg.cnptia.embrapa.br/satveg/login.html}
#'  }
#'
#' For all cubes, users need to provide information on:
#' \itemize{
#' \item{collection: }{Collections are the highest level of aggregation on
#' big data repositories. Use `sits_list_collections()` to see which collections
#' are supported by `sits`}
#' \item{spatial extent: }{The spatial extent of the data cube can be defined
#' in two ways: (a) a region of interest(`bbox`) in WGS 84 coordinates;
#' (b) a set of tiles defined according the collection tiling system.}
#' \item{temporal extent: }{The start and end date of the cube}
#' }
#'
#' Optional parameters include:
#' \itemize{
#' \item{data_dir: }{Directory where data is installed (required for data sets
#' stored in local disks)}
#' \item{bands: }{Bands used to build the cube}
#'}
#' @note In AWS, there are two types of collections: open data and
#' requester-pays. Currently, `sits` supports collection "SENTINEL-S2-L2A"
#' (requester-pays) and "SENTINEL-S2-L2A-COGS" (open data). There is no need
#' to provide AWS credentials to access open data collections.
#' For requester-pays data, users need to provide their access codes as
#' environment variables, as follows:
#' Sys.setenv(
#'     AWS_ACCESS_KEY_ID     = <your_access_key>,
#'     AWS_SECRET_ACCESS_KEY = <your_secret_access_key>
#' )
#'
#' @note Sentinel-2/2A level 2A files in AWS are organized by sensor
#' resolution. The AWS bands in 10m resolution are "B02", "B03", "B04", and
#' "B08". The  20m bands are "B05", "B06", "B07", B8A",
#' "B8A", "B11", and "B12". Bands "B01" and "B09" are available at 60m resolution.
#'
#'
#' @note For DEAFRICA, sits currently works with collection 'S2_L2A' (open data).
#' This collection is the same as AWS collection "SENTINEL-S2-L2A-COGS",
#' and is located in Africa (Capetown) for faster access to African users.
#' No payment for access is required.
#'
#' @note For USGS, sits currently works with collection 'landsat-c2l2-sr', which
#' corresponds to Landsat Collection 2 Level-2 surface reflectance data,
#' covering datasets from Landsat-4 to Landsat-8. This collection is open data.
#'
#' @note All BDC collections have been regularized.
#' BDC users need to provide their credentials using environment
#' variables. To create your credentials, please see
#' "https://brazildatacube.dpi.inpe.br/portal/explore". There is no
#' cost for accessing data in the BDC.
#' After obtaining the BDC access key, please include it as
#' an environment variable, as follows:
#' Sys.setenv(
#'     BDC_ACCESS_KEY = <your_bdc_access_key>
#' )
#'
#'@note To create a cube from local files, the user needs to inform:
#'\itemize{
#'\item{source:} {Provider from where the data has been downloaded
#'               (e.g, "BDC", "AWS)}
#'\item{collection:}{Collection from which the data has been extracted}
#'\item{data_dir: }{Local directory where the files are stored}
#'\item{parse_info: }{Parsing information for files (see below)}
#'\item{delim: }{Delimiter for parsing files (see below)}
#'}
#'
#'@note To create a cube from local files, all image files should have
#' the same spatial resolution and projection. Files can belong to different
#' tiles of a spatial reference system.
#' Each file should contain a single image band for a single date.
#' File names must include tile, date and band information.
#' For example: "CBERS-4_022024_B13_2018-02-02.tif"
#' and "cube_20LKP_B02_2018-07-18.jp2" are accepted names.
#' The user has to provide parsing information to allow `sits`
#' to extract the tile, the band and the date. In the examples above,
#' the parsing info is c("X1", "X2", "tile", "band", "date") and the delimiter is "_".
#'
#'
#' @note The SATVEG service is run by Embrapa Agricultural
#'  Informatics Centre provides access to time series from the MODIS sensor.
#'  There are three collections: "terra" (from the TERRA satellite),
#'  "aqua" (from the AQUA satellite) and "comb" (combination of
#'  both satellites).
#'
#' @note WTSS is a web service for providing individual time series from BDC.
#' Users specify a list of spatio-temporal positions and a collection where they
#' want to extract the data.
#'
#' @param source            Data source (one of "AWS", "BDC", "DEAFRICA",
#'                          "SATVEG", "USGS", "WTSS").
#' @param ...               Other parameters to be passed for specific types.
#' @param collection        Collection to be searched in the data source.
#' @param data_dir          directory where local data is located
#'                          (only for creating data cubes from local files).
#' @param url               URL for the STAC endpoint of the data source.
#'                          (if not provided, `sits` uses the URL from the configuration file)
#' @param bands             Bands to be included (optional)
#' @param tiles             Tiles from the collection to be included in the
#'                          data cube.
#' @param roi               Region of interest (see details below).
#' @param start_date        Initial date for the cube (optional).
#' @param end_date          Final date for the cube  (optional).
#' @param delim             delimiter for parsing files without STAC information
#'                          (only for creating data cubes from local files).
#' @param parse_info        parsing information for files without STAC
#'                          information
#'                          (only for creating data cubes from local files).
#' @param origin            deprecated parameter formely used for local cubes
#'                          (see documentation)
#' @param name              deprecated parameter formely used to describe cubes
#' @param multicores        a number of workers for parallel processing in
#'  local cubes
#' @param progress          Show a progress bar?
#'
#' @details The \code{roi} parameter allows a selection of an area of interest.
#' Either using a named \code{vector} ("lon_min", "lat_min", "lon_max", "lat_max") with
#' values in WGS 84, a \code{sfc} or \code{sf} object from sf package in WGS84 projection.
#' GeoJSON geometries (RFC 7946) and shapefiles should be converted to sf objects before
#' being used to define a region of interest. This parameter does not crop a
#' region, but only selects the images that intersect with it.
#'
#' @return The description of a data cube
#'
#' @examples
#' \dontrun{
#'
#' # --- Access to the Brazil Data Cube
#' # Provide your BDC credentials as environment variables
#' bdc_access_key <- Sys.getenv("BDC_ACCESS_KEY")
#' if (nchar(bdc_access_key) == 0)
#'        stop("No BDC_ACCESS_KEY defined in environment.")
#'
#' # create a raster cube file based on the information in the BDC
#' cbers_tile <- sits_cube(
#'     source = "BDC",
#'     collection = "CB4_64_16D_STK-1",
#'     bands = c("NDVI", "EVI"),
#'     tiles = "022024",
#'     start_date = "2018-09-01",
#'     end_date = "2019-08-28"
#' )
#'
#' # --- Create a WTSS cube from BDC cubes
#' # Provide your BDC credentials as environment variables
#' bdc_access_key <- Sys.getenv("BDC_ACCESS_KEY")
#' if (nchar(bdc_access_key) == 0)
#'        stop("No BDC_ACCESS_KEY defined in environment.")
#'
#' cube_wtss <- sits_cube(source = "WTSS",
#'                        collection = "MOD13Q1-6")
#'
#' # --- Access to Digital Earth Africa
#' # create a raster cube file based on the information about the files
#' cube_dea <- sits_cube(source = "DEAFRICA",
#'                       collection = "s2_l2a",
#'                       bands = c("B04", "B08"),
#'                       roi   = c("lat_min" = 17.379,
#'                                 "lon_min" = 1.1573,
#'                                 "lat_max" = 17.410,
#'                                 "lon_max" = 1.1910),
#'                       start_date = "2019-01-01",
#'                       end_date = "2019-10-28"
#' )
#'
#' # --- Access to open data Sentinel 2/2A level 2 collection in AWS
#' s2_cube <- sits_cube(source = "AWS",
#'                       collection = "sentinel-s2-l2a-cogs",
#'                       tiles = c("20LKP","20LLP"),
#'                       bands = c("B04", "B08", "B11"),
#'                       start_date = as.Date("2018-07-18"),
#'                       end_date = as.Date("2019-07-23")
#' )
#'
#' # --- Create a cube based on a local MODIS data
#' data_dir <- system.file("extdata/raster/mod13q1", package = "sits")
#'
#' modis_cube <- sits_cube(
#'     source = "BDC",
#'     collection = "MOD13Q1-6",
#'     data_dir = data_dir,
#'     delim = "_",
#'     parse_info = c("X1", "X2", "tile", "band", "date")
#' )
#' }
#'
#' @export
#'
sits_cube <- function(source, ..., collection, data_dir = NULL) {

    # set caller to show in errors
    .check_set_caller("sits_cube")

    if (purrr::is_null(data_dir))
        source <- .source_new(source = source, collection = collection)
    else
        source <- .source_new(source = source, is_local = TRUE)

    # Dispatch
    UseMethod("sits_cube", source)
}

#' @rdname sits_cube
#'
#' @export
#'
sits_cube.wtss_cube <- function(source = "WTSS", ...,
                                collection,
                                data_dir = NULL,
                                url = NULL) {

    # pre-condition
    .source_collection_check(source = source,
                             collection = collection)

    # Does the collection need a token for access?
    .source_collection_token_check(source = source,
                                   collection = collection)

    # Does the collection need environmental variables for access?
    .source_collection_access_vars_set(source = source,
                                       collection = collection)

    # dry run to verify if service is running
    .source_collection_access_test(source = source, collection = collection)

    # builds a sits data cube
    .source_cube(source = source,
                 collection = collection, ...)
}

#' @rdname sits_cube
#'
#' @export
sits_cube.stac_cube <- function(source,
                                collection,
                                data_dir = NULL,
                                ...,
                                bands = NULL,
                                tiles = NULL,
                                roi = NULL,
                                start_date = NULL,
                                end_date = NULL,
                                name = NULL) {

    dots <- list(...)

    # deal with wrong parameter "band"
    if ("band" %in% names(dots) && missing(bands)) {
        message("please use bands instead of band as parameter")
        bands <- as.character(dots[["band"]])
    }

    # deal with wrong parameter "tile"
    if ("tile" %in% names(dots) && missing(tiles)) {
        message("please use tiles instead of tile as parameter")
        tiles <- as.character(dots[["tile"]])
    }

    if (!is.null(roi) && !is.null(tiles)) {
        stop(paste("It is not possible to search with roi and tiles.",
                   "Please provide only roi or tiles."))
    }
    # check if roi is provided correctly
    if (!purrr::is_null(roi)) {
        roi <- .sits_parse_roi_cube(roi)
    }

    # name parameter has been deprecated
    if (!purrr::is_null(name)) {
        message("name parameter is no longer required")
    }

    # source is upper case
    source <- toupper(source)

    # collection is upper case
    collection <- toupper(collection)

    # pre-condition - check if source and collection exist
    .source_collection_check(source = source,
                             collection = collection)

    # Does the collection need a token for access?
    .source_collection_token_check(source = source,
                                   collection = collection)

    # Does the collection need environmental variables for access?
    .source_collection_access_vars_set(source = source,
                                       collection = collection)

    if (is.null(bands))
        bands <- .source_bands(source = source,
                               collection = collection)

    # Pre-condition - checks if the bands are supported by the collection
    .config_check_bands(source = source,
                        collection = collection,
                        bands = bands)

    # dry run to verify if service is running
    .source_collection_access_test(source = source,
                                   collection = collection,
                                   bands = bands, ...)

    # builds a sits data cube
    .source_cube(source = source,
                 collection = collection,
                 bands = bands,
                 tiles = tiles,
                 roi_sf = roi,
                 start_date = start_date,
                 end_date = end_date, ...)
}

#' @rdname sits_cube
#'
#' @export
sits_cube.local_cube <- function(source,
                                 collection,
                                 data_dir,
                                 ...,
                                 bands = NULL,
                                 start_date = NULL,
                                 end_date = NULL,
                                 parse_info,
                                 delim = "_",
                                 name = NULL,
                                 origin = NULL,
                                 multicores = 2,
                                 progress = TRUE) {


    # precondition - data directory must be provided
    .check_file(x = data_dir, msg = "data_dir must be to be provided.")

    # compatibility with earlier versions
    if (source == "LOCAL") {
        if (purrr::is_null(origin))
            stop(paste0("LOCAL value is deprecated", "\n",
                        "Please see the documentation on ?sits_cube"))
        else {
            message(paste0("LOCAL value is deprecated", "\n",
                           "Using origin as the source","\n",
                           "Please see the documentation on ?sits_cube")
            )
            source <- origin
        }
    }

    # precondition - check source and collection
    .source_check(source = source)
    .source_collection_check(source = source, collection = collection)

    # name parameter has been deprecated
    if (!purrr::is_null(name)) {
        message("name parameter is no longer required")
    }

    dots <- list(...)

    # deal with wrong parameter "band"
    if ("band" %in% names(dots) && missing(bands)) {
        message("please use bands instead of band as parameter")
        bands <- as.character(dots[["band"]])
    }

    # precondition - does the parse info have band and date?
    .check_chr_contains(
        parse_info,
        contains = c("tile", "band", "date"),
        msg = "parse_info must include tile, date, and band."
    )

    # bands in upper case
    if (!purrr::is_null(bands))
        bands <- toupper(bands)

    # builds a sits data cube
    .local_cube(source = source,
                collection = collection,
                data_dir = data_dir,
                parse_info = parse_info,
                delim = delim,
                bands = bands,
                start_date = start_date,
                end_date = end_date,
                multicores = multicores,
                progress = progress, ...)
}


#' @rdname sits_cube
#'
#' @export
sits_cube.satveg_cube <- function(source = "SATVEG",
                                  collection = "TERRA",
                                  data_dir = NULL, ...) {

    # verifies if httr package is installed
    if (!requireNamespace("httr", quietly = TRUE)) {
        stop("Please install package httr.", call. = FALSE)
    }


    # precondition
    .check_chr_within(x = collection,
                      within = .source_collections(source = "SATVEG"),
                      msg = "invalid SATVEG collection.")

    # precondition - is service online?
    .source_collection_access_test(source = source, collection = collection)

    # creating satveg cube
    .source_cube(source = source, collection = collection, ...)
}

#' @export
sits_cube.default <- function(source, collection, ...) {
    stop("sits_cube: source not found.")
}
