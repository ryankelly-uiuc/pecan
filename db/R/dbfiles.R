#-------------------------------------------------------------------------------
# Copyright (c) 2012 University of Illinois, NCSA.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the
# University of Illinois/NCSA Open Source License
# which accompanies this distribution, and is available at
# http://opensource.ncsa.illinois.edu/license.html
#-------------------------------------------------------------------------------

##' Function to insert a file into the dbfiles table as an input
##'
##' This will write into the dbfiles, inputs, machines and formats the required
##' data to store the file
##' @name dbfile.input.insert
##' @title Insert file into tables
##' @param filename the name of the file to be inserted
##' @param siteid the id of the site that this data is applicable to
##' @param startdate the start date of the data stored in the file
##' @param enddate the end date of the data stored in the file
##' @param mimetype the mime-type of the file
##' @param formatname the name of the format to distinguish between simmilair mime-types
##' @param parent the id of the parent of the input
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @param params database connection information
##' @param allow.conflicting.dates Whether to allow a new input record with same siteid, name, and format but different start/end dates
##' @return data.frame with the id, filename and pathname of the input that is requested
##' @export
##' @author Rob Kooper, Betsy Cowdery
##' @examples
##' \dontrun{
##'   dbfile.input.insert('trait.data.Rdata', siteid, startdate, enddate, 'application/x-RData', 'traits', dbcon)
##' }
dbfile.input.insert <- function(in.path, in.prefix, siteid, startdate, enddate, mimetype, formatname, parentid=NA, con, hostname=fqdn(), allow.conflicting.dates=FALSE) {
  name <- basename(in.path)
  filename <- file.path(in.path, in.prefix)
  
  if (hostname == "localhost") hostname <- fqdn();
  
  # find mimetype, if it does not exist, it will create one
  mimetypeid <- get.id("mimetypes", "type_string", mimetype, con, create=TRUE)
  
  # find appropriate format, create if it does not exist
  formatid <- get.id("formats", colname = c('mimetype_id', 'name'), 
                     value = c(mimetypeid, formatname), con, create=TRUE, dates=TRUE)
  
  # setup parent part of query if specified
  if (is.na(parentid)) {
    parent <- ""
  } else {
    parent <- paste0(" AND parent_id=", parentid)
  }
  
  # find appropriate input, if not in database, insert new input
  existing.input <- db.query(paste0(
    "SELECT * FROM inputs WHERE site_id=", siteid, " AND name= '", name, 
    "' AND format_id=", formatid, parent), con)
  
  inputid <- NULL
  if (nrow(existing.input) > 0) {
    # Convert dates to Date objects and strip all time zones (DB values are timezone-free)
    startdate <- lubridate::force_tz(lubridate::as_date(startdate), 'UTC')
    enddate <- lubridate::force_tz(lubridate::as_date(enddate), 'UTC')
    existing.input$start_date <- lubridate::force_tz(lubridate::as_date(existing.input$start_date), 'UTC')
    existing.input$end_date <- lubridate::force_tz(lubridate::as_date(existing.input$end_date), 'UTC')
    
    for(i in 1:nrow(existing.input)) {
      existing.input.i <- existing.input[i,]
      if(existing.input.i$start_date == startdate && existing.input.i$end_date == enddate) {
        inputid <- existing.input.i[['id']]
        break
      }
    }
    
    if(is.null(inputid) && !allow.conflicting.dates) {
      print(existing.input, digits=10)
      logger.error(paste0(
        "Duplicate inputs (in terms of site_id, name, and format_id) with differing ",
        "start/end dates are not allowed. The existing input record printed above would ",
        " conflict with the one to be inserted, which has requested start/end dates of ", 
        startdate, "/", enddate, "Please resolve this conflict or set", 
        "allow.conflicting.dates=TRUE if you want to allow multiple input records ",
        " with different dates."
      ))
      return(NULL)
    }
  } 
  
  if(is.null(inputid)) {
    # Either there was no existing input, or there was but the dates don't match and 
    # allow.conflicting.dates==TRUE. So, insert new input record. 
    if(parent == ""){
      cmd <- paste0("INSERT INTO inputs ",
                    "(site_id, format_id, created_at, updated_at, start_date, end_date, name) VALUES (",
                    siteid, ", ", formatid, ", NOW(), NOW(), '", startdate, "', '", enddate,"','", name, "')")
    } else {
      cmd <- paste0("INSERT INTO inputs ",
                    "(site_id, format_id, created_at, updated_at, start_date, end_date, name, parent_id) VALUES (",
                    siteid, ", ", formatid, ", NOW(), NOW(), '", startdate, "', '", enddate,"','", name, "',",parentid,")")
    }
    db.query(cmd, con)
    
    inputid <- db.query(paste0("SELECT id FROM inputs WHERE site_id=", siteid, 
                               " AND format_id=", formatid, " AND start_date='", startdate, 
                               "' AND end_date='", enddate, "'" , parent, ";"), con)[['id']]
  } 
  
  # find appropriate dbfile, if not in database, insert new dbfile
  dbfile <- dbfile.check('Input', inputid, con, hostname)
  
  if(nrow(dbfile) > 0) {
    if(nrow(dbfile) > 1) {
      print(dbfile)
      logger.warn("Multiple dbfiles found. Using last.")
      dbfile <- dbfile[nrow(dbfile),]
    }
    if(dbfile$file_name != in.prefix || dbfile$file_path != in.path) {
      print(dbfile, digits=10)
      logger.error(paste0(
        "The existing dbfile record printed above has the same machine_id and container ",
        "but a diferent file name than expected (prefix='", in.prefix, "', path=", in.path, ").",
        "This is not allowed."
      ))
      dbfileid <- NA
    } else {
      dbfileid <- dbfile[['id']]
    }
  } else {
    #insert dbfile & return dbfile id
    dbfileid <- dbfile.insert(in.path, in.prefix, 'Input', inputid, con, reuse=TRUE, hostname)
  }
  
  invisible(list(input.id = inputid, dbfile.id = dbfileid))
}

