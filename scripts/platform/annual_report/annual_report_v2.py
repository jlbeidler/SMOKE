#!/usr/bin/env python

###############################################################
##
## Annual report script
##
## This script takes smkmerge state/province summaries and aggregates
## over them to create an annual report.
##
## It uses the mrggrid dates files for each month to determine the
## representative dates for each date that it is summing over. It also
## uses the sector list file to determine the appropriate merge approach
## (i.e. which column of the dates files to use as representative dates).
##
## This script was loosely based on the CSC's sector specific annual
## report scripts.  This new script is sector neutral, uses the dates
## files, and can add aggregate species.
##
## Author:
##      Alexis Zubrow,  UNC I.E. ,   July, 2008  initial version
## Modified for county reports - 1 Aug 2012 J. Beidler (CSC)
###############################################################

from __future__ import division
from __future__ import print_function
import csv, string, os, copy, sys
if sys.version_info[0] >= 3:
    from builtins import map
    from builtins import str
    from builtins import range
    from builtins import object
elif sys.version_info[0] == 2:
    from __builtin__ import map
    from __builtin__ import str
    from __builtin__ import range
    from __builtin__ import object


## Some functions for parseing other types of files
def parseSectorlist(fileName, sectorName, colName = "mrgapproach"):
    """
    Parses the sector list file and returns a value for a specific sector
    and column.

    Ignores additional white space and differences in capitalization.

    Inputs:
        fileName - sector list file name

        sectorName - the sector to parse out

        colName - the column to select, default is 'mrgapproach'

    Output:
       colVal - the value for that sector and col.  Typically this would
                be the merge approach to match against the merge
                dates file (ie. to pick appropriate col in merge dates)
    """
    
    ## open sector list file and read into a buffer
    f = open(os.path.expanduser(fileName), "rt")
    buffLst = f.readlines()
    f.close()
    
    ## parse the sector list file based on commas
    ## creates a reader Dictionary that can loop over
    readerDct = csv.DictReader(buffLst, skipinitialspace=True)

    firstTime = True
    
    ## loop over the reader dictionary, find the sector appropriate line
    for rowDct in readerDct:
        if firstTime:
            ## figure out what is the key for sectors
            keys = list(rowDct.keys())
            sectorKey = None
            colKey = None
            for key in keys:
                if key.upper().strip() == "SECTOR":
                    sectorKey = key
                if key.upper().strip() == colName.upper():
                    colKey = key
            if sectorKey is None:
                raise LookupError("Sector column not in sectorlist: %s" %fileName)
            if colKey is None:
                raise LookupError("Column name (%s) not in sectorlist: %s" \
                      %(colName, fileName))
            firstTime = False

        ## Check sector name, need to ignore case and spaces
        if rowDct[sectorKey].upper().strip() == sectorName.upper().strip():
            ## return the col value, strip off excess white space
            return rowDct[colKey].strip()
        
    ## if get to this point, sector is not in sectorlist:
    raise LookupError("Sector (%s) is not in sector list file: %s" \
          %(sectorName, fileName))


def parseMergeDates(fileName, mrgApproach):
    """
    Parses the merge dates file

    Inputs:
        fileName - merge dates file name

        mrgApproach - the merge approach to get appropriate col

    Outputs:
        dateLst - list of all the dates to use for this month, strings

    """

    ## open merge dates file and read into a buffer
    f = open(os.path.expanduser(fileName), "rt")
    buffLst = f.readlines()
    f.close()
    
    ## parse the merge dates file based on commas
    ## creates a reader Dictionary that can loop over
    readerDct = csv.DictReader(buffLst, skipinitialspace=True)

    try:
        dateLst = [rowDct[mrgApproach].strip() for rowDct in readerDct]
    except:
        raise LookupError("Merge approach (%s) not in merge dates file: %s" \
              %(mrgApproach, fileName))

    return dateLst


## Class definition

