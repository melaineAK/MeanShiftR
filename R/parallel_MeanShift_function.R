#' Parallel application of mean shift clustering for individual tree crown delineation
#'
#' The function provides the frame work to apply the adaptive mean shift 3D (AMS3D) algorithm on several
#' sub point clouds of a large investigation area in parallel. It requires a list of sub point clouds as
#' input and returns one large clustered point cloud as output. The input should have buffer zones around
#' the focal areas. The buffer width should correspond to at least the maximal possible tree crown radius.
#' @param pc.list List of point clouds in data.table format containing columns X, Y and Z (produced by split_BufferedPointCloud function)
#' @param lib.path String specifying the path from where to load the R packages. Should be set to .libPaths()[1].
#' @param frac.cores Fraction of available cores to use for parallelization
#' @param version of the AMS3D algorithm. Can be set to "classic" (slow but precise also with small trees) or "voxel" (fast but based on rounded coordinates of 1-m precision)
#' @param CWInter Intercept for crown width. Determines kernel diameter.
#' @param H2CW Factor for the ratio of height to crown width. Determines kernel diameter based on its height above ground.
#' @param CLInter Intercept for crown length. Determines kernel height.
#' @param H2CL Factor for the ratio of height to crown length. Determines kernel height based on its height above ground.
#' @param max.iter Maximum number of iterations, i.e. steps that the kernel can move for each point. If centroid is not found after all iteration, the last position is assigned as centroid and the processing jumps to the next point
#' @param buffer.width Width of the buffer around the core area in meters
#' @param minz Minimum height above ground for a point to be considered in the analysis. Has to be > 0.
#' @param ctr.ac Centroid accuracy. Specifies the rounding accuracy for centroid positions. After rounding all centroids with the same coordinates are considered to belong to one tree crown.
#' @param eps maximum distance between two centroids to be merged.
#' @return data.table of point cloud with points labelled with tree IDs
#' @keywords point cloud split buffer area plot subset parallel
#' @author Nikolai Knapp, nikolai.knapp@ufz.de

parallel_MeanShift <- function(pc.list, lib.path=NA, frac.cores=0.5, version="classic", CWInter=0.1, H2CW=0.3, CLInter=0.1, H2CL=0.4,
                               max.iter=20, buffer.width=10, minz=2, ctr.ac=2, eps=1.0){

  # Package requirements
  require(data.table, lib.loc=lib.path)
  require(plyr, lib.loc=lib.path)
  require(parallel, lib.loc=lib.path)
  require(pbapply, lib.loc=lib.path)
  require(Rcpp, lib.loc=lib.path)
  require(dbscan, lib.loc=lib.path)


  # Calculate the number of cores
  N.cores <- detectCores()
  # Initiate cluster
  mycl <- makeCluster(N.cores*frac.cores)
  # Prepare the environment on each child worker
  clusterExport(cl=mycl, varlist=c("lib.path", "version", "CWInter", "H2CW", "CLInter", "H2CL", "max.iter", "buffer.width", "minz", "ctr.ac"), envir=environment())
  clusterEvalQ(cl=mycl, .libPaths(new=lib.path))
  clusterEvalQ(cl=mycl, require(data.table, lib.loc=lib.path))
  clusterEvalQ(cl=mycl, require(plyr, lib.loc=lib.path))
  clusterEvalQ(cl=mycl, require(Rcpp, lib.loc=lib.path))
  clusterEvalQ(cl=mycl, require(MeanShiftR, lib.loc=lib.path))

  # Wrapper function that runs mean shift and deals with buffers
  run.MeanShift <- function(my.dt){

    # Remove points below a minimum height (ground and near ground returns)
    my.dt <- subset(my.dt, Z >= minz)

    # Get margins
    my.minx <- floor(min(my.dt$X))
    my.maxx <- ceiling(max(my.dt$X))
    my.miny <- floor(min(my.dt$Y))
    my.maxy <- ceiling(max(my.dt$Y))
    my.rangex <- my.maxx - my.minx
    my.rangey <- my.maxy - my.miny
    my.maxz <- ceiling(max(my.dt$Z))

    # Get margins of the core area
    core.minx <- floor(min(my.dt[Buffer==0, X]))
    core.maxx <- ceiling(max(my.dt[Buffer==0, X]))
    core.miny <- floor(min(my.dt[Buffer==0, Y]))
    core.maxy <- ceiling(max(my.dt[Buffer==0, Y]))

    # Shift to coordinate origin
    my.dt[, X := X - my.minx]
    my.dt[, Y := Y - my.miny]

    # Convert to 3-column matrix
    my.mx <- as.matrix(my.dt)
    my.mx <- my.mx[, 1:3]

    # Run the mean shift (two different versions)
    if(version=="classic"){
      cluster.df <- MeanShift_Classical(pc=my.mx, CWInter_fac=CWInter, H2CW_fac=H2CW, CLInter_fac=CLInter, H2CL_fac=H2CL, UniformKernel=F, MaxIter=max.iter)
    }else if(version=="voxel"){
      cluster.df <- MeanShift_Voxels(pc=my.mx, H2CW_fac=H2CW, H2CL_fac=H2CL, UniformKernel=F, MaxIter=max.iter, maxx=my.rangex, maxy=my.rangey, maxz=my.maxz)
    }

    # Round the centroid coordinates
    cluster.dt <- data.table(cluster.df)
    cluster.dt[, RoundCtrX := round_any(CtrX, accuracy=ctr.ac)]
    cluster.dt[, RoundCtrY := round_any(CtrY, accuracy=ctr.ac)]
    cluster.dt[, RoundCtrZ := round_any(CtrZ, accuracy=ctr.ac)]

    # Shift back to original positions
    cluster.dt[, X := X + my.minx]
    cluster.dt[, Y := Y + my.miny]
    cluster.dt[, CtrX := CtrX + my.minx]
    cluster.dt[, CtrY := CtrY + my.miny]
    cluster.dt[, RoundCtrX := RoundCtrX + my.minx]
    cluster.dt[, RoundCtrY := RoundCtrY + my.miny]

    # Subset tree clusters with centers inside the core area of the
    # focal subplot and discard the clusters with centers in the buffer area
    cluster.dt <- subset(cluster.dt, RoundCtrX >= core.minx & RoundCtrX < core.maxx  &
                                     RoundCtrY >= core.miny & RoundCtrY < core.maxy)

    # Collect the clustered point cloud in the results list
    return(cluster.dt)
  }

  # Apply the mean shift wrapper function in parallel
  #result.list <- parLapply(cl=mycl, X=pc.list, fun=run.MeanShift)

  # Apply the mean shift wrapper function in parallel using pblapply to display a progress bar
  result.list <- pbapply::pblapply(cl=mycl, X=pc.list, FUN=run.MeanShift)

  # Bind all point clouds from the list in one large data.table
  result.dt <- rbindlist(result.list)

  # # Assign IDs to each cluster based on the rounded coordinates
  result.dt[ , ID := .GRP, by = .(RoundCtrX, RoundCtrY, RoundCtrZ)]

  # other option to merge modes
  # CtrXYZ <- as.matrix(result.dt[,c('CtrX','CtrY','CtrZ')])
  # IDCtr <- FindCluster(ctr = CtrXYZ, epsilon = eps)
  # result.dt$ID <- IDCtr$ID

  # dbscan
  # CtrXYZ <- as.matrix(result.dt[,c('CtrX','CtrY','CtrZ')])
  # clusters <- dbscan(x = CtrXYZ, eps = eps)
  # result.dt$ID <- clusters$cluster

  # Finish
  stopCluster(mycl)
  return(result.dt)
}