##' Function to check to see if a file exists in the dbfiles table as an input
##'
##' This will check the dbfiles, inputs, machines and formats tables to see if the
##' file exists
##' @name dbfile.input.check
##' @title Check for a file in the input/dbfiles tables
##' @param siteid the id of the site that this data is applicable to
##' @param startdate the start date of the data stored in the file
##' @param enddate the end date of the data stored in the file
##' @param mimetype the mime-type of the file
##' @param formatname the name of the format to distinguish between simmilair mime-types
##' @param parent the id of the parent of the input
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @param params database connection information
##' @param exact.dates setting to include start and end date in input query
##' @param pattern text to seach for in the file name (default NULL = no check). NOT YET IMPLEMENTED
##' @return data.frame with the id, filename and pathname of the input that is requested
##' @export
##' @author Rob Kooper, Tony Gardella
##' @examples
##' \dontrun{
##'   dbfile.input.check(siteid, startdate, enddate, 'application/x-RData', 'traits', dbcon)
##' }
dbfile.input.check <- function(siteid, startdate=NULL, enddate=NULL, mimetype, formatname, parentid=NA, 
                               con, hostname=fqdn(), exact.dates=FALSE,pattern=NULL) {
  if (hostname == "localhost") hostname <- fqdn();
  
  mimetypeid <- get.id('mimetypes', 'type_string', mimetype, con = con)
  if (is.null(mimetypeid)) {
    return(invisible(data.frame()))
  }
  
  # find appropriate format
  formatid <- get.id('formats', c("mimetype_id", "name"), c(mimetypeid, formatname), con) 
  if (is.null(formatid)) {
    invisible(data.frame())
  }
  
  # setup parent part of query if specified
  if (is.na(parentid)) {
    parent <- ""
  } else {
    parent <- paste0(" AND parent_id=", parentid)
  }
  
  # find appropriate input
  if(exact.dates) {
    inputs <- db.query(paste0(
      "SELECT * FROM inputs WHERE site_id=", siteid, " AND format_id=", formatid,
      " AND start_date='", startdate, "' AND end_date='", enddate, "'", parent), con)#[['id']]
  } else {
    inputs <- db.query(paste0(
      "SELECT * FROM inputs WHERE site_id=", siteid, " AND format_id=", formatid, parent), con)#[['id']]
  }
  
  if (is.null(inputs) | length(inputs$id) == 0) {
    return(data.frame())
  } else {
    
    ## parent check when NA
    if(is.na(parentid)){
      inputs <- inputs[is.na(inputs$parent_id),]
    }
    
    if(length(inputs$id) > 1){
      logger.warn("Found multiple matching inputs. Checking for one with associate files on host machine")
      
      print(inputs)        
      #      ni = length(inputs$id)
      #      dbfile = list()
      #      for(i in seq_len(ni)){
      #        dbfile[[i]] <- dbfile.check(type = 'Input', container.id = inputs$id[i], con = con, hostname = hostname, machine.check = TRUE)
      #    }
      dbfile <- dbfile.check(type = 'Input', container.id = inputs$id, con = con, hostname = hostname, machine.check = TRUE)
      
      
      if(nrow(dbfile) == 0){
        ## With the possibility of dbfile.check returning nothing,
        ## as.data.frame ensures a empty data.frame is returned 
        ## rather than an empty list.
        logger.info("File not found on host machine. Returning Valid input with file associated on different machine if possible")
        return(as.data.frame(dbfile.check('Input', inputs$id, con, hostname, machine.check = FALSE)))
      }
      
      return(dbfile)
    }else{
      
      logger.warn("Found possible matching input. Checking if its associate files are on host machine")
      print(inputs)        
      dbfile <- dbfile.check(type = 'Input', container.id = inputs$id, con = con, hostname = hostname, machine.check = TRUE)
      
      if(nrow(dbfile) == 0){
        ## With the possibility of dbfile.check returning nothing,
        ## as.data.frame ensures an empty data.frame is returned 
        ## rather than an empty list.
        logger.info("File not found on host machine. Returning Valid input with file associated on different machine if possible")
        return(as.data.frame(dbfile.check(type = 'Input', container.id = inputs$id, con = con, hostname = hostname, machine.check = FALSE)))
      }
      
      return(dbfile)
      
    }
  }
}

