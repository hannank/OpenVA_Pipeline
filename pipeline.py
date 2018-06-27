#-------------------------------------------------------------------------------------------------------------------------------------------#
#  openVA Pipeline: pipeline.py -- Software for processing Verbal Autopsy data with automated cause of death assignment.                    #
#  Copyright (C) 2018  Jason Thomas, Samuel Clark, Martin Bratschi in collaboration with the Bloomberg Data for Health Initiative           #
#                                                                                                                                           #
#  This program is free software: you can redistribute it and/or modify                                                                     #
#  it under the terms of the GNU General Public License as published by                                                                     #
#  the Free Software Foundation, either version 3 of the License, or                                                                        #
#  (at your option) any later version.                                                                                                      #
#                                                                                                                                           #
#  This program is distributed in the hope that it will be useful,                                                                          #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of                                                                           #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                                                                            #
#  GNU General Public License for more details.                                                                                             #
#                                                                                                                                           #
#  You should have received a copy of the GNU General Public License                                                                        #
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.                                                                    #
#                                                                                                                                           #
#-------------------------------------------------------------------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------------------------------------------------------------------#
# User Settings
sqlitePW = "enilepiP"  
dbName = "Pipeline.db" 
#-------------------------------------------------------------------------------------------------------------------------------------------#

from pysqlcipher3 import dbapi2 as sqlcipher
from pandas import read_csv, groupby
import pandas as pd
import sys
import csv
import datetime
import os
import subprocess
import shutil
import requests
import json
import sqlite3
import time
import re
import pickle

#-------------------------------------------------------------------------------------------------------------------------------------------#
# Define functions and objects needed for functioning of pipeline; then set up log files and configuration of pipeline
#-------------------------------------------------------------------------------------------------------------------------------------------#

class Dhis(object):
    """Access DHIS2 API."""

    def __init__(self, dhisURL, dhisUser, dhisPass):
        if '/api' in dhisURL:
            print('Please do not specify /api/ in the server argument: e.g. --server=play.dhis2.org/demo')
            sys.exit()
        if dhisURL.startswith('localhost') or dhisURL.startswith('127.0.0.1'):
            dhisURL = 'http://{}'.format(dhisURL)
        elif dhisURL.startswith('http://'):
            dhisURL = dhisURL
        elif not dhisURL.startswith('https://'):
            dhisURL = 'https://{}'.format(dhisURL)
        self.auth = (dhisUser, dhisPass)
        self.url = '{}/api/25'.format(dhisURL)

    def get(self, endpoint, params=None):
        """
        GET method for DHIS2 API.
        :rtype: dict
        """
        url = '{}/{}.json'.format(self.url, endpoint)
        if not params:
            params = {}
        params['paging'] = False
        try:
            r = requests.get(url=url, params=params, auth=self.auth)
            if r.status_code != 200:
                print("HTTP Code: {}".format(r.status_code)) ## HERE
                print(r.text)
            else:
                return r.json()
        except requests.RequestException:
            raise requests.RequestException

    def post(self, endpoint, data):
        """
        POST  method for DHIS2 API.
        :rtype: dict
        """
        url = '{}/{}.json'.format(self.url, endpoint)
        try:
            r = requests.post(url=url, json=data, auth=self.auth)
            if r.status_code not in range(200, 206):
                print("HTTP Code: {}".format(r.status_code)) ## HERE
                print(r.text)
            else:
                return r.json()
        except requests.RequestException:
            raise requests.RequestException

    def post_blob(self, f):
        """ Post file to DHIS2 and return created UID for that file
        :rtype: str
        """
        url = '{}/fileResources'.format(self.url)
        files = {'file': (f, open(f, 'rb'), 'application/x-sqlite3', {'Expires': '0'})}
        try:
            r = requests.post(url, files=files, auth=self.auth)
            if r.status_code not in (200, 202):
                print("HTTP Code: {}".format(r.status_code)) ## HERE
                print(r.text)
            else:
                response = r.json()
                file_id = response['response']['fileResource']['id']
                return file_id

        except requests.RequestException:
            raise requests.RequestException

