#' @title Scrape R script to create namespace calls for R documentation
#' @description Scrape r script to create namespace calls for roxygen2, namespace or description files
#' @param script character, connection to pass to readLines, can be file path, directory path, url path
#' @param cut integer, number of functions to write as importFrom until switches to import, Default: NULL
#' @param print boolean, print output to console, Default: TRUE
#' @param format character, the output format must be in c('oxygen','description','import'), Default: 'oxygen'
#' @param desc_loc character, path to DESCRIPTION file, if not NULL then the Imports fields in
#'  the DESCRIPTION file, Default: NULL
#' @examples
#' makeImport('R',format = 'oxygen')
#' makeImport('R',format = 'description')
#' makeImport('R',format = 'import')
#' @export
#' @importFrom utils installed.packages capture.output getParseData
#' @importFrom tools file_ext
makeImport <- function(script, cut=NULL, print=TRUE, format="oxygen", desc_loc=NULL) {
  rInst <- paste0(row.names(utils::installed.packages()), "::")

  if (inherits(script, "function")) {
    file <- tempfile()
    utils::capture.output(print(script), file = file)
    check.file <- readLines(file)
    cat(check.file[!grepl("^<", check.file)], file = file, sep = "\n")
  } else {
    if (all(nzchar(tools::file_ext(script)))) {
      file <- script
    } else {
      file <- list.files(script, full.names = TRUE, pattern = "\\.[R|r]$")
    }
  }

  pkg <- sapply(file, function(f) {
    parsed <- utils::getParseData(parse(f))
    parsed_f <- parsed[parsed$parent %in% parsed$parent[grepl("SYMBOL_PACKAGE", parsed$token)], ]
    parsed_f <- parsed_f[!grepl("::", parsed_f$text), c("parent", "token", "text")]

    PKGS <- unique(parsed_f$text[grepl("PACKAGE$", parsed_f$token)])

    ret <- sapply(PKGS, function(pkg) {
      x <- parsed_f[parsed_f$parent %in% parsed_f$parent[grepl(sprintf("^%s$", pkg), parsed_f$text)], ]
      fns <- unique(x$text[!grepl("SYMBOL_PACKAGE", x$token)])

      data.frame(pkg = pkg, fns = fns, stringsAsFactors = FALSE)
    }, simplify = FALSE)

    ret <- do.call("rbind", ret)
    rownames(ret) <- NULL

    if (format %in% c("oxygen", "import")) {
      ret <- sapply(unique(ret$pkg), function(pkg) {
        fns <- ret$fns[ret$pkg == pkg]
        if (format == "oxygen") {
          if (!is.null(cut) && length(fns) >= cut) {
            ret <- sprintf("#' @import %s", pkg)
          } else {
            ret <- sprintf("#' @importFrom %s %s", pkg, paste(fns, collapse = " "))
          }
        } else if (format == "import") {
          ret <- sprintf("import::from(%s, %s)", pkg, paste(fns, collapse = ", "))
        }
        ret
      })

      if (print) writeLines(paste(" ", f, paste(ret, collapse = "\n"), sep = "\n"))
    }

    return(ret)
  }, simplify = FALSE)

  if (format %in% c("oxygen", "import")) ret <- pkg

  if (format == "description") {
    ret <- do.call("rbind", pkg)

    ret <- sprintf("Imports: %s", paste(unique(ret$pkg), collapse = ","))

    if (print) writeLines(ret)

    if (!is.null(desc_loc)) {
      if (file.exists(file.path(desc_loc, "DESCRIPTION"))) {
        desc <- read.dcf(file.path(desc_loc, "DESCRIPTION"))

        import_col <- grep("Imports", colnames(desc))

        if (length(import_col) == 0) {
          desc <- cbind(desc, gsub("Imports: ", "\n", ret))

          colnames(desc)[ncol(desc)] <- "Imports"
        } else {
          desc[, "Imports"] <- gsub("Imports: ", "\n", ret)
        }

        write.dcf(desc, file = file.path(desc_loc, "DESCRIPTION"))
      }
    }
  }

  if (inherits(script, "function")) unlink(file)

  invisible(sapply(ret, paste0, collapse = "\n"))
}
