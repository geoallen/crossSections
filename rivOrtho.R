# rivOrtho.R

# 2016 George Allen. see license file
# georgehenryallen@gmail.com

# runs through each GRWL centerline, calculates the orthogonal
# direction to the along stream direction at each vertex. 
# this runs assuming a greographic lat/lon projection.

# load requred packages:
require(foreign)
require(geosphere)
require(rgdal)
require(shapefiles)


########################################################################
# input parameters:

# path of directory containing rivwidth dbf file(s): 
dbfD = "E:/misc/2016_01_02 AMHG Grant/GRWL/xSectionVectorsRscript_forColin/input" 

# path of output shapefile(s):
outD = "E:/misc/2016_01_02 AMHG Grant/GRWL/xSectionVectorsRscript_forColin/output"

n = 5 # N centerline vertices overwhich to calculate direction (must be odd numbers >1)
res = 30 # spatial resolution of dataset (m)
wt = c(5,5,3,1,1)/15 # weights for the weighted mean calculation
xLength = 1e-5 # multiplier controling length to draw Xsection lines
xSpacing = 20 # n pixel spacing between each cross section


########################################################################
# functions:

# insertRow takes an existing data table, a row to insert, and an index 
# of where the insert should occur and returns the updated data file:
insertRow = function(existingDF, newrow, r) {
  existingDF[seq(r+1,length(existingDF)+1)] = existingDF[seq(r,length(existingDF))]
  existingDF[r] = newrow
  return(existingDF)
}

# bearingExtrap takes a GRWL centerline X, Y, incomplete bearing vector, 
# vector length, and indices of missing bearing values 
# and returns a completed bearing vector: 
bearingExtrap = function(x, y, b, n, jNA){
  
  # indicies of adjacent NA values:
  closeL = jNA[-1] - 1
  closeR = jNA[-length(jNA)] + 1
  farL = jNA[-1] - floor(n/2)
  farR = jNA[-length(jNA)] + floor(n/2)
  
  # use a linearly shrinking window to calculate bearing at ends of vectors:
  for (i in 1:(length(jNA)-1)){
    
    fL = farL[i]:closeL[i]
    rL = closeR[i]:farR[i]
    
    for (ii in 1:length(fL)){
      
      # calculate all points on left sides of jumps:
      L = c((fL[ii]-floor(n/2)), closeL[i])
      b[fL[ii]] = bearing(cbind(x[L[1]], y[L[1]]), cbind(x[L[2]], y[L[2]]))
      
      # handle all points on right sides of vectors:
      R = c(closeR[i], (rL[ii]+floor(n/2)))
      b[rL[ii]] = bearing(cbind(x[R[1]], y[R[1]]), cbind(x[R[2]], y[R[2]]))
      
    }
  }
  
  return(b)
  
}

# widthExtrap takes an incomplete GRWL width vector and
# returns a completed width vector by interpolating or 
# extrapolating missing width values:
widthExtrap = function(w){
  
  wNA = which(w<30)
  if (length(wNA) > 0){
    jw = c(0, which(wNA[-1]-wNA[-length(wNA)]>1), length(wNA))
    
    # for each block of missing width values:
    for (i in 1:(length(jw)-1)){
      
      # find out what is on either side of the block of missing widths:
      wB = wNA[(jw[i]+1):jw[i+1]]
      lwB = length(wB)
      
      L = w[wB[1]-1]
      R = w[wB[lwB]+1]
      
      # if a block of missing widths does not contain a jump on either end,
      
      if (!is.na(L) & !is.na(R)){
        # linear interpolation:
        m = (w[wB[lwB]+1]-w[wB[1]-1])/(lwB+1)
        w[wB] = m * (1:lwB) +  w[wB[1]-1]
        
        # interpolate between missing width values with a cubic spline:
        #spx = c(c(1:n), c(1:n)+lwB)
        #spy = c(w[c((wB[1]-n):(wB[1]-1))], w[c((wB[lwB]+1):(wB[lwB]+n))])
        #spf = splinefun(spx, spy)
        #w[wB] = spf(c((n+1):(n+lwB)))
        
      }else{
        
        # if one side of block contains spatial jump, use data from other 
        # end of block to take a weighted average width:
        if (is.na(L) & !is.na(R)){
          mW = weighted.mean(w[c((wB[lwB]+1):(wB[lwB]+5))], wt, na.rm=T)
        }else{
          mW = weighted.mean(w[c((wB[1]-5):(wB[1]-1))], wt, na.rm=T)
        }
        w[wB] = rep(mW, lwB)
      }
      
      # if there is a jump on both sides of the NA bloack, fill with 30:
      if (is.na(L) & is.na(R)){
        print("BOTH ENDS OF MISSING WIDTH BLOCK = NA")
        w[wB] = rep(30, lwB)
      }
    }
  }
  
  return(w)
  
}


########################################################################
# get list of dbf files paths and names to process:
dbfPs = list.files(dbfD, 'dbf', full.names=T)
dbfNs = list.files(dbfD, 'dbf', full.names=F)

pdfPs = sub('dbf', 'pdf', paste0(outD, '/', dbfNs))
outPs = sub('.dbf', '', paste0(outD, '/', dbfNs[h]))

print(paste("N shapefies to process:", length(dbfPs)))

