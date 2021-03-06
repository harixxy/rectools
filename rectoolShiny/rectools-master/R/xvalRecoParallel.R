
# arguments:

#    ratingsIn: input data, in the (userID, itemID, rating) format
#    rnk: desired rank for the P and Q matrices; then A approx= PQ'

# value:

#    an object of class 'Reco', with components being the P and Q
#    matrices

# Tell console we want to make a generic function called predict.
setGeneric(name="predict", def = function(recoObj,testSet){standardGeneric("predict")})

# arguments:

#    recoObj: an object of class 'Reco'
#    testSet: a matrix of the form of ratingsIn above


trainReco <- function(ratingsIn,rnk = 10)
{
  library(recosystem)
  r <- Reco()
  train_set = data_memory(ratingsIn[,1],ratingsIn[,2],ratingsIn[,3])
  print(isS4(r))
  r$train(train_set,opts = list(dim=rnk)) 
  P_file = out_file(tempfile())
  Q_file = out_file(tempfile())
  res = r$output(out_memory(),out_memory())
  #res <- setClass("Reco")
  res
}

# value:

#     vector of values predicted for testSet by recoObj


setMethod(f ="predict",
				 definition = function(recoObj,testSet)
				 {
				 	 p = recoObj$P
 					 q = recoObj$Q
  					 testSet$pred <- vector(length=nrow(testSet))
  					 for(i in 1:nrow(testSet)){
      					 j = testSet[i,1]
      				     k = testSet[i,2]
   						 testSet$pred[i] <- 
       						if(j > nrow(p) || k > nrow(q)) NA else
       							p[j,] %*% q[k,]
  					 }
  					testSet$pred
				 })
				 
########## the remaining functions are for cross-validation:

# arguments:

#    ratingsIn: as above
#    trainprop: probability that a row from ratingsIn is selected for
#               the training set

# value:

#    training set, in the format of ratingsIn, plus a component
#    trainidxs, the indices of the training set in the original data

getTrainSet <- function(ratingsIn,trainprop = 0.5){
  rownew = nrow(ratingsIn)
  trainRow = floor(trainprop*rownew)
  trainidxs = sample(1:rownew,trainRow)
  trainSet = ratingsIn[trainidxs,]
  trainSet$trainidxs = trainidxs
  trainSet
}

# returns the set-theoretic complement of the training set, to be used
# as the test set

getTestSet <- function(ratingsIn, trainSet){
  testSet = ratingsIn[setdiff(1:nrow(ratingsIn),trainSet$trainidxs),]
  testSet
}

# perform cross-validation

# arguments:

#    ratingsIn: as above
#    trainprop: as above
#    cls: an R 'parallel' cluster
#    rnk: as above

# value: object of class 'xvalreco', consisting mainly of various
# prediction accuracy measures, plus the number of NA predictions

xvalReco <- function(ratingsIn, trainprop = 0.5,
                     cls = NULL,
                     rnk = 10)
{
  library(recosystem)
  library(parallel)
  if(is.null(cls)){
    trainSet = getTrainSet(ratingsIn, trainprop)
    testSet= getTestSet(ratingsIn, trainSet)
    res = trainReco(trainSet)
    totalPreds = predict(res,testSet)
  
  }else {
    require(partools)
    clusterEvalQ(cls,require(partools))
    distribsplit(cls, 'ratingsIn')
    clusterExport(cls,c('trainReco','predict.Reco','getTestSet','getTrainSet'))
    clusterEvalQ(cls, trainSet<- getTrainSet(ratingsIn,trainprop=0.5))
    testSet= clusterEvalQ(cls, testSet<- getTestSet(ratingsIn,trainSet))
    testSet = mapply(c,testSet$ratings[1],testSet$ratings[2],SIMPLIFY = FALSE)
    clusterEvalQ(cls,resu <- trainReco(trainSet,rnk=10))
    allPreds = clusterEvalQ(cls, pred <- predict(ratingsIn,resu,testSet))
    totalPreds = mapply(c,totalPreds[1],totalPreds[2],SIMPLIFY = FALSE)
  }
  numpredna = sum(is.na(totalPreds))
  result = list(ndata = nrow(ratingsIn),trainprop = trainprop, 
                numpredna = numpredna)
  # accuracy measures
  exact <- mean(round(totalPreds) == testSet[,3],na.rm=TRUE)
  mad <- mean(abs(totalPreds-testSet[,3]),na.rm=TRUE)
  rms= sqrt(mean((totalPreds-testSet[,3])^2,na.rm=TRUE))
  # if just guess mean
  meanRat <- mean(testSet[,3],na.rm=TRUE)
  overallexact <-
     mean(round(meanRat) == testSet[,3],na.rm=TRUE)
  overallmad <- mean(abs(meanRat-testSet[,3]),na.rm=TRUE)
  overallrms <- sd(testSet[,3],na.rm=TRUE)
  result$acc <- list(exact=exact,mad=mad,rms=rms,
     overallexact=overallexact,
     overallmad=overallmad,
     overallrms=overallrms)
  if (is.null(cls)) {
     result$idxs <- as.numeric(rownames(testSet))
     result$preds <- totalPreds
     result$actuals <- ratingsIn[result$idxs,3]
  }
  class(result) <- 'xvalb'
  result
}

