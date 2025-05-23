#!/bin/tcsh -f

# This script creates .lst files for inventory or concatenates 
#     datasets into a single dataset.

# Creation date: 20 jun 2007
# Original author: M. Houyoux

# Purpose: to provide a scriptable way of combining datasets from the EMF,
#     which will be stored in the EMF as separate "inputs" to a case.

# Calling syntax:
#    combine_data.csh [prefix] [outfile] [type] [monthNum] [Style]
#
#    Where,
#       prefix = e.v. prefix to search for
#       outfile = e.v. for file to create (for concat mode, it's the ROOT of the filename,
#                 and this script will append the <date>.txt using the <date> of the newest
#                 component file.
#       type = list | concat. Default is "list".
#       monthNum = Set to month number of interest, unless no month applies, then leave blank
#       Style = Daily or Hourly
#
#       Also, for style = Daily or Hourly, requires that environment variable BASE_YEAR be defined.
#
# Updated October 19, 2007 by M. Houyoux to remove blank lines from inputs
#       when in type=concat
# Updated Feb 4, 2011 by J. Beidler to fix POSIX compliancy issues with the previous month calculation
# Updated 21 Jun 2013 by C. Allen (CSC) to handle FF10 Daily Point processing, in which all PTHOUR files
# 	for the entire year are added to a single PTHOUR.lst
#
# C.Allen (GDIT) updated 13 Nov 2019 to include support for hourly CMV inventories using Style Hourly_CMV
#   Updated again 06 Dec 2021 to support a slightly different hourly CMV file naming convention using Style Hourly_CMV19
#
# J. Beidler (GDIT) updated 31 Jan 2023 to include support for hourly EGU inventories
#
# Check the number of arguments. It must have at least two arguments.
switch ( $#argv )
    case 1:
    case 0:
      echo "SCRIPT ERROR: Script requires at least two arguments."
      echo "  The syntax for calling this script is:"
      echo " "
      echo "     combine_data.csh [prefix] [outfile] [type] [month] [style]"
      echo " "
      echo "         where,"
      echo "            [prefix]  = environment variable prefix to search for"
      echo "            [outfile] = environment variable for file to create"
      echo "            ["type"]    "= \"list\" or \"concat\". Default is \"list\".
      echo "                        This argument is optional."
      echo "            [month]   = the month number of interest for the file."
      echo "                        Use values 01 through 12. Default is not"
      echo "                        month-specific. This argument is optional."
      echo "            [style]   = For type=list, use:"
      echo "                        "\"Daily\" "when want to use daily file convention "
      echo "                             with current month and last day of previous"
      echo "                        "\"Hourly\" "when want to use current month, last day"
      echo "                             of current month, and last day of previous"
      echo "                             month, including previous year"
      echo "                        "\"Hourly_CMV\" "when want to use current month and next"
      echo "                             month for CMV processing"
      echo "                        "\"Hourly_CMV19\" "when want to use current month and next"
      echo "                             month for CMV processing starting with the 2019 inventory"
      exit( 1 )

endsw

set scriptname = combine_data.csh

# Create formatted date
set date = `date +%m/%d/%Y`

# Inializations
set eflag = N   # Initialize 
set monname = (jan feb mar apr may jun jul aug sep oct nov dec)
set lastday = (31  28  31  30  31  30  31  31  30  31  30  31)

# Parse out arguments
set valid_month = N
set style = 0
if ( $#argv > 3 ) then
    set month = $argv[4]
    foreach m ( 01 02 03 04 05 06 07 08 09 10 11 12)
       if ( $m == $month ) then
          set valid_month = Y
       endif
    end
    if ( $valid_month == N ) then
       echo SCRIPT ERROR: month argument is invalid value of \"$month\"
       echo "              "Enter valid value of 01 through 12.
       exit ( 1 )
    endif

    # Set previous month number
    set prevmonnum = 0

    # POSIX compliant shells interpret numbers with leading zeroes as octal.  Convert single digit numbers back to base 10 by stripping the leading zero.
    if ( `echo $month | cut -c1` == 0 ) then 
       set pmonth = `echo $month | cut -c2`
    else
       set pmonth = $month
    endif 

    @ prevmonnum = $pmonth - 1
    @ nextmonnum = $pmonth + 1

    if ( $#argv > 4 ) then
       set style = $argv[5]
       switch ( $style )
          case Daily:
          case Hourly:
          case Hourly_CMV:
          case Hourly_CMV19:
          case Hourly_egu:
             if ( $?BASE_YEAR ) then
                if ( $BASE_YEAR % 4 == 0 ) then
                    set lastday[2] = 29
                endif

                set thisyear = $BASE_YEAR
                set prevyear = $thisyear
                @ prevyear = $prevyear - 1

             else
                echo "SCRIPT ERROR: Environment variable BASE_YEAR must be defined"
                echo "              when using style = Daily, Hourly, Hourly_CMV, or Hourly_CMV19"
                exit ( 1 )
             endif
      
          breaksw
          default:
             echo SCRIPT ERROR: Script setting for \"style\" is set to
             echo "              "invalid value of \"$argv[3]\". Valid values
             echo "              "are \"Daily\", \"Hourly\", \"Hourly_CMV\", and \"Hourly_CMV19\", and 
             echo "              "these are case sensitive.
             exit ( 1 )
       endsw  
    endif

else
    set month = N
endif

if ( $#argv > 2 ) then
   switch ( $argv[3] )
      case list:
      case concat:
         set type = $argv[3]
         breaksw
      default:
         echo SCRIPT ERROR: Script setting for \"type\" is set to
         echo "              "invalid value of \"$argv[3]\". Valid values
         echo "              "are \"list\" and \"concat\", and these are
         echo "              "case sensitive.
         exit ( 1 )
   endsw

endif

set prefix = $argv[1]
set outfile = $argv[2]

# Message      
echo Creating dataset $outfile 
echo "     using script $scriptname"

# Get list of input environment variables
set sort_list_evs = N
if ( $?SORT_LIST_EVS ) then
   set sort_list_evs = $SORT_LIST_EVS
endif

if ( $sort_list_evs == Y ) then
   set envlist = ( `env | grep $prefix | sort | cut -d\= -f1` )
   set filelist = ( `env | grep $prefix | sort | cut -d\= -f2` )  # note: sorted in order of envlist
else
   set envlist = ( `env | grep $prefix | cut -d\= -f1` )
   set filelist = ( `env | grep $prefix | cut -d\= -f2` )
endif

# If e.v. MULTIFILE_NAMEBREAK is set > 0, this indicates that EMF external multifiles are in use,
# and therefore the prefix in combination with the _MULTI_ field should be treated specially
# The value of this variable is set to the number of underscores to use to set 
#        prefix of file name for the files in "list" mode.
set multifile_break = 0
if ( $?MULTIFILE_NAMEBREAK ) then
   if ( $MULTIFILE_NAMEBREAK > 0 ) then
      set multifile_break = $MULTIFILE_NAMEBREAK
   endif
endif

# Check if list is empty before proceeding
if ( "$envlist" == "" ) then
   echo "SCRIPT ERROR: No environment variables with prefix $prefix "
   echo "              have been defined."
   exit ( 1 )
endif

# Check if all files in list exist
set exitstat = 0
foreach f ( $filelist ) 

   if ( ! -e $f ) then
      echo "SCRIPT ERROR: File name match prefix ${prefix}:"
      echo "              $f"
      echo "              Does not exist\!"
      set exitstat = 1
   endif

end

# Abort if any files don't exist
if ( $exitstat > 0 ) then
   exit ( $exitstat ) 
endif
   
# In concat mode, only create output file if the output file doesn't exist or if any 
#   of the component pieces are newer than the existing file.  This will prevent an 
#   existing file from being overwritten for no reason (with possible problems for
#   concurrent jobs)
# Updated logic in 11/2008 because original "do not write" logic was too simple.
#   Updates: (1) make sure that file will be updated even if one of the components
#                was changed to an older file.   Do this simply  by comparing the list
#                of files in the header with the list of files being requested to 
#                decide if a re-write is needed.
#            (2) If multiple scripts are writing to the same file at the same time
#                (e.g., when processing in quarters), need a way to support only
#                the very first attempt to write the file by scanning the other
#                executables running and allowing only the executable that has
#                the earliest start time to write the file.

if ( $type == concat ) then

   # Initialize flag to indicate whether the outfile was just written by another process
   set just_written = 0  # i.e., assume NOT just written by another file.

   if ( -e $outfile ) then

      # Prevent this file from being written by 2 processes at once. Assume that if another process
      #    is currently writing the file, that the file will be completed.  Go into sleep mode on
      #    20 second intervals until the process writing the file has ended, and then exit with note.

      # First, get process ID from header of the existing file.  Put this in a loop to account for the
      #    case where the write process has started by the PID line hasn't completed.  Assume that 25
      #    seconds is plenty of time to write the single line that has the PID.
      set pidstat = 1
      set c = 0
      while ( $c < 5 )
         @ c = $c + 1
         set pid = `grep '#Creation Process ID' $outfile | cut -d":" -f2`
         set pidstat = $status   # 0 is for a successful grep
         if ( $pidstat == 0 ) goto pid_found
         sleep 5  # wait for 5 seconds while writing process is done
      end

      #  If still no process ID found in the file, assume the file is older than the script that inserts the process IDs
      #       or that the last file write was interrupted and that no other processes are writing to it currently.
      if ( $pidstat == 1 ) goto continue1

pid_found:      
      # If get here, then have found the process ID.  Check if process that wrote the file is currently running.
      set pslist = (`ps -p $pid  | grep $pid` )

      # If process is found, then confirm that it's a "combine data" process and not some random other process
      #    on a recycled process number.
      if ( $#pslist > 0 ) then
         set process_check = `echo $pslist[4] | cut -c1-12`
         if ( $process_check != 'combine_data' ) goto continue1       # This means that the process ID just happened to be used again, but is not really the writing process

      # If process is not found, then skip ahead
      else
         goto continue1
      endif

      ##  Wait until the writing process is done, then exit.
      set c = 0
      while ( $#pslist > 0 ) 
         sleep 5   # wait 5 seconds before checking again
         @ c = $c + 1
         set pslist = (`ps -p $pid  | grep $pid ` )
         if ( $c == 60 ) then
             echo 'SCRIPT NOTE: combine_data script has been waiting for 5 minutes for '
             echo '             process '$pid' to finish writing file:'
             echo '             '$outfile
         endif

         if ( $c == 720 ) then
             echo 'SCRIPT ERROR: combine_data script has been waiting 1 hour for'
             echo '              process '$pid' to finish writing file:'
             echo '              '$outfile
             echo '              Aborting script with error exit status'
             exit ( 1 )
         endif
      end

      # If get through this loop, then other writing process has ended.  This means that we
      # can assume that the output file has been created by another process and exit this script.
      echo 'SCRIPT NOTE: combine_data script did not write file:'
      echo '             '$outfile
      echo '             because it determined that another process successfully wrote the file.'
      echo '             Now checking that the files used by the other process match list expected here...'
      set just_written = 1

continue1:

      #### Compare list of files in existing output file with list of desired files to see if need to continue or not.
      # Get and sort list of files used in existing output file
      set filelist_current = (`grep '####' $outfile | grep -v 'Header from' | sort | cut -c 10-`)

      # Sort file list based on the file names
      set filelist_sorted =  (`env | grep $prefix | cut -d\= -f2 | sort`)

      # Only proceed checking file list if the file count (current and expected) is the same.
      if ( $#filelist_current == $#filelist_sorted ) then

         # Loop through file names.  If any are different, skip to "continue2" and keep going, unless file
         #   was just written by another process.  If the file was just written by other process and
         #   the file lists are different, then there is a conflict between concurrently running processes
         #   for the same file. In that case, abort with an error.
         set cnt = 0
         while ( $cnt < $#filelist_current )
            @ cnt = $cnt + 1
            if ( $filelist_current[$cnt] !=  $filelist_sorted[$cnt] ) then
               if ( $just_written == 1 ) then
                  goto abort_with_concurrent_error
               else
                  goto continue2
               endif
            endif 
         end
         
         # If script gets here, it means that all of the files in the existing and new lists are the same,
         #     so the file should not be rewritten.
         echo "SCRIPT NOTE: Output file from combine_data.csh was not rewritten because"
         echo "             the component files requested already match the existing file."
         exit ( 0 )

      # If file count is different and the file was just written by a concurrent process, then abort.
      else   
         if ( $just_written == 1 ) goto abort_with_concurrent_error

      endif

continue2:

   endif

endif



# If got this far, then delete output file if it exists
if ( -e $outfile ) then
   /bin/rm -f $outfile
endif

# Temporary list printout
echo Processing environment variables $envlist

# Initializations prior to loop
set n = 0
set firstime = Y
set nmax = 90
set use_ev_array = ( N N N N N N N N N N N N N N N N N N N N \
                     N N N N N N N N N N N N N N N N N N N N \
                     N N N N N N N N N N N N N N N N N N N N \
                     N N N N N N N N N N N N N N N N N N N N \
                     N N N N N N N N N N N N N N N N N N N N \
                     N N N N N N N N N N )

set filename = ""

# Loop through environment variables and files to create output file
#    For "list" mode, this loop creates the actual .lst file.
#    For "concat" mode, this loop creates only the header of the file.
foreach ev ( $envlist )

   @ n = $n + 1

   set use_ev = Y        # Use this e.v. in creating the output file (initialize)
   set ev_month = `echo $ev | cut -d_ -f2 | cut -c1-2`   # If present, the value of the month in the e.v.
   set ev_month_yn = N   #  No month in environment variable

   # Determine if contains _MULTI_ in name
   set multi = N
   echo $ev | grep -q _MULTI_ 
   if ( $status == 0 ) then
      set multi = Y
   endif

   #  See whether environment variable contains a month or not
   foreach m ( 01 02 03 04 05 06 07 08 09 10 11 12 )
      if ( $m == $ev_month ) then
         set ev_month_yn = Y
      endif
   end

   # If not using monthly data, then skip any environment variables
   #     with the monthly denotation, unless it has _MULTI_ when namebreak > 0
   if ( $month == N && $ev_month_yn == Y ) then
      if ( $multifile_break > 0 && $multi == Y ) then
      else 
         set use_ev = N
      endif
   endif

   # If using monthly data, then skip any environment variables specified
   #     for a different month.
   if ( $valid_month == Y && $ev_month_yn == Y ) then
      if ( $month != $ev_month ) then
         set use_ev = N
      endif
   endif

   set eflag = N   # Initialize before next section
 
   # If environment variable in list is to be used, the process it, otherwise skip
   if ( $use_ev == Y ) then
     
      # For multifile case, use special approach to set filename, otherwise, just use filelist directly
      if ( $multifile_break > 0 && $multi == Y ) then
         # C. Allen, 5 Jan 2017: Figure out what the NAMEBREAK_HOURLY setting should be so that the user doesn't have to set it themselves.
	 # This is the number of underscores in the "header" of the full path of the hourly data files up through HOUR_UNIT. 
	 # This parses the EMISHOUR_MULTI filename by underscores and figures out the location of "UNIT", and sets the breakpoint accordingly.
	 # If the filenames don't have HOUR_UNIT, then crash.
         if ($style == Hourly) then
            set fields = `echo $filelist[$n] | sed 's/_/ /g'`
            set i = 1
            set found = 0
            foreach field ($fields)
               if ($field == "UNIT") then
                  set found = 1
                  break
               endif
               @ i++
            end
            if ($found == 0) then
               echo 'ERROR: EMISHOUR filenames must start with "HOUR_UNIT_[YYYY]_[MM]_", where YYYY = four-digit year and MM = two-digit month.'
               set exitstat = 1
            endif
            set nameprefix = ( `echo $filelist[$n] | cut -d_ -f1-$i` )
	 else if ($style == Hourly_CMV || $style == Hourly_CMV19 || $style == Hourly_egu) then
            # Check that the file ends with hourly
            set namecheck = `ls $filelist[$n] | awk 'match($0, /.*_hourly.csv$/) {print($0)}'|wc -m`
            if ($namecheck == 0) then
               echo 'ERROR: EMISHOUR filenames for CMV must end with "hourly.csv". Make sure the first file in your EMISHOUR_MULTI dataset ends with that suffix.'
               set exitstat = 1
            endif
	    # want prefix to be everything up until the month ID in the file name
            set i = `basename $filelist[$n] | awk 'match($0, /.*?_(0[1-9]{1}|1[0-2]{1}|[1-9]{1})_/) {print substr($0,RSTART,RLENGTH-1)}' | tr -dc '_' | awk '{ print length; }'` 
            set nameprefix = ( `dirname $filelist[$n]`/`basename $filelist[$n] | cut -d_ -f1-$i` )
	 else
            set nameprefix = ( `echo $filelist[$n] | cut -d_ -f1-$multifile_break` )
	 endif
	 
         echo nameprefix = $nameprefix
         echo month = $month
         echo monname = $monname[$month]
         #note: asterisk in the middle of the file name is to handle CEM file 
         #      naming convention, which includes the date range of the files,
         #      since some files are only for the last day of the month.

         # For all cases of Style
         switch( $style )
         case Daily:
            ## For all months but January, include file for last day of previous month.
            if ( $prevmonnum > 0 ) then
               set filename = ( `/bin/ls ${nameprefix}_$lastday[$prevmonnum]$monname[$prevmonnum]_*` )
               if ( $status > 0 ) set exitstat = 1
            else
            ## For January, include file for last day of previous year
	       echo ${nameprefix}_${lastday[12]}${monname[12]}${prevyear}
               set filename = ( `/bin/ls ${nameprefix}_${lastday[12]}${monname[12]}${prevyear}_*` )
               if ( $status > 0 ) set exitstat = 1
            endif
            ## Include file for current month.
            set filename = ( $filename `/bin/ls ${nameprefix}_${monname[$month]}_*` )
            if ( $status > 0 ) set exitstat = 1
         breaksw

         case Hourly:
            ## For all months but January, include file for last day of previous month for current year.
            if ( $prevmonnum > 0 ) then
               set filename = ( `/bin/ls ${nameprefix}_${thisyear}_*_$lastday[$prevmonnum]$monname[$prevmonnum]*` )
               if ( $status > 0 ) set exitstat = 1
            ## For January, include file for last day of previous year.
            else
               set filename = ( `/bin/ls ${nameprefix}_${prevyear}_*_${lastday[12]}${monname[12]}*` )
               if ( $status > 0 ) set exitstat = 1
            endif

            ## For all months, include files for current month (last day and other days).
            ##     Note extra asterisk before month name
	    ## If USE_FF10_DAILY_POINT = Y, then put all "thisyear" files for the entire year in there,
	    #  otherwise just put those from the current month
            set filename_x = ( $filename `/bin/ls ${nameprefix}_${thisyear}_$month*` )
            if ( $status > 0 ) set exitstat = 1
	    
	    ## C. Allen, 16 Mar 2017: Add new parameter for purposes of running SMOKE for AERMOD, in which we're not using 
	    #  FF10 daily point, but we still need entire year of PTHOURs run at once
	    if (! $?PTHOUR_WHOLE_YEAR) then
	       setenv PTHOUR_WHOLE_YEAR N
	    endif
	    if (! $?USE_FF10_DAILY_POINT) then
	       setenv USE_FF10_DAILY_POINT N
	    endif
	    if ($USE_FF10_DAILY_POINT == Y || $PTHOUR_WHOLE_YEAR == Y) then 
	       set filename_x = ( $filename `/bin/ls ${nameprefix}_${thisyear}_*` )
               if ( $status > 0 ) set exitstat = 1
	    endif	  
	    
	    set filename = ( $filename_x )
            if ( $status > 0 ) set exitstat = 1
         breaksw

         case Hourly_CMV:
         case Hourly_CMV19:
            ## For all months but December, include files for current month and next month.
	    #  For CMV19, month needs a leading zero if < 10, but not for older CMV
	    set nextmonnum0 = $nextmonnum
	    if ( $nextmonnum < 10  && $style == Hourly_CMV19 ) set nextmonnum0 = 0$nextmonnum
            if ( $nextmonnum < 13 ) then
               set filename = ( `/bin/ls ${nameprefix}_${nextmonnum0}_*_hourly.csv` )
               if ( $status > 0 ) set exitstat = 1
	       echo $filename #testing
            else # For December, include nexthour.csv files for month 12
	       set filename = ( `/bin/ls ${nameprefix}_12_*_nexthour.csv` )
               if ( $status > 0 ) set exitstat = 1
	       echo $filename #testing
	    endif
            ## For all months, include files for current month
            ##     Note extra asterisk before month name
	    @ monthnum = $month + 0
	    set monthnum0 = $monthnum
	    if ( $monthnum < 10 && $style == Hourly_CMV19 ) set monthnum0 = 0$monthnum
            set filename_x = ( $filename `/bin/ls ${nameprefix}_${monthnum0}_*_hourly.csv` )
            if ( $status > 0 ) set exitstat = 1
            echo $filename_x #testing
	    set filename = ( $filename_x )
            if ( $status > 0 ) set exitstat = 1
         breaksw

         # Hourly FF10 based EGU
         case Hourly_egu:
	    echo $nameprefix
            echo $month
	    set nextmonnum0 = $nextmonnum
            echo $nextmonnum0
	    if ( $nextmonnum < 10 ) set nextmonnum0 = 0$nextmonnum
            if ( $nextmonnum < 13 ) then
               set filename = ( `/bin/ls ${nameprefix}_${nextmonnum0}_*_hourly.csv` )
               if ( $status > 0 ) set exitstat = 1
	       echo $filename #testing
            else # For December, include nexthour.csv files for month 12
	       set filename = ( `/bin/ls ${nameprefix}_12_*_nexthour.csv` )
               if ( $status > 0 ) set exitstat = 1
	       echo $filename #testing
	    endif
            ## For all months, include files for current month
            ##     Note extra asterisk before month name
	    @ monthnum = $month + 0
	    set monthnum0 = $monthnum
	    if ( $monthnum < 10 ) set monthnum0 = 0$monthnum
            set filename_x = ( $filename `/bin/ls ${nameprefix}_${monthnum0}_*_hourly.csv` )
            if ( $status > 0 ) set exitstat = 1
            echo $filename_x #testing
	    set filename = ( $filename_x )
            if ( $status > 0 ) set exitstat = 1
         breaksw

         # Default for multifiles
         case 0:
            set filename = ( `ls ${nameprefix}_${monname[$month]}_*` )
         breaksw
	 endsw

      # If no multifile namebreak
      else
         set filename = $filelist[$n]
      endif

      if ( $exitstat > 0 ) then
          echo "SCRIPT ERROR: Some file patterns not matched for style $style"
          echo "              According to MULTIFILE_NAMEBREAK, the file prefixes are:"
          echo "                 $nameprefix"
          echo "              Check file names and rerun"
          exit ( 1 )
      endif

      # Loop through files (will usually be 1 file, but may be more for multifile case)
      foreach file ( $filename )

         # If data file exists then process it
         if ( -e $file ) then

            # Store use_ev in array for later use (in another loop)     
            set use_ev_array[$n] = $use_ev

            switch( $type )

               # Create a .lst file (for input to Smkinven)
               case list:

                  # insert #LIST header into the output file.
                  if ( $firstime == Y ) then
                     set firstime = N

                    ## If style is defined, then use style to set the header
                    if ( $style != 0 ) then
                       switch ( $style )
                          case Daily:
                             echo "#LIST EMS-95" > $outfile
                             breaksw
                          case Hourly:
			  case Hourly_CMV:
			  case Hourly_CMV19:
                          case Hourly_egu:
                             echo "#LIST CEM" > $outfile
                             breaksw
                       endsw

                    ## Otherwise, just insert the normal list file header
                    else
                       echo "#LIST" > $outfile

                    endif

                  endif

                  # insert each path and filename into the output file
                  echo $file >> $outfile

                  breaksw

               # In this loop, process only the header lines and output
               #    these to the new file's header.  Will loop again to
               #    actually output the non-header data to the output file.
               case concat:

                  # Check that nmax has not been violated
                  if ( $n > $nmax ) then
                     echo "SCRIPT ERROR: $scriptname script cannot handle more than"
                     echo "              $nmax files when type=concat is used."
                     set eflag = Y

                  # Otherwise, process header
                  else
                     if ( $firstime == Y ) then
                        set firstime = N
                        echo '#Creation Process ID:' $$ > $outfile
                     endif

                     echo "#### Header from data file:" >> $outfile
                     echo "####     "$filename >> $outfile
                     grep "^#" $filename | grep -v ^\$ >> $outfile
                  endif

                  breaksw
               default:
                  echo 'SCRIPT ERROR: Script setting for \"type\" is set to' $concat
                  set eflag = 1
            endsw

         # If data file doesn't exist, then 
         else
            echo "SCRIPT ERROR: File $file"
            echo "              does not exist. Will not add to output file."
            set eflag = Y
         endif
      end   # End loop on files

   endif    # End if e.v. is used or not

end

# Abort if an error was found in previous loop
if ( $eflag == Y ) then
   /bin/rm -f $outfile
   exit ( 1 )
endif

# For concatenate mode, loop through variables/files again to concatenate contents
#    of data files into outfile (instead of just the headers done in the previous loop).

if ( $type == concat ) then

   set n = 0
   foreach ev ( $envlist )

      @ n = $n + 1
      if ( $use_ev_array[$n] == Y ) then
         echo Including file: $filelist[$n]
         grep -v "^#" $filelist[$n] | grep -v ^\$ >> $outfile
      endif  

   end

endif  #  concat mode 

# Successful script end
exit ( 0 )

abort_with_concurrent_error:

echo 'SCRIPT ERROR: List of files requested for concatenated file does not'
echo '              match the list included in a file that was just written by'
echo '              a concurrent process.'
echo ' '
echo '     List of files INCLUDED in CURRENT file:'
foreach f ( $filelist_current )
   echo '         '$f
end
echo ' '
echo '     List of files REQUESTED for NEW file:'
foreach f ( $filelist_sorted )
   echo '         '$f
end

# Error abort script
exit ( 1 )
