###################################
#                                 #
#             SETTINGS            #
#                                 #
###################################

# clearing the memory
rm(list = ls())

# setting directory depending on a user
if (Sys.info()[8] == "lizzzi111")           {setwd("~/Documents/DSG_2017_Finals/")} 
if (Sys.info()[8] == "kozodoi")             {setwd("~/Documents/Competitions/DSG_2017_Finals/")}
if (Sys.info()[8] == "nataliasverchkova")   {setwd("~/Documents/DSG/DSG_2017_Finals/")}
if (Sys.info()[8] == "oleksiyostapenko")    {setwd("/Users/oleksiyostapenko/Documents/HU_Berlin/ML/DSG/DSG_2017_Finals")}

# setting inner folders
code.folder <- "codes"
data.folder <- "data"
func.folder <- "functions"
subm.folder <- "submissions"

# loading libraries
if (require(pacman) == FALSE) install.packages("pacman")
library(pacman)
p_load(dplyr, data.table, caret, Metrics, xgboost, vtreat, plyr)

# loading all functions
source(file.path(code.folder, "code_0_helper_functions.R"))
source(file.path(code.folder, "code_0_parameters.R"))


###################################
#                                 #
#           TRANSFORMATION        #
#                                 #
###################################

# loading data
load(file.path(data.folder, "known_structured.rda"))
load(file.path(data.folder, "data_unknown.rda"))

# adding numeric T to data sets
known$t <- known$Month
levels(known$t) <- 1:length(levels(known$Month))
known$t <- as.numeric(as.character(known$t))
data_unknown$t  <- data_unknown$date
levels(data_unknown$t) <- (1+length(levels(known$Month))):(length(levels(known$Month))+length(levels(data_unknown$date)))
data_unknown$t <- as.numeric(as.character(data_unknown$t))

# convert to DT
known <- as.data.table(known)
unknown <- as.data.table(data_unknown)

# creating DV
known$ID <- NA
known$date <- NA
unknown$demand <- NA
unknown$Month <- NA

# merge 
data <- rbind(known[, c("ID", "Month", "SalOrg", "Material", "date", "t", "demand")], unknown)

# adding lags
data[, .demand_lag_1  := shift(demand, 1),  by = .(SalOrg, Material)]
data[, .demand_lag_2  := shift(demand, 2),  by = .(SalOrg, Material)]
data[, .demand_lag_3  := shift(demand, 3),  by = .(SalOrg, Material)]
data[, .demand_lag_4  := shift(demand, 4),  by = .(SalOrg, Material)]
data[, .demand_lag_5  := shift(demand, 5),  by = .(SalOrg, Material)]
data[, .demand_lag_6  := shift(demand, 6),  by = .(SalOrg, Material)]
data[, .demand_lag_7  := shift(demand, 7),  by = .(SalOrg, Material)]
data[, .demand_lag_8  := shift(demand, 8),  by = .(SalOrg, Material)]
data[, .demand_lag_9  := shift(demand, 9),  by = .(SalOrg, Material)]
data[, .demand_lag_10 := shift(demand, 10), by = .(SalOrg, Material)]
data[, .demand_lag_11 := shift(demand, 11), by = .(SalOrg, Material)]
data[, .demand_lag_12 := shift(demand, 12), by = .(SalOrg, Material)]


sub <- list()

for (country in levels(data$SalOrg)) {
  
  data_country <- as.data.frame(data)
  data_country <- data_country[data_country$SalOrg == country, ]
  
  # partition data
  known   <- data_country[data_country$t < 64, ]
  unknown <- data_country[data_country$t > 63, ]
  
  # known data with lags only
  cols <- c("Month", colnames(known)[grepl("demand", colnames(known))])
  known <- as.data.frame(known)
  known <- known[, colnames(known) %in% cols]
  known3 <- na.omit(known[, c("Month", "demand", paste0(".demand_lag_", 3:12))])
  
  # unknown data with lags only
  cols <- c("ID", colnames(unknown)[grepl(".demand", colnames(unknown))])
  unknown <- as.data.frame(unknown)
  unknown <- unknown[, colnames(unknown) %in% cols]
  unknown3 <- na.omit(unknown[, c("ID", paste0(".demand_lag_", 3:12))])
  
  # data partitioning
  valid.months <- c("2017-01", "2017-02", "2017-03")
  data_train3 <- known3[!(known3$Month %in% valid.months), ]
  data_valid3 <- known3[ (known3$Month %in% valid.months), ]
  
  
  
  ######### XGBOOST
  
  # parameters
  obje = "reg:linear"
  metrics = list(eval_metric = "mae", eval_metric = "mae")
  param <- c(list(booster = "gbtree", nthread = 4, objective = obje), metrics, nrounds = 100)
  ign_vars <- c("ID", "Month", dv)
  
  # xgb on lags from 3 to 12
  DMMatrixTrain <- xgb.DMatrix(data = as.matrix(data_train3[, !(colnames(data_train3) %in% ign_vars)]), label = data_train3$demand)
  DMMatrixTest  <- xgb.DMatrix(data = as.matrix(data_valid3[, !(colnames(data_valid3) %in% ign_vars)]), label = data_valid3$demand)
  watchlist <- list(train = DMMatrixTrain, test = DMMatrixTest)
  xgb3 <- xgb.train(data = DMMatrixTrain, params = param, watchlist=watchlist, nrounds = param$nrounds)
  varimp <- xgb.importance(colnames(data_train3[, !(colnames(data_train3) %in% ign_vars)]), xgb3)
  xgb.plot.importance(importance_matrix = varimp)
  valid.pred3  <- predict(xgb3, as.matrix(data_valid3[, !(colnames(data_valid3) %in% ign_vars)]))
  unknown3$pred3 <- predict(xgb3, as.matrix(unknown3[, !(colnames(unknown3) %in% ign_vars)]))
  
  # computing score on validation
  valid <- data.frame(pred3 = valid.pred3, demand = data_valid3$demand)
  valid$pred3[valid$pred3 < 0] <- 0
  apply(valid, 2, function(x) mean(abs((x - valid$demand))))
  
  # merging predictions
  subm <- as.data.frame(unknown3[, c("ID", "pred3")])
  subm$demand <- subm$pred3
  subm <- subm[, c("ID", "demand")]
  subm <- subm[order(subm$ID), ]
  subm$demand[subm$demand < 0] <- 0
  
  sub[[country]] <- subm
}

subm <- data.frame(ID = data_unknown[, c("ID")])

colnames(sub[[1]][2]) <- "p1"
colnames(sub[[2]][2]) <- "p2"
colnames(sub[[3]][2]) <- "p3"
colnames(sub[[4]][2]) <- "p4"

subm <- merge(subm, sub[[1]], all.x = T, all.y = F)
subm <- merge(subm, sub[[2]], all.x = T, all.y = F)
subm <- merge(subm, sub[[3]], all.x = T, all.y = F)
subm <- merge(subm, sub[[4]], all.x = T, all.y = F)

subm$demand <- subm$p1
subm$demand[is.na(subm$demand)] <- subm$p2[is.na(subm$demand)]
subm$demand[is.na(subm$demand)] <- subm$p3[is.na(subm$demand)]
subm$demand[is.na(subm$demand)] <- subm$p4[is.na(subm$demand)]

subm <- subm[, c("ID", "demand")]

# submit
prev <- read.csv(file.path(subm.folder, "xgb_lags_nikita.csv"))
cor(prev$demand, subm$demand)
write.table(as.data.frame(subm), file.path(subm.folder, "xgb_lags_1model_4countries.csv"), sep = ",", row.names = F, quote = F)