##' Function to insert a file into the dbfiles table as a posterior
##'
##' This will write into the dbfiles, posteriors, machines and formats the require
##' data to store the file
##' @name dbfile.posterior.insert
##' @title Insert file into tables
##' @param filename the name of the file to be inserted
##' @param pft the name of the pft that this data is applicable to
##' @param mimetype the mime-type of the file
##' @param formatname the name of the format to distinguish between simmilair mime-types
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @param params database connection information
##' @return data.frame with the id, filename and pathname of the posterior that is requested
##' @author Rob Kooper
##' @export
##' @examples
##' \dontrun{
##'   dbfile.posterior.insert('trait.data.Rdata', pft, 'application/x-RData', 'traits', dbcon)
##' }
dbfile.posterior.insert <- function(filename, pft, mimetype, formatname, con, hostname=fqdn()) {
  if (hostname == "localhost") hostname <- fqdn();
  
  # find appropriate pft
  pftid <- get.id("pfts", "name", pft, con)
  if (is.null(pftid)) {
    logger.severe("Could not find pft, could not store file", filename)
  }
  
  mimetypeid <- get.id('mimetypes', 'type_string', mimetype, con = con, create=TRUE)
  
  # find appropriate format
  formatid <- get.id("formats", colname=c('mimetype_id', 'name'), value=c(mimetypeid, formatname), con, create=TRUE, dates=TRUE)
  
  # find appropriate posterior
  posterior_ids <- get.id("posteriors", "pft_id", pftid, con)
  
  posteriorid_query <- paste0("SELECT id FROM posteriors WHERE pft_id=", 
                              pftid, " AND format_id=", formatid)
  posteriorid <- db.query(posteriorid_query, con)[['id']]
  if (is.null(posteriorid)) {
    # insert input
    db.query(paste0("INSERT INTO posteriors (pft_id, format_id, created_at, updated_at) VALUES (", pftid, ", ", formatid, ", NOW(), NOW())"), con)
    posteriorid <- db.query(posteriorid_query, con)[['id']]
  }
  
  invisible(dbfile.insert(filename, 'Posterior', posteriorid, con, reuse=TRUE, hostname))
}

