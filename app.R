# ImmgenT Explorer — app.R (upload OR bundled demo + multiselect filters + dot size)

options(shiny.maxRequestSize = 4096*4096^2)  # ~1 GB upload limit

suppressPackageStartupMessages({
    library(shiny); library(Seurat); library(ggplot2); library(dplyr); library(DT)
    has_zlib <- requireNamespace("ZemmourLib", quietly = TRUE)
})

if (has_zlib) {
    mypal_level2 <- ZemmourLib::immgent_colors$level2
} else {
    mypal_level2 <- scales::hue_pal()(length(unique(rv$filt_obj$annotation_level2)))
}

# ---- UI ----
ui <- fluidPage(
    titlePanel("immgenT Explorer"),
    sidebarLayout(
        sidebarPanel(
            # NEW: choose data source
            radioButtons(
                "data_source", "Choose data source:",
                choices = c("Upload a file" = "upload", "Use bundled demo" = "demo"),
                selected = "upload", inline = TRUE
            ),
            # Show upload control when "upload"
            conditionalPanel(
                "input.data_source == 'upload'",
                fileInput("file", "Upload Seurat file", accept = c(".rds", ".RData"))
            ),
            # Show demo picker when "demo"
            conditionalPanel(
                "input.data_source == 'demo'",
                uiOutput("demo_ui")
            ),
            actionButton("load", "Load dataset once uploaded/selected", class = "btn-primary"),
            hr(),
            h4("Choose samples"),
            uiOutput("exp_ui"),
            uiOutput("igt_ui"),
            uiOutput("sample_ui"),
            helpText("Tip: leave IGT/sample empty to include all values."),
            hr(),
            h4("Gene expression"),
            selectizeInput("gene", "Gene", choices = NULL, multiple = FALSE),
            sliderInput("pt_size", "Dot size", min = 0.1, max = 5, value = 1, step = 0.1),
            actionButton("apply_all", "Render / Update plots", class = "btn-success"),
            hr(),
            downloadButton("dl_plot", "Download current plot (PDF)")
        ),
        mainPanel(
            tabsetPanel(id = "tabs",
                        tabPanel("FeaturePlot", plotOutput("featureplot", height = "700px")),
                        tabPanel("DimPlot", plotOutput("dimplot", height = "700px")),
                        tabPanel("Metadata", DTOutput("metatable"))
            )
        )
    )
)

