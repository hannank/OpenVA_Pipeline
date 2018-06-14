import subprocess
import pandas as pd
import numpy as np

class SmartVA(object):
    """Run SmartVA and store results for further processing in Pipeline."""
    
    def __init__(self, country, hiv, malaria, hce, freetext, figures, language, inFile, outDir):
        self.country  = country
        self.hiv      = hiv
        self.malaria  = malaria
        self.hce      = hce
        self.freetext = freetext
        self.figures  = figures
        self.language = language
        self.inFile   = inFile
        self.outDir   = outDir

    def cli(self):

        """Run SmartVA with arguments supplied by user and return a subprocess.Popen() object."""

        svaArgs = ["./smartva", "--country", "{}".format(self.country), "--hiv", "{}".format(self.hiv),
                   "--malaria", "{}".format(self.malaria), "--hce", "{}".format(self.hce),
                   "--freetext", "{}".format(self.freetext), "--figures", "{}".format(self.figures),
                   "--language", "{}".format(self.language), self.inFile, self.outDir]
        process = subprocess.Popen(svaArgs, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return process

class FormatSVA(object):
    """Format SmartVA output for DHIS2 Verbal Autopsy Program"""

    def __init__(self, dataDir, outDir, metadataAlgorithmCode):
        self.dataDir = dataDir
        self.outDir  = outDir
        self.code    = metadataAlgorithmCode

    def va_to_csv(self):
        """Write two CSV files: (1) Entity Value Attribute blob pushed to DHIS2 (entityAttributeValue.csv)
                                (2) table for transfer database (recordStorage.csv)

           Both CSV files are stored in the SmartVA Output folder."""

        dfData    = pd.read_csv(self.dataDir + "/vaReadyFile.csv")
        dfResults = pd.read_csv(self.outDir + "/1-individual-cause-of-death/individual-cause-of-death.csv")
        codeDF    = pd.DataFrame(np.repeat(self.code, dfResults.shape[0]), columns=["metadataCode"])
        dfResults = pd.concat([dfResults, codeDF], axis=1)
        

        ## Dataframe for transfer database
        colsKeep = ["sex", "birth_date", "death_date", "age", "cause34", "metadataCode", "sid"]
        dfRecordStorage = pd.merge(left=dfResults[colsKeep], left_on="sid", right=dfData, right_on="Generalmodule-sid", how="right")
        dfRecordStorage.drop(columns="sid", inplace=True)
        dfRecordStorage.insert(loc=0, column="ID", value=dfRecordStorage["meta-instanceID"])

        dfRecordStorage.to_csv(self.outDir + "/recordStorage.csv", index=False)

        ## dfEVA.shape
        colsKeep = ["sid", "cause34", "metadataCode"]
        dfTemp   = pd.merge(left=dfResults[colsKeep], left_on="sid", right=dfData, right_on="Generalmodule-sid", how="right")
        dfTemp.dropna(subset=["cause34"])
        dfTemp.drop(columns="sid", inplace=True)
        dfTemp["ID"] = dfTemp["meta-instanceID"]
        dfEVA = dfTemp.melt(id_vars=["ID"], var_name="Attribute", value_name="Value")
        dfEVA.sort_values(by=["ID"], inplace=True)
        dfEVA.to_csv(self.outDir + "/entityAttributeValue.csv", index=False)
