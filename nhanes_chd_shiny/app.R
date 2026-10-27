# NHANES CHD Explorer: an R Shiny app built on the nhanes-chd project
# (CDC NHANES 2013-2014, 5,751 adults with a coronary heart disease answer).
#
# Tabs
#   1. Outreach planner     - choose an outreach capacity or a risk threshold and see
#                              who is flagged, cases reached, PPV and lift (live).
#   2. Population prevalence - survey-weighted CHD prevalence (Taylor linearization,
#                              logit CIs) for any subgroup you filter to.
#   3. Data quality checks   - edit checks run live on the analysis file, with a
#                              drill-down to the flagged records.
#   4. About                 - data, methods and limitations.
#
# Run locally:   shiny::runApp()        (from this folder)
# Packages:      install.packages(c("shiny", "bslib", "survey", "ggplot2", "DT"))

library(shiny)
library(bslib)
library(survey)
library(ggplot2)
library(DT)

options(survey.lonely.psu = "adjust")

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------
cohort <- read.csv("data/nhanes_chd_cohort.csv", stringsAsFactors = FALSE)
oof    <- read.csv("data/oof_predictions.csv")

# Same safeguard as the analysis pipeline: one row per participant, aligned files
stopifnot(!anyDuplicated(cohort$SEQN), identical(cohort$SEQN, oof$SEQN),
          identical(cohort$CHD_Flag, oof$CHD_Flag))
cohort$p_lr_weighted   <- oof$p_lr_weighted
cohort$p_lr_unweighted <- oof$p_lr_unweighted

clean_label <- function(x) sub("^[0-9] ", "", x)   # "2 Elevated" -> "Elevated"

filter_vars <- c(
  "Age group"              = "AgeGroup",
  "Sex"                    = "Sex",
  "Blood pressure"         = "BPCategory",
  "HbA1c"                  = "HbA1cCategory",
  "Self-reported diabetes" = "DiabetesSelfReport",
  "Stroke history"         = "StrokeHistory"
)

# Survey design: examined adults only (exam weight > 0), strata and PSUs nested
svy_data <- cohort[cohort$WTMEC2YR > 0, ]
des <- svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTMEC2YR,
                 nest = TRUE, data = svy_data)

model_choices <- c(
  "Logistic regression, class-weighted (ranks well, overstates risk)" = "p_lr_weighted",
  "Logistic regression, unweighted (calibrated risk)"                 = "p_lr_unweighted"
)