##' Function to check to see if a file exists in the dbfiles table as an input
##'
##' This will check the dbfiles, inputs, machines and formats tables to see if the
##' file exists
##' @name dbfile.posterior.check
##' @title Check for a file in the input/dbfiles tables
##' @param pft the name of the pft that this data is applicable to
##' @param mimetype the mime-type of the file
##' @param formatname the name of the format to distinguish between simmilair mime-types
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @param params database connection information
##' @return data.frame with the id, filename and pathname of the posterior that is requested
##' @author Rob Kooper
##' @export
##' @examples
##' \dontrun{
##'   dbfile.posterior.check(pft, 'application/x-RData', 'traits', dbcon)
##' }
dbfile.posterior.check <- function(pft, mimetype, formatname, con, hostname=fqdn()) {
  if (hostname == "localhost") hostname <- fqdn();
  
  # find appropriate pft
  pftid <- get.id("pfts", "name", pft, con)
  if (is.null(pftid)) {
    invisible(data.frame())
  }
  
  # find appropriate format
  mimetypeid <- get.id("mimetypes", "type_string", mimetype, con)
  if(is.null(mimetypeid)) logger.error("mimetype ", mimetype, "does not exist")
  formatid <- get.id("formats", colnames = c("mimetype_id", "name"), values = c(mimetypeid, formatname), con) 
  
  if (is.null(formatid)) {
    invisible(data.frame())
  }
  
  # find appropriate posterior
  posteriorid <- db.query(paste0("SELECT id FROM posteriors WHERE pft_id=", pftid, " AND format_id=", formatid), con)[['id']]
  if (is.null(posteriorid)) {
    invisible(data.frame())
  }
  
  invisible(dbfile.check('Posterior', posteriorid, con, hostname))
}

##' Function to insert a file into the dbfiles table
##'
##' This will write into the dbfiles and machines the required data to store the file
##' @name dbfile.insert
##' @title Insert file into tables
##' @param filename the name of the file to be inserted
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @param params database connection information
##' @return id of the file that is written
##' @author Rob Kooper, Ryan Kelly
##' @export
##' @examples
##' \dontrun{
##'   dbfile.insert('somefile.txt', 'Input', 7, dbcon)
##' }
dbfile.insert <- function(in.path, in.prefix, type, id, con, reuse = TRUE, hostname=fqdn()) {
  if (hostname == "localhost") hostname <- fqdn()
  
  if (substr(in.path, 1, 1) != '/') logger.error("path to dbfiles:", in.path, " is not a valid full path")
  
  # find appropriate host
  hostid <- get.id("machines", colname = "hostname", value = hostname, con, create=TRUE, dates=TRUE)
  
  # Query for existing dbfile record with same file_name, file_path, machine_id, 
  # container_type, and container_id.
  dbfile <- invisible(db.query(
    paste0(
      "SELECT * FROM dbfiles WHERE ",
      "file_name='", basename(in.prefix), "' AND ", 
      "file_path='", in.path, "' AND ", 
      "machine_id='", hostid, "'"
    ), con))
  
  if(nrow(dbfile)==0) {
    # If no exsting record, insert one
    now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    
    db.query(paste0("INSERT INTO dbfiles ",
                    "(container_type, container_id, file_name, file_path, machine_id, created_at, updated_at) VALUES (",
                    "'", type, "', ", id, ", '", basename(in.prefix), "', '", in.path, "', ", hostid, 
                    ", '", now, "', '", now, "')"), con)
    
    file.id <- invisible(db.query(paste0(
      "SELECT * FROM dbfiles WHERE container_type='", type, "' AND container_id=", id, 
      " AND created_at='", now, "' ORDER BY id DESC LIMIT 1"), con)[['id']])
  } else if(!reuse) {
    # If there is an existing record but reuse==FALSE, return NA.
    file.id <- NA
  } else {
    if(dbfile$container_type != type || dbfile$container_id != id) {
      print(dbfile, digits=10)
      logger.error(paste0(
        "The existing dbfile record printed above has the same machine_id, file_path, and file_name ",
        "but is associated with a different input than requested (type='", type, "', id=", id, ").",
        "This is not allowed."
      ))
      file.id <- NA
    } else {
      file.id <- dbfile[['id']]
    }
  }
  
  # Return the new dbfile ID, or the one that existed already (reuse==T), or NA (reuse==F)
  return(file.id)
}

##' Function to check to see if a file exists in the dbfiles table
##'
##' This will check the dbfiles and machines to see if the file exists
##' @name dbfile.check
##' @title Check for a file in the dbfiles tables
##' @param type the type of dbfile (Input, Posterior)
##' @param container.id the id of container type
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @param machine.check setting to check for file on named host, otherwise will check for any file given container id
##' @return data.frame with the id, filename and pathname of all the files that are associated
##' @author Rob Kooper
##' @export
##' @examples
##' \dontrun{
##'   dbfile.check('Input', 7, dbcon)
##' }

