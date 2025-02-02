#' @title Images arrangement in sits cube
#' @name .gc_arrange_images
#'
#' @keywords internal
#'
#' @param cube       A sits data cube
#'
#' @param agg_method A \code{character} with method that will be applied by
#'  \code{gdalcubes} for aggregation. Options: \code{min}, \code{max},
#'  \code{mean}, \code{median} and \code{first}. Default is \code{median}.
#'
#' @param duration   A \code{Duration} object from lubridate package.
#'
#' @param ...        Additional parameters.
#'
#' @return  A sits cube with the images arranged according to some criteria.
.gc_arrange_images <- function(cube, agg_method, duration, ...) {

    class(agg_method) <- agg_method

    UseMethod(".gc_arrange_images", agg_method)
}

#' @keywords internal
#' @export
.gc_arrange_images.default <- function(cube, agg_method, duration, ...) {

    return(cube)
}

#' @keywords internal
#' @export
.gc_arrange_images.first <- function(cube, agg_method, duration, ...) {

    .sits_fast_apply(data = cube, col = "file_info", fn = function(x) {

        tl_length <- max(2,
                         lubridate::interval(start = min(x[["date"]]),
                                             end = max(x[["date"]]))  / duration
        )

        dplyr::group_by(x, date_interval = cut(.data[["date"]], tl_length),
                        .add = TRUE) %>%
            dplyr::arrange(.data[["cloud_cover"]], .by_group = TRUE) %>%
            dplyr::ungroup() %>%
            dplyr::select(-.data[["date_interval"]])
    })
}

