#' predictHVT
#'
#' Predict which cell and what level each point in the test dataset belongs to
#'
#'
#' @param data List. A dataframe containing test dataset. The dataframe should have atleast one variable used while training. The variables from
#' this dataset can also be used to overlay as heatmap
#' @param hvt.results A list of hvt.results obtained from HVT function while performing hierarchical vector quantization on train data
#' @param hmap.cols - The column number of column name from the dataset indicating the variables for which the heat map is to be plotted.(Default = #' NULL). A heatmap won’t be plotted if NULL is passed
#' @param child.level A number indicating the level for which the heat map is to be plotted.(Only used if hmap.cols is not NULL)
#' @param ...  color.vec and line.width can be passed from here
#' @author Sangeet Moy Das <sangeet.das@@mu-sigma.com>
#' @seealso \code{\link{HVT}} \cr \code{\link{hvtHmap}}
#' @keywords predict
#' @importFrom magrittr %>%
#' @examples
#' data(USArrests)
#' #Split in train and test
#'
#' train <- USArrests[1:40,]
#' test <- USArrests[41:50,]
#'
#' hvt.results <- list()
#' hvt.results <- HVT(train, nclust = 3, depth = 2, quant.err = 0.2,
#'                   projection.scale = 10, normalize = TRUE)
#'
#' predictions <- predictHVT(test,hvt.results,hmap.cols = NULL, child.level=2)
#' print(predictions$predictions)
#' @export predictHVT
predictHVT <- function(data,hvt.results,hmap.cols= NULL,child.level=1,quant.err_hmap = NULL,
                       nclust_hmap = NULL, line.width = NULL,
                       color.vec = NULL,...){

  requireNamespace("dplyr")
  requireNamespace("purrr")

  options(warn = -1)

  summary_list <- hvt.results[[3]]
  # nclust <- nrow(summary_list[["compression_summary"]])
  # nclust <- length(summary_list[['plt.clust']][[child.level]])
  nclust <- nclust_hmap
  train_colnames <- names(summary_list$scale_summary$mean_data)

  if(!all(train_colnames %in% colnames(data))){
    if(any(train_colnames %in% colnames(data))){
      train_colnames <- train_colnames[train_colnames %in% colnames(data)]
    }
    else{
      stop('test columns not part of train dataset')
    }
  }

  if(!is.null(summary_list$scale_summary)){
    scaled_test_data <- scale(data[,train_colnames],center = summary_list$scale_summary$mean_data[train_colnames],scale = summary_list$scale_summary$std_data[train_colnames])
  }

  colnames(scaled_test_data) <- train_colnames

  level <- length(summary_list$nodes.clust)

  # hierachy_structure <- c(1:level) %>% purrr::map(~data.frame(gtools::permutations(n = nclust,r = .x,v = seq(1:nclust),repeats.allowed = T))) %>% purrr::map(~apply(.,1,function(x) paste(x,collapse=''))) %>% unlist()
  #
  # pathString <- hierachy_structure %>% purrr::map_chr(~paste(c('cluster',unlist(strsplit(.,''))),collapse=' -> '))


  # hierarchy_structure <- function(nclust,init,depth,temp_list,final_list,sep = "->"){
  # 
  #   empty_list = c()
  # 
  #   if(init>depth){
  #     return(final_list)
  #   }
  # 
  #   if(length(final_list)==0){
  #     empty_list <- seq(1:nclust)
  #     final_list <- empty_list
  #   }
  #   else{
  #     for(i in temp_list){
  #       for(j in 1:nclust){
  #         final_list <- c(final_list,paste(i,j,sep = sep))
  #         empty_list <- c(empty_list,paste(i,j,sep = sep))
  #       }
  #     }
  #   }
  #   hierarchy_structure(nclust= nclust, init+1,depth= depth,temp_list = empty_list,final_list = final_list ,sep = sep)
  # 
  # }
  # 
  # pathString <- hierarchy_structure(nclust = nclust,init = 1,depth = level,temp_list = list(),final_list  = list(),sep = "->")
  lpc<-summary_list$summary
  pathString<-paste(lpc$Segment.Level,lpc$Segment.Parent,lpc$Segment.Child,sep="->")
  rm(lpc)
  summary_table_with_hierarchy <- cbind(summary_list$summary,pathString,index=as.numeric(rownames(summary_list$summary)),stringsAsFactors = FALSE)
  
  dfWithMapping <- summary_table_with_hierarchy 

  #tree_summary <- data.tree::as.Node(summary_table_with_hierarchy)
  path_list <- list()

  find_path <- function(summary,data,nclust,final_level,init_level,init_row,path_list){

    if(init_level > final_level){
      return(path_list)
    }
    else{
      intermediate_df <- summary %>% dplyr::filter(Segment.Level==init_level & index>=init_row & index<=init_row+nclust-1)
      min_dist <- apply(intermediate_df[,train_colnames,drop=F],1,FUN = function(x,y) stats::dist(rbind(x,y)),data)
      if(all(is.na(min_dist))){
        return(path_list)
      }
      index_min_row <- as.numeric(intermediate_df[which.min(min_dist),"index"])
      path_list <- summary[index_min_row,"pathString"]
      # next_row_no <- index_min_row*nclust + 1
      next_row_no <- nclust+(index_min_row-1)*nclust+1
      find_path(summary,data,nclust,final_level,init_level +1,init_row = next_row_no,path_list)
    }
  }

  path_list <- apply(scaled_test_data, 1,FUN = function(data) find_path(summary_table_with_hierarchy,data = data,nclust = nclust ,final_level = level,init_level = 1,init_row = 1,path_list = path_list))

  path_df <- data.frame(path_list)

  output_path_with_data <- cbind(data[,train_colnames],path_df)
  lpc<-dplyr::select(dfWithMapping,pathString,Segment.Level,Segment.Parent,Segment.Child)
  lpc<-left_join(output_path_with_data,lpc,by = c("path_list" = "pathString"))
  output_path_with_data<-lpc
  colnames(output_path_with_data) <- c(train_colnames,"Cell_path","Segment.Level","Segment.Parent","Segment.Child")
  # Calculating overall means
  
  # original scaled data multiplied by n clusters
  umean_train_scaled<-summary_table_with_hierarchy
  umean_train_scaled[,c("Quant.Error","pathString","index")]<- list(NULL)
  umean_train_scaled[,train_colnames]<-umean_train_scaled[,train_colnames] * umean_train_scaled$n
  umean_train_scaled<-umean_train_scaled[complete.cases(umean_train_scaled),]
  # Grouping test scaled data
  n<-rep(1,length(scaled_test_data[,1]))
  scaled_test_data_lpc<-cbind(output_path_with_data$Segment.Level,output_path_with_data$Segment.Parent,output_path_with_data$Segment.Child,n,scaled_test_data)
  colnames(scaled_test_data_lpc)<-colnames(umean_train_scaled)
  updated_table<-rbind(umean_train_scaled,scaled_test_data_lpc)
  # rm(umean_train_scaled,n,scaled_test_data_lpc)
  updated_table<-updated_table[stats::complete.cases(updated_table),]
  updated_table<-updated_table %>% group_by(Segment.Level,Segment.Parent,Segment.Child) %>% summarise_all(funs(sum))
  updated_table[,train_colnames]<-updated_table[,train_colnames] / updated_table$n
  summary_table_with_hierarchy<-summary_table_with_hierarchy[stats::complete.cases(summary_table_with_hierarchy),]
  # updated_table[,"Quant.Error"]<-summary_table_with_hierarchy[,"Quant.Error"]
  lpc<-updated_table[,1:4]
  lpc[,"Quant.Error"]<-summary_table_with_hierarchy[,"Quant.Error"]
  lpc[,train_colnames]<-updated_table[,train_colnames]
  updated_table<-lpc
  #####################################################################################
  
  ### Heatmap
  if (!is.null(hmap.cols)) {
    if (class(hmap.cols) == "character") {
      column_no_for_hmap = which(colnames(data) == hmap.cols)
      if (length(hmap.cols) == 0) {
        stop("Column name for plotting heatmap incorrect")
      }
    }
    else if (class(hmap.cols) == "numeric") {
      column_no_for_hmap = hmap.cols

      if (length(column_no_for_hmap) == 0 ||
          column_no_for_hmap > length(colnames(data))) {
        stop("Column number for plotting heatmap incorrect")
      }

    }
  }
  else{
    return(list(predictions = output_path_with_data, predictPlot = NULL))
  }

  # df_with_hmapcol_path <- data[,column_no_for_hmap,drop=F]
  # df_with_hmapcol_path["path_list"]  <-  path_df["path_list"]
  # hmap_colname <- colnames(df_with_hmapcol_path)[1]
  # 
  # test_hmap_colname <- paste0(hmap_colname,"_test")
  # 
  # colnames(df_with_hmapcol_path)[1] <- test_hmap_colname
  # 
  # mean_of_hmap_per_cluster <- df_with_hmapcol_path %>% dplyr::group_by(path_list) %>% dplyr::summarise_at(test_hmap_colname,dplyr::funs(mean))
  # 
  # summary_table_with_hierarchy <- dplyr::left_join(summary_table_with_hierarchy,mean_of_hmap_per_cluster,by=c("pathString"="path_list"))
  updated_table<-as.data.frame(updated_table)
  # plot modification
  plot_updated_table<-updated_table
  plot_updated_table[,"n"]<-umean_train_scaled[,"n"]
  hvt.results[[3]][['summary']] <- plot_updated_table

  # line_color_func <- function(child.level) {
  #   switch (
  #     child.level,
  #     list(
  #       line.width = c(0.8),
  #       color.vec = c('#326273')
  #     ),
  #     list(
  #       line.width = c(0.8, 0.5),
  #       color.vec = c('#326273', '#ADB2D3')
  #     ),
  #     list(
  #       line.width = c(0.8, 0.5, 0.3),
  #       color.vec = c("#326273", "#ADB2D3", "#BFA89E")
  #     ),
  #     list(
  #       line.width = c(0.8, 0.5, 0.3, 0.1),
  #       color.vec = c("#326273", "#ADB2D3", "#BFA89E", "#CFC7D2")
  #     ),
  #   )
  # }
  # 
  # if(length(list(...))){
  #   input_col_line <- list(...)
  #   color.vec <- input_col_line$color.vec
  #   line.width <-  input_col_line$line.width
  # }
  # else{
  #   input_col_line <- line_color_func(child.level)
  #   if(is.null(input_col_line)){
  #     stop('Please pass color.vec and line.width to the predict function')
  #   }
  #    color.vec <- input_col_line$color.vec
  #    line.width <-  input_col_line$line.width
  # }
  
  
# suppressMessages(
plot_gg_test <- hvtHmap(hvt.results,data,hmap.cols = hmap.cols,child.level = child.level,line.width = line.width,color.vec = color.vec,palette.color = 6,test=T,quant.err_hmap = quant.err_hmap,
                        nclust_hmap = nclust_hmap)+ ggtitle(
  paste(
    "Hierarchical Voronoi Tessellation with",
    hmap.cols,
    "heatmap overlay"
  )
) +
  theme(plot.title = element_text(
    size = 20,
    hjust = 0.5,
    margin = margin(0, 0, 20, 0)
  ),
  panel.grid.major = element_blank(),
  panel.grid.minor = element_blank(),
  panel.background = element_blank(),
  axis.text.x=element_blank(),
  axis.ticks.x=element_blank(),
  axis.title.x=element_blank(),
  axis.text.y=element_blank(),
  axis.ticks.y=element_blank(),
  axis.title.y=element_blank()
  )+
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0))
# )
  # dfWithMapping<-dfWithMapping[complete.cases(dfWithMapping),]
  updated_table[,"Quant.Error"]<-NULL
  return(list(predictions = output_path_with_data,predictionQESummary = updated_table, predictPlot = plot_gg_test))



}