class VerbalAutopsyEvent(object):
    """ DHIS2 event + a BLOB file resource"""

    def __init__(self, va_id, program, dhis_orgunit, event_date, sex, dob, age, cod_code, algorithm_metadata, file_id):
        self.va_id = va_id
        self.program = program
        self.dhis_orgunit = dhis_orgunit
        self.event_date = event_date
        self.sex = sex
        self.dob = dob
        self.age = age
        self.cod_code = cod_code
        self.algorithm_metadata = algorithm_metadata

        self.datavalues = [
            {"dataElement": "htm6PixLJNy", "value": self.va_id},
            {"dataElement": "hi7qRC4SMMk", "value": self.sex},
            {"dataElement": "mwSaVq64k7j", "value": self.dob},
            {"dataElement": "F4XGdOBvWww", "value": self.cod_code},
            {"dataElement": "wiJviUqN1io", "value": self.algorithm_metadata},
            {"dataElement": "oPAg4MA0880", "value": self.age},
            {"dataElement": "XLHIBoLtjGt", "value": file_id}

        ]

    def format_to_dhis2(self, dhisUser):
        """
        Format object to DHIS2 compatible event for DHIS2 API
        :rtype: dict
        """
        event = {
            "program": self.program,
            "orgUnit": self.dhis_orgunit,
            "eventDate": datetime.datetime.strftime(self.event_date, '%Y-%m-%d'),
            "status": "COMPLETED",
            "storedBy": dhisUser,
            "dataValues": self.datavalues
        }
        return event

    def __str__(self):
        return json.dumps(self, default=lambda o: o.__dict__)

def create_db(fName, evaList):
    """
    Create a SQLite database with VA data + COD
    :rtype: None
    """
    conn = sqlite3.connect(fName)
    with conn:
        cur = conn.cursor()
        cur.execute("CREATE TABLE vaRecord(ID INT, Attrtibute TEXT, Value TEXT)")
        cur.executemany("INSERT INTO vaRecord VALUES (?,?,?)", evaList)

def getCODCode(myDict, searchFor):
    for i in range(len(myDict.keys())):
        match = re.search(searchFor, list(myDict.keys())[i])
        if match:
            return list(myDict.values())[i]

# set the ODK_Conf table item odkLastRunResult as 0, log error message, and exit script
def cleanup(errorMsg):
    # handle single case when DB file not found
    if connectionError == "1":
        with open(connectionErrorFile, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([timeFMT, "Unable to Connect to SQLite Database, see {} for details".format(errorFile)])
        sys.exit(1)
    else:
        # update ODK_Conf table with LastRunResult = 0
        try:
            sql = "UPDATE ODK_Conf SET odkLastRunResult = ?"
            par = ("0",)
            cursor.execute(sql, par)
            db.commit()
            if os.path.isfile(connectionErrorFile) == True:
                try:
                    os.remove(connectionErrorFile)
                except OSError:
                    print("Could not remove {}".format(connectionErrorFile))
        # write errorMsg to errorFile if DB is inaccessible
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError):
            db.rollback()
            errorMsg[2] += "; unable to set odkLastRunResult to 0 (in ODK_Conf table)"
            try:
                with open(errorFile, "a", newline="") as f:
                    writer = csv.writer(f)
                    writer.writerow(errorMsg)
            except OSError:
                print(errorMsg)
        # close DB resources and exit script
        finally:
            cursor.close()
            db.close()    
            sys.exit(1)

def findKeyValue(key, d):
    if key in d:
        yield d[key]
    for k in d:
        if isinstance(d[k], list):
            for i in d[k]:
                for j in findKeyValue(key, i):
                    yield j

# error log files
errorFile = "./dbErrorLog.csv"
timeFMT = datetime.datetime.now().strftime("%Y-%m-%d_%H:%M:%S")
connectionError = "0"
connectionErrorFile = "./sqlConnect.csv"