#' @title Save the images based on an aggregation method.
#' @name .gc_new_cube
#' @keywords internal
#'
#' @param tile          A data cube tile
#' @param img_col       A \code{object} 'image_collection' containing information
#'  about the images metadata.
#' @param cv            A \code{list} 'cube_view' with values from cube.
#' @param cloud_mask    A \code{logical} corresponds to the use of the cloud band
#'  for aggregation.
#' @param path_db       Database to be created by gdalcubes
#' @param output_dir    Directory where the aggregated images will be written.
#' @param cloud_mask    A \code{logical} corresponds to the use of the cloud band
#'  for aggregation.
#' @param multithreads  A \code{numeric} with the number of cores will be used in
#'  the regularize. By default is used 1 core.
#' @param ...         Additional parameters that can be included. See
#'  '?gdalcubes::write_tif'.
#'
#' @return  A data cube tile with information used in its creation.
.gc_new_cube <- function(tile,
                         cv,
                         img_col,
                         path_db,
                         output_dir,
                         cloud_mask,
                         multithreads, ...) {

    # set caller to show in errors
    .check_set_caller(".gc_new_cube")

    bbox <- .cube_tile_bbox(cube = tile)

    # create a list of creation options and metadata
    .get_gdalcubes_pack <- function(cube, band) {

        # returns the type that the file will write
        format_type <- .source_collection_gdalcubes_type(
            .cube_source(cube = tile),
            collection = .cube_collection(cube = tile)
        )

        return(
            list(type   = format_type,
                 nodata = .cube_band_missing_value(cube = cube, band = band),
                 scale  = 1,
                 offset = 0
            )
        )
    }

    .get_cube_chunks <- function(cv) {

        bbox <- c(xmin = cv[["space"]][["left"]],
                  xmax = cv[["space"]][["right"]],
                  ymin = cv[["space"]][["bottom"]],
                  ymax = cv[["space"]][["top"]])

        size_x <- (max(bbox[c("xmin", "xmax")]) - min(bbox[c("xmin", "xmax")]))
        size_y <- (max(bbox[c("ymin", "ymax")]) - min(bbox[c("ymin", "ymax")]))

        # a vector with time, x and y
        chunk_size <- .config_gdalcubes_chunk_size()

        chunks_x <- round(size_x / cv[["space"]][["dx"]]) / chunk_size[[2]]
        chunks_y <- round(size_y / cv[["space"]][["dy"]]) / chunk_size[[3]]

        # guaranteeing that it will return fewer blocks than calculated
        num_chunks <- (ceiling(chunks_x) * ceiling(chunks_y)) - 1

        return(max(1, num_chunks))
    }

    # setting threads to process
    # multicores number must be smaller than chunks
    gdalcubes::gdalcubes_options(
        threads = min(multithreads, .get_cube_chunks(cv))
    )

    file_info <- purrr::map_dfr(.cube_bands(tile, add_cloud = FALSE), function(band) {

        # create a raster_cube object to each band the select below change
        # the object value
        cube_brick <- .gc_raster_cube(tile, img_col, cv, cloud_mask)

        # write the aggregated cubes
        path_write <- gdalcubes::write_tif(
            gdalcubes::select_bands(cube_brick, band),
            dir = output_dir,
            prefix = paste("cube", tile[["tile"]], band, "", sep = "_"),
            creation_options = list("COMPRESS" = "LZW", "BIGTIFF" = "YES"),
            pack = .get_gdalcubes_pack(tile, band), ...
        )

        # post-condition
        .check_length(path_write, len_min = 1,
                      msg = "no image was created")

        # retrieving image date
        images_date <- .gc_get_date(path_write)

        # post-condition
        .check_length(images_date, len_min = length(path_write))

        # open first image to retrieve metadata
        r_obj <- .raster_open_rast(path_write[[1]])

        # set file info values
        tibble::tibble(
            fid = paste("cube", .cube_tiles(tile), images_date, sep = "_"),
            date = images_date,
            band = band,
            xres  = .raster_xres(r_obj),
            yres  = .raster_yres(r_obj),
            xmin  = .raster_xmin(r_obj),
            xmax  = .raster_xmax(r_obj),
            ymin  = .raster_ymin(r_obj),
            ymax  = .raster_ymax(r_obj),
            nrows = .raster_nrows(r_obj),
            ncols = .raster_ncols(r_obj),
            path = path_write
        )
    })

    # arrange file_info by date and band
    file_info <- dplyr::arrange(file_info, .data[["date"]], .data[["band"]])

    # generate sequential fid
    file_info[["fid"]] <- paste0(seq_along(file_info[["fid"]]))

    cube_gc <- .cube_create(
        source     = tile[["source"]],
        collection = tile[["collection"]],
        satellite  = tile[["satellite"]],
        sensor     = tile[["sensor"]],
        tile       = tile[["tile"]],
        xmin       = cv[["space"]][["left"]],
        xmax       = cv[["space"]][["right"]],
        ymin       = cv[["space"]][["bottom"]],
        ymax       = cv[["space"]][["top"]],
        crs        = tile[["crs"]],
        file_info  = file_info
    )

    return(cube_gc)
}

#' @title Extracted date from aggregated cubes
#' @name .gc_get_date
#' @keywords internal
#'
#' @param dir_images A \code{character}  corresponds to the path on which the
#'  images will be saved.
#'
#' @return a \code{character} vector with the dates extracted.
.gc_get_date <- function(dir_images) {

    # get image name
    image_name <- basename(dir_images)

    date_files <-
        purrr::map_chr(strsplit(image_name, "_"), function(split_path) {
            tools::file_path_sans_ext(split_path[[4]])
        })

    # check type of date interval
    if (length(strsplit(date_files, "-")[[1]]) == 1)
        date_files <- lubridate::fast_strptime(date_files, "%Y")
    else if (length(strsplit(date_files, "-")[[1]]) == 2)
        date_files <- lubridate::fast_strptime(date_files, "%Y-%m")
    else
        date_files <- lubridate::fast_strptime(date_files, "%Y-%m-%d")

    # transform to date object
    date_files <- lubridate::as_date(date_files)

    return(date_files)
}