dbfile.check <- function(type, container.id, con, hostname=fqdn(), machine.check = TRUE) {
  
  if (hostname == "localhost") hostname <- fqdn()
  
  # find appropriate host
  hostid <- get.id("machines", "hostname", hostname, con) 
  # hostid <- db.query(paste0("SELECT id FROM machines WHERE hostname='", hostname, "'"), con)[['id']]
  if (is.null(hostid)) {
    return(data.frame())
  } else if (machine.check){
    
    dbfiles <- db.query(paste0("SELECT * FROM dbfiles WHERE container_type='", type, 
                               "' AND container_id IN (", paste(container.id, collapse = ", "), 
                               ") AND machine_id=", hostid), con)
    
    if(nrow(dbfiles) > 1){
      
      logger.warn("Multiple Valid Files found on host machine. Returning last updated record")
      return(dbfiles[dbfiles$updated_at == max(dbfiles$updated_at),])
      
    }else{
      
      return(dbfiles)
      
    }
    
  }else{
    
    dbfiles <- db.query(paste0("SELECT * FROM dbfiles WHERE container_type='", type, 
                               "' AND container_id IN (", paste(container.id, collapse = ", "),")"), con)
    
    if(nrow(dbfiles) > 1){
      
      logger.warn("Multiple Valid Files found on host machine. Returning last updated record")
      return(dbfiles[dbfiles$updated_at == max(dbfiles$updated_at),])
      
    }else{
      
      return(dbfiles)
    }
  }
}



##' Function to return full path to a file using dbfiles table
##'
##' This will check the dbfiles and machines to see if the file exists,
##' and return the full filename with path to the first one found. If
##' none is found it will return NA.
##'
##' @name dbfile.file
##' @title Return file from the dbfiles tables
##' @param type the type of dbfile (Input, Posterior)
##' @param id the id of container type
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @return filename on host, or NA if none found
##' @author Rob Kooper
##' @export
##' @examples
##' \dontrun{
##'   dbfile.file('Input', 7, dbcon)
##' }
dbfile.file <- function(type, id, con, hostname=fqdn()) {
  if (hostname == "localhost") hostname <- fqdn();
  
  files <- dbfile.check(type, id, con, hostname)
  
  if(nrow(files) > 1) {
    logger.warn("multiple files found for", id, "returned; using the first one found")
    invisible(file.path(files[1, 'file_path'], files[1, 'file_name']))
  } else if (nrow(files) == 1) {
    invisible(file.path(files[1, 'file_path'], files[1, 'file_name']))
  } else {
    logger.warn("no files found for ", id, "in database")
    invisible(NA)
  }
}

##' Function to return id to containter type given a filename.
##'
##' This will check the dbfiles and machines to see if the file exists,
##' and return the id of the container type of the first one found. If
##' none is found it will return NA.
##'
##' @name dbfile.file
##' @title Return id from the dbfiles tables
##' @param type the type of dbfile (Input, Posterior)
##' @param file the full pathname to the file
##' @param con database connection object
##' @param hostname the name of the host where the file is stored, this will default to the name of the current machine
##' @return filename on host, or NA if none found
##' @author Rob Kooper
##' @export
##' @examples
##' \dontrun{
##'   dbfile.id('Model', '/usr/local/bin/sipnet', dbcon)
##' }
dbfile.id <- function(type, file, con, hostname=fqdn()) {
  if (hostname == "localhost") hostname <- fqdn();
  
  # find appropriate host
  hostid <- db.query(paste0("SELECT id FROM machines WHERE hostname='", hostname, "'"), con)[['id']]
  if (is.null(hostid)) {
    invisible(NA)
  }
  
  # find file
  file_name <- basename(file)
  file_path <- dirname(file)
  ids <- db.query(paste0("SELECT container_id FROM dbfiles WHERE container_type='", type, "' AND file_path='", file_path, "' AND file_name='", file_name, "' AND machine_id=", hostid), con)
  
  if(nrow(ids) > 1) {
    logger.warn("multiple ids found for", file, "returned; using the first one found")
    invisible(ids[1, 'container_id'])
  } else if (nrow(ids) == 1) {
    invisible(ids[1, 'container_id'])
  } else {
    logger.warn("no id found for", file, "in database")
    invisible(NA)
  }
}