class AnnualReports(object):
    """
    Annual SMOKE Reports class.  Organizes all the information for
    parseing, storing, and writing out summaries of the annual
    smkmerge reports.
    """

    def __init__(self, sectorName = "", case = "", grid = "", year="",\
                 reportDir = "", outDir = "", chem_mech = "", \
                 mole_o_mass = "mole", molecDct = {}, aggregSpecDct = {},\
                 repRegion = "county", repDelimiter = ";"):
        """
        """
        self.sectorName = sectorName
        self.case = case
        self.grid = grid
        self.year = year
        self.reportDir = reportDir
        self.outDir = outDir
        self.chem_mech = chem_mech
        self.mole_o_mass = mole_o_mass
        self.repDelimiter = repDelimiter
        ## molecular weight dictionary
        self.molecDct = molecDct
        ## aggregate species dictionary
        self.aggregSpecDct = aggregSpecDct

        ## aggregate species list, aggregate species represented in this sector
        self.aggregSpecLst = []

        ## Region totals dictionary -- keys are county fips or state names 
        ## below is a dictionary of species containing the running total
        ## in mass (g)
        self.totalDct={}

        ## State totals dictionary -- keys are state fips
        ## used only when inputs are county reports 
        ## below is a dictionary of species containing the running total
        ## in mass (g)
        self.stFipsTotalDct={}

        ## last processed report
        self.lastReportDct={}

        ## list of the reports processed, depending on the merging
        ## technique, we would expect repetitions
        self.reportsProcessed = []

        ## list of species
        self.speciesLst=[]
        ## Dictionary of fips to state and county names
        ## used only when inputs are county reports
        self.ctyStDict={}
	## list of county fips or state names in reports
        self.keysLst=[]
        ## list of state fips in reports
        ## used only when inputs are county reports
        self.stFipsLst=[]

        ## Smkmerge input report type
        self.repRegion=repRegion

    def generateReportName(self,dateStr):
        """
        Generates a report name based on EPA nameing structure and
        directory structure.

        Input:
           dateStr - date string, eg. '20021131'

        Output:
           reportName - report file name
        """

        reportName = "rep_" + self.mole_o_mass + "_" + self.sectorName + \
                     "_%s_" %dateStr + self.grid + "_" + \
                     self.chem_mech + "_" + self.case + ".txt"
        reportDir = os.path.join(self.reportDir, self.sectorName)
        reportName = os.path.join(reportDir, reportName)
        return os.path.expanduser(reportName)
   
    def parseStReport(self, fileName):
        """
        Parses a smoke merge report
        """

        fileName = os.path.expanduser(fileName)
        if not os.path.isfile(fileName):
            raise LookupError("Can't find report: %s" %fileName)

        ## open merge report file and read into a buffer
        f = open(fileName, "rt", encoding='utf-8')
        buffLst = f.readlines()
        f.close()

        delimiter = self.repDelimiter
        
        firstLine = -1
        lastLine = -1
        ## find the header of the first section and end of first section
        for i, line in enumerate(buffLst):
            if (line[0:7].find("State") != -1):
                firstLine = i
                break

        if firstLine == -1:
            raise LookupError("Couldn't find header line starting w/ 'State' in smoke report")

        for i, line in enumerate(buffLst[firstLine + 1:]):
            if line[0] == "#":
                lastLine = i 
                break

        lastLine = firstLine + lastLine

        ## subset the buffer for section 1 and clean it up
        ## (remove extra spaces)
        cleanBuff = []
        for line in buffLst[firstLine:lastLine+1]:
            ## split on delimiter, clean out white space and recreate line
            tmpLst = line.split(delimiter)
            tmpLst = [x.strip() for x in tmpLst]
            cleanBuff.append(delimiter.join(tmpLst))

        ## clean up header line
        ## remove leading # and trailing ;
        cleanBuff[0] = cleanBuff[0].replace("#","",1)
        if cleanBuff[0][-1] == delimiter:
            cleanBuff[0] = cleanBuff[0][0:-1]

        ## parse the clean buffer to create a reader dictionary
        readerDct = csv.DictReader(cleanBuff, skipinitialspace=True, \
                                   delimiter=delimiter)

        ## loop over rows, create a dictionary of states with
        ## dictionary of species and their values below
        stateDct = {}
        speciesKeys = []
        for rowDct in readerDct:
            ## copy the dictionary values for the particular state
            ## and remove the state value from the copy
            stateName = rowDct["State"]
            stateDct[stateName] = rowDct
            stateDct[stateName].pop("State")

            ## convert values to floats
            itemsLst = [(elem[0], float(elem[1])) for elem in stateDct[stateName].items()]
            stateDct[stateName] = dict(itemsLst)

        return stateDct

    def parseCtyReport(self, fileName):
        """
        Parses a smoke merge report
        """

        fileName = os.path.expanduser(fileName)
        if not os.path.isfile(fileName):
            raise LookupError("Can't find report: %s" %fileName)

        ## open merge report file and read into a buffer
        f = open(fileName, "rt", encoding='utf-8')
        buffLst = f.readlines()
        f.close()

        delimiter = self.repDelimiter
        
        firstLine = -1
        lastLine = -1
        ## find the header of the first section and end of first section
        for i, line in enumerate(buffLst):
            if (line[0:10].find("County") != -1):
                firstLine = i
                break

        if firstLine == -1:
            raise LookupError("Couldn't find header line starting w/ 'County' in smoke report")

        for i, line in enumerate(buffLst[firstLine + 1:]):
            if line[0] == "#":
                lastLine = i 
                break

        lastLine = firstLine + lastLine

        ## subset the buffer for section 1 and clean it up
        ## (remove extra spaces)
        cleanBuff = []
        for line in buffLst[firstLine:lastLine+1]:
            ## split on delimiter, clean out white space and recreate line
            tmpLst = line.split(delimiter)
            tmpLst = [x.strip() for x in tmpLst]
            cleanBuff.append(delimiter.join(tmpLst))

        ## clean up header line
        ## remove leading # and trailing ;
        cleanBuff[0] = cleanBuff[0].replace("#","",1)
        if cleanBuff[0][-1] == delimiter:
            cleanBuff[0] = cleanBuff[0][0:-1]

        ## parse the clean buffer to create a reader dictionary
        readerDct = csv.DictReader(cleanBuff, skipinitialspace=True, \
                                   delimiter=delimiter)

        ## loop over rows, create a dictionary of fips with
        ## dictionary of species and their values below
        fipsDct = {}
        speciesKeys = []
        for rowDct in readerDct:
            ## copy the dictionary values for the particular county 
            ## and remove the county value from the copy
            countyCell = rowDct["County"]
            ## grab the fips, state, and county name from a county smkmerge report
            ## this input field is offset-based formatted
            fips = countyCell[8:20]
            stateName = countyCell[21:41].strip()
            countyName = countyCell[41:].strip()
            fipsDct[fips] = rowDct
            fipsDct[fips].pop("County")

            ## convert values to floats
            itemsLst = [(elem[0], float(elem[1])) for elem in fipsDct[fips].items()]
            fipsDct[fips] = dict(itemsLst)

            ## add the fips and county/state definitions to the cty/st fips x-ref dictionary
            stFips = fips[:9]
            if stFips not in list(self.ctyStDict.keys()):
                self.ctyStDict[stFips] = stateName
            if fips not in list(self.ctyStDict.keys()):
                self.ctyStDict[fips] = countyName

        return fipsDct

    def value2grams(self, speciesName, speciesVal):
        """
        Converts from species value (typically in moles) to grams
        """
        return speciesVal * self.molecDct[speciesName]
    
    def g2tons(self, grams):
        """
        Converts from grams to short tons (US tons)
        """
        return grams/907185.  ## more accurately 907184.74g = 1 us ton


    def convertTotal2Mass(self, totalDct):
        """
        Returns a new total dictionary, converted to mass
        
        """
        ## if already in tons, just return the states total dict
        if self.mole_o_mass == "mass":
            return totalDct 

        ## otherwise, convert from moles --> g --> tons
        totalMassDct = {}
        for fips in totalDct:
            totalMassDct[fips] = {}
            for speciesName in totalDct[fips]:
                totalMassDct[fips][speciesName] = self.g2tons(self.value2grams(speciesName, totalDct[fips][speciesName]))

        return totalMassDct 

    def formatValues(self, val):
        """
        Converts a float to a string.

        If val > 0, returns a %.4f
        if val < 0, returns in scientific notation %.6e
        
        """
        if val >= 0:
            return "%.4f" %val
        else:
            return "%.6e" %val
        
    def addDct(self, origDct, addDct):
        """
        Adds the values into the input dictionary.  If the county/state key is not
        there, it gives a warning but adds the new key.  If the species key
        isn't there, it gives a warning but adds a new key.

        Note:  This adds inplace.  Despite no return, origDct values will
               be updated
        """

        ## Loop over keys - fips or state names 
        for fips in list(addDct.keys()):
            if fips in origDct:
                ## add values
                for speciesName in list(addDct[fips].keys()):
                    if speciesName in origDct[fips]:
                        ## add values
                        origDct[fips][speciesName] = origDct[fips][speciesName] + addDct[fips][speciesName]

                    else:
                        ## print warning about missing species and add to orig
                        print("WARNING: species (%s) not in all of the smoke reports for this sector" %speciesName)
                        origDct[fips][speciesName] = copy.deepcopy(addDct[fips][speciesName])

                        ## add it to the master list of species
                        self.speciesLst.append(speciesName)

            else:
                ## print warning and add new item to orig dictionary
                print("WARNING: fips or state (%s) not in all of the smoke reports for this sector" %fips)
                origDct[fips] = copy.deepcopy(addDct[fips])

                ## add it to the master list of fips 
                self.keysLst.append(fips)


    def processAll(self, reportsLst):
        """
        Process all the reports in the list.  Stores a running total
        for each species for each county.

        Inputs:
            reportsLst - list of county total smoke reports for each day
                         Should be full path.

        Note:
        1. If you run this multiple times, it will keep adding to
           the running total (self.totalDct).  Generally,
           you should run this once for your complete list of reports.

        2. For many merge approaches, the reports list will repeat
           many of the report files.  Generally, there should be 365
           elements in the reportsLst, though many will be the same for
           most sectors (e.g. "ag").
        """


        ## loop smoke merge reports
        lastReport = None
        for reportName in reportsLst:
            
            ## if this report matches the last report,
            ## no need to process the file, just add the last report's
            ## values to the the total
            if lastReport == reportName:
                self.addDct(self.totalDct, self.lastReportDct)
                #print "Dates match %s, %s" %(reportName, lastReport)
            else:
                ## Need to reparse the report and add the new data

                ## make sure clean dict b/c don't want to over reference
                ## and double count
                reportDct = {} 
                if self.repRegion == 'state': 
                    reportDct = self.parseStReport(reportName)
                elif self.repRegion == 'county':
                    reportDct = self.parseCtyReport(reportName)

                ## add to the county totals
                if lastReport is None:
                    ## first time through
                    self.totalDct = copy.deepcopy(reportDct)

                    ## get full list of fips 
                    self.keysLst = list(reportDct.keys())

                    ## for the first county, get full list of species
                    self.speciesLst = list(reportDct[self.keysLst[0]].keys())
                    
                else:
                    ## add to running total for each county and species
                    self.addDct(self.totalDct,reportDct)

                ## update last report  
                lastReport = reportName

                ## store this report data as last report
                self.lastReportDct = reportDct
                
            ## Keep list of all reports processed (repetitions included)
            self.reportsProcessed.append(reportName)


    def appendAggregateSpecies(self):
        """
        Appends aggregate species.  Checks for intersection of
        aggregate species.  If any component species are there,
        adds this aggregate species and sums up the values.
        """
        ## check for empty aggregate species dictionary
        if len(self.aggregSpecDct) == 0:
            print("WARNING:  AnnualReports was not initialized with an aggregSpecDct")
            return


        ## Create a set of species list, and temporary list to append aggregate
        ## species to
        speciesSet = set(self.speciesLst)
        tmpSpeciesLst = list(speciesSet)
        
        ## loop over aggregate species
        for aggregSpec in list(self.aggregSpecDct.keys()):
            ##check if there is any intersection with any of the species
            aggregSet = self.aggregSpecDct[aggregSpec]
            interSet = aggregSet.intersection(speciesSet)
            if len(interSet) > 0:
                ## there is an intersection ie. some of the component
                ## species are in this sector

                ## add the aggregate species to temp species list
                tmpSpeciesLst.append(aggregSpec)

                ## loop over fips 
                for fips in self.keysLst:
                    ## create a set of the secies for this county 
                    ## (may be a subset??)
                    fipsSpecSet = set(self.totalDct[fips].keys())

                    ## see if aggregate species has already been added
                    if aggregSpec in fipsSpecSet:
