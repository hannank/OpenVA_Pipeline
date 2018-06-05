library(shiny)
library(shinyjs)
library(openVA)
library(CrossVA)

options(shiny.maxRequestSize=30*1024^2)

indivCOD <- function(x, top=3){

    probs <- getIndivProb(x)
    cods  <- colnames(probs)

    out <- matrix(NA, nrow=nrow(probs), ncol=top*2)

    for(i in 1:nrow(probs)){
        probsOrdered <- order(probs[i,], decreasing=TRUE)
        newTop <- top
        if(length(unique(probsOrdered)) <= top) newTop = (top-1)
        if(newTop < 1){
            cat("Error: not enough unique causes \n")
            next
        }
        for(j in 1:newTop){
            k <- seq(1, top*2, by=2)[j]
            out[i,k  ] <- cods[probsOrdered[j]]
            out[i,k+1] <- round(probs[i, probsOrdered[j]],4)
        }
    }
    out <- cbind(rownames(probs), out)
    colnames(out) <- c("ID", "Most Likely Cause", "Probability",
                       "Second Most Likely Cause", "Probability",
                       "Third Most Likely Cause", "Probability")
    out
}

CSMF2 <- function(x, top){

    csmf  <- CSMF(x, InterVA.rule=TRUE, noplot=TRUE, min.prob=.00001)
    csmf2 <- sort(csmf, decreasing=TRUE)[1:top]
    isUndet <- "Undetermined"%in%names(csmf2)
    if(isUndet){
        idUndet <- which(names(csmf2)=="Undetermined")
        newBars <- c(csmf2[-idUndet], csmf2[idUndet])
        par(las = 2)
        par(mar = c(5, 15, 4, 2))
        barplot(newBars[top:1], horiz=TRUE, names.arg=names(newBars)[top:1],
                cex.names = 0.8, xlab = "Probability",
                col = rev(grey.colors(length(newBars))))
    } else{
        CSMF(x, InterVA.rule=TRUE, min.prob=.00001)
    }
}

ui <- fluidPage(

    titlePanel("Probabilistic Cause-of-death Assignment using Verbal Autopsies"),
    p("Developed by Tyler McCormick ", (a(href="mailto:tylermc@uw.edu", "(tylermc@uw.edu)")),
      "Zehang Richard Li ", (a(href="mailto:lizehang@uw.edu", "(lizehang@uw.edu)")),
      "and Samuel Clark ", a(href="mailto:work@samclark.net ", "(work@samclark.net)")),
    p("The complete study can be viewed ", a(href="http://arxiv.org/abs/1411.3042", "here")),
    hr(),
    shinyjs::useShinyjs(),

    ## Inputs
    ## tags$head(tags$script(src = "message-handler.js")),

    sidebarLayout(
        sidebarPanel(
            fileInput("readIn",
                      "Upload your own data here",
                      multiple = FALSE,
                      accept = NULL),
            ## fileInput("customProbbase",
            ##           "Upload a customized conditional probability table",
            ##           multiple = FALSE,
            ##           accept = NULL),
            ## checkboxInput("defaultCondProb", "or click here to use the default", FALSE),
            h3("Choose your preferences"),
            br(),
            checkboxInput("byAll", "Include an analysis of all records?", TRUE),
            checkboxInput("bySex", "Include sex-specific results?", FALSE),
            checkboxInput("byAge", "Include age-specific results (infant, child, adult)?", FALSE),
            sliderInput(inputId="topDeaths", label="Number of causes to include in summaries/plots", min=5, max=20, value=10),
            selectInput(inputId="algorithm", label="Select Algorithm:",
                        choices=c("InSilico"="InSilicoVA", "InterVA4"="InterVA"),
                        ## choices=c("InSilico"="InSilicoVA", "InterVA4"="InterVA",
                        ##           "Naive Bayes"="NBC", "Tariff"="Tariff"),
                        width="150px"),
            conditionalPanel(condition="input.algorithm=='InSilicoVA'",
                             sliderInput(inputId="simLength", label="Number of iterations in the simulation", min=300, max=7000, value=5000)),
            ## conditionalPanel(condition="input.algorithm=='InSilicoVA'",
            ##                  checkboxInput("autoLength", "Automatically increase iterations if needed?", FALSE)),
            conditionalPanel(condition="input.algorithm=='InterVA'",
                             selectInput(inputId="HIV", label="Level of HIV prevalence",
                                         choices=c("v (very low: < 0.01% of all deaths)" = "v",
                                                   "l (low:  ~ 0.1% of all deaths)" = "l",
                                                   "h (high: >= 1% of all deaths)" = "h"), width="300px")),
            ## conditionalPanel(condition="input.algorithm=='InSilicoVA' || input.algorithm=='InterVA'",
            conditionalPanel(condition="input.algorithm=='InterVA'",
                             selectInput(inputId="Malaria", label="Level of malaria prevalence",
                                         choices=c("v (very low: < 0.01% of all deaths)" = "v",
                                                   "l (low:  ~ 0.1% of all deaths)" = "l",
                                                   "h (high: >= 1% of all deaths)" = "h"), width="300px")),

            br(),
            h4("Data Checks"),
            checkboxInput("odkBC", "Are the data from an ODKBriefcase export?", TRUE),
            conditionalPanel(condition="input.algorithm=='InSilicoVA'"
                             ## checkboxInput("isNumeric", "Data already in numeric form?", FALSE)## ,
                             ## checkboxInput("useProbbase", "Use InterVA conditional probability without reestimating?", FALSE),
                             ## checkboxInput("keepProbbase", "Estimating Probbase levels only?", TRUE),
                             ## checkboxInput("datacheck", "Check data consistency?", TRUE),
                             ## checkboxInput("externalSep", "Separate out external clauses (suggested)?", TRUE),
                             ## numericInput("seed", "Select Seed Value", 1, min = "1")
                             ),
            ## h6("(Please note this connection is not encrypted.  Do not upload data that require a secure connection.)"),
            conditionalPanel("output.fileUploaded", actionButton("processMe", "Analyze my data!")),
            hr(),
            helpText("Downloads will be available once the data have been analyzed"),
            downloadButton("downloadAgeDist", "Download Plot of Age Distribution as .pdf"), br(), br(),
            downloadButton("downloadCOD1", "Download Causes for All Records as .csv"), br(),
            downloadButton("downloadData1", "Download Summary for All Records as .csv"), br(),
            downloadButton("downloadPlot1", "Download Plot for All Records as .pdf"), br(), br(),
            ##
            downloadButton("downloadCOD2", "Download Causes for all Males as .csv"), br(),
            downloadButton("downloadData2", "Download Summary for Males as .csv"),
            downloadButton("downloadPlot2", "Download Plot for Males as .pdf"), br(), br(),
            ##
            downloadButton("downloadCOD3", "Download Causes for all Females as .csv"), br(),
            downloadButton("downloadData3", "Download Summary for Females as .csv"),
            downloadButton("downloadPlot3", "Download Plot for Females as .pdf"), br(), br(),
            ##
            downloadButton("downloadCOD4", "Download  Causes for all Neonates as .csv"), br(),
            downloadButton("downloadData4", "Download Summary for Neonates as .csv"),
            downloadButton("downloadPlot4", "Download Plot for Neonates as .pdf"), br(), br(),
            ##
            downloadButton("downloadCOD5", "Download Causes for all Children as .csv"), br(),
            downloadButton("downloadData5", "Download Summary for Children as .csv"),
            downloadButton("downloadPlot5", "Download Plot for Children as .pdf"), br(), br(),
            ##
            downloadButton("downloadCOD6", "Download Causes for all Adults as .csv"), br(),
            downloadButton("downloadData6", "Download Summary for Adults as .csv"),
            downloadButton("downloadPlot6", "Download Plot for Adults as .pdf"), br(), br(),
            ##
            downloadButton("downloadWarnings", "Download warnings as .txt")
            ),

        ## Outputs
        mainPanel(
            ## verbatimTextOutput("mainWarnings"),
            ## verbatimTextOutput("titleDescriptiveStats"),
            h4(textOutput("titleDescriptiveStats")),
            tableOutput("descriptiveStats"),
            ## plotOutput("plotAgeDist"),
            h4(textOutput("titleSummaryAll")),
            verbatimTextOutput("summaryAll"),
            h4(textOutput("titlePlotAll")),
            plotOutput("plotAll"),
            h4(textOutput("titleSummaryMale")),
            h4(textOutput("emptySummaryMale")),
            verbatimTextOutput("summaryMale"),
            h4(textOutput("titlePlotMale")),
            h4(textOutput("emptyPlotMale")),
            plotOutput("plotMale"),
            h4(textOutput("titleSummaryFemale")),
            h4(textOutput("emptySummaryFemale")),
            verbatimTextOutput("summaryFemale"),
            h4(textOutput("titlePlotFemale")),
            h4(textOutput("emptyPlotFemale")),
            plotOutput("plotFemale"),
            h4(textOutput("titleSummaryNeonate")),
            h4(textOutput("emptySummaryNeonate")),
            verbatimTextOutput("summaryNeonate"),
            h4(textOutput("titlePlotNeonate")),
            h4(textOutput("emptyPlotNeonate")),
            plotOutput("plotNeonate"),
            h4(textOutput("titleSummaryChild")),
            h4(textOutput("emptySummaryChild")),
            verbatimTextOutput("summaryChild"),
            h4(textOutput("titlePlotChild")),
            h4(textOutput("emptyPlotChild")),
            plotOutput("plotChild"),
            h4(textOutput("titleSummaryAdult")),
            h4(textOutput("emptySummaryAdult")),
            verbatimTextOutput("summaryAdult"),
            h4(textOutput("titlePlotAdult")),
            h4(textOutput("emptyPlotAdult")),
            plotOutput("plotAdult")
        )
    )
)


