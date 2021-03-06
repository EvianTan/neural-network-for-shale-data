#Load necessary libraries:
library(nnet)
library(NeuralNetTools)
library(ggplot2)

#read csv
data <- read.csv('Data-Shale Analytics Project.csv')

#Check if "NA" in data and delete:
apply(data,2,function(x) sum(is.na(x)))
data1 <- na.omit(data)

#Import the Reservoir parameters and Production parameters from data1 as data_Reservoir and set input/ouput:
cols_Reservoir <- c(11:15, 29:36)
data_Reservoir <- data1[,cols_Reservoir]
input_Reservoir <- data_Reservoir[ ,1:5]
output_Reservoir <- data_Reservoir[, 6:13]

#Set random seed 
#Choose mlp() funtion to fit the data, the size of hidden layer is about 2/3 of the input, so here size is seleted as 3:
set.seed(125)
model_Reservoir <- mlp(input_Reservoir, output_Reservoir, size=3)

#Generate the plot of neural network model for data:
library(devtools)
source_url('https://gist.githubusercontent.com/fawda123/7471137/raw/466c1474d0a505ff044412703516c34f1a4684a5/nnet_plot_update.r')
plot.nnet(model1)

#Use the gar.fun function to generate the variable-importance plot of data:
gar.fun<-function(out.var,mod.in,bar.plot=T,struct=NULL,x.lab=NULL,
                  y.lab=NULL, wts.only = F){
  
  require(ggplot2)
  
  # function works with neural networks from neuralnet, nnet, and RSNNS package
  # manual input vector of weights also okay
  
  #sanity checks
  if('numeric' %in% class(mod.in)){
    if(is.null(struct)) stop('Three-element vector required for struct')
    if(length(mod.in) != ((struct[1]*struct[2]+struct[2]*struct[3])+(struct[3]+struct[2])))
      stop('Incorrect length of weight matrix for given network structure')
    if(substr(out.var,1,1) != 'Y' | 
       class(as.numeric(gsub('^[A-Z]','', out.var))) != 'numeric')
      stop('out.var must be of form "Y1", "Y2", etc.')
  }
  if('train' %in% class(mod.in)){
    if('nnet' %in% class(mod.in$finalModel)){
      mod.in<-mod.in$finalModel
      warning('Using best nnet model from train output')
    }
    else stop('Only nnet method can be used with train object')
  }
  
  #gets weights for neural network, output is list
  #if rescaled argument is true, weights are returned but rescaled based on abs value
  nnet.vals<-function(mod.in,nid,rel.rsc,struct.out=struct){
    
    require(scales)
    require(reshape)
    
    if('numeric' %in% class(mod.in)){
      struct.out<-struct
      wts<-mod.in
    }
    
    #neuralnet package
    if('nn' %in% class(mod.in)){
      struct.out<-unlist(lapply(mod.in$weights[[1]],ncol))
      struct.out<-struct.out[-length(struct.out)]
      struct.out<-c(
        length(mod.in$model.list$variables),
        struct.out,
        length(mod.in$model.list$response)
      )      	
      wts<-unlist(mod.in$weights[[1]])   
    }
    
    #nnet package
    if('nnet' %in% class(mod.in)){
      struct.out<-mod.in$n
      wts<-mod.in$wts
    }
    
    #RSNNS package
    if('mlp' %in% class(mod.in)){
      struct.out<-c(mod.in$nInputs,mod.in$archParams$size,mod.in$nOutputs)
      hid.num<-length(struct.out)-2
      wts<-mod.in$snnsObject$getCompleteWeightMatrix()
      
      #get all input-hidden and hidden-hidden wts
      inps<-wts[grep('Input',row.names(wts)),grep('Hidden_2',colnames(wts)),drop=F]
      inps<-melt(rbind(rep(NA,ncol(inps)),inps))$value
      uni.hids<-paste0('Hidden_',1+seq(1,hid.num))
      for(i in 1:length(uni.hids)){
        if(is.na(uni.hids[i+1])) break
        tmp<-wts[grep(uni.hids[i],rownames(wts)),grep(uni.hids[i+1],colnames(wts)),drop=F]
        inps<-c(inps,melt(rbind(rep(NA,ncol(tmp)),tmp))$value)
      }
      
      #get connections from last hidden to output layers
      outs<-wts[grep(paste0('Hidden_',hid.num+1),row.names(wts)),grep('Output',colnames(wts)),drop=F]
      outs<-rbind(rep(NA,ncol(outs)),outs)
      
      #weight vector for all
      wts<-c(inps,melt(outs)$value)
      assign('bias',F,envir=environment(nnet.vals))
    }
    
    if(nid) wts<-rescale(abs(wts),c(1,rel.rsc))
    
    #convert wts to list with appropriate names 
    hid.struct<-struct.out[-c(length(struct.out))]
    row.nms<-NULL
    for(i in 1:length(hid.struct)){
      if(is.na(hid.struct[i+1])) break
      row.nms<-c(row.nms,rep(paste('hidden',i,seq(1:hid.struct[i+1])),each=1+hid.struct[i]))
    }
    row.nms<-c(
      row.nms,
      rep(paste('out',seq(1:struct.out[length(struct.out)])),each=1+struct.out[length(struct.out)-1])
    )
    out.ls<-data.frame(wts,row.nms)
    out.ls$row.nms<-factor(row.nms,levels=unique(row.nms),labels=unique(row.nms))
    out.ls<-split(out.ls$wts,f=out.ls$row.nms)
    
    assign('struct',struct.out,envir=environment(nnet.vals))
    
    out.ls
    
  }
  
  # get model weights
  best.wts<-nnet.vals(mod.in,nid=F,rel.rsc=5,struct.out=NULL)
  
  # weights only if T
  if(wts.only) return(best.wts)
  
  # get column index value for response variable to measure
  if('numeric' %in% class(mod.in)){
    out.ind <-  as.numeric(gsub('^[A-Z]','',out.var))
  } else {
    out.ind<-which(out.var==colnames(eval(mod.in$call$y)))
  }
  
  #get variable names from mod.in object
  #change to user input if supplied
  if('numeric' %in% class(mod.in)){
    x.names<-paste0(rep('X',struct[1]),seq(1:struct[1]))
    y.names<-paste0(rep('Y',struct[3]),seq(1:struct[3]))
  }
  if('mlp' %in% class(mod.in)){
    all.names<-mod.in$snnsObject$getUnitDefinitions()
    x.names<-all.names[grep('Input',all.names$unitName),'unitName']
    y.names<-all.names[grep('Output',all.names$unitName),'unitName']
  }
  if('nn' %in% class(mod.in)){
    x.names<-mod.in$model.list$variables
    y.names<-mod.in$model.list$response
  }
  if('xNames' %in% names(mod.in)){
    x.names<-mod.in$xNames
    y.names<-attr(terms(mod.in),'factor')
    y.names<-row.names(y.names)[!row.names(y.names) %in% x.names]
  }
  if(!'xNames' %in% names(mod.in) & 'nnet' %in% class(mod.in)){
    if(is.null(mod.in$call$formula)){
      x.names<-colnames(eval(mod.in$call$x))
      y.names<-colnames(eval(mod.in$call$y))
    }
    else{
      forms<-eval(mod.in$call$formula)
      x.names<-mod.in$coefnames
      facts<-attr(terms(mod.in),'factors')
      y.check<-mod.in$fitted
      if(ncol(y.check)>1) y.names<-colnames(y.check)
      else y.names<-as.character(forms)[2]
    } 
  }
  #change variables names to user sub 
  if(!is.null(x.lab)){
    if(length(x.names) != length(x.lab)) stop('x.lab length not equal to number of input variables')
    else x.names<-x.lab
  }
  if(!is.null(y.lab)){
    if(length(y.names) != length(y.lab)) stop('y.lab length not equal to number of output variables')
    else y.names<-y.lab
  }
  
  #get input-hidden weights and hidden-output weights, remove bias
  inp.hid<-data.frame(
    do.call('cbind',best.wts[grep('hidden',names(best.wts))])[-1,],
    row.names=x.names#c(colnames(eval(mod.in$call$x)))
  )
  hid.out<-best.wts[[grep(paste('out',out.ind),names(best.wts))]][-1]
  
  #multiply hidden-output connection for each input-hidden weight
  mult.dat<-data.frame(
    sapply(1:ncol(inp.hid),function(x) inp.hid[,x]*hid.out[x]),
    row.names=rownames(inp.hid)
  )    
  names(mult.dat)<-colnames(inp.hid)
  
  #get relative contribution of each input variable to each hidden node, sum values for each input
  #inp.cont<-rowSums(apply(mult.dat,2,function(x) abs(x)/sum(abs(x))))
  inp.cont<-rowSums(mult.dat)
  
  #get relative contribution
  #inp.cont/sum(inp.cont)
  
  rel.imp<-{
    signs<-sign(inp.cont)
    signs*rescale(abs(inp.cont),c(0,1))
  }
  
  if(!bar.plot){
    return(list(
      mult.wts=mult.dat,
      inp.cont=inp.cont,
      rel.imp=rel.imp
    ))
  }
  
  to_plo <- data.frame(rel.imp,x.names)[order(rel.imp),,drop = F]
  to_plo$x.names <- factor(x.names[order(rel.imp)], levels = x.names[order(rel.imp)])
  out_plo <- ggplot(to_plo, aes(x = x.names, y = rel.imp, fill = rel.imp,
                                colour = rel.imp)) + 
    geom_bar(stat = 'identity') + 
    scale_x_discrete(element_blank()) +
    scale_y_continuous(y.names)
  
  return(out_plo)
  
}

