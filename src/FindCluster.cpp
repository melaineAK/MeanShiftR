#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;


//' Find clusters of modes
//'
//' @title Find cluster
//' @description
//' find clusters of modes if they are less than a meter far from each other
//' @param Ctr centroides (modes) coordinates
//' @return a Dataframe with the clusters for each mode
//' @export
// [[Rcpp::export]]
DataFrame FindCluster(NumericMatrix ctr, double epsilon)
{
  int nrows = ctr.nrow();
  NumericVector clus(nrows);
  for (int i = 0 ; i<nrows ; i++)
  {
    int id = i;
    bool found = false;

    for (int j = 0 ; j < i && !found ; j++)
    {
      double delta = sqrt(pow((ctr(i,0) - ctr(j,0)) , 2) + pow((ctr(i,1) - ctr(j,1)) , 2) + pow((ctr(i,2) - ctr(j,2)) , 2));

      if (delta < epsilon)
      {
        id = j;
        found = true;
      }
    }
    clus[i] = id;
  }
  return DataFrame::create(_["X"]= ctr(_,0),_["Y"]= ctr(_,1),_["Z"]= ctr(_,2),_["ID"]= clus);
}