##                         print "%s already added to %s species dictionary" \
##                               %(aggregSpec, state)
                        pass
                    else:
                        ## find the intersection
                        fipsInterSet = aggregSet.intersection(fipsSpecSet)
                        ## add this aggregate species
                        aggregVal = 0
                        for species in fipsInterSet:
                            aggregVal += self.totalDct[fips][species]
                        self.totalDct[fips][aggregSpec] = aggregVal

        ## If the speciesSet is bigger than the original speciesLst, replace
        ## the speciesLst, ie. we are adding the aggregate species
        if len(tmpSpeciesLst) > len(self.speciesLst):
            ## record the aggregate species
            self.aggregSpecLst = list(set(tmpSpeciesLst).difference(self.speciesLst))
            self.speciesLst = tmpSpeciesLst
                        
    def genStateSums(self):
        """
        Generates the state totals for each pollutant from the county
        total dictionaries.
        """
        self.keysLst.sort()
        for fips in self.keysLst:
            stFips = fips[:9]

            ## append the state fips to the fips list
            if stFips not in self.stFipsLst:
                self.stFipsLst.append(stFips)

            ## generate an entry for the state in the totals dictionary
            ## if the state does not yet exist
            if stFips not in self.stFipsTotalDct:
                self.stFipsTotalDct[stFips] = self.totalDct[fips]
            ## otherwise add the county total to that state total for each species 
            else:
                for speciesName,ctyVal in self.totalDct[fips].items():
                    self.stFipsTotalDct[stFips][speciesName] += ctyVal
      
    def writeSmokeReport(self, outFile, outRegion):
        """
        Writes the SMOKE report format.  One county/state per row with species
        as the columns. The delimiter is ';'.

        Input:
           outFile - name of annual county report to create
           
        """
        outFile = os.path.expanduser(outFile)
        outDir = os.path.dirname(outFile)
        if not os.path.isdir(outDir):
            ## make the directory if doesn't exist
            os.mkdir(outDir)
            os.chmod(outDir,0o775)

        f = open(outFile,"w", encoding='utf-8')

        ## Set up variables for county or state reports
        if outRegion == 'state':
            if self.repRegion == 'state':
                ## get the state totals in tons for state report inputs
                totalsTonsDct = self.convertTotal2Mass(self.totalDct)
                fipsList = self.keysLst
                self.stFipsLst = fipsList
            elif self.repRegion == 'county':
                ## get the state totals in tons for county report inputs
                totalsTonsDct = self.convertTotal2Mass(self.stFipsTotalDct)
                fipsList = self.stFipsLst
            else:
                print("ERROR: Input region (-r) needs to be 'state' or 'county'")
            ## write the output header for state annual total reports
            headerStr = "# State"
        elif outRegion == 'county':
            ## get the county totals in tons for county report inputs
            totalsTonsDct = self.convertTotal2Mass(self.totalDct)
            ## write the output header for county annual total reports
            headerStr = "# FIPS"+self.repDelimiter+"State"+self.repDelimiter+"County"
            fipsList = self.keysLst

        self.speciesLst.sort()
        for speciesName in self.speciesLst:
            ## add the species names to the header
            headerStr += "%s%s" %(self.repDelimiter, speciesName)

        f.write(headerStr + "\n")

        fipsList.sort()
        for fips in fipsList:
            ## write the state or county name based on outRegion type
            if outRegion == 'state':
                if self.repRegion == 'state':
                    ## Set the state name as the list entry
                    ## Variable name is fips, but string will be state name 
                    lineStr = fips 
                elif self.repRegion == 'county':
                    ## Set the state name to dictionary entry by fips
                    lineStr = self.ctyStDict[fips]
            elif outRegion == 'county':
                ## Set the fips, county, and state names for the output line of the county annual report
                lineStr = fips+self.repDelimiter+self.ctyStDict[fips[:9]]+self.repDelimiter+self.ctyStDict[fips]
            for speciesName in self.speciesLst:
                ## append species values to this line
                lineStr += self.repDelimiter + str(totalsTonsDct[fips][speciesName])

            #print(lineStr)

            ## write one state/county's values to file
            f.write(lineStr + "\n")

        f.close()

    def writeSpeciesReport(self, outFile, outRegion):
        """
        Writes the species report format.  One county and one species per row with
        the additional sector name as a column. Format is CSV.

        Input:
           outFile - name of annual species report to create

        Note:
          1.  If the outFile exists, it will be replaced.
        """
        outFile = os.path.expanduser(outFile)
        outDir = os.path.dirname(outFile)
        if not os.path.isdir(outDir):
            ## make the directory if doesn't exist
            os.mkdir(outDir)
            os.chmod(outDir,0o775)
            
        ## open file and add the header
        f = open(outFile,"w", encoding='utf-8')

        ## Set up variables for county or state reports
        if outRegion == 'state':
            ## get the county totals in tons
            if self.repRegion == 'state':
                ## When the input report type is state, use the generic
                ## keys (state names)
                totalsTonsDct = self.convertTotal2Mass(self.totalDct)
                fipsList = self.keysLst
                self.stFipsLst = fipsList # for qa purposes
            elif self.repRegion == 'county':
                ## When the input report type is county, use the fips
                ## keys shortened to state fips
                totalsTonsDct = self.convertTotal2Mass(self.stFipsTotalDct)
                fipsList = self.stFipsLst
            ## write the output report header for state annual reports
            headerStr = "State,Sector,Species,ann_emis\n"
        elif outRegion == 'county':
            ## get the county totals in tons
            totalsTonsDct = self.convertTotal2Mass(self.totalDct)
            ## write the output report header for county annual reports
            headerStr = "FIPS,State,County,Sector,Species,ann_emis\n"
            fipsList = self.keysLst

        f.write(headerStr)
        
        fipsList.sort()
        for fips in fipsList:
            if outRegion == 'state':
                if self.repRegion == 'state':
                    ## Set the state name as the list entry
                    ## Variable name is fips, but string will be state name 
                    outRegionName = fips 
                elif self.repRegion == 'county':
                    ## Set the state name to dictionary entry by fips
                    outRegionName = self.ctyStDict[fips]
            elif outRegion == 'county':
                ## for county output reports write the fips, state name, and county name
                outRegionName = '%s,%s,%s' %(fips, self.ctyStDict[fips[:9]], self.ctyStDict[fips])

            emfSpeciesList = list(totalsTonsDct[fips].keys())
            emfSpeciesList.sort()
            
            for speciesName in emfSpeciesList:
                ## append species values to the output line
                speciesStr = "%s,%s,%s,%s\n" %(outRegionName, self.sectorName, speciesName,\
                                               self.formatValues(totalsTonsDct[fips][speciesName]))

                ## write one species's values to file
                f.write(speciesStr)

        f.close()

        
