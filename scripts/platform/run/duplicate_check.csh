#!/bin/tcsh -f
# 
# duplicate_check.csh - Christine Allen, created 29 Apr 2008
#
# This script checks a speciation, gridding, and temporal cross-reference
# file for duplicates. SMOKE does this accurately for area and point sectors,
# but not for mobile sectors. Because of that, we must check for duplicates
# outside of SMOKE for mobile sectors. Also, this is a more thorough check than
# what SMOKE does, because SMOKE only checks for duplicates in whatever sector
# SMOKE happens to be running at the time.

## The script takes two command line arguments: the filename for which to check 
#  duplicates, and the type of file (see below). This script is called
#  separately for each file, to allow for cases where we might not want to
#  check a particular file. (For example, there is no need to check the
#  gridding cross-reference for point sectors.)

## Script updated 29 Jun 2015 in support of SMOKE 3.6 Temporal cross-reference format.
#  Assumes comma-delimited Temporal cross-reference.

## Calling syntax:
#     duplicate_check.csh [filename] [filetype]
#
#  Where,
#     [filename] = name of cross-reference file to check for duplicates
#                  (e.g. $ATREF, $GSREF)
#     [filetype] = S for speciation, G for gridding, or T for temporal
#                  (necessary because each file has a different format)

# Check the number of arguments. It must have at least two arguments.
switch ( $#argv )
    case 1:
    case 0:
      echo "SCRIPT ERROR: Script requires at least two arguments."
      echo "  The syntax for calling this script is:"
      echo " "
      echo "     duplicate_check.csh [filename] [filetype]"
      echo " "
      echo "  Where,"
      echo "     [filename] = name of cross-reference file to check for duplicates"
      echo '                  (e.g. $ATREF, $GSREF)'
      echo "     [filetype] = S for speciation, G for gridding, or T for temporal"
      exit( 1 )
endsw

set filename = $argv[1]
set filetype = $argv[2]

## Make sure input file exists
if ( ! -e $filename ) then
   echo "SCRIPT ERROR: File $filename"
   echo "              does not exist. Cannot check file for duplicates."
   exit (1)
endif

set tmpfile = $INTERMED/dupcheck_tmpfile_$$.txt

## Remove header comments and end-of-line comments
grep -v "^#" $filename | cut -d"!" -f1 > $tmpfile

## Remove profile/surrogate code(s), depending on file format
switch ( $filetype )
   case G:
      cut -d";" -f1-2 $tmpfile > $tmpfile.2
      breaksw
   case S:
      cut -d";" -f1,3- $tmpfile > $tmpfile.2
      breaksw
   case T:
      if ($?ATPRO_WEEKLY) then # new temporal format; if ATPRO_WEEKLY env variable is defined, then we're using new format
         cut -d"," -f1-8 $tmpfile > $tmpfile.2
      else # old temporal format
         cut -d";" -f1,5- $tmpfile > $tmpfile.2
      endif
      breaksw
   default:
      echo "SCRIPT ERROR: filetype needs to be G, S, or T"
      echo "  The syntax for calling this script is:"
      echo " "
      echo "     duplicate_check.csh [filename] [filetype]"
      echo " "
      echo "  Where,"
      echo "     [filename] = name of cross-reference file to check for duplicates"
      echo '                  (e.g. $ATREF, $GSREF)'
      echo "     [filetype] = S for speciation, G for gridding, or T for temporal"
      rm ${tmpfile}*
      exit (1)
endsw

## Count number of rows in existing file
set nlines = `cat $tmpfile.2 | wc -l`

## Perform a unique sort to remove duplicates, and count number of rows again
set nlines2 = `sort -u $tmpfile.2 | wc -l`

## If nlines != nlines2, then there is at least one duplicate
if ( $nlines != $nlines2 ) then

   ## Compute number of duplicates, for informational purposes
   @ nlines3 = $nlines - $nlines2
   
   ## Create output file that contains the contents of a "diff" between
   #  the file with duplicates and file without duplicates, so that the user
   #  knows what records are duplicated. Include the PID in the filename in case
   #  two jobs from the same sector are running this at the same time
   set outfile = $REPOUT/programs/duplicates_${filetype}REF_${CASE}_${SECTOR}_$$.txt
   sort $tmpfile.2 > $tmpfile.3
   sort -u $tmpfile.2 > $tmpfile.4
   diff $tmpfile.3 $tmpfile.4 > $outfile
   
   echo "ERROR: $filename contains $nlines3 duplicate records"
   echo "Check $outfile for list of duplicates"
   rm ${tmpfile}*
   exit (1)
   
endif

echo "SCRIPT NOTE: No duplicates found in $filename"

rm ${tmpfile}*

exit (0)