## create error file if it does not exist
if os.path.isfile(errorFile) == False:
    try:
        with open(errorFile, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Date"] + ["Description"] + ["Additional Information"])
    except (OSError) as e:
        print(str(e))
        sys.exit(1)

# connect to the database and configure the pipeline's settings for ODK Aggregate, openVA, and DHIS2.
if os.path.isfile(dbName) == False:
    connectionError = "1"
    with open(errorFile, "a", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([timeFMT, "Database {}.db not found".format(dbName), ])
    cleanup()

db = sqlcipher.connect(dbName)
db.execute("PRAGMA key = " + sqlitePW)
sqlODK                = "SELECT odkID, odkURL, odkUser, odkPass, odkFormID, odkLastRun, odkLastRunResult FROM ODK_Conf"
sqlPipeline           = "SELECT workingDirectory, openVA_Algorithm, algorithmMetadataCode, codSource FROM Pipeline_Conf"
sqlInterVA4           = "SELECT HIV, Malaria FROM InterVA4_Conf"
sqlAdvancedInterVA4   = "SELECT directory, filename, output, append, groupcode, replicate, replicate_bug1, replicate_bug2, write FROM Advanced_InterVA4_Conf"
sqlInSilicoVA         = "SELECT Nsim FROM InSilicoVA_Conf"
sqlAdvancedInSilicoVA = "SELECT isNumeric, updateCondProb, keepProbbase_level, CondProb, CondProbNum, datacheck, datacheck_missing," \
                          + "warning_write, external_sep, thin, burnin, auto_length, conv_csmf, jump_scale,"                  \
                          + "levels_prior, levels_strength, trunc_min, trunc_max, subpop, java_option, seed,"                 \
                          + "phy_code, phy_cat, phy_unknown, phy_external, phy_debias, exclude_impossible_cause, indiv_CI "   \
                          + "FROM Advanced_InSilicoVA_Conf"
sqlDHIS               = "SELECT dhisURL, dhisUser, dhisPass, dhisOrgUnit FROM DHIS_Conf"
sqlCODCodes_WHO       = "SELECT codName, codCode FROM COD_Codes_DHIS WHERE codSource = 'WHO'"
sqlCODCodes_Tariff    = "SELECT codName, codCode FROM COD_Codes_DHIS WHERE codSource = 'Tariff'"

## grab configuration settings from SQLite DB
try:
    # ODK configuration
    cursor = db.cursor()
    cursor.execute(sqlODK)
    odkQuery = cursor.fetchall()
    for row in odkQuery:
        odkID              = row[0]
        odkURL             = row[1]
        odkUser            = row[2]
        odkPass            = row[3]
        odkFormID          = row[4]
        odkLastRun         = row[5]
        odkLastRunDate     = datetime.datetime.strptime(odkLastRun, "%Y-%m-%d_%H:%M:%S").strftime("%Y/%m/%d")
        odkLastRunDatePrev = (datetime.datetime.strptime(odkLastRunDate, "%Y/%m/%d") - datetime.timedelta(days=1)).strftime("%Y/%m/%d")
        odkLastRunResult   = row[6]
    # Pipeline configuration
    cursor.execute(sqlPipeline)
    pipelineQuery = cursor.fetchall()
    for row in pipelineQuery:
        processDir             = row[0]
        pipelineAlgorithm      = row[1]
        algorithmMetadataCode  = row[2]
        codSource              = row[3]
    # InterVA4 configuration
    cursor.execute(sqlInterVA4)
    interVA4Query = cursor.fetchall()
    for row in interVA4Query:
        interVA_HIV     = row[0]
        interVA_Malaria = row[1]
    # InterVA4 advanced configuration
    cursor.execute(sqlAdvancedInterVA4)
    advancedInterVA4Query = cursor.fetchall()
    for row in advancedInterVA4Query:
        interVA_directory      = row[0]
        interVA_filename       = row[1]
        interVA_output         = row[2]
        interVA_append         = row[3]
        interVA_groupcode      = row[4]
        interVA_replicate      = row[5]
        interVA_replicate_bug1 = row[6]
        interVA_replicate_bug2 = row[7]
        interVA_write          = row[8]
    # InSilicoVA configuration
    cursor.execute(sqlInSilicoVA)
    insilicoVAQuery = cursor.fetchall()
    for row in insilicoVAQuery:
        insilico_Nsim = row[0]
    # InSilicoVA advanced configuration
    cursor.execute(sqlAdvancedInSilicoVA)
    advancedInsilicoVAQuery = cursor.fetchall()
    for row in advancedInsilicoVAQuery:
        insilico_isNumeric                = row[ 0]
        insilico_updateCondProb           = row[ 1]
        insilico_keepProbbase_level       = row[ 2]
        insilico_CondProb                 = row[ 3]
        insilico_CondProbNum              = row[ 4]
        insilico_datacheck                = row[ 5]
        insilico_datacheck_missing        = row[ 6]
        insilico_warning_write            = row[ 7]
        insilico_external_sep             = row[ 8]
        insilico_thin                     = row[ 9]
        insilico_burnin                   = row[10]
        insilico_auto_length              = row[11]
        insilico_conv_csmf                = row[12]
        insilico_jump_scale               = row[13]
        insilico_levels_prior             = row[14]
        insilico_levels_strength          = row[15]
        insilico_trunc_min                = row[16]
        insilico_trunc_max                = row[17]
        insilico_subpop                   = row[18]
        insilico_java_option              = row[19]
        insilico_seed                     = row[20]
        insilico_phy_code                 = row[21]
        insilico_phy_cat                  = row[22]
        insilico_phy_unknown              = row[23]
        insilico_phy_external             = row[24]
        insilico_phy_debias               = row[25]
        insilico_exclude_impossible_cause = row[26]
        insilico_indiv_CI                 = row[27]
    # DHIS2 configuration
    cursor.execute(sqlDHIS)
    dhisQuery = cursor.fetchall()
    for row in dhisQuery:
        dhisURL     = row[0]
        dhisUser    = row[1]
        dhisPass    = row[2]
        dhisOrgUnit = row[3]
    # CoD Codes for DHIS2
    cursor.execute(sqlCODCodes_WHO)
    resultsWHO = cursor.fetchall()
    codesWHO   = dict(resultsWHO)
    cursor.execute(sqlCODCodes_Tariff)
    resultsTariff = cursor.fetchall()
    codesTariff   = dict(resultsTariff) 
except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
    try:
        sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
        par = ("Problem selecting config information from ODK_Conf ", str(e), timeFMT)
        cursor.execute(sql, par)
        db.commit()
    except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
        db.rollback()
    errorMsg = [timeFMT, str(e), "Problem selecting config information from ODK_Conf"]
    cleanup(errorMsg)

#-------------------------------------------------------------------------------------------------------------------------------------------#
# create folders & files to store (ODK & openVA) input and output; also create call to ODK Briefcase 
#-------------------------------------------------------------------------------------------------------------------------------------------#
odkBCExportDir      = processDir + "/ODKExport"
odkBCExportFilename = "ODKExportNew.csv"
odkBCExportPrevious = odkBCExportDir   + "/ODKExportPrevious.csv"
odkBCExportNewFile  = odkBCExportDir   + "/" + odkBCExportFilename
odkBCArgumentList   = "java -jar ODK-Briefcase-v1.10.1.jar -oc -em -id '" + odkFormID + "' -sd '" + odkBCExportDir + "' -ed '" \
                      + odkBCExportDir + "' -f '" + odkBCExportFilename + "' -url '" + odkURL + "' -u '" + odkUser \
                      + "' -p '" + odkPass + "' -start '" + odkLastRunDatePrev + "'"
openVAFilesDir      = processDir + "/OpenVAFiles"
openVAReadyFile     = odkBCExportDir   + "/OpenVAReadyFile.csv"
rScriptIn           = openVAFilesDir   + "/" + timeFMT + "/RScript_" + timeFMT + ".R"
rScriptOut          = openVAFilesDir   + "/" + timeFMT + "/RScript_" + timeFMT + ".Rout"
dhisDir             = processDir + "/DHIS2"
if codSource=="WHO":
    dhisCODCodes = codesWHO
else:
    dhisCODCodes = codesTariff

# check if processing directory exists and create if necessary 
if not os.path.exists(processDir):
    try:
        os.makedirs(processDir)
    except OSError as e:
        sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
        par = ("Could not create processing directory: " + processDir, str(e), timeFMT)
        try:
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Could not create processing directory: " + processDir]
        cleanup(errorMsg)

# create openVAFilesDir (if does not exist)
if not os.path.exists(openVAFilesDir + "/" + timeFMT):
    try:
        os.makedirs(openVAFilesDir + "/" + timeFMT)
    except OSError as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Could not create openVA Directory: " + openVAFilesDir + "/" + timeFMT, str(e), timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Could not create openVA directory: " + openVAFilesDir + "/" + timeFMT]
        cleanup(errorMsg)

# make a copy of current ODK Briefcase Export file, to compare with new file once exported (if there is an existing export file)
if os.path.isfile(odkBCExportNewFile) == True and odkLastRunResult == 1 and not os.path.isfile(connectionErrorFile):
    try:
        shutil.copy(odkBCExportNewFile, odkBCExportPrevious)
    except (OSError, shutil.Error) as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Error: Trying to copy export files from ODK Briefcase", str(e), timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Error: Trying to copy export files from ODK Briefcase"]
        cleanup(errorMsg)
    try:
        os.remove(openVAReadyFile)
    except (OSError) as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime)"
            par = ("Could not remove " + openVAReadyFile, str(e), timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Could not remove " + openVAReadyFile]
        cleanup(errorMsg)

# launch ODK Briefcase to collect ODK Aggregate data and export to file for further processing
try:
    process = subprocess.Popen(odkBCArgumentList, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout, stderr = process.communicate()
    rc = process.returncode
except:
    try:
        sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
        par = ("Could not launch ODK Briefcase Java Application", "Error", timeFMT)
        cursor.execute(sql, par)
        db.commit()
    except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
        db.rollback()
    errorMsg = [timeFMT, "Error: Could not launch ODK Briefcase Java Application",""]
    cleanup(errorMsg)

# catch application errors from ODK Briefcase and log into EventLog table
if rc != 0:
    try:
        sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
        par = (str(stderr), "Error", timeFMT)
        cursor.execute(sql, par)
        db.commit()
    except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
        db.rollback()
    errorMsg = [timeFMT, str(stderr),""]
    cleanup(errorMsg)
if "SEVERE" in str(stderr):
    try:
        sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
        par = (stderr,"Error", timeFMT)
        cursor.execute(sql, par)
        db.commit()
    except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
        db.rollback()
    errorMsg = [timeFMT, str(stderr),""]
    cleanup(errorMsg)
else:
    try:
        sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
        par = ("Briefcase Export Completed Successfully", "Information", timeFMT)
        cursor.execute(sql, par)
        db.commit()
        sql = "UPDATE ODK_Conf SET odkLastRun=?, odkLastRunResult=?"
        par = (timeFMT,"1")
        cursor.execute(sql, par)
        db.commit()
    except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
        db.rollback()
        errorMsg = [timeFMT, str(e), "ODK Briefcase ran successfully but problems writing to DB (check odkLastRunResult in ODK_Conf)"]
        cleanup(errorMsg)

    # check if previous file exists from above operations and create delta file of new entries
    if os.path.isfile(odkBCExportPrevious) == True:
        try:
            ## WARNING: odkBCExportPrevious & odkBCExportNewFil (CSV files)
            ##          contain sensitive VA information (leaving them in folder)
            with open(odkBCExportPrevious, "r", newline="") as t1, open(odkBCExportNewFile, "r", newline="") as t2:
                fileone = t1.readlines()
                filetwo = t2.readlines()
                header = filetwo[0]
            with open(openVAReadyFile, "w", newline="") as outFile:
                outFile.write(header)
                for line in filetwo:
                    if line not in fileone:
                        outFile.write(line)
        except OSError as e:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES"
                par = ("Could not create: " + openVAReadyFile, "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, str(e), "Error: Could not create: " + openVAReadyFile]
            cleanup(errorMsg)
    else:
        # if there is no pre-existing ODK Briefcase Export file, then copy and rename to OpenVAReadyFile.csv
        try:
            shutil.copy(odkBCExportNewFile, openVAReadyFile)
        except (OSError, shutil.Error) as e:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                par = (e, "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, str(e), "Error: Could not copy: " + odkBCExportNewFile + " to: " + openVAReadyFile]
            cleanup(errorMsg)

    # if no records retrieved, then close up shop; otherwise, create R script for running openVA
    ## WARNING: openVAReadyFile (CSV file) contains sensitive VA information (leaving it in folder)
    outFile  = pd.read_csv(openVAReadyFile)
    nRecords = outFile.shape[0]

    if nRecords == 0:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("No Records From ODK Briefcase (nothing more to do)", "Information", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
            errorMsg = [timeFMT, str(e), "No records from ODK Briefcase, but error writing to DB"]
            cleanup(errorMsg)
        try:
            sql = "UPDATE ODK_Conf SET odkLastRun=?, odkLastRunResult=?"
            par = (timeFMT,"1")
            cursor.execute(sql, par)
            db.commit()
            cursor.close()
            db.close()
            sys.exit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
            errorMsg = [timeFMT, str(e),
                        "No records from ODK Briefcase, but error writing to DB (trying to set odkLastRun & odkLastRunResult)."]
            cleanup(errorMsg)

    try:
        with open(rScriptIn, "w", newline="") as f:
            f.write("date() \n")
            f.write("library(openVA); library(CrossVA) \n")
            f.write("getwd() \n")
            f.write("records <- read.csv('" + openVAReadyFile + "') \n")
            # InSilicoVA
            if pipelineAlgorithm == "InSilicoVA":
                f.write("names(data) <- tolower(data) \n")
                f.write("data <- map_records_insilicova(records) \n")
                ## assign ID from survey (odkID) if specified, otherwise use uuid from ODK Aggregate
                if odkID == None:
                    f.write("data$ID <- records$meta.instanceID \n")
                else: 
                    f.write("data$ID <- records$" + odkID + "\n")
                f.write("results <- insilico(data=data, " + ", \n")
                f.write("\t isNumeric=" + insilico_isNumeric + ", \n")
                f.write("\t updateCondProb=" + insilico_updateCondProb + ", \n")
                f.write("\t keepProbbase.level=" + insilico_keepProbbase_level + ", \n")
                f.write("\t CondProb=" + insilico_CondProb + ", \n")
                f.write("\t CondProbNum=" + insilico_CondProbNum + ", \n")
                f.write("\t datacheck=" + insilico_datacheck + ", \n")
                f.write("\t datacheck.missing=" + insilico_datacheck_missing + ", \n")
                f.write("\t warning.write=" + insilico_warning_write + ", \n")
                f.write("\t external.sep=" + insilico_external_sep + ", \n")
                f.write("\t Nsim=" + insilico_Nsim + ", \n")
                f.write("\t thin=" + insilico_thin + ", \n")
                f.write("\t burnin=" + insilico_burnin + ", \n")
                f.write("\t auto.length=" + insilico_auto_length + ", \n")
                f.write("\t conv.csmf=" + insilico_conv_csmf + ", \n")
                f.write("\t jump.scale=" + insilico_jump_scale + ", \n")
                f.write("\t levels.prior=" + insilico_levels_prior + ", \n")
                f.write("\t levels.strength=" + insilico_levels_strength + ", \n")
                f.write("\t trunc.min=" + insilico_trunc_min + ", \n")
                f.write("\t trunc.max=" + insilico_trunc_max + ", \n")
                f.write("\t subpop=" + insilico_subpop + ", \n")
                f.write("\t java.option=" + insilico_java_option + ", \n")
                f.write("\t seed=" + insilico_seed + ", \n")
                f.write("\t phy.code=" + insilico_phy_code + ", \n")
                f.write("\t phy.cat=" + insilico_phy_cat + ", \n")
                f.write("\t phy.unknown=" + insilico_phy_unknown + ", \n")
                f.write("\t phy.external=" + insilico_phy_external + ", \n")
                f.write("\t phy.debias=" + insilico_phy_debias + ", \n")
                f.write("\t exclude.impossible.cause=" + insilico_exclude_impossible_cause + ", \n")
                f.write("\t indiv.CI=" + insilico_indiv_CI + ") \n")
                f.write("sex <- ifelse(tolower(data$male)=='y', 'Male', 'Female') \n")
            # InterVA
            if pipelineAlgorithm == "InterVA":
                f.write("data <- map_records_interva4(records) \n")
                ## assign ID from survey (odkID) if specified, otherwise use uuid from ODK Aggregate
                if odkID == None:
                    f.write("data$ID <- records$meta.instanceID \n")
                else: 
                    f.write("data$ID <- records$" + odkID + "\n")
                f.write("results <- InterVA(Input=data, \n")
                f.write("\t HIV= '" + interVA_HIV + "', \n")
                f.write("\t Malaria = '" + interVA_Malaria + "', \n")
                f.write("\t output='" + interVA_output + "', \n")
                f.write("\t groupcode=" + interVA_groupcode + ", \n")
                f.write("\t replicate=" + interVA_replicate + ", \n")
                f.write("\t replicate.bug1=" + interVA_replicate_bug1 + ", \n")
                f.write("\t replicate.bug2=" + interVA_replicate_bug2 + ", \n")
                f.write("\t write=FALSE) \n")
                f.write("sex <- ifelse(tolower(data$MALE)=='y', 'Male', 'Female') \n")
            # write results
            f.write("cod <- getTopCOD(results) \n")
            f.write("hasCOD <- as.character(data$ID) %in% as.character(levels(cod$ID)) \n")
            f.write("dob <- as.Date(as.character(records$consented.deceased_CRVS.info_on_deceased.Id10021), '%b %d, %Y') \n") ## HERE -- not sure if date format will vary!
            f.write("dod <- as.Date(as.character(records$consented.deceased_CRVS.info_on_deceased.Id10023), '%b %d, %Y') \n") ## HERE -- not sure if date format will vary!
            f.write("age <- floor(records$consented.deceased_CRVS.info_on_deceased.ageInDays/365.25) \n")
            f.write("## create matrices for DHIS2 blob (data2) and transfer database (data3) \n")
            f.write("## first column must be ID \n")
            f.write("metadataCode <- '" + algorithmMetadataCode + "'\n")
            f.write("cod2 <- rep('MISSING', nrow(data)); cod2[hasCOD] <- as.character(cod[,2]) \n")
            f.write("data2 <- cbind(data[,-1], cod2, metadataCode) \n")
            f.write("names(data2) <- c(names(data[,-1]), 'Cause of Death', 'Metadata') \n")
            f.write("evaBlob <- cbind(rep(as.character(data[,1]), each=ncol(data2)), rep(names(data2)), c(apply(data2, 1, c))) \n")
            f.write("colnames(evaBlob) <- c('ID', 'Attribute', 'Value') \n")
            f.write("write.csv(evaBlob, file='" + openVAFilesDir + "/entityAttributeValue.csv', row.names=FALSE, na='') \n\n")
            f.write("data3 <- cbind(as.character(data[,1]), sex, dob, dod, age, cod2, metadataCode, data[,-1]) \n")
            f.write("names(data3) <- c('id', 'sex', 'dob', 'dod', 'age', 'cod', 'metadataCode', names(data[,-1])) \n")
            f.write("write.csv(data3, file='" + openVAFilesDir + "/recordStorage.csv', row.names=FALSE, na='') \n")
    except OSError as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Could not create R Script File","Error", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Error: Could not create R Script File"]
        cleanup(errorMsg)

    # run R script
    rBatch = "R CMD BATCH --vanilla " + rScriptIn + " " + rScriptOut
    rprocess = subprocess.Popen(rBatch, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout, stderr = rprocess.communicate()
    rrc = rprocess.returncode
    if rrc != 0:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Could not run R Script", str(stderr), timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, "Error: Could not run R Script", str(stderr)]
        cleanup(errorMsg)
    else:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("OpenVA Analysis Completed Successfully", "Information", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
            errorMsg = [timeFMT, str(e), "OpenVA Analysis Completed Successfully (error committing message to database)."]
            cleanup(errorMsg)

    # push results to DHIS2
    try:
        api = Dhis(dhisURL, dhisUser, dhisPass)
    except (requests.RequestException) as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Unable to connect to DHIS2", str(e), timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Error: Unable to connect to DHIS2"]
        cleanup(errorMsg)

    # verify VA program and orgUnit
    try:
        vaPrograms   = api.get("programs", params={"filter": "name:like:Verbal Autopsy"}).get("programs")
        orgUnitValid = len(api.get("organisationUnits", params={"filter": "id:eq:{}".format(dhisOrgUnit)})["organisationUnits"])==1 

        if not orgUnitValid:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                par = ("Organisation Unit UID could not be found.", "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, "Error: Organisation Unit UID could not be found.", "Error committing message to database"]
            cleanup(errorMsg)

        if not vaPrograms:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                par = ("'Verbal Autopsy' program not found", "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, "Error: 'Verbal Autopsy' program not found.", "Error committing message to database"]
            cleanup(errorMsg)

        elif len(vaPrograms) > 1:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                par = ("More than one 'Verbal Autopsy' found.", "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, "Error: More than one 'Verbal Autopsy' found.", "Error committing message to database"]
            cleanup(errorMsg)
    except:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Error using Dhis.get, unable to either get UID for VA Program or verify Org Unit ID", "Error", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, "Error: Error using Dhis.get, unable to either get UID for VA Program or verify Org Unit ID",
                    "Error committing message to database"]
        cleanup(errorMsg)

    vaProgramUID = vaPrograms[0]["id"]

    blobPath = os.path.join(dhisDir, "blobs")
    try:
        if not os.path.isdir(blobPath):
            os.makedirs(blobPath)
    except OSError as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Unable to create folder for DHIS blobs.", "Error", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Error: Unable to create folder for DHIS blobs."]
        cleanup(errorMsg)

    events = []
    export = {}

    ## read in VA data (with COD and algorithm metadata) from csv's (and create groups by ID for Entity-Attribute-Value file)
    try:
        ## WARNING: The following CSV file contains sensitive VA information (leaving it in folder)!
        dfDHIS2   = pd.read_csv(openVAFilesDir + "/entityAttributeValue.csv")
    except:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Unable to access file: " + openVAFilesDir + "entityAttributeVAlue.csv", "Error", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, "Unable to access file: " + openVAFilesDir + "entityAttributeVAlue.csv",
                    "Error committing message to database"]
        cleanup(errorMsg)

    grouped   = dfDHIS2.groupby(["ID"])
    
    ## prepare events for DHIS2 export
    try:
        with open(openVAFilesDir + "/recordStorage.csv", "r", newline="") as csvIn:
            with open(openVAFilesDir + "/newStorage.csv", "w", newline="") as csvOut:
                reader = csv.reader(csvIn)
                writer = csv.writer(csvOut, lineterminator="\n")

                header = next(reader)
                header.extend(["dhisVerbalAutopsyID", "pipelineOutcome"])
                writer.writerow(header)

                for row in reader:
                    if row[5]!="MISSING":

                        vaID = str(row[0])
                        blobFile = "{}.db".format(os.path.join(dhisDir, "blobs", vaID))
                        blobRecord = grouped.get_group(str(row[0]))
                        blobEVA = blobRecord.values.tolist()

                        ## create DHIS2 blob
                        try:
                            create_db(blobFile, blobEVA)
                        except:
                            try:
                                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                                par = ("Unable to create DHIS2 BLOB", "Error", timeFMT)
                                cursor.execute(sql, par)
                                db.commit()
                            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                                db.rollback()
                            errorMsg = [timeFMT, "Unable to create DHIS2 BLOB", "Error committing message to database"]
                            cleanup(errorMsg)

                        ## post DHIS2 blob
                        try:
                            fileID = api.post_blob(blobFile)
                        except requests.RequestException as e:
                            try:
                                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                                par = ("Unable to post BLOB to DHIS2", str(e), timeFMT)
                                cursor.execute(sql, par)
                                db.commit()
                            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                                db.rollback()
                            errorMsg = [timeFMT, str(e), "Unable to post BLOB to DHIS2"]
                            cleanup(errorMsg)

                        sex = row[1].lower()
                        dob = row[2]
                        if row[3] =="":
                            eventDate = datetime.date(9999,9,9)
                        else:
                            dod       = datetime.datetime.strptime(row[3], "%Y-%m-%d")
                            eventDate = datetime.date(dod.year, dod.month, dod.day)
                        age = row[4]
                        if row[5] == "Undetermined":
                            codCode = "99"
                        else:
                            codCode = getCODCode(dhisCODCodes, row[5])

                        e = VerbalAutopsyEvent(vaID, vaProgramUID, dhisOrgUnit,
                                                eventDate, sex, dob, age, codCode, algorithmMetadataCode, fileID)
                        events.append(e.format_to_dhis2(dhisUser))

                        row.extend([vaID, "Pushing to DHIS2"])
                        writer.writerow(row)
                    else:
                        row.extend(["", "No CoD Assigned"])
                        writer.writerow(row)
    except:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Unable to access one of record/newStorage.csv files in folder: " + openVAFilesDir, "Error", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, "Unable to access one of record/newStorage.csv files in folder: " + openVAFilesDir,
                    "Error committing message to database"]
        cleanup(errorMsg)

    export["events"] = events

    try:
        log = api.post("events", data=export)
    except requests.RequestException as e:
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Unable to post events to DHIS2 VA Program.", str(e), timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, str(e), "Unable to post events to DHIS2 VA Program."]
        cleanup(errorMsg)

    if 'importSummaries' not in log['response'].keys():
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Failed to retrieve summary from post to DHIS2 VA Program.", "Error", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
        errorMsg = [timeFMT, "Error", "Failed to retrieve summary from post to DHIS2 VA Program."]
        cleanup(errorMsg)

    if log["httpStatusCode"] == 200:
        nPosted = len(log['response']['importSummaries'])

        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Successfully posted {} events to DHIS2 VA Program.".format(nPosted), "Information", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
            errorMsg = [timeFMT, str(e), "Successfully posted {} events to DHIS2 VA Program, but error writing to DB".format(nPosted)]
            cleanup(errorMsg)
        
        vaReferences = list(findKeyValue("reference", d=log["response"]))
        dfNewStorage = pd.read_csv(openVAFilesDir + "/newStorage.csv")

        try:
            for vaReference in vaReferences:
                postedDataValues = api.get("events/{}".format(vaReference)).get("dataValues")
                postedVAIDIndex  = next((index for (index, d) in enumerate(postedDataValues) if d["dataElement"]=="htm6PixLJNy"), None)
                postedVAID       = postedDataValues[postedVAIDIndex]["value"]
                rowVAID          = dfNewStorage["dhisVerbalAutopsyID"] == postedVAID
                dfNewStorage.loc[rowVAID,"pipelineOutcome"] = "Pushed to DHIS2"
        except:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                par = ("Error trying to verify events posted to DHIS2", "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, "Error trying to verify events posted to DHIS2", ""]
            cleanup(errorMsg)

        # store results in database
        try:
            for row in dfNewStorage.itertuples():
                xferDBID      = row[1]
                xferDBOutcome = row[254]
                vaData        = row[1],row[8:253]
                vaDataFlat    = tuple([y for x in vaData for y in (x if isinstance(x, tuple) else (x,))])
                xferDBRecord  = pickle.dumps(vaDataFlat)
                sqlXferDB = "INSERT INTO VA_Storage (id, outcome, record, dateEntered) VALUES (?,?,?,?)"
                par       = [xferDBID, xferDBOutcome, sqlite3.Binary(xferDBRecord), timeFMT]
                cursor.execute(sqlXferDB, par)
                db.commit()
                ## note: to read back in: (1) cursor.exetute(SQL SELECT STATEMENT) (2) results = pickle.loads(sqlResult[0])

                ## An alternative version of storing VA records to SQLite DB(not relying on pickle)
                # for row in dfNewStorage.itertuples():
                #     xferDBID      = row[1]
                #     xferDBOutcome = row[254]
                #     with open("xferDBRecord.txt", "w", newline="") as f:
                #         vaData     = row[1],row[8:253]
                #         vaDataFlat = tuple([y for x in vaData for y in (x if isinstance(x, tuple) else (x,))])
                #         writer = csv.writer(f, lineterminator="\n")            
                #         writer.writerow(vaDataFlat)
                #     with open("xferDBRecord.txt", "rb") as f:
                #         xferDBRecord = f.read()
                #     sqlXferDB = "INSERT INTO VA_Storage (id, outcome, record, dateEntered) VALUES (?,?,?,?)"
                #     par       = [xferDBID, xferDBOutcome, sqlite3.Binary(xferDBRecord), timeFMT]
                #     cursor.execute(sqlXferDB, par)
                #     db.commit()
        except:
            try:
                sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
                par = ("Error storing Blobs to {}.db".format(dbName), "Error", timeFMT)
                cursor.execute(sql, par)
                db.commit()
            except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
                db.rollback()
            errorMsg = [timeFMT, "Error storing Blobs to {}.db".format(dbName), ""]
            cleanup(errorMsg)
            
        try:
            nNewStorage = dfNewStorage.shape[0]
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Stored {} records to {}.db".format(nNewStorage, dbName), "Information", timeFMT)
            cursor.execute(sql, par)
            db.commit()
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
            errorMsg = [timeFMT, str(e),
                        "Stored {} records to {}.db, but error trying to log message to EventLog".format(nNewStorage, dbName)]
            cleanup(errorMsg)

        # all done!
        try:
            sql = "INSERT INTO EventLog (eventDesc, eventType, eventTime) VALUES (?, ?, ?)"
            par = ("Successful completion of Pipeline", "Information", str(datetime.datetime.now()))
            cursor.execute(sql, par)
            db.commit()
            cursor.close()
            db.close()
            sys.exit()            
        except (sqlcipher.Error, sqlcipher.Warning, sqlcipher.DatabaseError) as e:
            db.rollback()
            errorMsg = [timeFMT, str(e), "Finished executing Pipeline steps, but error trying to log last message."]
            cleanup(errorMsg)
            
