" Author: Tom Slee (tslee@ianywhere.com)
" Last Modified: Tue Jul 08 09:21:36 2003 
" Version: 0.4
" 
" ---------------------------------------------------------------------------
" perforce.vim - An interface to the perforce command line.  This script 
" provides a shortcut to the most frequently used operations such as edit,
" sync, and revert. There is no attempt to make this lits comprehensive. If you
" want to carry out all your p4 tasks from within vim, see Hari Krishna Dara's
" perforce integration.
"
" Perforce is a source control system, also known as 'the Fast Software 
" Configuration Management System'.  See http://www.perforce.com
" ---------------------------------------------------------------------------

" Standard code to avoid loading twice and to allow not loading
if exists("loaded_perforce")
   finish
endif
let loaded_perforce=1

" define the mappings that provide the user interface to this plug-in
augroup perforce

  " events
  autocmd FileChangedRO * nested call <SID>P4OpenFileForEditWithPrompt()
  autocmd BufRead * call <SID>P4InitialBufferVariables()
  autocmd BufRead * call <SID>P4GetFileStatus()

  " Keyboard shortcuts - default <Leader> is \
  map <silent> <Leader>e :call <SID>P4OpenFileForEdit()<CR>
  map <silent> <Leader>r :call <SID>P4RevertFile()<CR>
  map <silent> <Leader>s :echo <SID>P4GetFileStatus()<CR>
  map <silent> <Leader>y :echo <SID>P4SyncFile()<CR>
  map <silent> <Leader>d :echo <SID>P4DiffFile()<CR>

  " user-defined commands must start with a capital letter and should not include digits
  command -nargs=1 Perforce :call <SID>P4ShellCommandAndEditCurrentBuffer( <f-args> )
  command -nargs=0 PerforceLaunch :call <SID>P4LaunchFromP4()

  " menus
  menu <silent> &Perforce.&Edit :call <SID>P4OpenFileForEdit()<CR>
  menu <silent> &Perforce.&Revert :call <SID>P4RevertFile()<CR>
  menu <silent> &Perforce.&Status :echo <SID>P4GetFileStatus()<CR>
  menu <silent> &Perforce.S&ync :echo <SID>P4SyncFile()<CR>
  menu <silent> &Perforce.&Diff :echo <SID>P4DiffFile()<CR>
augroup END

"----------------------------------------------------------------------------
" Function to initialize variables
"----------------------------------------------------------------------------
function s:P4InitialBufferVariables()
    let b:headrev=""
    let b:depotfile=""
    let b:haverev=""
    let b:action=""
    let b:otheropen=""
    let b:otheraction=""
endfunction

if !exists( "p4ruler" )
    let p4SetRuler = 1
endif

if( strlen( &rulerformat ) == 0 ) && ( p4SetRuler == 1 )
  set rulerformat=%60(%=%{P4RulerStatus()}\ %4l,%-3c\ %3p%%%)
endif

"Basic check for p4-enablement
if executable( "p4.exe" )
    let s:PerforceExecutable="p4" 
else
    augroup! perforce
endif 

"----------------------------------------------------------------------------
" Minimal execution of a p4 command, followed by re-opening
" of the file so that status changes are recognised
" - mainly for use by Perforce command 
"----------------------------------------------------------------------------
function s:P4ShellCommandAndEditCurrentBuffer( sCmd )
		 call s:P4ShellCommandCurrentBuffer( a:sCmd )
		 e!
endfunction

"----------------------------------------------------------------------------
" A wrapper around a p4 command line
"----------------------------------------------------------------------------
function s:P4ShellCommandCurrentBuffer( sCmd )
    let sReturn = ""
    let filename = expand( "%:p" )
    let sCommandLine = s:PerforceExecutable . " " . a:sCmd . " " . filename 
    let sReturn = system( sCommandLine )
    " echo "P4ShellCommandCurrentBuffer " . a:sCmd
    return sReturn
endfunction

"----------------------------------------------------------------------------
" Revert a file, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4RevertFile()
    let action=confirm("p4 Revert this file and lose any changes?" ,"&Yes\n&No", 2, "Question")
    if action == 1
        let v:errmsg = ""
		 if s:P4Action() != ""
            call s:P4ShellCommandCurrentBuffer( "revert" )
		     if v:errmsg != ""
		         echoerr "Unable to revert file"
		         return
		     else
		         e!
		 		 call s:P4RestoreLastPosition()   
		     endif
		 endif
      " No, abandon changes
    elseif action == 2
      " Cancel (or any other result), don't do the edit
    endif
endfunction

"----------------------------------------------------------------------------
" Diff a file, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4DiffFile()
    call s:P4ShellCommandCurrentBuffer( "diff" )
endfunction

"----------------------------------------------------------------------------
" Sync a file, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4SyncFile()
    let action=confirm("p4 Sync this file and lose any changes?" ,"&Yes\n&No", 2, "Question")
    if action == 1
        let v:errmsg = ""
		 if s:P4Action() == ""
            call s:P4ShellCommandCurrentBuffer( "sync" )
		     if v:errmsg != ""
		         echoerr "Unable to sync file"
		         return
		     else
		         e!
		     endif
		 else
		    echoerr "File is already opened: cannot sync"
		 endif
      " No, abandon changes
    elseif action == 2
      " Cancel (or any other result), don't do the edit
    endif
"    "wincmd p
endfunction

"----------------------------------------------------------------------------
" Open a file for editing, with more checking than just wrapping the command
" This function prompts before opening -- it is used when a read-only file
" is altered for the first time
"----------------------------------------------------------------------------
function s:P4OpenFileForEditWithPrompt()
    let action=confirm("File is read only.  p4 Edit the file?" ,"&Yes\n&No", 1, "Question")
    if action == 1
    		 call s:P4OpenFileForEdit()
    endif