##-----------------------------------------------------------------------##
## Actual script


if __name__ == "__main__":
    from optparse import OptionParser

    ## Command line options
    usage = "usage: %prog [options] parameterFile"
    parser = OptionParser(usage=usage)

    parser.add_option("-s", metavar=" sector_name", dest="sectorName", default="",
                      help="Sector name.  Overrides environmental variable SECTOR")
    parser.add_option("-c", metavar=" case_abbrev", dest="case", default="",
                      help="Case abbreviation.  Overrides environmental variable CASE")
    parser.add_option("-y", metavar=" year", dest="year", default="",
                      help="Year.  Overrides environmental variable BASE_YEAR. "
                      "This is used for constructing the smkmerge dates filename.")
    parser.add_option("-g", metavar=" grid", dest="grid", default="",
                      help="Grid abbreviation.  Overrides environmental variable GRID")
    parser.add_option("-f", metavar=" output_format", dest="format", default="both",
                      help="Output format. The 'smoke' format is 1 state/county per row and species as "
                      "columns. The 'species' format is 1 species per row. Default is 'both', "
                      "create both formatted outputs.")
    parser.add_option("-m", metavar=" mole_o_mass", dest="mole_o_mass", default="mole",
                      help="Mass or mole. This is used to construct the SMOKE report "
                      "names.  The default values is 'mole'.  Alternatively, could be set to "
                      "'mass'")
    parser.add_option("-S", metavar=" sector_list", dest="sectorListFile", default="",
                      help="Sector list file.  Overrides environmental variable SECTORLIST")
    parser.add_option("-R", metavar=" report_dir", dest="reportDir", default="",
                      help="Report directory.  Where the SMOKE reports reside. "
                      "Below the report_dir, the script expects sector specific "
                      "directories.")
    parser.add_option("-D", metavar=" dates_dir", dest="datesDir", default="",
                      help="Smkmerge date files directory.  Where the smkmerge "
                      "dates file reside.")
    parser.add_option("-o", metavar=" out_name", dest="outBaseName", default="annual_summary",
                      help="Output name for the annual summary reports.  For the 'smoke' "
                      "format it will append a '.txt' and for the 'species' format it "
                      "will append '_emf.csv'.  For example, out_name = 'onroad_annual_2002' "
                      "will become onroad_annual_2002.txt and onroad_annual_2002_emf.csv. "
                      "Default value is 'annual_summary'.")
    parser.add_option("-O", metavar=" out_dir", dest="outDir", default="",
                      help="Output directory for the annual reports.")
    parser.add_option("-r", metavar=" rep_region", dest="repRegion", default="county",
                      help="Smkmerge report region type for input reports."
                      "Set either to county or state.  Defaults to county.")
    parser.add_option("-a", metavar=" out_region", dest="outRegion", default="both",
                      help="Annual report output by region type."
                      "Will create report by state, by county, or create both types."
                      "Options are 'state', 'county', or 'both'."
                      "Defaults to 'both'.") 
    
    parser.add_option("--chem", metavar=" chem_mech", dest="chem_mech", default="",
                      help="Chemical mechanism.  Overrides chem_mechanism "
                      "in the parameter file")
    parser.add_option("--start_month", metavar=" month", dest="startMonth", default=1,
                      help="Start month. First month to aggregate over. Default is 1, January.") 
    parser.add_option("--end_month", metavar=" month", dest="endMonth", default=12,
                      help="End month. Last month to aggregate over. Default is 12, December.")
    parser.add_option("--debug", dest="debug", default=False, action="store_true",
                      help="Turn debugging on.")
    parser.add_option("--debug_extra", dest="debugX", default=False, action="store_true",
                      help="Turn debugging on. Prints which smkmerge reports were processed.")

    (options, args) = parser.parse_args()

    ## get args
    if len(args) < 1:
        raise LookupError("Must pass parameter file")
    parameterFile = os.path.expanduser(args[0])
    
    ## get options
    sectorName = options.sectorName
    case = options.case
    grid = options.grid
    year = options.year
    chem_mech = options.chem_mech
    mole_o_mass = options.mole_o_mass
    sectorListFile = options.sectorListFile
    datesDir = options.datesDir
    reportDir = options.reportDir
    outDir = options.outDir
    format = options.format
    startMonth = int(options.startMonth)
    endMonth = int(options.endMonth)
    outBaseName = options.outBaseName
    debug = options.debug
    debugX = options.debugX
    repRegion = options.repRegion.lower()
    outRegion = options.outRegion.lower()

    ## get molecular weights and other things
    loc = {}
    exec(open(parameterFile).read(), {}, loc)
    molecDct = loc['molecDct']
    chem_mechanism = loc['chem_mechanism']
    aggregSpecDct = loc['aggregSpecDct']
