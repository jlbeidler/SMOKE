        program fix_header
!
!   Purpose:           fix IOAPI header from spatial allocator output
!    for polar stereographic files
!   Programmer: George Pouliot
!    3/5/2009
!
!
!******** environmental variables used
!
!        
!         
!        FILENAME
!        
!

         implicit none
      
         include 'PARMS3.EXT'      ! I/O API constants
         include 'FDESC3.EXT'      ! I/O API file description data structure
         include 'IODECL3.EXT'     ! I/O API function declarations 

       integer logdev
       character(len=16) :: this_program, input
       character(len=16) :: output

       integer nsteps,nvars, nlays, ncols, nrows, tstep, sdate, stime
       integer istatus

       integer :: i_loop, j_loop, k_loop, l_loop,t_loop


       real, allocatable :: buffer(:,:,:,:)

       integer jdate, jtime



       character*80 mesg

       integer trimlen, envint,getefile
       external trimlen, envint, getefile
       real envreal
       external envreal


       logdev = init3()	!  initialization returns unit # for log

       this_program = 'CHECK_NEG'
       input        = 'INFILE'
       output       = 'OUTFILE'
       


        if ( .not. open3( input, FSREAD3, this_program ) ) THEN
           MESG = 'Could not open file "' //
     &     input( 1: TRIMLEN(input)) 
     &     // '" for input'
           CALL M3EXIT( this_program, 0, 0, MESG, 2 )
        end if        

        IF ( .NOT. DESC3(input))THEN
           MESG = 'Could not get description info for file "' //
     &              input( 1: TRIMLEN( input) ) //'"'
           CALL M3EXIT( this_program, 0, 0, MESG, 2 )     
        ENDIF

        nsteps  = MXREC3D
	nvars   = NVARS3D
        nlays   = NLAYS3D
	ncols   = NCOLS3D
	nrows   = NROWS3D
	sdate   = SDATE3D
	stime   = STIME3D
	tstep   = TSTEP3D	

	jdate    = sdate
	jtime    = stime
        
        GDTYP3D  = POLGRD3
	P_ALP3D  = 1.0D0
	P_GAM3D  = -98.0D0
	P_BET3D  = 45.0D0
	XCENT3D  = -98.0D0
	YCENT3D  = 90.0D0
        XORIG3D  = -7398000.0D0
	YORIG3D  = -7398000.0D0


        if ( .not. open3( output, FSUNKN3, this_program ) ) THEN
           MESG = 'Could not open file "' //
     &     output( 1: TRIMLEN(output)) 
     &     // '" for output'
           CALL M3EXIT( this_program, 0, 0, MESG, 2 )
        end if 


            allocate(buffer(ncols,nrows,nlays,nvars))


        do t_loop = 1,nsteps        
	   if ( .not. 
     &        read3(input,ALLVAR3,ALLAYS3,jdate,jtime,buffer)
     &        ) then
              mesg = 'Error reading from file '//
     &           input( 1: TRIMLEN( input ) ) 
              call m3exit( this_program, 0, 0, MESG, 2 )
           end if 

			  


	   if ( .not. 
     &        write3(output,ALLVAR3,jdate,jtime,buffer)
     &        ) then
              mesg = 'Error writing to file '//
     &           output( 1: TRIMLEN( output ) ) 
              call m3exit( this_program, 0, 0, MESG, 2 )
           end if 

           call nextime(jdate, jtime, tstep)
        enddo




	if (.not. shut3()) then
	   write (*,*) 'UNRECOVERABLE ERROR: could not do a shut3' 
	endif

	end