#' @title Create a raster_cube object
#' @name .gc_raster_cube
#' @keywords internal
#'
#' @param cube       Data cube from where data is to be retrieved.
#' @param img_col    A \code{object} 'image_collection' containing information
#'  about the images metadata.
#' @param cv         A \code{object} 'cube_view' with values from cube.
#' @param cloud_mask A \code{logical} corresponds to the use of the cloud band
#'  for aggregation.
#'
#' @return a \code{object} 'raster_cube' from gdalcubes containing information
#'  about the cube brick metadata.
.gc_raster_cube <- function(cube, img_col, cv, cloud_mask) {

    mask_band <- NULL
    if (cloud_mask)
        mask_band <- .gc_cloud_mask(cube)

    # create a brick of raster_cube object
    cube_brick <- gdalcubes::raster_cube(
        image_collection = img_col,
        view = cv,
        mask = mask_band,
        chunking = .config_gdalcubes_chunk_size())

    return(cube_brick)
}

#' @title Create an object image_mask with information about mask band
#' @name .gc_cloud_mask
#' @keywords internal
#'
#' @param tile Data cube tile from where data is to be retrieved.
#'
#' @return A \code{object} 'image_mask' from gdalcubes containing information
#'  about the mask band.
.gc_cloud_mask <- function(tile) {

    bands <- .cube_bands(tile)
    cloud_band <- .source_cloud()

    # checks if the cube has a cloud band
    .check_chr_within(
        x = cloud_band,
        within = unique(bands),
        discriminator = "any_of",
        msg = paste("It was not possible to use the cloud",
                    "mask, please include the cloud band in your cube")
    )

    # create a image mask object
    mask_values <- gdalcubes::image_mask(
        cloud_band,
        values = .source_cloud_interp_values(
            source = .cube_source(cube = tile),
            collection = .cube_collection(cube = tile)
        )
    )

    # is this a bit mask cloud?
    if (.source_cloud_bit_mask(
        source = .cube_source(cube = tile),
        collection = .cube_collection(cube = tile)))

        mask_values <- list(
            band = cloud_band,
            min = 1,
            max = 2^16,
            bits = mask_values$values,
            values = NULL,
            invert = FALSE
        )

    class(mask_values) <- "image_mask"

    return(mask_values)
}

#' @title Create an image_collection object
#' @name .gc_create_database
#' @keywords internal
#'
#' @param cube      Data cube from where data is to be retrieved.
#' @param path_db   A \code{character} with the path and name where the
#'  database will be create. E.g. "my/path/gdalcubes.db"
#'
#' @return a \code{object} 'image_collection' containing information about the
#'  images metadata.
.gc_create_database <- function(cube, path_db) {

    # set caller to show in errors
    .check_set_caller(".gc_create_database")

    file_info <- dplyr::bind_rows(cube$file_info)
    # retrieving the collection format
    format_col <- .source_collection_gdalcubes_config(
        .cube_source(cube = cube),
        collection = .cube_collection(cube = cube)
    )

    message("Creating database of images...")
    ic_cube <- gdalcubes::create_image_collection(
        files    = file_info$path,
        format   = format_col,
        out_file = path_db
    )
    return(ic_cube)
}