#    execfile(parameterFile)

    ## If any of the options are not set, try to get from the
    ## environmental variables
    if sectorName == "":
        try:
            sectorName = os.environ["SECTOR"]
        except:
            raise LookupError("Sector name must be set.  Not found in environment or passed as an option.")
    if case  == "":
        try:
            case = os.environ["CASE"]
        except:
            raise LookupError("Case abbreviation must be set.  Not found in environment or passed as an option.")        
    if grid == "":
        try:
            grid = os.environ["GRID"]
        except:
            raise LookupError("Grid abbreviation must be set.  Not found in environment or passed as an option.")
    if year == "":
        try:
            year = os.environ["BASE_YEAR"]
        except:
            raise LookupError("Year must be set.  Not found in environment or passed as an option.")
    if chem_mech == "":
        try:
            chem_mech = chem_mechanism ## from parameterFile
        except:
            raise LookupError("Chemical mechanism must be set.  Not found in parameter file or passed as an option.")
    if sectorListFile == "":
        try:
            sectorListFile = os.environ["SECTORLIST"]
        except:
            raise LookupError("Sector list file must be set.  Not found in environment or passed as an option.")


    ## create an annual reports obj
    reports = AnnualReports(sectorName, case, grid, year, reportDir,\
                            outDir, chem_mech, mole_o_mass, molecDct, \
                            aggregSpecDct, repRegion)
    
    ## get the merge approach for this sector
    mrgApproach = parseSectorlist(sectorListFile, sectorName)

    ## loop over the months and get a complete date list of all
    ## files based on the merge dates files
    ## these are the dates to use as representative days
    ## the length of an annual datesLst = 365, but there will likely be
    ## repetitions of the dates depending on the merge approach
    datesLst = []
    for i in range(startMonth, endMonth+1):
        datesFile = "smk_merge_dates_%s%02d.txt"%(year, i)
        datesFile = os.path.join(datesDir, datesFile)
        datesLst += parseMergeDates(datesFile, mrgApproach)


    ## generate report file names
    reportsLst = [reports.generateReportName(dateStr) for dateStr in datesLst]

    ## process all reports
    reports.processAll(reportsLst)

    ## get the number of non-aggregate species
    numNonaggregSpec = len(reports.speciesLst)
    
    ## Add aggregates species
    reports.appendAggregateSpecies()

    ## Write the county reports if selected and possible
    if (repRegion == 'county') and (outRegion == 'county' or outRegion == 'both'):
        ctySmokeReport = outBaseName + "_county.txt"
        ctySpeciesReport = outBaseName + "_county_emf.csv" 
        ctySmokeReport = os.path.join(outDir,ctySmokeReport)
        ctySpeciesReport = os.path.join(outDir,ctySpeciesReport)

        if format.lower() == "smoke" or format.lower() == "both":
            ## write the SMOKE formatted reports
            reports.writeSmokeReport(ctySmokeReport, 'county')
        if format.lower() == "species" or format.lower() == "both":
            ## write the 'species' or EMF formatted reports
            reports.writeSpeciesReport(ctySpeciesReport, 'county')

        ## Write some county report diagnostics
        print("Wrote %s annual smkmerge summaries: %d counties, %d species (non-aggregrate)" \
              % (sectorName, len(reports.keysLst),numNonaggregSpec))

    ## Write the state reports if selected
    if outRegion == 'state' or outRegion == 'both':

        if repRegion == 'county':
            ## Generate the state totals
            reports.genStateSums()

        ## write the state reports
        stSmokeReport = outBaseName + "_state.txt"
        stSpeciesReport = outBaseName + "_state_emf.csv" 
        stSmokeReport = os.path.join(outDir,stSmokeReport)
        stSpeciesReport = os.path.join(outDir,stSpeciesReport)

        if format.lower() == "smoke" or format.lower() == "both":
            ## write the SMOKE formatted reports
            reports.writeSmokeReport(stSmokeReport, 'state')
        if format.lower() == "species" or format.lower() == "both":
            ## write the 'species' or EMF formatted reports
            reports.writeSpeciesReport(stSpeciesReport, 'state')

        ## Write some state report diagnostics
        print("Wrote %s annual smkmerge summaries: %d states, %d species (non-aggregrate)" \
              % (sectorName, len(reports.stFipsLst),numNonaggregSpec))

    ## Debug info
    if debug or debugX:
        print("Dates merge approach: ", mrgApproach)

        if len(reports.aggregSpecLst) > 0:
            print("Aggregate species included: %s" %string.join(reports.aggregSpecLst, ", "))

        print("Total number of reports processed (including repetitions): %d" %len(reports.reportsProcessed))

    if debugX:
        print("Unique smkmerge reports processed:")
        uniqueReports = list(set(reports.reportsProcessed))
        uniqueReports.sort()
        for elem in uniqueReports:
            print(elem)