# ---- Server ----
server <- function(input, output, session) {
    rv <- reactiveValues(
        obj = NULL,
        filt_obj = NULL,
        last_filter = list(exp = NULL, igt = character(0), sample = character(0)),
        current_gene = NULL
    )
    
    # --- discover bundled demo files once (data/*.rds or *.RData) ---
    demo_dir <- "data"
    demos <- tryCatch({
        f <- list.files(demo_dir, pattern = "\\.(rds|RDS|RData|Rds)$", full.names = TRUE)
        stats::setNames(f, basename(f))
    }, error = function(e) character(0))
    
    output$demo_ui <- renderUI({
        if (!length(demos)) {
            tagList(
                strong("No demo files found in 'data/'."),
                helpText("Add a .rds or .RData Seurat object to the app's data/ folder.")
            )
        } else {
            selectInput("demo_file", "Choose demo object:", choices = demos, selected = demos[1])
        }
    })
    
    observeEvent(input$load, {
        # validate source
        if (identical(input$data_source, "upload")) {
            req(input$file$datapath)
        } else if (identical(input$data_source, "demo")) {
            req(input$demo_file)
            if (!file.exists(input$demo_file)) {
                showNotification("Selected demo file not found on server.", type = "error")
                return(invisible(NULL))
            }
        }
        
        withProgress(message = "Loading data", value = 0, {
            incProgress(0.05, detail = "Reading Seurat object...")
            
            # Load either uploaded file or selected demo
            obj <- tryCatch({
                path <- if (identical(input$data_source, "upload")) input$file$datapath else input$demo_file
                if (grepl("\\.RData$", path, ignore.case = TRUE)) {
                    e <- new.env(parent = emptyenv())
                    load(path, envir = e)
                    get(ls(e)[1], envir = e)
                } else {
                    readRDS(path)
                }
            }, error = function(e) {
                showNotification(paste("Failed to read object:", e$message), type = "error")
                NULL
            })
            req(obj)
            
            incProgress(0.25, detail = "Checking normalized data...")
            assay <- DefaultAssay(obj)
            # only normalize if no "data" matrix present
            if (!"data" %in% slotNames(obj[[assay]])) {
                obj <- NormalizeData(obj, normalization.method = "LogNormalize", verbose = FALSE)
            }
            
            incProgress(0.25, detail = "Initializing UI...")
            rv$obj <- obj
            rv$filt_obj <- obj
            
            metas <- colnames(obj@meta.data)
            
            # ---- Cascading filter UIs (IGT/sample are MULTI-select) ----
            if ("exp_name" %in% metas) {
                output$exp_ui <- renderUI({
                    selectInput(
                        "exp", "exp_name",
                        choices = c("All", sort(unique(obj$exp_name))),
                        selected = if (!is.null(rv$last_filter$exp) &&
                                       rv$last_filter$exp %in% c("All", sort(unique(obj$exp_name))))
                            rv$last_filter$exp else "All"
                    )
                })
            } else output$exp_ui <- renderUI(NULL)
            
            if ("IGT" %in% metas) {
                output$igt_ui <- renderUI({
                    selectizeInput(
                        "igt", "IGT (multi)", choices = NULL, multiple = TRUE,
                        options = list(plugins = list("remove_button"), placeholder = "Pick one or more IGTs")
                    )
                })
            } else output$igt_ui <- renderUI(NULL)
            
            if ("sample_code" %in% metas) {
                output$sample_ui <- renderUI({
                    selectizeInput(
                        "sample", "sample_code (multi)", choices = NULL, multiple = TRUE,
                        options = list(plugins = list("remove_button"), placeholder = "Pick one or more samples")
                    )
                })
            } else output$sample_ui <- renderUI(NULL)
            
            # Initial gene choices
            updateSelectizeInput(session, "gene", choices = rownames(obj), server = TRUE)
            
            incProgress(0.2, detail = "Preparing filter choices...")
            
            # Update IGT choices when exp changes
            observeEvent(list(rv$obj, input$exp), {
                req(rv$obj)
                md <- rv$obj@meta.data
                igts <- if (is.null(input$exp) || input$exp == "All" || !"exp_name" %in% colnames(md)) {
                    sort(unique(md$IGT))
                } else {
                    sort(unique(md$IGT[md$exp_name == input$exp]))
                }
                sel <- intersect(isolate(input$igt), igts)
                updateSelectizeInput(session, "igt", choices = igts, selected = sel, server = TRUE)
            }, ignoreInit = FALSE)
            
            # Update sample choices when exp or IGT selection changes
            observeEvent(list(rv$obj, input$exp, input$igt), {
                req(rv$obj)
                md <- rv$obj@meta.data
                keep <- rep(TRUE, nrow(md))
                if (!is.null(input$exp) && input$exp != "All" && "exp_name" %in% colnames(md)) keep <- keep & (md$exp_name == input$exp)
                if (!is.null(input$igt) && length(input$igt) > 0 && "IGT" %in% colnames(md))   keep <- keep & (md$IGT %in% input$igt)
                sams <- sort(unique(md$sample_code[keep]))
                sel <- intersect(isolate(input$sample), sams)
                updateSelectizeInput(session, "sample", choices = sams, selected = sel, server = TRUE)
            }, ignoreInit = FALSE)
            
            incProgress(0.25, detail = "Done")
        })
    })
    
    # Apply filters and gene only when button is clicked
    observeEvent(input$apply_all, {
        req(rv$obj)
        withProgress(message = "Applying filters", value = 0, {
            md <- rv$obj@meta.data
            cells <- rownames(md)
            
            incProgress(0.25, detail = "Filtering by exp_name...")
            if (!is.null(input$exp) && input$exp != "All" && "exp_name" %in% colnames(md)) {
                keep_exp <- md$exp_name == input$exp
                keep_exp[is.na(keep_exp)] <- FALSE
                cells <- cells[keep_exp]
                rv$last_filter$exp <- input$exp
            }
            
            incProgress(0.25, detail = "Filtering by IGT...")
            if (!is.null(input$igt) && length(input$igt) > 0 && "IGT" %in% colnames(md)) {
                md_sub <- md[cells, , drop = FALSE]
                keep_igt <- md_sub$IGT %in% input$igt
                keep_igt[is.na(keep_igt)] <- FALSE
                cells <- rownames(md_sub)[keep_igt]
                rv$last_filter$igt <- input$igt
            }
            
            incProgress(0.25, detail = "Filtering by sample_code...")
            if (!is.null(input$sample) && length(input$sample) > 0 && "sample_code" %in% colnames(md)) {
                md_sub <- md[cells, , drop = FALSE]
                keep_sam <- md_sub$sample_code %in% input$sample
                keep_sam[is.na(keep_sam)] <- FALSE
                cells <- rownames(md_sub)[keep_sam]
                rv$last_filter$sample <- input$sample
            }
            
            incProgress(0.15, detail = "Subsetting object...")
            if (length(cells) == 0) {
                showNotification("No cells matched those filters — showing all cells.", type = "warning")
                rv$filt_obj <- rv$obj
                updateSelectizeInput(session, "igt", selected = character(0))
                updateSelectizeInput(session, "sample", selected = character(0))
                updateSelectInput(session, "exp", selected = "All")
            } else {
                rv$filt_obj <- subset(rv$obj, cells = cells)
            }
            
            rv$current_gene <- input$gene
            incProgress(0.10, detail = "Done")
        })
    })
    
    choose_reduction <- function(so) {
        reds <- names(so@reductions)
        if (!length(reds)) return(NULL)
        if ("mde_incremental" %in% reds) return("mde_incremental")
        if ("umap" %in% reds) return("umap")
        reds[1]
    }
    
    output$featureplot <- renderPlot({
        req(rv$filt_obj, rv$current_gene, input$apply_all)
        red <- choose_reduction(rv$filt_obj)
        validate(need(!is.null(red), "No dimensional reduction found in object."))
        FeaturePlot(rv$filt_obj, features = rv$current_gene, reduction = red,
                    pt.size = input$pt_size) + theme_classic()
    })
    
    output$dimplot <- renderPlot({
        req(rv$filt_obj, input$apply_all)
        red <- choose_reduction(rv$filt_obj)
        validate(need(!is.null(red), "No dimensional reduction found in object."))
        if ("annotation_level2" %in% colnames(rv$filt_obj@meta.data)) {
            DimPlot(rv$filt_obj, reduction = red, group.by = "annotation_level2",
                    label = TRUE, pt.size = input$pt_size) + scale_color_manual(values = mypal_level2) + theme_classic()
        } else {
            DimPlot(rv$filt_obj, reduction = red, label = TRUE,
                    pt.size = input$pt_size) + theme_classic()
        }
    })
    
    output$metatable <- renderDT({
        req(rv$filt_obj, input$apply_all)
        md <- rv$filt_obj@meta.data
        validate(need("sample_code" %in% colnames(md), "sample_code column not found in metadata."))
        
        top3 <- function(x) {
            x <- as.character(x); x <- x[!is.na(x) & x != ""]
            if (!length(x)) return(NA_character_)
            tb <- sort(table(x), decreasing = TRUE)
            paste(names(tb)[seq_len(min(3, length(tb)))], collapse = ", ")
        }
        
        to_chr_if_factor <- function(x) if (is.factor(x)) as.character(x) else x
        
        md2 <- md %>% dplyr::mutate(dplyr::across(dplyr::everything(), to_chr_if_factor))
        cols_to_sum <- setdiff(names(md2), "sample_code")
        
        df <- md2 %>%
            dplyr::group_by(sample_code, .drop = FALSE) %>%
            dplyr::summarise(dplyr::across(dplyr::all_of(cols_to_sum), top3), .groups = "drop")
        
        DT::datatable(df, options = list(pageLength = 25, scrollX = TRUE))
    })
    
    output$dl_plot <- downloadHandler(
        filename = function(){
            if (!is.null(input$tabs) && input$tabs == "DimPlot") sprintf("dimplot_%s.pdf", Sys.Date())
            else sprintf("featureplot_%s.pdf", Sys.Date())
        },
        content = function(file) {
            req(rv$filt_obj)
            red <- choose_reduction(rv$filt_obj)
            validate(need(!is.null(red), "No dimensional reduction found in object."))
            if (!is.null(input$tabs) && input$tabs == "DimPlot") {
                if ("annotation_level2" %in% colnames(rv$filt_obj@meta.data)) {
                    p <- DimPlot(rv$filt_obj, reduction = red, group.by = "annotation_level2",
                                 label = TRUE, pt.size = input$pt_size) + scale_color_manual(values = mypal_level2) + theme_classic()
                } else {
                    p <- DimPlot(rv$filt_obj, reduction = red,
                                 label = TRUE, pt.size = input$pt_size) + theme_classic()
                }
            } else {
                req(rv$current_gene)
                p <- FeaturePlot(rv$filt_obj, features = rv$current_gene, reduction = red,
                                 pt.size = input$pt_size) + theme_classic()
            }
            ggsave(file, p, width = 8, height = 6, device = grDevices::cairo_pdf)
        }
    )
}

shinyApp(ui, server)