endfunction

"----------------------------------------------------------------------------
" Open a file for editing, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4OpenFileForEdit()
    if filewritable( expand( "%:p" ) ) == 0
        let v:errmsg = ""
        if s:P4IsCurrent() != 0
            let sync = confirm("You do not have the head revision.  p4 Sync the file before opening?", "&Yes\n&No", 1, "Question")
            if sync == 1
                call s:P4ShellCommandCurrentBuffer( "sync" )
            endif
        endif
        call s:P4ShellCommandCurrentBuffer( "edit" )
        if v:errmsg != ""
            echoerr "Unable to open file for editing"
            return
        else
            e!
            call s:P4RestoreLastPosition()   
        endif
    else
        echomsg "File is writable.  p4 Edit was not executed."
    endif
endfunction

"----------------------------------------------------------------------------
" Produce string for ruler output
"----------------------------------------------------------------------------
function P4RulerStatus()
    if !exists( "b:headrev" ) 
        let b:headrev = 0
    endif
    if b:headrev == ""
        return "[Not in p4]" 
    elseif b:action == ""
        if b:otheropen == ""
            return "[p4 unopened]"
        else
            return "[p4 " . b:otheropen . ":" . b:otheraction . "]"
        endif
    else
        return "[p4 " . b:action . "]"
    endif
endfunction

"----------------------------------------------------------------------------
" Return file status information
"----------------------------------------------------------------------------
function s:P4GetFileStatus()
    let filestatus = s:P4ShellCommandCurrentBuffer( "fstat" )

    " \\C forces case-sensitive comparison
    let b:headrev = matchstr( filestatus, "headRev [0-9]*\\C" )
    let b:headrev = strpart( b:headrev, 8 )

    let b:depotfile = matchstr( filestatus, "depotFile [0-9a-zA-Z\/]*\\C" )
    let b:depotfile = strpart( b:depotfile, 10 )

    let b:haverev = matchstr( filestatus, "haveRev [0-9]*\\C" )
    let b:haverev = strpart( b:haverev, 8 )

    let b:action = matchstr( filestatus, "action [a-zA-Z]*\\C" )
    let b:action = strpart( b:action, 7 )

    let b:otheropen = matchstr( filestatus, "otherOpen0 [a-zA-Z]*\\C" )
    let b:otheropen = strpart( b:otheropen, 11 )

    let b:otheraction = matchstr( filestatus, "otherAction0 [a-zA-Z]*\\C" )
    let b:otheraction = strpart( b:otheraction, 13 )

    if b:headrev == ""
        return "Not in p4"
    else 
        return filestatus
    endif
endfunction

"----------------------------------------------------------------------------
" One of a set of functions that returns fields from the p4 fstat command
"----------------------------------------------------------------------------
function s:P4GetDepotFile()
    let filestatus = s:P4GetFileStatus()
    let depotfile = matchstr( filestatus, "depotFile [0-9a-zA-Z\/]*" )
    let depotfile = strpart( depotfile, 10 )
    echo depotfile
endfunction

"----------------------------------------------------------------------------
" One of a set of functions that returns fields from the p4 fstat command
"----------------------------------------------------------------------------
function s:P4GetHeadRev()
    let filestatus = s:P4GetFileStatus()
    let headrev = matchstr( filestatus, "headRev [0-9]*" )
    let headrev = strpart( headrev, 8 )
    return headrev
endfunction

"----------------------------------------------------------------------------
" One of a set of functions that returns fields from the p4 fstat command
" haverev does not change without action from the client, so avoid executing
" the p4 command if possible.
"----------------------------------------------------------------------------
function s:P4GetHaveRev()
    if b:haverev != ""
		 let haverev = b:haverev 
    else
		 let filestatus = s:P4GetFileStatus()
        let haverev = matchstr( filestatus, "haveRev [0-9]*" )
        let haverev = strpart( haverev, 8 )
    endif
    return haverev
endfunction

"----------------------------------------------------------------------------
" One of a set of functions that returns fields from the p4 fstat command
"----------------------------------------------------------------------------
function s:P4IsCurrent()
    let revdiff = s:P4GetHeadRev() - s:P4GetHaveRev()
    if revdiff == 0
    		 return 0
    else
    		 return -1
    endif
endfunction

"----------------------------------------------------------------------------
" One of a set of functions that returns fields from the p4 fstat command
"----------------------------------------------------------------------------
function s:P4Action()
    let filestatus = s:P4GetFileStatus()
    let action = matchstr( filestatus, "action [a-zA-Z]*\\C" )
    let action = strpart( action, 7 )
    return action
endfunction

"----------------------------------------------------------------------------
" Function to be called when loading vim as the p4 editor 
" ( on "p4 submit", "p4 client" and some others )
"----------------------------------------------------------------------------
function s:P4LaunchFromP4()
    " search for description text, starting from the end of the file and 
    " wrapping
    "
    let submitdescription = "<enter description here>" 
    let clientdescription = "^View:"
    normal G$
    let ret = search( submitdescription, "w" )
    if ret != 0 " string found -- launched by p4 submit or p4 job
	silent exec 'norm! C'
	silent exec 'startinsert'
    else
        let retclient = search( clientdescription, "w" )
	if retclient != 0 " string found -- launched by p4 client or p4 branch
	    silent exec 'norm! j'
	    silent exec 'norm! z.'
	else
	    silent exec 'norm! 1G'
	endif
    endif
endfunction

"----------------------------------------------------------------------------
" Function to restore last position when re-opening a file 
" after edit or revert or sync
"----------------------------------------------------------------------------
function s:P4RestoreLastPosition()
    if line("'\"") > 0 && line("'\"") <= line("$") |
		 exe "normal g`\"" |
    endif
endfunction