#Output the variable-importance plot for Reservonior parameters:
vals.only <- unlist(gar.fun('y', model_Reservoir, wts.only = T))
p_Reservoir <- gar.fun('Y1',vals.only, struct = c(5,3,8)) + theme_bw() + theme(legend.position = 'none')
p_Reservoir



#Predict productions by given data
#Example data (Porosity%=9, Gross Thickness(ft)=150, NTG=0.9, Sw(%)=10, TOC %=3)
set.seed(125)
data_Reservoir <- data.frame(input_Reservoir, output_Reservoir)
mod_Reservoir <- nnet(input_Reservoir,output_Reservoir,data=data_Reservoir,size=2,linout=T)
predict(mod_Reservoir, c(9,150,0.9,10,3))


#Plot of sensitivity analysis for neural network:
set.seed(125)
data_sens <- data.frame(input, output)
mod_sens <- nnet(input,output,data=data_sens,size=2,linout=T)
#overall plot
lekprofile(mod_sens, group_vals = 5)
#plot for specific variable
lekprofile(mod_sens, group_vals = 5, ysel = "X180.Day..Cum.Gas..MCF.")

#Scale the original data and do sensitivity analysis again
#Get more readable result
input_s <- scale(input)
output_s <- scale(output)
input_s <- as.data.frame(input_s)
output_s <- as.data.frame(output_s)
data__s <- data.frame(input_s, output_s)
mod_s <- nnet(input_s,output_s,data=data_s,size=2,linout=T, maxit=10000)
lekprofile(mod_s, group_vals = 5)