server <- function(input, output, session){

    ## Read in data
    getData <- reactive({

        ## vaData <- isolate(input$readIn)
        vaData <- input$readIn

        if(is.null(vaData)){
            return(NULL)
        }
        read.csv(vaData$datapath)
    })
    output$fileUploaded <- reactive({
        return(!is.null(getData()))
    })
    outputOptions(output, "fileUploaded", suspendWhenHidden=FALSE)

    selectedAlgorithm <- reactive({
        switch(input$algorithm,
               "InSilicoVA"=1, "InterVA"=2)
    })
    ## choices=c("InSilico"="InSilicoVA", "InterVA4"="InterVA"),


    ## Run model
    rv <- reactiveValues()
    rv$male     <- TRUE
    rv$female   <- TRUE
    rv$neonate  <- TRUE
    rv$child    <- TRUE
    rv$adult    <- TRUE

    observeEvent(input$processMe, {

        rv$fitAll     <- NULL
        rv$fitMale    <- NULL
        rv$fitFemale  <- NULL
        rv$fitNeonate <- NULL
        rv$fitChild   <- NULL
        rv$fitAdult   <- NULL

        shinyjs::disable("processMe")
        shinyjs::disable("algorithm")
        shinyjs::disable("downloadAgeDist")
        shinyjs::disable("downloadCOD1")
        shinyjs::disable("downloadCOD2")
        shinyjs::disable("downloadCOD3")
        shinyjs::disable("downloadCOD4")
        shinyjs::disable("downloadCOD5")
        shinyjs::disable("downloadCOD6")
        shinyjs::disable("downloadData1")
        shinyjs::disable("downloadData2")
        shinyjs::disable("downloadData3")
        shinyjs::disable("downloadData4")
        shinyjs::disable("downloadData5")
        shinyjs::disable("downloadData6")
        shinyjs::disable("downloadPlot1")
        shinyjs::disable("downloadPlot2")
        shinyjs::disable("downloadPlot3")
        shinyjs::disable("downloadPlot4")
        shinyjs::disable("downloadPlot5")
        shinyjs::disable("downloadPlot6")
        shinyjs::disable("downloadWarnings")

        withProgress(value=0,{

           setProgress(message = paste("Starting analysis of data (this may take a while)"))

            if(input$algorithm=="InSilicoVA"){

                records <- map_records(getData(), mapping="insilicova")
                ## if( input$odkBC){
                ##     if("cores"%in%names(formals(map_records2))){
                ##         records <- map_records2(getData(), mapping="insilicova", cores=2)
                ##     }
                ##     if(!("cores"%in%names(formals(map_records2)))){
                ##         records <- map_records2(getData(), mapping="insilicova")
                ##     }
                ## }

                if(!input$odkBC) records <- getData()
                names(records) <- tolower(names(records))

                male <- rep(FALSE, length(records$male))
                male[records$male=="y"] <- TRUE
                female <- rep(FALSE, length(records$female))
                female[records$female=="y"] <- TRUE
                neonate <- rep(FALSE, length(records$neonate))
                neonate[records$neonate=="y"] <- TRUE
                child  <- rep(FALSE, length(records$infant))
                child[records$infant =="y"] <- TRUE
                child[records$under5 =="y"] <- TRUE
                child[records$child  =="y"] <- TRUE
                adult <- rep(FALSE, length(records$adult))
                adult[records$adult  =="y"] <- TRUE
                adult[records$midage =="y"] <- TRUE
                adult[records$elder  =="y"] <- TRUE

                ageGroup <- rep(NA, length(records$child))
                ageGroup[neonate] <- "neonate"
                ageGroup[child]  <- "child"
                ageGroup[adult]  <- "ages >11"

                counts <- c(length(male[male]), length(female[female]),
                            length(neonate[neonate]), length(child[child]),
                            length(adult[adult]),
                            length(records$id[records$neonate=="" & records$infant=="" & records$under5=="" &
                                              records$child=="" & records$adult=="" & records$midage=="" &
                                              records$elder==""]),
                            nrow(records))

                output$descriptiveStats <- renderTable({
                    if(!is.null(counts)){
                        matrix(counts, nrow=1, ncol=7,
                               dimnames = list(c("# of Deaths"),
                                               c("Male", "Female", "Neonate", "Child", "Ages >11",
                                                 "Age is Missing", "Total")))
                    }
                })

                ## output$plotAgeDist <- renderPlot({
                ##     if(!is.null(counts)){
                ##         barplot(table(ageGroup), horiz = TRUE, main="Age Distribution", xlab="Counts")
                ##     }
                ## })

                if(file.exists("plotAgeDist.pdf")) file.remove("plotAgeDist.pdf")
                pdf("plotAgeDist.pdf")
                barplot(table(ageGroup), horiz = TRUE, main="Age Distribution", xlab="Counts")
                dev.off()
                ## ggsave("plotAgeDist.pdf", device="pdf"); dev.off()
                output$downloadAgeDist <- downloadHandler(
                    filename = "plotAgeDist.pdf",
                    content = function(file) {
                        file.copy("plotAgeDist.pdf", file)
                    }
                )

                burn <- round(input$simLength / 2)
                if(file.exists("warning_insilico.txt")) file.remove("warning_insilico.txt")
                if(file.exists("InSilico-warnings.txt")) file.remove("InSilico-warnings.txt")
                file.create("InSilico-warnings.txt")
                cat("Warnings and Errors from InSilico \t", date(), "\n", file="InSilico-warnings.txt")

                if(input$byAll){
                    incProgress(.01, detail=paste("Analysis with all cases"))
                    ## rv$fitAll     <- insilico(records, Nsim = isolate(input$simLength), burnin = burn)
                    rv$fitAll <- do.call("codeVA", list(data=records, model="InSilicoVA",
                                                        Nsim=input$simLength, burnin=burn, warning.write=TRUE))
                    rv$indivCODAll <- indivCOD(rv$fitAll, top=3)

                    file.append("InSilico-warnings.txt", "warning_insilico.txt")
                    file.remove("warning_insilico.txt")
                    if(file.exists("plotAll.pdf")) file.remove("plotAll.pdf")
                    plot(rv$fitAll, top=input$topDeaths); ggsave("plotAll.pdf", device="pdf")
                    ## rv$agg.csmf <- get.indiv(rv$fitAll, data=records, CI = 0.95, is.aggregate=TRUE)
                    ## indivplot(rv$agg.csmf, top = 20, title = "Aggregated COD distribution")
                    ## ggsave("plotAll.pdf", device="pdf")
                    output$downloadPlot1 <- downloadHandler(
                        filename = "plotAll.pdf",
                        content = function(file) {
                            if(!is.null(rv$fitAll)){
                                file.copy("plotAll.pdf", file)
                            }
                        }
                    )
                    output$downloadCOD1 <- downloadHandler(
                        filename = "individual-causes-All.csv",
                        content = function(file) {
                            if(!is.null(rv$fitAll)){
                                write.csv(rv$indivCODAll, file=file, row.names=FALSE)
                            }
                        }
                    )
                    output$downloadData1 <- downloadHandler(
                        filename = "resultsAll.csv",
                        content = function(file) {
                            if(!is.null(rv$fitAll)){
                                ## summary(rv$fitAll, file=file)
                                write.csv(print(summary(rv$fitAll, top=input$topDeaths)), file=file)
                            }
                        }
                    )
                }

                if(input$bySex){
                    incProgress(.15, detail=paste("Analysis with Males"))
                    if(length(male[male])==0) rv$male <- NULL
                    if(length(male[male])>0){
                        ## rv$fitMale <- insilico(records[male,], Nsim = isolate(input$simLength), burnin = burn)
                        try(rv$fitMale <- do.call("codeVA", list(data=records[male,], model="InSilicoVA",
                                                                 Nsim=isolate(input$simLength), burnin=burn, warning.write=TRUE)))
                        if(!is.null(rv$fitMale)){

                            rv$indivCODMale <- indivCOD(rv$fitMale, top=3)

                            cat("\n", "Warnings and Errors from Analysis for Males", date(), "\n", file="InSilico-warnings.txt", append=TRUE)
                            file.append("InSilico-warnings.txt", "warning_insilico.txt")
                            file.remove("warning_insilico.txt")
                            if(file.exists("plotMale.pdf")) file.remove("plotMale.pdf")
                            plot(rv$fitMale, top=input$topDeaths); ggsave("plotMale.pdf", device="pdf")
                            ## rv$agg.csmfMale <- get.indiv(rv$fitMale, data=records[male,], CI = 0.95, is.aggregate=TRUE)
                            ## indivplot(rv$agg.csmfMale, top = 20, title = "Aggregated COD distribution")
                            ## ggsave("plotMale.pdf", device="pdf")
                            output$downloadPlot2 <- downloadHandler(
                                filename = "plotMale.pdf",
                                content = function(file) {
                                    if(!is.null(rv$fitMale)){
                                        file.copy("plotMale.pdf", file)
                                    }
                                }
                            )
                            output$downloadCOD2 <- downloadHandler(
                                filename = "individual-causes-Males.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitMale)){
                                        write.csv(rv$indivCODMale, file=file, row.names=FALSE)
                                    }
                                }
                            )
                            output$downloadData2 <- downloadHandler(
                                filename = "resultsMales.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitMale)){
                                        ## summary(rv$fitMale, file=file)
                                        write.csv(print(summary(rv$fitMale, top=input$topDeaths)), file=file)
                                    }
                                }
                            )
                        }
                    }
                    if(is.null(rv$fitMale)) rv$male <- NULL

                    incProgress(.15, detail=paste("Analysis with Females"))
                    if(length(female[female])==0) rv$female <- NULL
                    if(length(female[female])>0){
                        ## rv$fitFemale <- insilico(records[female,], Nsim = isolate(input$simLength), burnin = burn)
                        try(rv$fitFemale <- do.call("codeVA", list(data=records[female,], model="InSilicoVA",
                                                                   Nsim=isolate(input$simLength), burnin=burn, warning.write=TRUE)))
                        if(!is.null(rv$fitFemale)){

                            rv$indivCODFemale <- indivCOD(rv$fitFemale, top=3)

                            cat("\n", "Warnings and Errors from Analysis for Females", date(), "\n", file="InSilico-warnings.txt", append=TRUE)
                            file.append("InSilico-warnings.txt", "warning_insilico.txt")
                            file.remove("warning_insilico.txt")

                            if(file.exists("plotFemale.pdf")) file.remove("plotFemale.pdf")
                            plot(rv$fitFemale, top=input$topDeaths); ggsave("plotFemale.pdf", device="pdf")
                            ## rv$agg.csmfFemale <- get.indiv(rv$fitFemale, data=records[female,], CI = 0.95, is.aggregate=TRUE)
                            ## indivplot(rv$agg.csmfFemale, top = 20, title = "Aggregated COD distribution")
                            ## ggsave("plotFemale.pdf", device="pdf")
                            output$downloadPlot3 <- downloadHandler(
                                filename = "plotFemale.pdf",
                                content = function(file) {
                                    if(!is.null(rv$fitFemale)){
                                        file.copy("plotFemale.pdf", file)
                                    }
                                }
                            )
                            output$downloadCOD3 <- downloadHandler(
                                filename = "individual-causes-Females.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitFemale)){
                                        write.csv(rv$indivCODFemale, file=file, row.names=FALSE)
                                    }
                                }
                            )
                            output$downloadData3 <- downloadHandler(
                                filename = "resultsFemales.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitFemale)){
                                        ## summary(rv$fitFemale, file=file)
                                        write.csv(print(summary(rv$fitFemale, top=input$topDeaths)), file=file)
                                    }
                                }
                            )
                        }
                    }
                    if(is.null(rv$fitFemale)) rv$female <- NULL
                }
                if(input$byAge){
                    incProgress(.15, detail=paste("Analysis with Neonates"))
                    if(length(neonate[neonate])==0) rv$neonate <- NULL
                    if(length(neonate[neonate])>0){
                        ## rv$fitNeonate <- insilico(records[neonate,], Nsim = isolate(input$simLength), burnin = burn)
                        try(rv$fitNeonate <- do.call("codeVA", list(data=records[neonate,], model="InSilicoVA",
                                                                   Nsim=isolate(input$simLength), burnin=burn, warning.write=TRUE)))
                        if(!is.null(rv$fitNeonate)){

                            rv$indivCODNeonate <- indivCOD(rv$fitNeonate, top=3)

                            cat("\n", "Warnings and Errors from Analysis for Neonates", date(), "\n", file="InSilico-warnings.txt", append=TRUE)
                            file.append("InSilico-warnings.txt", "warning_insilico.txt")
                            file.remove("warning_insilico.txt")
                            if(file.exists("plotNeonate.pdf")) file.remove("plotNeonate.pdf")
                            plot(rv$fitNeonate, top=input$topDeaths); ggsave("plotNeonate.pdf", device="pdf")
                            ## rv$agg.csmfNeonate <- get.indiv(rv$fitNeonate, data=records[neonate,], CI = 0.95, is.aggregate=TRUE)
                            ## indivplot(rv$agg.csmfNeonate, top = 20, title = "Aggregated COD distribution")
                            ## ggsave("plotNeonate.pdf", device="pdf")
                            output$downloadPlot4 <- downloadHandler(
                                filename = "plotNeonate.pdf",
                                content = function(file) {
                                    if(!is.null(rv$fitNeonate)){
                                        file.copy("plotNeonate.pdf", file)
                                    }
                                }
                            )
                            output$downloadCOD4 <- downloadHandler(
                                filename = "individual-causes-Neonates.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitNeonate)){
                                        write.csv(rv$indivCODNeonate, file=file, row.names=FALSE)
                                    }
                                }
                            )
                            output$downloadData4 <- downloadHandler(
                                filename = "resultsNeonates.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitNeonate)){
                                        ## summary(rv$fitNeonate, file=file)
                                        write.csv(print(summary(rv$fitNeonate, top=input$topDeaths)), file=file)
                                    }
                                }
                            )
                        }
                    }
                    if(is.null(rv$fitNeonate)) rv$neonate <- NULL

                    incProgress(.15, detail=paste("Analysis with Children"))
                    if(length(child[child])==0) rv$child <- NULL
                    if(length(child[child])>0){
                        ## rv$fitChild <- insilico(records[child,], Nsim = isolate(input$simLength), burnin = burn)
                        try(rv$fitChild <- do.call("codeVA", list(data=records[child,], model="InSilicoVA",
                                                                  Nsim=isolate(input$simLength), burnin=burn, warning.write=TRUE)))
                        if(!is.null(rv$fitChild)){

                            rv$indivCODChild <- indivCOD(rv$fitChild, top=3)

                            cat("\n", "Warnings and Errors from Analysis for Children", date(), "\n", file="InSilico-warnings.txt", append=TRUE)
                            file.append("InSilico-warnings.txt", "warning_insilico.txt")
                            file.remove("warning_insilico.txt")
                            if(file.exists("plotChild.pdf")) file.remove("plotChild.pdf")
                            plot(rv$fitChild, top=input$topDeaths); ggsave("plotChild.pdf", device="pdf")
                            ## rv$agg.csmfChild <- get.indiv(rv$fitChild, data=records[child,], CI = 0.95, is.aggregate=TRUE)
                            ## indivplot(rv$agg.csmfChild, top = 20, title = "Aggregated COD distribution")
                            ## ggsave("plotChild.pdf", device="pdf")
                            output$downloadPlot5 <- downloadHandler(
                                filename = "plotChild.pdf",
                                content = function(file) {
                                    if(!is.null(rv$fitChild)){
                                        file.copy("plotChild.pdf", file)
                                    }
                                }
                            )
                            output$downloadCOD5 <- downloadHandler(
                                filename = "individual-causes-Children.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitChild) & !is.null(rv$child)){
                                        write.csv(rv$indivCODChild, file=file, row.names=FALSE)
                                    }
                                }
                            )
                            output$downloadData5 <- downloadHandler(
                                filename = "resultsChildren.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitChild)){
                                        ## summary(rv$fitChild, file=file)
                                        write.csv(print(summary(rv$fitChild, top=input$topDeaths)), file=file)
                                    }
                                }
                            )
                        }
                    }
                    if(is.null(rv$fitChild)) rv$child <- NULL

                    incProgress(.15, detail=paste("Analysis with Adults"))
                    if(length(adult[adult])==0) rv$adult <- NULL
                    if(length(adult[adult])>0){
                        ## rv$fitAdult <- insilico(records[adult,], Nsim = isolate(input$simLength), burnin = burn)
                        try(rv$fitAdult <- do.call("codeVA", list(data=records[adult,], model="InSilicoVA",
                                                                  Nsim=isolate(input$simLength), burnin=burn, warning.write=TRUE)))
                        if(!is.null(rv$fitAdult)){

                            rv$indivCODAdult <- indivCOD(rv$fitAdult, top=3)

                            cat("\n", "Warnings and Errors from Analysis for Adults", date(), "\n", file="InSilico-warnings.txt", append=TRUE)
                            file.append("InSilico-warnings.txt", "warning_insilico.txt")
                            file.remove("warning_insilico.txt")

                            if(file.exists("plotAdult.pdf")) file.remove("plotAdult.pdf")
                            plot(rv$fitAdult, top=input$topDeaths); ggsave("plotAdult.pdf", device="pdf")
                            ## rv$agg.csmfAdult <- get.indiv(rv$fitAdult, data=records[adult,], CI = 0.95, is.aggregate=TRUE)
                            ## indivplot(rv$agg.csmfAdult, top = 20, title = "Aggregated COD distribution")
                            ## ggsave("plotAdult.pdf", device="pdf")
                            output$downloadPlot6 <- downloadHandler(
                                filename = "plotAdult.pdf",
                                content = function(file) {
                                    if(!is.null(rv$fitAdult)){
                                        file.copy("plotAdult.pdf", file)
                                    }
                                }
                            )
                            output$downloadCOD6 <- downloadHandler(
                                filename = "individual-causes-Adults.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitAdult)){
                                        write.csv(rv$indivCODAdult, file=file, row.names=FALSE)
                                    }
                                }
                            )
                            output$downloadData6 <- downloadHandler(
                                filename = "resultsAdults.csv",
                                content = function(file) {
                                    if(!is.null(rv$fitAdult)){
                                        ## summary(rv$fitAdult, file=file)
                                        write.csv(print(summary(rv$fitAdult, top=input$topDeaths)), file=file)
                                    }
                                }
                            )
                        }
                    }
                    if(is.null(rv$fitAdult)) rv$adult <- NULL
                }
                ## shinyjs::enable("downloadWarnings")
                rv$counts <- c(length(male[male]), length(female[female]),
                               length(neonate[neonate]), length(child[child]),
                               length(adult[adult]),
                               length(records$id[records$neonate=="" & records$neonate=="" & records$under5=="" &
                                                 records$child=="" & records$adult=="" & records$midage=="" &
                                                 records$elder==""]),
                               nrow(records))
            }

            if(input$algorithm=="InterVA"){

                records <- map_records(getData(), mapping="interva4")
                ## if( input$odkBC){
                ##     if("cores"%in%names(formals(map_records2))){
                ##         records <- map_records2(getData(), mapping="interva4", cores=2)
                ##     }
                ##     if(!("cores"%in%names(formals(map_records2)))){
                ##         records <- map_records2(getData(), mapping="interva4")
                ##     }
                ## }
                if(!input$odkBC) records <- getData()

                male <- rep(FALSE, length(records$MALE))
                male[records$MALE=="y"] <- TRUE
                female <- rep(FALSE, length(records$FEMALE))
                female[records$FEMALE=="y"] <- TRUE
                neonate <- rep(FALSE, length(records$NEONATE))
                neonate[records$NEONATE=="y"] <- TRUE
                neonate[records$INFANT =="y"] <- TRUE
                child  <- rep(FALSE, length(records$UNDER5))
                child[records$UNDER5 =="y"] <- TRUE
                child[records$CHILD  =="y"] <- TRUE
                adult <- rep(FALSE, length(records$CHILD))
                adult[records$ADULT  =="y"] <- TRUE
                adult[records$MIDAGE =="y"] <- TRUE
                adult[records$ELDER  =="y"] <- TRUE

                ageGroup <- rep(NA, length(records$CHILD))
                ageGroup[neonate] <- "neonate"
                ageGroup[child]  <- "child"
                ageGroup[adult]  <- "ages >11"

                counts <- c(length(male[male]), length(female[female]),
                            length(neonate[neonate]), length(child[child]),
                            length(adult[adult]),
                            length(records$ID[records$NEONATE=="" & records$INFANT=="" & records$UNDER5=="" &
                                              records$CHILD=="" & records$ADULT=="" & records$MIDAGE=="" &
                                              records$ELDER==""]),
                            nrow(records))

                output$descriptiveStats <- renderTable({
                    if(!is.null(counts)){
                        matrix(counts, nrow=1, ncol=7,
                               dimnames = list(c("# of Deaths"),
                                               c("Male", "Female", "Neonate", "Child", "Ages >11",
                                                 "Age is Missing", "Total")))
                    }
                })

                ## output$plotAgeDist <- renderPlot({
                ##     barplot(table(ageGroup), horiz = TRUE, main="Age Distribution", xlab="Counts")
                ## })

                if(file.exists("plotAgeDist.pdf")) file.remove("plotAgeDist.pdf")
                pdf("plotAgeDist.pdf")
                barplot(table(ageGroup), horiz = TRUE, main="Age Distribution", xlab="Counts")
                dev.off()
                ## ggsave("plotAgeDist.pdf", device="pdf"); dev.off()
                output$downloadAgeDist <- downloadHandler(
                    filename = "plotAgeDist.pdf",
                    content = function(file) {
                        file.copy("plotAgeDist.pdf", file)
                    }
                )
                ## shinyjs::enable("downloadAgeDist")

                if(file.exists("InterVA-warnings.txt")) file.remove("InterVA-warnings.txt")
                file.create("InterVA-warnings.txt")
                cat("Warnings and Errors from InterVA \t", date(), "\n", file="InterVA-warnings.txt")

                if(input$byAll){
                    incProgress(.01, detail=paste("Analysis with all cases"))
                    rv$fitAll     <- InterVA(Input=records, HIV=input$HIV, Malaria=input$Malaria)
                    rv$resultsAll <- read.csv("VA_result.csv")

                    if(file.exists("plotAll.pdf")) file.remove("plotAll.pdf")
                    ## pdf("plotAll.pdf");CSMF(rv$fitAll, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001);dev.off()
                    pdf("plotAll.pdf");CSMF2(rv$fitAll, top=input$topDeaths);dev.off()
                    output$downloadPlot1 <- downloadHandler(
                        filename = "plotAll.pdf",
                        content = function(file) {
                            if(!is.null(rv$fitAll)){
                                file.copy("plotAll.pdf", file)
                            }
                        }
                    )
                    ## shinyjs::enable("downloadPlot1")

                    cat("\n", "Warnings from Analysis for All Records", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                    file.append("InterVA-warnings.txt", "warnings.txt")
                    cat("\n", "Errors from Analysis for All Records", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                    file.append("InterVA-warnings.txt", "errorlog.txt")
                    file.remove("warnings.txt"); file.remove("errorlog.txt")
                    file.remove("VA_result.csv")

                    output$downloadCOD1 <- downloadHandler(
                        filename = "individual-causes-All.csv",
                        content = function(file) {
                            if(!is.null(rv$fitAll)){
                                write.csv(rv$resultsAll, file=file, row.names=FALSE)
                            }
                        }
                    )
                    ## shinyjs::enable("downloadCOD1")

                    output$downloadData1 <- downloadHandler(
                        filename = "resultsAll.csv",
                        content = function(file) {
                            if(!is.null(rv$fitAll)){
                                write.csv(print(summary(rv$fitAll, top=input$topDeaths)), file=file, row.names=FALSE)
                            }
                        }
                    )
                    ## shinyjs::enable("downloadData1")
                }

                if(input$bySex){
                    incProgress(.15, detail=paste("Analysis with Males"))
                    if(length(male[male])==0) rv$male <- NULL
                    if(length(male[male])>0){
                        rv$fitMale     <- InterVA(Input=records[male,], HIV=input$HIV, Malaria=input$Malaria)
                        rv$resultsMale <- read.csv("VA_result.csv")

                        if(file.exists("plotMale.pdf")) file.remove("plotMale.pdf")
                        ## pdf("plotMale.pdf");CSMF(rv$fitMale, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001);dev.off()
                        pdf("plotMale.pdf");CSMF2(rv$fitMale, top=input$topDeaths);dev.off()
                        output$downloadPlot2 <- downloadHandler(
                            filename = "plotMale.pdf",
                            content = function(file) {
                                if(!is.null(rv$fitMale)){
                                    file.copy("plotMale.pdf", file)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadPlot2")

                        cat("\n", "Warnings from Analysis for Males", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "warnings.txt")
                        cat("\n", "Errors from Analysis for Males", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "errorlog.txt")
                        file.remove("warnings.txt"); file.remove("errorlog.txt")
                        file.remove("VA_result.csv")

                        output$downloadCOD2 <- downloadHandler(
                            filename = "individual-causes-Males.csv",
                            content = function(file) {
                                if(!is.null(rv$fitMale)){
                                    write.csv(rv$resultsMale, file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadCOD2")

                        output$downloadData2 <- downloadHandler(
                            filename = "resultsMales.csv",
                            content = function(file) {
                                if(!is.null(rv$fitMale)){
                                    write.csv(print(summary(rv$fitMale, top=input$topDeaths)), file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadData2")
                    }
                    if(is.null(rv$fitMale)) rv$male <- NULL

                    incProgress(.15, detail=paste("Analysis with Females"))
                    if(length(female[female])==0) rv$female <- NULL
                    if(length(female[female])>0){
                        ## rv$female <- TRUE
                        rv$fitFemale     <- InterVA(Input=records[female,], HIV=input$HIV, Malaria=input$Malaria)
                        rv$resultsFemale <- read.csv("VA_result.csv")

                        if(file.exists("plotFemale.pdf")) file.remove("plotFemale.pdf")
                        ## pdf("plotFemale.pdf");CSMF(rv$fitFemale, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001);dev.off()
                        pdf("plotFemale.pdf");CSMF2(rv$fitFemale, top=input$topDeaths);dev.off()
                        output$downloadPlot3 <- downloadHandler(
                            filename = "plotFemale.pdf",
                            content = function(file) {
                                if(!is.null(rv$fitFemale)){
                                    file.copy("plotFemale.pdf", file)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadPlot3")

                        cat("\n", "Warnings from Analysis for Females", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "warnings.txt")
                        cat("\n", "Errors from Analysis for Females", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "errorlog.txt")
                        file.remove("warnings.txt"); file.remove("errorlog.txt")
                        file.remove("VA_result.csv")

                        output$downloadCOD3 <- downloadHandler(
                            filename = "individual-causes-Females.csv",
                            content = function(file) {
                                if(!is.null(rv$fitFemale)){
                                    write.csv(rv$resultsFemale, file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadCOD3")

                        output$downloadData3 <- downloadHandler(
                            filename = "resultsFemales.csv",
                            content = function(file) {
                                if(!is.null(rv$fitFemale)){
                                    write.csv(print(summary(rv$fitFemale, top=input$topDeaths)), file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadData3")
                    }
                    if(is.null(rv$fitFemale)) rv$female <- NULL
                }

                if(input$byAge){
                    incProgress(.15, detail=paste("Analysis with Neonates"))
                    if(length(neonate[neonate])==0) rv$neonate <- NULL
                    if(length(neonate[neonate])>0){
                        ## rv$neonate <- TRUE
                        rv$fitNeonate     <- InterVA(Input=records[neonate,], HIV=input$HIV, Malaria=input$Malaria)
                        rv$resultsNeonate <- read.csv("VA_result.csv")

                        if(file.exists("plotNeonate.pdf")) file.remove("plotNeonate.pdf")
                        ## pdf("plotNeonate.pdf");CSMF(rv$fitNeonate, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001);dev.off()
                        pdf("plotNeonate.pdf");CSMF2(rv$fitNeonate, top=input$topDeaths);dev.off()
                        output$downloadPlot4 <- downloadHandler(
                            filename = "plotNeonate.pdf",
                            content = function(file) {
                                if(!is.null(rv$fitNeonate)){
                                    file.copy("plotNeonate.pdf", file)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadPlot4")

                        cat("\n", "Warnings from Analysis for Neonates", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "warnings.txt")
                        cat("\n", "Errors from Analysis for Neonates", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "errorlog.txt")
                        file.remove("warnings.txt"); file.remove("errorlog.txt")
                        file.remove("VA_result.csv")

                        output$downloadCOD4 <- downloadHandler(
                            filename = "individual-causes-Neonates.csv",
                            content = function(file) {
                                if(!is.null(rv$fitNeonate)){
                                    write.csv(rv$resultsNeonate, file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadCOD4")

                        output$downloadData4 <- downloadHandler(
                            filename = "resultsNeonates.csv",
                            content = function(file) {
                                if(!is.null(rv$fitNeonate)){
                                    write.csv(print(summary(rv$fitNeonate, top=input$topDeaths)), file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadData4")
                    }
                    if(is.null(rv$fitNeonate)) rv$neonate <- NULL

                    incProgress(.15, detail=paste("Analysis with Children"))
                    if(length(child[child])==0) rv$child <- NULL
                    if(length(child[child])>0){
                        ## rv$child <- TRUE
                        rv$fitChild     <- InterVA(Input=records[child,], HIV=input$HIV, Malaria=input$Malaria)
                        rv$resultsChild <- read.csv("VA_result.csv")

                        if(file.exists("plotChild.pdf")) file.remove("plotChild.pdf")
                        ## pdf("plotChild.pdf");CSMF(rv$fitChild, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001);dev.off()
                        pdf("plotChild.pdf");CSMF2(rv$fitChild, top=input$topDeaths);dev.off()
                        output$downloadPlot5 <- downloadHandler(
                            filename = "plotChild.pdf",
                            content = function(file) {
                                if(!is.null(rv$fitChild)){
                                    file.copy("plotChild.pdf", file)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadPlot5")

                        cat("\n", "Warnings from Analysis for Child", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "warnings.txt")
                        cat("\n", "Errors from Analysis for Child", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "errorlog.txt")
                        file.remove("warnings.txt"); file.remove("errorlog.txt")
                        file.remove("VA_result.csv")

                        output$downloadCOD5 <- downloadHandler(
                            filename = "individual-causes-Children.csv",
                            content = function(file) {
                                if(!is.null(rv$fitChild)){
                                    write.csv(rv$resultsChild, file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadCOD5")

                        output$downloadData5 <- downloadHandler(
                            filename = "resultsChildren.csv",
                            content = function(file) {
                                if(!is.null(rv$fitChild)){
                                    write.csv(print(summary(rv$fitChild, top=input$topDeaths)), file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadData5")
                    }
                    if(is.null(rv$fitChild)) rv$child <- NULL

                    incProgress(.15, detail=paste("Analysis with Adults"))
                    if(length(adult[adult])==0) rv$adult <- NULL
                    if(length(adult[adult])>0){
                        ## rv$adult <- TRUE
                        rv$fitAdult     <- InterVA(Input=records[adult,], HIV=input$HIV, Malaria=input$Malaria)
                        rv$resultsAdult <- read.csv("VA_result.csv")

                        if(file.exists("plotAdult.pdf")) file.remove("plotAdult.pdf")
                        ## pdf("plotAdult.pdf"); CSMF(rv$fitAdult, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001); dev.off()
                        pdf("plotAdult.pdf");CSMF2(rv$fitAdult, top=input$topDeaths);dev.off()
                        output$downloadPlot6 <- downloadHandler(
                            filename = "plotAdult.pdf",
                            content = function(file) {
                                if(!is.null(rv$fitAdult)){
                                    file.copy("plotAdult.pdf", file)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadPlot6")

                        cat("\n", "Warnings from Analysis for Adults", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "warnings.txt")
                        cat("\n", "Errors from Analysis for Adults", date(), "\n", file="InterVA-warnings.txt", append=TRUE)
                        file.append("InterVA-warnings.txt", "errorlog.txt")
                        file.remove("warnings.txt"); file.remove("errorlog.txt")
                        file.remove("VA_result.csv")

                        output$downloadCOD6 <- downloadHandler(
                            filename = "individual-causes-Adults.csv",
                            content = function(file) {
                                if(!is.null(rv$fitAdult)){
                                    write.csv(rv$resultsAdult, file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadCOD6")

                        output$downloadData6 <- downloadHandler(
                            filename = "resultsAdults.csv",
                            content = function(file) {
                                if(!is.null(rv$fitAdult)){
                                    write.csv(print(summary(rv$fitAdult, top=input$topDeaths)), file=file, row.names=FALSE)
                                }
                            }
                        )
                        ## shinyjs::enable("downloadData6")
                    }
                    if(is.null(rv$fitAdult)) rv$adult <- NULL
                }

                shinyjs::enable("downloadWarnings")
                rv$counts <- c(length(male[male]), length(female[female]),
                               length(neonate[neonate]), length(child[child]),
                               length(adult[adult]),
                               length(records$ID[records$NEONATE=="" & records$NEONATE=="" & records$UNDER5=="" &
                                                 records$CHILD=="" & records$ADULT=="" & records$MIDAGE=="" &
                                                 records$ELDER==""]),
                               nrow(records))
            }
        })
        shinyjs::enable("processMe")
        shinyjs::enable("algorithm")
        shinyjs::enable("downloadAgeDist")
        if(input$byAll){
            shinyjs::enable("downloadPlot1")
            shinyjs::enable("downloadCOD1")
            shinyjs::enable("downloadData1")
        }
        if(input$bySex & length(male[male])>0){
            shinyjs::enable("downloadPlot2")
            shinyjs::enable("downloadCOD2")
            shinyjs::enable("downloadData2")
        }
        if(input$bySex & length(female[female])>0){
            shinyjs::enable("downloadPlot3")
            shinyjs::enable("downloadCOD3")
            shinyjs::enable("downloadData3")
        }
        if(input$byAge & length(neonate[neonate])>0){
            shinyjs::enable("downloadPlot4")
            shinyjs::enable("downloadCOD4")
            shinyjs::enable("downloadData4")
        }
        if(input$byAge & length(child[child])>0){
            shinyjs::enable("downloadPlot5")
            shinyjs::enable("downloadCOD5")
            shinyjs::enable("downloadData5")
        }
        if(input$byAge & length(adult[adult])>0){
            shinyjs::enable("downloadPlot6")
            shinyjs::enable("downloadCOD6")
            shinyjs::enable("downloadData6")
        }
    })

    ## Print warning messages -- HERE

    ## Output table with descriptive statistics
    output$titleDescriptiveStats <- renderText({
        ## if(!is.null(rv$counts)){
            "Counts of Deaths by Sex & Age"
        ## }
    })

    ## output$descriptiveStats <- renderTable({
    ##     if(!is.null(rv$counts)){
    ##         ## matrix(rv$counts, nrow=1, ncol=11, dimnames = list(c("# of Deaths"),
    ##         ##                                                    c("Male", "Female", "Neonate", "Neonate",
    ##         ##                                                      "Age 1-4", "Age 5-14", "Age 14-49",
    ##         ##                                                      "Age 50-64", "Age 65+", "Age is Missing", "Total")))
    ##         matrix(rv$counts, nrow=1, ncol=7, dimnames = list(c("# of Deaths"),
    ##                                                            c("Male", "Female", "Neonate (0-1)", "Child (1-4)", "Ages 5+",
    ##                                                              "Age is Missing", "Total")))
    ##     }
    ## })

    output$downloadWarnings <- downloadHandler(
        filename = "warnings-openVA.txt",
        content = function(file) {
            if(input$algorithm=="InterVA"){
                file.copy("InterVA-warnings.txt", file)
            }
            if(input$algorithm=="InSilicoVA"){
                file.copy("InSilico-warnings.txt", file)
            }
        }
    )

    ## All
    #### Summarize and print output (all)
    output$titleSummaryAll <- renderText({
        ## if(!is.null(rv$fitAll)){
            "Summary of Results using All Records"
        ## }
    })
    output$summaryAll <- renderPrint({
        algorithm <- selectedAlgorithm()
        if(!is.null(rv$fitAll)){
            if(algorithm==1 & is.null(rv$fitAll$HIV)){
                ## printIndiv(rv$fitAll, rv$agg.csmf)
                print(summary(rv$fitAll, top=input$topDeaths))
            }
            if(algorithm==2 & !is.null(rv$fitAll$HIV)){
                print(summary(rv$fitAll, top=input$topDeaths))
            }
        }
    })
    #### Create plot (all)
    output$titlePlotAll <- renderText({
        ## if(!is.null(rv$fitAll)){
            "CSMF Plot for Total Population"
        ## }
    })
    output$plotAll <- renderPlot({
        if(!is.null(rv$fitAll)){
            if(input$algorithm=="InterVA" & !is.null(rv$fitAll$HIV)){
                ## CSMF(rv$fitAll, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001)
                CSMF2(rv$fitAll, top=input$topDeaths)
            }
            if(input$algorithm=="InSilicoVA" & is.null(rv$fitAll$HIV)){
                plot(rv$fitAll, top=input$topDeaths)
            }
        }
    })
    ## Male
    #### Summarize and print output (male)
    output$titleSummaryMale <- renderText({
        ## if(!is.null(rv$fitMale)){
            "Summary of Results for Males"
        ## }
    })
    output$emptySummaryMale <- renderText({
        if(is.null(rv$male)){
            "No Summary for Males (not enough deaths for analysis)"
        }
    })
    output$summaryMale <- renderPrint({
        algorithm <- selectedAlgorithm()
        if(!is.null(rv$fitMale)){
            if(algorithm==1 & is.null(rv$fitMale$HIV)){
                ## sumMale <- printIndiv(rv$fitMale, rv$agg.csmfMale)
                print(summary(rv$fitMale, top=input$topDeaths))
            }
            if(algorithm==2 & !is.null(rv$fitMale$HIV)){
                print(summary(rv$fitMale, top=input$topDeaths))
            }
        }
    })
    #### Create plot (male)
    output$titlePlotMale <- renderText({
        ## if(!is.null(rv$fitMale)){
            "CSMF Plot for Males"
        ## }
    })
    output$emptyPlotMale <- renderText({
        if(is.null(rv$male)){
            "No Plot for Males (not enough deaths for analysis)"
        }
    })
    output$plotMale <- renderPlot({
        if(!is.null(rv$fitMale)){
            if(input$algorithm=="InterVA" & !is.null(rv$fitMale$HIV)){
                ## CSMF(rv$fitMale, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001)
                CSMF2(rv$fitMale, top=input$topDeaths)
            }
            if(input$algorithm=="InSilicoVA" & is.null(rv$fitMale$HIV)){
                ## indivplot(rv$agg.csmfMale, top=20, title="Aggregated COD distribution")
                plot(rv$fitMale, top=input$topDeaths)
            }
        }
    })

    ## Female
    #### Summarize and print output (female)
    output$titleSummaryFemale <- renderText({
        ## if(!is.null(rv$fitFemale)){
            "Summary of Results for Females"
        ## }
    })
    output$emptySummaryFemale <- renderText({
        if(is.null(rv$female)){
            "No Summary for Females (not enough deaths for analysis)"
        }
    })
    output$summaryFemale <- renderPrint({
        algorithm <- selectedAlgorithm()
        if(!is.null(rv$fitFemale)){
            if(algorithm==1 & is.null(rv$fitFemale$HIV)){
                ## sumFemale <- printIndiv(rv$fitFemale, rv$agg.csmfFemale)
                print(summary(rv$fitFemale, top=input$topDeaths))
            }
            if(algorithm==2 & !is.null(rv$fitFemale$HIV)){
                print(summary(rv$fitFemale, top=input$topDeaths))
            }
        }
    })
    #### Create plot (female)
    output$titlePlotFemale <- renderText({
        ## if(!is.null(rv$fitFemale)){
            "CSMF Plot for Females"
        ## }
    })
    output$emptyPlotFemale <- renderText({
        if(is.null(rv$female)){
            "No Plot for Females (not enough deaths for analysis)"
        }
    })
    output$plotFemale <- renderPlot({
        if(!is.null(rv$fitFemale)){
            if(input$algorithm=="InterVA" & !is.null(rv$fitFemale$HIV)){
                ## CSMF(rv$fitFemale, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001)
                CSMF2(rv$fitFemale, top=input$topDeaths)
            }
            if(input$algorithm=="InSilicoVA" & is.null(rv$fitFemale$HIV)){
                ## indivplot(rv$agg.csmfFemale, top=20, title="Aggregated COD distribution")
                plot(rv$fitFemale, top=input$topDeaths)

            }
        }
    })

    ## Neonate
    #### Summarize and print output
    output$titleSummaryNeonate <- renderText({
        ## if(!is.null(rv$fitNeonate)){
            "Summary of Results for Neonates"
        ## }
    })
    output$emptySummaryNeonate <- renderText({
        if(is.null(rv$neonate)){
            "No Summary for Neonates (not enough deaths for analysis)"
        }
    })
    output$summaryNeonate <- renderPrint({
        algorithm <- selectedAlgorithm()
        if(!is.null(rv$fitNeonate)){
            if(algorithm==1 & is.null(rv$fitNeonate$HIV)){
                ## sumNeonate <- printIndiv(rv$fitNeonate, rv$agg.csmfNeonate)
                print(summary(rv$fitNeonate, top=input$topDeaths))
            }
            if(algorithm==2 & !is.null(rv$fitNeonate$HIV)){
                print(summary(rv$fitNeonate, top=input$topDeaths))
            }
        }
    })
    #### Create plot (neonates)
    output$titlePlotNeonate <- renderText({
        ## if(!is.null(rv$fitNeonate)){
            "CSMF Plot for Neonates"
        ## }
    })
    output$emptyPlotNeonate <- renderText({
        if(is.null(rv$neonate)){
            "No Plot for Neonates (not enough deaths for analysis)"
        }
    })
    output$plotNeonate <- renderPlot({
        if(!is.null(rv$fitNeonate)){
            if(input$algorithm=="InterVA" & !is.null(rv$fitNeonate$HIV)){
                ## CSMF(rv$fitNeonate, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001)
                CSMF2(rv$fitNeonate, top=input$topDeaths)
            }
            if(input$algorithm=="InSilicoVA" & is.null(rv$fitNeonate$HIV)){
                ## indivplot(rv$agg.csmfNeonate, top=20, title="Aggregated COD distribution")
                plot(rv$fitNeonate, top=input$topDeaths)
            }
        }
    })

    ## Child
    #### Summarize and print output
    output$titleSummaryChild <- renderText({
        ## if(!is.null(rv$fitChild)){
            "Summary of Results for Children"
        ## }
    })
    output$emptySummaryChild <- renderText({
        if(is.null(rv$child)){
            "No Summary for Children (not enough deaths for analysis)"
        }
    })
    output$summaryChild <- renderPrint({
        algorithm <- selectedAlgorithm()
        if(!is.null(rv$fitChild)){
            if(algorithm==1 & is.null(rv$fitChild$HIV)){
                ## sumChild <- printIndiv(rv$fitChild, rv$agg.csmfChild)
                print(summary(rv$fitChild, top=input$topDeaths))
            }
            if(algorithm==2 & !is.null(rv$fitChild$HIV)){
                print(summary(rv$fitChild, top=input$topDeaths))
            }
        }
    })
    #### Create plot (children)
    output$titlePlotChild <- renderText({
        ## if(!is.null(rv$fitChild)){
            "CSMF Plot for Children"
        ## }
    })
    output$emptyPlotChild <- renderText({
        if(is.null(rv$child)){
            "No Plot for Children (not enough deaths for analysis)"
        }
    })
    output$plotChild <- renderPlot({
        if(!is.null(rv$fitChild)){
            if(input$algorithm=="InterVA" & !is.null(rv$fitNeonate$HIV)){
                ## CSMF(rv$fitChild, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001)
                CSMF2(rv$fitChild, top=input$topDeaths)
            }
            if(input$algorithm=="InSilicoVA" & is.null(rv$fitNeonate$HIV)){
                ## indivplot(rv$agg.csmfChild, top=20, title="Aggregated COD distribution")
                plot(rv$fitChild, top=input$topDeaths)
            }
        }
    })

    ## Adult
    #### Summarize and print output
    output$titleSummaryAdult <- renderText({
        ## if(!is.null(rv$fitAdult)){
            "Summary of Results for Adults"
        ## }
    })
    output$emptySummaryAdult <- renderText({
        if(is.null(rv$adult)){
            "No Summary for Adults (not enough deaths for analysis)"
        }
    })
    output$summaryAdult <- renderPrint({
        algorithm <- selectedAlgorithm()
        if(!is.null(rv$fitAdult)){
            if(algorithm==1 & is.null(rv$fitAdult$HIV)){
                ## sumAdult <- printIndiv(rv$fitAdult, rv$agg.csmfAdult)
                print(summary(rv$fitAdult, top=input$topDeaths))
            }
            if(algorithm==2 & !is.null(rv$fitAdult$HIV)){
                print(summary(rv$fitAdult, top=input$topDeaths))
            }
        }
    })
    #### Create plot
    output$titlePlotAdult <- renderText({
        ## if(!is.null(rv$fitAdult)){
            "CSMF Plot for Adults"
        ## }
    })
    output$emptyPlotAdult <- renderText({
        if(is.null(rv$adult)){
            "No Plot for Adults (not enough deaths for analysis)"
        }
    })
    output$plotAdult <- renderPlot({
        if(!is.null(rv$fitAdult)){
            if(input$algorithm=="InterVA" & !is.null(rv$fitAdult$HIV)){
                ## CSMF(rv$fitAdult, top.plot=input$topDeaths, InterVA.rule=TRUE, min.prob=.001)
                CSMF2(rv$fitAdult, top=input$topDeaths)
            }
            if(input$algorithm=="InSilicoVA" & is.null(rv$fitAdult$HIV)){
                ## indivplot(rv$agg.csmfAdult, top=20, title="Aggregated COD distribution")
                plot(rv$fitAdult, top=input$topDeaths)
            }
        }
    })

    # disable download button on page load
    shinyjs::disable("downloadAgeDist")
    shinyjs::disable("downloadCOD1")
    shinyjs::disable("downloadCOD2")
    shinyjs::disable("downloadCOD3")
    shinyjs::disable("downloadCOD4")
    shinyjs::disable("downloadCOD5")
    shinyjs::disable("downloadCOD6")
    shinyjs::disable("downloadData1")
    shinyjs::disable("downloadData2")
    shinyjs::disable("downloadData3")
    shinyjs::disable("downloadData4")
    shinyjs::disable("downloadData5")
    shinyjs::disable("downloadData6")
    shinyjs::disable("downloadPlot1")
    shinyjs::disable("downloadPlot2")
    shinyjs::disable("downloadPlot3")
    shinyjs::disable("downloadPlot4")
    shinyjs::disable("downloadPlot5")
    shinyjs::disable("downloadPlot6")
    shinyjs::disable("downloadWarnings")
}

shinyApp(ui=ui, server=server)
## shinyApp(ui=ui, server=server, option=list(port=5567))