#' @title Create an image_collection object
#' @name .gc_create_database_stac
#'
#' @keywords internal
#'
#' @param cube      Data cube from where data is to be retrieved.
#'
#' @param path_db   A \code{character} with the path and name where the
#'  database will be create. E.g. "my/path/gdalcubes.db"
#'
#' @return a \code{object} 'image_collection' containing information about the
#'  images metadata.
.gc_create_database_stac <- function(cube, path_db) {

    # deleting the existing database to avoid errors in the stac database
    if (file.exists(path_db))
        unlink(path_db)

    create_gc_database <- function(cube) {

        file_info <- dplyr::select(cube, .data[["file_info"]],
                                   .data[["crs"]]) %>%
            tidyr::unnest(cols = c("file_info")) %>%
            dplyr::transmute(fid = .data[["fid"]],
                             xmin = .data[["xmin"]],
                             ymin = .data[["ymin"]],
                             xmax = .data[["xmax"]],
                             ymax = .data[["ymax"]],
                             href = .data[["path"]],
                             datetime = as.character(.data[["date"]]),
                             band = .data[["band"]],
                             `proj:epsg` = gsub("^EPSG:", "", .data[["crs"]]))

        features <- dplyr::mutate(file_info, id = .data[["fid"]]) %>%
            tidyr::nest(features = -.data[["fid"]])

        features <- slider::slide_dfr(features, function(feat) {

            bbox <- .sits_coords_to_bbox_wgs84(
                xmin = feat$features[[1]][["xmin"]][[1]],
                xmax = feat$features[[1]][["xmax"]][[1]],
                ymin = feat$features[[1]][["ymin"]][[1]],
                ymax = feat$features[[1]][["ymax"]][[1]],
                crs = as.numeric(feat$features[[1]][["proj:epsg"]][[1]])
            )

            feat$features[[1]] <- dplyr::mutate(feat$features[[1]],
                                                xmin = bbox[["xmin"]],
                                                xmax = bbox[["xmax"]],
                                                ymin = bbox[["ymin"]],
                                                ymax = bbox[["ymax"]])

            feat
        })

        purrr::map(features[["features"]], function(feature) {

            feature <- feature %>%
                tidyr::nest(assets = c(.data[["href"]], .data[["band"]])) %>%
                tidyr::nest(properties = c(.data[["datetime"]],
                                           .data[["proj:epsg"]])) %>%
                tidyr::nest(bbox = c(.data[["xmin"]], .data[["ymin"]],
                                     .data[["xmax"]], .data[["ymax"]]))

            feature[["assets"]] <- purrr::map(feature[["assets"]], function(asset) {

                asset %>%
                    tidyr::pivot_wider(names_from = .data[["band"]],
                                       values_from = .data[["href"]]) %>%
                    purrr::map(
                        function(x) list(href = x, `eo:bands` = list(NULL))
                    )
            })

            feature <- unlist(feature, recursive = FALSE)
            feature[["properties"]] <- c(feature[["properties"]])
            feature[["bbox"]] <- unlist(feature[["bbox"]])
            feature
        })
    }

    ic_cube <- gdalcubes::stac_image_collection(
        s = create_gc_database(cube),
        out_file = path_db,
        url_fun = identity)

    return(ic_cube)
}

#' @title Internal function to handle with different file collection formats
#'  for each provider.
#' @name .gc_format_col
#' @keywords internal
#'
#' @description
#' Generic function with the goal that each source implements its own way of
#' localizing the collection format file.
#'
#' @param source     A \code{character} value referring to a valid data source.
#' @param collection A \code{character} value referring to a valid collection.
#' @param ...        Additional parameters.
#'
#' @return A \code{character} path with format collection.
.gc_format_col <- function(source, collection, ...) {

    # set caller to show in errors
    .check_set_caller("sits_cube")
    # try to find the gdalcubes configuration format for this collection
    gdal_config <- .config_get(key = c("sources", source, "collections",
                                       collection, "gdalcubes_format_col"),
                               default = NA)
    # if the format does not exist, report to the user
    .check_that(!(is.na(gdal_config)),
                msg = paste0("collection ", collection, " in source ", source,
                             "not supported yet\n",
                             "Please raise an issue in github"))
    # return the gdal format file path
    system.file(paste0("extdata/gdalcubes/", gdal_config), package = "sits")
}

