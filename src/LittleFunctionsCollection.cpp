#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;


// Collection of all the little functions used by the main functions

// Function to check whether a point [PointX, PointY, PointZ] is within a cylider of a given radius
// and height from the center point of the top circle [TopX, TopY, TopZ]
bool InCylinder(double PointX, double PointY, double PointZ, double Radius, double Height, double CtrX, double CtrY, double CtrZ){
  if ((pow((PointX - CtrX), 2.0) + pow((PointY - CtrY), 2.0) <= pow(Radius, 2.0)) && (PointZ >= (CtrZ - (0.5*Height))) && (PointZ <= (CtrZ + (0.5*Height)))) {
    return true;
  }
  return false;
}

// Help functions for vertical filter
double VerticalDistance(double Height, double CtrZ, double PointZ){
  double BottomDistance = (double) std::fabs((CtrZ-Height/4.0-PointZ)/(3.0*Height/8.0));
  double TopDistance = (double) std::fabs((CtrZ+Height/2.0-PointZ)/(3.0*Height/8.0));
  double MinDistance = std::min(BottomDistance, TopDistance);
  return MinDistance;
}

//Equivalent R code
//distx <- function(h, CtrZ, PointZ){
//  bottomdist <- abs((CtrZ-h/4-PointZ)/(3*h/8))
//  topdist <- abs((CtrZ+h/2-PointZ)/(3*h/8))
//  mindist <- pmin(bottomdist, topdist)
//  return(mindist)
//}

// Epanechnikov function, with horizontal mask
double EpanechnikovFunction(double Height, double CtrZ, double PointZ){
  if((PointZ >= CtrZ-Height/4.0) && (PointZ <= CtrZ+Height/2.0)){
    return (1.0 - (pow(1.0-VerticalDistance(Height, CtrZ, PointZ), 2.0)));
  }
    return 0;
}

// Gauss function for horizontal filter
double GaussFunction(double Width, double CtrX, double CtrY, double PointX, double PointY){
  double Distance = sqrt(pow((PointX-CtrX), 2.0) + pow((PointY-CtrY), 2.0));
  double NormDistance = Distance/(Width/2.0);
  double Result = std::exp(-5.0*pow(NormDistance, 2.0));
  return Result;
}

//Equivalent R code
//gauss <- function(w, CtrX, CtrY, PointX, PointY){
//  distance <- ((PointX-CtrX)^2+(PointY-CtrY)^2)^0.5
//  norm.distance <- distance/w
//  output <- exp(-5*norm.distance^2)
//  return(output)
//}
