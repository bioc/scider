#' Perform kernel density estimation on SpatialExperiment for
#' cell types of interest
#'
#' @param spe A SpatialExperiment object.
#' @param coi A character vector of cell types of interest (COIs).
#' Default to all cell types.
#' @param id A character. The name of the column of colData(spe) containing
#' the cell type identifiers. Set to cell_type by default.
#' @param kernel The smoothing kernel. Options are "gaussian",
#' "epanechnikov", "quartic" or "disc".
#' @param bandwidth The smoothing bandwidth. By default performing
#' automatic bandwidth selection using cross-validation using
#' function spatstat.explore::bw.diggle.
#' @param ngrid.x Number of grids in the x-direction. Default to 100.
#' @param ngrid.y Number of grids in the y-direction.
#' @param grid.length.x Grid length in the x-direction.
#' @param grid.length.y Grid length in the y-direction.
#' @param diggle Logical. If TRUE, use the Jones-Diggle improved edge
#' correction. See spatstat.explore::density.ppp() for details.
#'
#' @return A SpatialExperiment object. Grid density estimates for
#' all cell type of interest are stored in spe@metadata$grid_density.
#' Grid information is stored in spe@metadata$grid_info
#'
#' @export
#'
#' @examples
#'
#' data("xenium_bc_spe")
#'
#' spe <- gridDensity(spe)
#'
gridDensity <- function(spe,
                        coi = NULL,
                        id = "cell_type",
                        kernel = "gaussian",
                        bandwidth = NULL,
                        ngrid.x = 100, ngrid.y = NULL,
                        grid.length.x = NULL, grid.length.y = NULL,
                        diggle = FALSE) {
    if (!id %in% colnames(colData(spe))) {
        stop(paste(id, "is not a column of the colData."))
    }

    if (is.null(coi)) {
        coi <- names(table(colData(spe)[[id]]))
    }

    if (length(which(!coi %in% names(table(colData(spe)[[id]])))) > 0L) {
        stop(paste(paste0(
            coi[which(!coi %in%
                names(table(colData(spe)[[id]])))],
            collapse = ", "
        ), "not found in data!", sep = " "))
    }

    coi_clean <- janitor::make_clean_names(coi)

    # define canvas
    spatialCoordsNames(spe) <- c("x_centroid", "y_centroid")
    coord <- spatialCoords(spe)
    xlim <- c(min(coord[, "x_centroid"]), max(coord[, "x_centroid"]))
    ylim <- c(min(coord[, "y_centroid"]), max(coord[, "y_centroid"]))

    # Calculate bandwidth
    pts <- ppp(coord[, 1], coord[, 2], xlim, ylim)
    if (is.null(bandwidth) & !is.null(spe@metadata$grid_info$bandwidth)) {
        bandwidth <- spe@metadata$grid_info$bandwidth
        message("Reusing existing bandwidth for kernel smoothing!")
    }
    if (is.null(bandwidth)) {
        bandwidth <- bw.diggle(pts) * 4
    }

    if (is.null(spe@metadata)) spe@metadata <- list()

    # Reset when the function is rerun again
    spe@metadata$grid_density <- spe@metadata$grid_info <- NULL

    # compute density for each cell type and then, filter
    for (ii in seq_len(length(coi))) {
        # subset data to this COI
        sub <- which(colData(spe)[[id]] == coi[ii])
        obj <- spe[, sub]

        # compute density
        out <- computeDensity(obj,
            mode = "pixels", kernel = kernel,
            bandwidth = bandwidth,
            ngrid.x = ngrid.x, ngrid.y = ngrid.y,
            grid.length.x = grid.length.x, grid.length.y = grid.length.y,
            xlim = xlim, ylim = ylim, diggle = diggle
        )
        RES <- out$grid_density

        ngrid.x <- out$density_est$dim[2]
        ngrid.y <- out$density_est$dim[1]

        if (is.null(spe@metadata$grid_density)) {
            spe@metadata <- list("grid_density" = RES[, seq_len(2)])
            # horizontal ind
            spe@metadata$grid_density$node_x <- rep(seq_len(ngrid.x),
                each = ngrid.y
            )
            # vertical ind
            spe@metadata$grid_density$node_y <- rep(
                seq_len(ngrid.y),
                ngrid.x
            )
            spe@metadata$grid_density$node <- paste(
                spe@metadata$grid_density$node_x,
                spe@metadata$grid_density$node_y,
                sep = "-"
            )
        }
        spe@metadata$grid_density <- cbind(
            spe@metadata$grid_density,
            RES$density
        )
        colnames(spe@metadata$grid_density)[5 + ii] <- paste("density",
            coi_clean[ii],
            sep = "_"
        )

        # grid info
        if (is.null(spe@metadata$grid_info)) {
            spe@metadata$grid_info <- list(
                dims = c(ngrid.x, ngrid.y),
                xlim = xlim,
                ylim = ylim,
                xcol = out$density_est$xcol,
                yrow = out$density_est$yrow,
                xstep = out$density_est$xstep,
                ystep = out$density_est$ystep,
                bandwidth = bandwidth
            )
        }
    }
    return(spe)
}