#' @title Create a cube_view object
#' @name .gc_create_cube_view
#' @keywords internal
#'
#' @param tile       A data cube tile
#' @param period     A \code{character} with the The period of time in which it
#'  is desired to apply in the cube, must be provided based on ISO8601, where 1
#'  number and a unit are provided, for example "P16D".
#' @param res        A \code{numeric} with spatial resolution of the image that
#'  will be aggregated.
#' @param roi        A region of interest.
#' @param toi        A timeline of intersection
#' @param agg_method A \code{character} with the method that will be applied in
#'  the aggregation, the following are available: "min", "max", "mean",
#'  "median" or "first".
#' @param resampling A \code{character} with method to be used by
#'  \code{gdalcubes} for resampling in mosaic operation.
#'  Options: \code{near}, \code{bilinear}, \code{bicubic} or others supported by
#'  gdalwarp (see https://gdal.org/programs/gdalwarp.html).
#'  By default is bilinear.
#'
#' @return a \code{cube_view} object from gdalcubes.
.gc_create_cube_view <- function(tile,
                                 period,
                                 res,
                                 roi,
                                 toi,
                                 agg_method,
                                 resampling) {

    # set caller to show in errors
    .check_set_caller(".gc_create_cube_view")

    .check_that(
        x = nrow(tile) == 1,
        msg = "tile must have only one row."
    )

    .check_null(
        x = period,
        msg = "the parameter 'period' must be provided."
    )

    .check_null(
        x = agg_method,
        msg = "the parameter 'method' must be provided."
    )

    .check_num(
        x = res,
        msg = "the parameter 'res' is invalid.",
        allow_null = TRUE,
        len_max = 1
    )

    bbox_roi <- sits_bbox(tile)

    if (!is.null(roi))
        bbox_roi <- .sits_roi_bbox(roi, tile)

    roi <- list(left   = bbox_roi[["xmin"]],
                right  = bbox_roi[["xmax"]],
                bottom = bbox_roi[["ymin"]],
                top    = bbox_roi[["ymax"]])

    # create a list of cube view
    cv <- gdalcubes::cube_view(
        extent = list(left   = roi[["left"]],
                      right  = roi[["right"]],
                      bottom = roi[["bottom"]],
                      top    = roi[["top"]],
                      t0 = format(toi[[1]], "%Y-%m-%d"),
                      t1 = format(toi[[2]], "%Y-%m-%d")),
        srs = tile[["crs"]][[1]],
        dt = period,
        dx = res,
        dy = res,
        aggregation = agg_method,
        resampling = resampling
    )

    return(cv)
}
#' @title Get the timeline of intersection in all tiles
#' @name .gc_get_valid_timeline
#'
#' @keywords internal
#'
#' @param cube       Data cube from where data is to be retrieved.
#' @param period     A \code{character} with ISO8601 time period for regular
#'  data cubes produced by \code{gdalcubes}, with number and unit, e.g., "P16D"
#'  for 16 days. Use "D", "M" and "Y" for days, month and year.
#'
#' @return a \code{vector} with all timeline values.
.gc_get_valid_timeline <- function(cube, period) {

    # pre-condition
    .check_chr(period, allow_empty = FALSE,
               len_min = 1, len_max = 1,
               msg = "invalid 'period' parameter")

    # start date - maximum of all minimums
    max_min_date <- do.call(
        what = max,
        args = purrr::map(cube[["file_info"]], function(file_info){
            return(min(file_info[["date"]]))
        })
    )

    # end date - minimum of all maximums
    min_max_date <- do.call(
        what = min,
        args = purrr::map(cube[["file_info"]], function(file_info){
            return(max(file_info[["date"]]))
        }))

    # check if all timeline of tiles intersects
    .check_that(
        x = max_min_date <= min_max_date,
        msg = "the timeline of the cube tiles do not intersect."
    )

    if (substr(period, 3, 3) == "M") {
        max_min_date <- lubridate::date(paste(
            lubridate::year(max_min_date),
            lubridate::month(max_min_date),
            "01", sep = "-"))
    } else if (substr(period, 3, 3) == "Y") {
        max_min_date <- lubridate::date(paste(
            lubridate::year(max_min_date),
            "01", "01", sep = "-"))
    }

    # generate timeline
    date <- lubridate::ymd(max_min_date)
    min_max_date <- lubridate::ymd(min_max_date)
    tl <- date
    while (TRUE) {
        date <- lubridate::ymd(date) %m+% lubridate::period(period)
        if (date > min_max_date) break
        tl <- c(tl, date)
    }

    # timeline cube
    tiles_tl <- suppressWarnings(sits_timeline(cube))

    if (!is.list(tiles_tl))
        tiles_tl <- list(tiles_tl)

    return(tl)
}