auc_rank <- function(p, y) {
  r  <- rank(p)
  n1 <- sum(y == 1)
  n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

pct <- function(x, digits = 1) {
  ifelse(is.na(x), "-", paste0(formatC(100 * x, format = "f", digits = digits), "%"))
}

# ---------------------------------------------------------------------------
# Edit checks (each returns TRUE for a record that fails the rule)
# ---------------------------------------------------------------------------
lab_vars <- c("SystolicBP", "DiastolicBP", "TotalCholesterol", "HDL", "Triglycerides",
              "Glucose", "HbA1c", "Creatinine", "UricAcid", "LDH", "PlateletCount", "RDW")

checks <- list(
  list(id = "DQ-01", severity = "Critical", rule = "Participant ID (SEQN) is unique",
       vars = "SEQN",
       fail = function(d) duplicated(d$SEQN) | duplicated(d$SEQN, fromLast = TRUE)),
  list(id = "DQ-02", severity = "Critical", rule = "CHD flag (0/1) matches the CHD label (No/Yes)",
       vars = c("CHD", "CHD_Flag"),
       fail = function(d) (d$CHD == "Yes") != (d$CHD_Flag == 1)),
  list(id = "DQ-03", severity = "Error", rule = "Age is between 20 and 80 years",
       vars = "Age",
       fail = function(d) d$Age < 20 | d$Age > 80),
  list(id = "DQ-04", severity = "Info", rule = "Age is top-coded at 80 in NHANES public data",
       vars = "Age",
       fail = function(d) d$Age == 80),
  list(id = "DQ-05", severity = "Error", rule = "Systolic BP is between 60 and 250 mmHg",
       vars = c("SystolicBP", "DiastolicBP"),
       fail = function(d) !is.na(d$SystolicBP) & (d$SystolicBP < 60 | d$SystolicBP > 250)),
  list(id = "DQ-06", severity = "Warning", rule = "Diastolic BP is at least 30 mmHg (0 = sound not heard)",
       vars = c("SystolicBP", "DiastolicBP"),
       fail = function(d) !is.na(d$DiastolicBP) & d$DiastolicBP < 30),
  list(id = "DQ-07", severity = "Error", rule = "Diastolic BP is below systolic BP",
       vars = c("SystolicBP", "DiastolicBP"),
       fail = function(d) !is.na(d$SystolicBP) & !is.na(d$DiastolicBP) &
         d$DiastolicBP >= d$SystolicBP),
  list(id = "DQ-08", severity = "Error", rule = "HDL is below total cholesterol",
       vars = c("TotalCholesterol", "HDL"),
       fail = function(d) !is.na(d$HDL) & !is.na(d$TotalCholesterol) &
         d$HDL >= d$TotalCholesterol),
  list(id = "DQ-09", severity = "Error", rule = "HbA1c is between 3% and 20%",
       vars = "HbA1c",
       fail = function(d) !is.na(d$HbA1c) & (d$HbA1c < 3 | d$HbA1c > 20)),
  list(id = "DQ-10", severity = "Warning", rule = "Triglycerides are at most 1,000 mg/dL",
       vars = "Triglycerides",
       fail = function(d) !is.na(d$Triglycerides) & d$Triglycerides > 1000),
  list(id = "DQ-11", severity = "Warning",
       rule = "Exam weight is positive (otherwise excluded from weighted estimates)",
       vars = c("WTMEC2YR", "SDMVSTRA", "SDMVPSU"),
       fail = function(d) is.na(d$WTMEC2YR) | d$WTMEC2YR <= 0)
)

check_results <- lapply(checks, function(ch) {
  flagged <- ch$fail(cohort)
  flagged[is.na(flagged)] <- FALSE
  ch$flagged <- flagged
  ch
})

check_summary <- data.frame(
  ID       = vapply(check_results, `[[`, "", "id"),
  Severity = vapply(check_results, `[[`, "", "severity"),
  Rule     = vapply(check_results, `[[`, "", "rule"),
  Flagged  = vapply(check_results, function(ch) sum(ch$flagged), 0L),
  stringsAsFactors = FALSE
)
check_summary$Status <- ifelse(
  check_summary$Flagged == 0, "Pass",
  ifelse(check_summary$Severity %in% c("Critical", "Error"), "Fail",
         ifelse(check_summary$Severity == "Info", "Note", "Review"))
)

missingness <- data.frame(
  Variable = lab_vars,
  Missing  = vapply(lab_vars, function(v) mean(is.na(cohort[[v]])), 0)
)

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
filter_inputs <- lapply(names(filter_vars), function(nm) {
  v   <- filter_vars[[nm]]
  lv  <- sort(unique(cohort[[v]]))
  checkboxGroupInput(paste0("f_", v), nm,
                     choices = setNames(lv, clean_label(lv)), selected = lv)
})

ui <- page_navbar(
  title = "NHANES CHD Explorer",
  theme = bs_theme(version = 5, primary = "#1F497D"),

  nav_panel(
    "Outreach planner",
    layout_sidebar(
      sidebar = sidebar(
        width = 330,
        radioButtons("model", "Risk model (5-fold out-of-fold predictions)",
                     choices = model_choices),
        radioButtons("mode", "Plan by",
                     choices = c("Outreach capacity" = "capacity",
                                 "Risk threshold"    = "threshold")),
        conditionalPanel(
          "input.mode == 'capacity'",
          sliderInput("capacity", "Share of adults the team can contact",
                      min = 1, max = 60, value = 10, step = 1, post = "%")
        ),
        conditionalPanel(
          "input.mode == 'threshold'",
          sliderInput("threshold", "Flag adults with predicted risk at or above",
                      min = 0.01, max = 0.95, value = 0.40, step = 0.01)
        ),
        helpText("Figures use the analytic sample (5,751 adults, unweighted).",
                 "They illustrate a capacity-based decision, not a deployable screening tool.")
      ),
      layout_columns(
        fill = FALSE,
        value_box("Adults flagged", textOutput("vb_flagged"), textOutput("vb_flagged_n")),
        value_box("CHD cases reached", textOutput("vb_sens"), textOutput("vb_sens_n")),
        value_box("Calls that reach a case (PPV)", textOutput("vb_ppv"), textOutput("vb_lift")),
        value_box("Specificity", textOutput("vb_spec"), textOutput("vb_auc"))
      ),
      layout_columns(
        col_widths = c(7, 5),
        card(card_header("Cumulative gains: cases reached by contacting the riskiest adults first"),
             plotOutput("gains_plot", height = "330px")),
        card(card_header("Confusion matrix and per-10,000 view"),
             tableOutput("confusion"),
             tableOutput("per10k"),
             textOutput("threshold_note"))
      ),
      card(card_header("Calibration by decile: do predicted risks match observed rates?"),
           plotOutput("calib_plot", height = "280px"))
    )
  ),

  nav_panel(
    "Population prevalence",
    layout_sidebar(
      sidebar = sidebar(
        width = 330,
        selectInput("by", "Break down by", choices = filter_vars, selected = "AgeGroup"),
        accordion(
          open = FALSE,
          do.call(accordion_panel, c(list("Filter the population"), filter_inputs))
        ),
        actionButton("reset_filters", "Reset filters", class = "btn-sm btn-outline-secondary"),
        helpText("Survey-weighted with NHANES exam weights (WTMEC2YR), 15 strata and 30 PSUs;",
                 "Taylor-linearized standard errors and logit 95% confidence intervals.")
      ),
      layout_columns(
        fill = FALSE,
        value_box("Weighted CHD prevalence", textOutput("vb_prev"), textOutput("vb_prev_ci")),
        value_box("Adults in sample", textOutput("vb_n"), textOutput("vb_cases")),
        value_box("U.S. adults represented", textOutput("vb_pop"), textOutput("vb_pop_chd"))
      ),
      uiOutput("reliability_note"),
      card(card_header(textOutput("by_title")),
           plotOutput("prev_plot", height = "360px")),
      card(card_header("Estimates"), tableOutput("prev_table"))
    )
  ),

  nav_panel(
    "Data quality checks",
    layout_columns(
      col_widths = c(7, 5),
      card(card_header("Edit checks on the analysis file (select a row to see flagged records)"),
           DTOutput("check_table")),
      card(card_header("Missing values by laboratory and exam variable"),
           plotOutput("missing_plot", height = "360px"))
    ),
    card(card_header(textOutput("flagged_title")), DTOutput("flagged_table"))
  ),

  nav_panel(
    "About",
    card(
      card_body(
        h4("What this app shows"),
        p("An interactive companion to a data audit and revalidation of a coronary heart disease (CHD)",
          "prediction model on CDC NHANES 2013-2014. The analysis file has one row per participant:",
          "5,751 adults with a CHD answer, of whom 232 (4.0%) report a CHD diagnosis."),
        h4("Methods"),
        tags$ul(
          tags$li("Risk scores are 5-fold out-of-fold predictions from logistic regression with",
                  "imputation and scaling fit inside each fold (out-of-fold AUC 0.859 class-weighted,",
                  "0.860 unweighted)."),
          tags$li("Prevalence is design-based: exam weights, strata and PSUs via the R survey package,",
                  "with logit confidence intervals; these match the project's Python estimates",
                  "(all adults 3.7%, 95% CI 2.8-4.7%)."),
          tags$li("Edit checks are run live on the analysis file; each has an ID, a severity and a",
                  "drill-down to the records it flags.")
        ),
        h4("Limitations"),
        p("NHANES is cross-sectional and CHD is a self-reported past diagnosis, so the model describes",
          "associations rather than future risk, and the outreach figures illustrate a decision",
          "framework rather than a screening tool ready to deploy. Outreach figures are unweighted;",
          "prevalence estimates are weighted to the U.S. adult population."),
        p("Code and full analysis: ",
          a("github.com/Markholmezza/nhanes-chd", href = "https://github.com/Markholmezza/nhanes-chd",
            target = "_blank"))
      )
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
server <- function(input, output, session) {

  # ---- Outreach planner --------------------------------------------------
  observeEvent(input$model, {
    default <- if (input$model == "p_lr_weighted") 0.40 else 0.10
    updateSliderInput(session, "threshold", value = default)
  }, ignoreInit = TRUE)

  scores <- reactive(cohort[[input$model]])

  sel <- reactive({
    p <- scores()
    y <- cohort$CHD_Flag
    n <- length(p)
    if (input$mode == "capacity") {
      k    <- round(input$capacity / 100 * n)
      ord  <- order(p, decreasing = TRUE)
      flag <- rep(FALSE, n)
      flag[ord[seq_len(k)]] <- TRUE
      thr  <- if (k > 0) p[ord[k]] else NA
    } else {
      flag <- p >= input$threshold
      thr  <- input$threshold
    }
    tp <- sum(flag & y == 1); fp <- sum(flag & y == 0)
    fn <- sum(!flag & y == 1); tn <- sum(!flag & y == 0)
    list(tp = tp, fp = fp, fn = fn, tn = tn, n = n, cases = sum(y), thr = thr,
         flagged = (tp + fp) / n,
         sens = tp / (tp + fn), spec = tn / (tn + fp),
         ppv = if (tp + fp > 0) tp / (tp + fp) else NA)
  })

  output$vb_flagged   <- renderText(pct(sel()$flagged))
  output$vb_flagged_n <- renderText(sprintf("%s of %s adults",
                                            format(sel()$tp + sel()$fp, big.mark = ","),
                                            format(sel()$n, big.mark = ",")))
  output$vb_sens      <- renderText(pct(sel()$sens))
  output$vb_sens_n    <- renderText(sprintf("%d of %d cases (sensitivity)", sel()$tp, sel()$cases))
  output$vb_ppv       <- renderText(pct(sel()$ppv))
  output$vb_lift      <- renderText({
    s <- sel()
    if (is.na(s$ppv)) "No adults flagged" else
      sprintf("%.1f times the rate of random calls", s$ppv / (s$cases / s$n))
  })
  output$vb_spec      <- renderText(pct(sel()$spec))
  output$vb_auc       <- renderText(sprintf("Out-of-fold AUC %.3f",
                                            auc_rank(scores(), cohort$CHD_Flag)))

  gains <- reactive({
    p   <- scores()
    y   <- cohort$CHD_Flag[order(p, decreasing = TRUE)]
    data.frame(contacted = seq_along(y) / length(y), reached = cumsum(y) / sum(y))
  })

  output$gains_plot <- renderPlot({
    g <- gains()
    s <- sel()
    ggplot(g, aes(contacted, reached)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey60") +
      geom_line(colour = "#1F497D", linewidth = 1) +
      annotate("point", x = s$flagged, y = s$sens, size = 3.5, colour = "#C0504D") +
      annotate("label", x = s$flagged, y = s$sens, hjust = -0.1, vjust = 1.2, size = 3.6,
               label = sprintf("Contact %s -> reach %s of cases", pct(s$flagged, 0), pct(s$sens, 0))) +
      scale_x_continuous(labels = function(x) paste0(100 * x, "%"), limits = c(0, 1)) +
      scale_y_continuous(labels = function(x) paste0(100 * x, "%"), limits = c(0, 1)) +
      labs(x = "Adults contacted (riskiest first)", y = "CHD cases reached",
           caption = "Dashed line: contacting adults at random") +
      theme_minimal(base_size = 13)
  })

  output$confusion <- renderTable({
    s <- sel()
    data.frame(
      ` `            = c("Flagged", "Not flagged", "Total"),
      `Has CHD`      = c(s$tp, s$fn, s$tp + s$fn),
      `No CHD`       = c(s$fp, s$tn, s$fp + s$tn),
      Total          = c(s$tp + s$fp, s$fn + s$tn, s$n),
      check.names = FALSE
    )
  }, digits = 0, align = "lrrr")

  output$per10k <- renderTable({
    s <- sel()
    data.frame(
      `Per 10,000 adults` = c("Contacted", "Cases reached", "Cases reached by random calls"),
      Count = round(c(s$flagged, s$tp / s$n, s$flagged * s$cases / s$n) * 10000),
      check.names = FALSE
    )
  }, digits = 0, align = "lr")

  output$threshold_note <- renderText({
    s <- sel()
    if (input$mode == "capacity" && !is.na(s$thr))
      sprintf("This capacity corresponds to a risk cutoff of %.3f on the selected model.", s$thr)
    else if (input$model == "p_lr_weighted")
      "Class weighting shifts scores upward (mean 0.30 vs 4% observed): use them to rank, not as probabilities."
    else
      "Unweighted scores are calibrated: a score of 0.10 means about a 10% observed rate."
  })

  output$calib_plot <- renderPlot({
    df <- do.call(rbind, lapply(names(model_choices), function(lbl) {
      v   <- model_choices[[lbl]]
      p   <- cohort[[v]]
      bin <- cut(rank(p, ties.method = "first"), 10, labels = FALSE)
      data.frame(Model = ifelse(v == "p_lr_weighted", "Class-weighted", "Unweighted"),
                 Predicted = as.numeric(tapply(p, bin, mean)),
                 Observed  = as.numeric(tapply(cohort$CHD_Flag, bin, mean)))
    }))
    ggplot(df, aes(Predicted, Observed, colour = Model)) +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey60") +
      geom_line() + geom_point(size = 2.5) +
      scale_colour_manual(values = c("Class-weighted" = "#C0504D", "Unweighted" = "#1F497D")) +
      scale_x_continuous(labels = function(x) paste0(100 * x, "%")) +
      scale_y_continuous(labels = function(x) paste0(100 * x, "%")) +
      labs(x = "Mean predicted risk in decile", y = "Observed CHD rate",
           caption = "Points on the dashed line mean predicted risk equals observed rate") +
      theme_minimal(base_size = 13) + theme(legend.position = "top")
  })

  # ---- Population prevalence ---------------------------------------------
  observeEvent(input$reset_filters, {
    for (v in filter_vars) {
      updateCheckboxGroupInput(session, paste0("f_", v), selected = sort(unique(cohort[[v]])))
    }
  })

  keep <- reactive({
    k <- rep(TRUE, nrow(svy_data))
    for (v in filter_vars) {
      chosen <- input[[paste0("f_", v)]]
      k <- k & svy_data[[v]] %in% chosen
    }
    k
  })

  svy_est <- function(k) {
    n     <- sum(k)
    cases <- sum(svy_data$CHD_Flag[k])
    pop   <- sum(svy_data$WTMEC2YR[k])
    if (n == 0) return(NULL)
    if (cases == 0) {
      return(list(p = 0, lo = NA, hi = NA, n = n, cases = cases, pop = pop))
    }
    ci <- svyciprop(~CHD_Flag, des[k, ], method = "logit")
    lim <- as.numeric(attr(ci, "ci"))
    list(p = as.numeric(coef(ci)), lo = lim[1], hi = lim[2], n = n, cases = cases, pop = pop)
  }

  overall <- reactive(svy_est(keep()))

  output$vb_prev    <- renderText({ e <- overall(); if (is.null(e)) "-" else pct(e$p) })
  output$vb_prev_ci <- renderText({
    e <- overall()
    if (is.null(e)) "No adults match the filters"
    else if (is.na(e$lo)) "No cases in this group"
    else sprintf("95%% CI %s to %s", pct(e$lo), pct(e$hi))
  })
  output$vb_n     <- renderText({ e <- overall(); if (is.null(e)) "0" else format(e$n, big.mark = ",") })
  output$vb_cases <- renderText({ e <- overall(); if (is.null(e)) "" else sprintf("%d with CHD", e$cases) })
  output$vb_pop   <- renderText({ e <- overall(); if (is.null(e)) "-" else sprintf("%.1f million", e$pop / 1e6) })
  output$vb_pop_chd <- renderText({
    e <- overall()
    if (is.null(e)) "" else sprintf("About %.1f million with CHD", e$p * e$pop / 1e6)
  })

  output$reliability_note <- renderUI({
    e <- overall()
    if (!is.null(e) && (e$n < 30 || e$cases < 10)) {
      div(class = "alert alert-warning",
          "Interpret with caution: this subgroup has fewer than 30 adults or fewer than 10 cases,",
          "so the estimate is unstable.")
    }
  })

  by_table <- reactive({
    k  <- keep()
    v  <- input$by
    lv <- sort(unique(svy_data[[v]][k]))
    rows <- lapply(lv, function(l) {
      e <- svy_est(k & svy_data[[v]] == l)
      if (is.null(e)) return(NULL)
      data.frame(Level = clean_label(l), Prevalence = e$p, Low = e$lo, High = e$hi,
                 n = e$n, Cases = e$cases,
                 Caution = e$n < 30 | e$cases < 10)
    })
    out <- do.call(rbind, rows)
    if (!is.null(out)) out$Level <- factor(out$Level, levels = out$Level)
    out
  })

  output$by_title <- renderText({
    paste("Survey-weighted CHD prevalence by", tolower(names(filter_vars)[filter_vars == input$by]))
  })

  output$prev_plot <- renderPlot({
    df <- by_table()
    validate(need(!is.null(df) && nrow(df) > 0, "No adults match the current filters."))
    ggplot(df, aes(Level, Prevalence, fill = Caution)) +
      geom_col(width = 0.6) +
      geom_errorbar(aes(ymin = Low, ymax = High), width = 0.2, na.rm = TRUE) +
      scale_fill_manual(values = c(`FALSE` = "#1F497D", `TRUE` = "#BFBFBF"),
                        labels = c(`FALSE` = "Reliable", `TRUE` = "Interpret with caution"),
                        name = NULL, drop = FALSE) +
      scale_y_continuous(labels = function(x) paste0(100 * x, "%")) +
      labs(x = NULL, y = "Weighted prevalence (95% CI)") +
      theme_minimal(base_size = 13) + theme(legend.position = "top")
  })

  output$prev_table <- renderTable({
    df <- by_table()
    validate(need(!is.null(df) && nrow(df) > 0, "No adults match the current filters."))
    data.frame(
      Group        = as.character(df$Level),
      Prevalence   = pct(df$Prevalence),
      `95% CI`     = ifelse(is.na(df$Low), "-", paste(pct(df$Low), "to", pct(df$High))),
      `Adults (n)` = format(df$n, big.mark = ","),
      Cases        = df$Cases,
      Note         = ifelse(df$Caution, "Interpret with caution", ""),
      check.names = FALSE
    )
  }, align = "lrrrrl")

  # ---- Data quality checks -----------------------------------------------
  output$check_table <- renderDT({
    datatable(check_summary, rownames = FALSE, selection = list(mode = "single", selected = 6),
              options = list(dom = "t", pageLength = 20, ordering = FALSE,
                             columnDefs = list(list(className = "dt-nowrap", targets = c(0, 1, 4))))) |>
      formatStyle("Status", target = "cell", fontWeight = "bold",
                  color = styleEqual(c("Pass", "Fail", "Review", "Note"),
                                     c("#2E7D32", "#C62828", "#E65100", "#1F497D")))
  })

  selected_check <- reactive({
    i <- input$check_table_rows_selected
    if (length(i) == 0) NULL else check_results[[i]]
  })

  output$flagged_title <- renderText({
    ch <- selected_check()
    if (is.null(ch)) "Select a check above to see the records it flags"
    else sprintf("%s: %d record(s) flagged - %s", ch$id, sum(ch$flagged), ch$rule)
  })

  output$flagged_table <- renderDT({
    ch <- selected_check()
    validate(need(!is.null(ch), "Select a check above."))
    cols <- unique(c("SEQN", ch$vars, "Age", "Sex", "CHD"))
    d <- cohort[ch$flagged, cols, drop = FALSE]
    datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "tip"))
  })

  output$missing_plot <- renderPlot({
    df <- missingness
    df$Variable <- factor(df$Variable, levels = df$Variable[order(df$Missing)])
    ggplot(df, aes(Missing, Variable)) +
      geom_col(fill = ifelse(df$Missing > 0.5, "#C0504D", "#9AA0A6")) +
      geom_vline(xintercept = 0.5, linetype = "dashed", colour = "grey40") +
      geom_text(aes(label = pct(Missing)), hjust = -0.15, size = 3.6) +
      scale_x_continuous(labels = function(x) paste0(100 * x, "%"), limits = c(0, 0.7)) +
      labs(x = "Missing (% of 5,751 adults)", y = NULL,
           caption = "Triglycerides were measured only in the fasting subsample") +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui, server)