for (h in 1:length(dbfPs)){
  dbfP = dbfPs[h]
  
  ########################################################################
  # calculate cross sectional direction at each vertex:
  
  # read in GRWL shapefile dbf: 
  tab = foreign::read.dbf(dbfP)
  if("dbf" %in% names(tab)){tab=tab$dbf}
  
  x = tab$lon
  y = tab$lat
  w = tab$width
  l = nrow(tab)
  
  # chop start and end of vectors calculate bearing between neighbors: 
  p1x = x[-c((l-n+2):l)]
  p1y = y[-c((l-n+2):l)]
  p2x = x[-c(1:(n-1))]
  p2y = y[-c(1:(n-1))]
  
  p1 = cbind(p1x, p1y)
  p2 = cbind(p2x, p2y)
  
  # calculate distance (in meters) between two adjacent vertices 
  # to find big jumps and remove them from this calculation:
  d = distGeo(p1, p2)
  j = which(d > res*n*2) + floor(n/2)
  
  # calculate bearing (rather than slope account for the distortion of lat lon):
  b = bearing(p1, p2)
  # make vector original length:
  b = c(rep(-999, floor(n/2)), b, rep(-999, floor(n/2)))
  b[j] = -999
  
  
  #### handle river segment ends: 
  # recalculate jumps, this time over a single nextdoor neighbor vertices:
  p1x = x[-l]
  p1y = y[-l]
  p2x = x[-1]
  p2y = y[-1]
  
  p1 = cbind(p1x, p1y)
  p2 = cbind(p2x, p2y)
  
  sd = distGeo(p1, p2)
  sj = which(sd > res*2)+1
  
  # insert NAs at start, end, and jump in vector:
  for (i in rev(1:length(sj))){
    x = insertRow(x, NA, sj[i])
    y = insertRow(y, NA, sj[i])
    b = insertRow(b, NA, sj[i])
    w = insertRow(w, NA, sj[i])
  }
  
  x = c(NA, x, NA)
  y = c(NA, y, NA)
  b = c(NA, b, NA)
  w = c(NA, w, NA)
  
  # get bounds of -999 values:
  jNA = which(is.na(b))
  
  # calculate bearings at ends of the vectors:
  b = bearingExtrap(x, y, b, n, jNA)
  
  # occationally, there are a situations where the GRWL
  # centerline is clipped such that there is only 1 segment, 
  # thus introducing NANs into the bearing calculation above.
  # fill these NANs in with a bear of 90. 
  b[which(is.nan(b))] = 90
  b[jNA] = NA
  
  
  
  # interpolate/extrapolate any missing width values:
  w = widthExtrap(w)
  
  # remove NA values:
  x = na.omit(x)
  y = na.omit(y)
  b = na.omit(b)
  w = na.omit(w)
  
  
  ########################################################################
  # PLOT as PDF: 
  
  pdfOut = pdfPs[h]
  pdf(pdfOut, width=100, height=100)
  
  j = which(d > res*n*2)
  
  # convert azimuth to quadrant degree coordinate system 
  # (0 degrees to the right, counter clockwise rotation):
  q = 90-b
  q[q < 0] = q[q < 0] + 360
  
  o1x = x + sin(q*pi/180)*(w*xLength+.005)
  o1y = y - cos(q*pi/180)*(w*xLength+.005)
  o2x = x - sin(q*pi/180)*(w*xLength+.005)
  o2y = y + cos(q*pi/180)*(w*xLength+.005)
  
  # recalculate jumps, this time over a single nextdoor neighbor vertices:
  p1x = x[-l]
  p1y = y[-l]
  p2x = x[-1]
  p2y = y[-1]
  
  p1 = cbind(p1x, p1y)
  p2 = cbind(p2x, p2y)
  
  sj = which(distGeo(p1, p2) > res*2)+1
  
  for (i in rev(1:length(sj))){
    x = insertRow(x, NA, sj[i])
    y = insertRow(y, NA, sj[i])
  }
  
  plot(x, y, type='l', asp=1, lwd=.1, col=1,
       xlab="lon", ylab='lat')
  
  xI = seq(xSpacing/2, nrow(tab), xSpacing)
  segments(o1x[xI], o1y[xI], o2x[xI], o2y[xI], col=2, lwd=.1)

  # close writing pdf file
  dev.off() 
  
  # oepn PDF file:
  cmd = paste('open', pdfOut)
  system(cmd)
  
  
  ########################################################################
  # write out original DBF file:
  
  # convert bearing to azimuth:
  b[b < 0] = b[b < 0] + 360
  
  # calculate orthogonal to azimuth:
  xDir = b#b+90
  xDir[xDir > 360] = xDir[xDir > 360] - 360
  
  tab$azimuth = xDir
  tab$width_m = w
  
  # update original dbf to include azimuth 
  # and extrapolated width data: 
  #write.dbf(tab, dbfP)
  
  ########################################################################
  # write out cross section shapefile:
  
  # create polygon shapefile:
  X = c(o1x[xI], o2x[xI])
  Y = c(o1y[xI], o2y[xI])
  ID = rep(1:length(o1x[xI]), 2)
  Name = unique(ID)
  
  dd = data.frame(ID=ID, X=X, Y=Y)
  ddTable = data.frame(ID=Name, lat_dd=tab$lat[xI], lon_dd=tab$lon[xI],
                       width_m=tab$width[xI], xDir=xDir[xI])
  ddShapefile = convert.to.shapefile(dd, ddTable, "ID", 3)
  
  # write out shapefile:
  write.shapefile(ddShapefile, outPs[h], arcgis=T)
  
  # copy prj file:
  file.copy(prjP, paste0(outPs[h], '.prj'))

  print(paste(h, dbfNs[h], "done run!"))
  
}


