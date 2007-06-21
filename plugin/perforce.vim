" Authors: Tom Slee (tslee@ianywhere.com); Suresh Srinivasan; Terrance Cohen
" Last Modified: Mon May 28 2007
" Version: 0.5
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
  map <silent> <Leader><Leader> :echo <SID>P4GetInfo()<CR>
  map <silent> <Leader>a :echo <SID>P4AnnotateFile()<CR>
  map <silent> <Leader>e :call <SID>P4OpenFileForEdit()<CR>
  map <silent> <Leader>r :call <SID>P4RevertFile()<CR>
  map <silent> <Leader>i :echo <SID>P4GetFileStatus()<CR>
  map <silent> <Leader>s :echo <SID>P4GetFileStatus()<CR> " For backward compatibility
  map <silent> <Leader>y :echo <SID>P4SyncFile()<CR>
  map <silent> <Leader>d :echo <SID>P4DiffFile()<CR>
  map <silent> <Leader>u :echo <SID>P4UDiffFile()<CR>
  map <silent> <Leader>z :echo <SID>P4VDiffFile()<CR>
  map <silent> <Leader>v :echo <SID>P4VersionsFile()<CR>
  map <silent> <Leader>p :echo <SID>P4PrintFile()<CR>
  map <silent> <Leader>h :echo <SID>P4Help()<CR>
  map <silent> <Leader>l :call <SID>P4Login()<CR>
  map <silent> <Leader>x :call <SID>P4OpenFileForDeletion()<CR>
  map <silent> <Leader>C :call <SID>P4CreateChangelist()<CR>
  map <silent> <Leader>D :echo <SID>P4DiffFiles()<CR>
  map <silent> <Leader>U :echo <SID>P4UDiffFiles()<CR>
  map <silent> <Leader>L :echo <SID>P4GetChangelists(1)<CR>
  map <silent> <Leader>I :echo <SID>P4GetChangelistInfo()<CR>
  map <silent> <Leader>F :echo <SID>P4GetFiles()<CR>
  map <silent> <Leader>X :call <SID>P4DeleteChangelist()<CR>
  map <silent> <Leader>S :call <SID>P4SubmitChangelist()<CR>

  " user-defined commands must start with a capital letter and should not include digits
  command -nargs=1 Perforce :call <SID>P4ShellCommandAndEditCurrentBuffer( <f-args> )
  command -nargs=0 PerforceLaunch :call <SID>P4LaunchFromP4()

  " menus
  menu <silent> &Perforce.&Login :call <SID>P4Login()<CR>
  menu <silent> &Perforce.Info :echo <SID>P4GetInfo()<CR>
  menu <silent> Perforce.-Sep1- :
  menu <silent> &Perforce.Show\ file\ &annotated :echo <SID>P4AnnotateFile()<CR>
  menu <silent> &Perforce.List\ file\ &versions :echo <SID>P4VersionsFile()<CR>
  menu <silent> &Perforce.&Diff :echo <SID>P4DiffFile()<CR>
  menu <silent> &Perforce.&Unified diff :echo <SID>P4UDiffFile()<CR>
  menu <silent> &Perforce.&Edit :call <SID>P4OpenFileForEdit()<CR>
  menu <silent> &Perforce.Mark\ file\ for\ deletion :call <SID>P4OpenFileForDeletion()<CR>
  menu <silent> &Perforce.&Revert :call <SID>P4RevertFile()<CR>
  menu <silent> &Perforce.S&ync :echo <SID>P4SyncFile()<CR>
  menu <silent> &Perforce.&Status :echo <SID>P4GetFileStatus()<CR>
  menu <silent> Perforce.-Sep2- :
  menu <silent> &Perforce.Submit\ changelist :call <SID>P4SubmitChangelist()<CR>
  menu <silent> Perforce.-Sep3- :
  menu <silent> &Perforce.&Create\ changelist :call <SID>P4CreateChangelist()<CR>
  menu <silent> &Perforce.Diff\ all\ files :echo <SID>P4DiffFiles()<CR>
  menu <silent> &Perforce.Unified diff\ all\ files :echo <SID>P4UDiffFiles()<CR>
  menu <silent> &Perforce.Delete\ changelist :call <SID>P4DeleteChangelist()<CR>
  menu <silent> &Perforce.List\ change&lists :echo <SID>P4GetChangelists(1)<CR>
  menu <silent> &Perforce.Get\ changelist\ info :echo <SID>P4GetChangelistInfo()<CR>
  menu <silent> &Perforce.List\ &file\ names :echo <SID>P4GetFiles()<CR>
augroup END

"----------------------------------------------------------------------------
" Initialize variables
"----------------------------------------------------------------------------
function s:P4InitialBufferVariables()
    let b:headrev=""
    let b:depotfile=""
    let b:haverev=""
    let b:action=""
    let b:otheropen=""
    let b:otheraction=""
    let b:changelist=""
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
" of the file so that status changes are recognised. This is
" mainly for use by Perforce command.
"----------------------------------------------------------------------------
function s:P4ShellCommandAndEditCurrentBuffer( sCmd )
		 call s:P4ShellCommandCurrentBuffer( a:sCmd )
		 e!
endfunction

"----------------------------------------------------------------------------
" A wrapper around a p4 command line for the current buffer
"----------------------------------------------------------------------------
function s:P4ShellCommandCurrentBuffer( sCmd )
                let filename = expand( "%:p" )
                return s:P4ShellCommand( a:sCmd . " " . filename )
endfunction

"----------------------------------------------------------------------------
" A wrapper around a p4 command line
"----------------------------------------------------------------------------
function s:P4ShellCommand( sCmd )
    let sReturn = ""
    let sCommandLine = s:PerforceExecutable . " " . a:sCmd
    let v:errmsg = ""
    let sReturn = system( sCommandLine )
    if v:errmsg == ""
        if match( sReturn, "Perforce password (P4PASSWD) invalid or unset\." ) != -1
            let v:errmsg = "Not logged in to Perforce."
        elseif v:shell_error != 0
            let v:errmsg = sReturn
        else
            return sReturn
        endif
    endif
endfunction

"----------------------------------------------------------------------------
" Return the p4 command line string
"----------------------------------------------------------------------------
function s:P4GetShellCommand( sCmd )
    return s:PerforceExecutable . " " . a:sCmd
endfunction

"----------------------------------------------------------------------------
" Revert a file, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4RevertFile()
    let action=confirm("p4 Revert this file and lose any changes?" ,"&Yes\n&No", 2, "Question")
    if action == 1
		 if s:P4Action() != ""
            call s:P4ShellCommandCurrentBuffer( "revert" )
		     if v:errmsg != ""
		         echoerr "Unable to revert file. " . v:errmsg
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
    let diff = s:P4ShellCommandCurrentBuffer( "diff -db" )
    return diff
endfunction

"----------------------------------------------------------------------------
" Unified diff a file, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4UDiffFile()
    let diff = s:P4ShellCommandCurrentBuffer( "diff -du -db" )
    return diff
endfunction

"----------------------------------------------------------------------------
" Diff between different versions of a file
"----------------------------------------------------------------------------
function s:P4VDiffFile()
    let s = inputdialog( "Version(s) to diff: ")
    echo "\n"
    if s != ""
        let vers = split(s)
        let i = 0
        let files = ""
        for v in vers
            let files = files . ' ' . expand( "%:p" ) . '#' . v
            let i = i + 1
            if i == 2
                break
            endif
        endfor
        let cmd = ""

        if i == 0
            return ""
        elseif i == 1
            let cmd = "diff"
        elseif i == 2
            let cmd = "diff2"
        endif
        return s:P4ShellCommand(cmd . ' -db ' . files)
    else
        return ""
    endif
endfunction

"----------------------------------------------------------------------------
" List version history of the file.
"----------------------------------------------------------------------------
function s:P4VersionsFile()
    let verinfo = s:P4ShellCommandCurrentBuffer( "filelog -l" )
    if v:errmsg != ""
        echoerr "Unable to get version info. " . v:errmsg
        return ""
    endif
    let cllist = split(verinfo, "\n")
    let l = ""
    let gotchange = 0
    let getcomment = 0
    let cl = ""
    for item in cllist[1:-1]
        if match(item, '^\s*$') != -1
            if gotchange == 1
                let getcomment = 1
                let gotchange = 0
            elseif getcomment == 1
                let l = l . ' ' . cl . "\n"
                let cl = ""
                let getcomment = 0
            endif
            continue
        endif
        if getcomment == 1
            let cl = cl . ' ' . strpart(item, 1)
        else
            let fields = split(item)
            if fields[2] == 'change'
                let user = split(fields[8], "@")[0]
                let cl = printf("%4.4s %6d %s %-12s", fields[1], fields[3], fields[6], user)
                let gotchange = 1
                let getcomment = 1
            endif
        endif
    endfor
    return l
endfunction

"----------------------------------------------------------------------------
" Print the file.
"----------------------------------------------------------------------------
function s:P4PrintFile()
    let versions = s:P4VersionsFile()
    let ver = inputdialog(versions . "\n\n" . "Specify version to print", b:haverev)
    if v:errmsg != "" || ver == ""
        return ""
    endif
    let filename = expand( "%:p" ) . '#' . ver
    return s:P4ShellCommand("print " . filename )
    let p = s:P4ShellCommandCurrentBuffer( "print" )
    return p
endfunction

"----------------------------------------------------------------------------
" Sync a file, with more checking than just wrapping the command
"----------------------------------------------------------------------------
function s:P4SyncFile()
    let action=confirm("p4 sync this file and lose any changes?" ,"&Yes\n&No", 2, "Question")
    if action == 1
		 if s:P4Action() == ""
            call s:P4ShellCommandCurrentBuffer( "sync" )
		     if v:errmsg != ""
		         echoerr "Unable to sync file. " . v:errmsg
		         return
		     else
		         e!
		     endif
		 else
		    echoerr "File is already opened: cannot sync."
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
    if filewritable(expand( "%:p" ) ) == 0
        if s:P4IsCurrent() != 0
            let sync = confirm("You do not have the head revision.  p4 sync the file before opening?", "&Yes\n&No", 1, "Question")
            if sync == 1
                call s:P4ShellCommandCurrentBuffer( "sync" )
            endif
        endif
    endif
    if (b:headrev == "" || b:action == "add")
        let action = "add"
    else
        let action = "edit"
    endif
    let listnum = ""
    let listnum = s:P4GetChangelist( "Current changelists:\n" . s:P4GetChangelists(0) . "\nEnter changelist number: ", b:changelist )
    if listnum == ""
        echomsg "No changelist specified. Edit cancelled."
        return
    endif
    call s:P4ShellCommandCurrentBuffer( action . " -c " . listnum )
    if v:errmsg != ""
        echoerr "Unable to open file for " action . ". " . v:errmsg
        return
    else
        e!
        call s:P4RestoreLastPosition()   
    endif
endfunction

"----------------------------------------------------------------------------
" Print annotated version of file
"----------------------------------------------------------------------------
function s:P4AnnotateFile()
    let p = s:P4ShellCommandCurrentBuffer( "annotate -q -db")
    return p
endfunction

"----------------------------------------------------------------------------
" Delete a file
"----------------------------------------------------------------------------
function s:P4OpenFileForDeletion()
    let action=confirm("Mark file for deletion?" ,"&Yes\n&No", 2, "Question")
    if action == 1
        let listnum = ""
        let listnum = s:P4GetChangelist( "Current changelists:\n" . s:P4GetChangelists(0) . "\nEnter changelist number: ", "" )
        if listnum == ""
            echomsg "No changelist specified. Delete cancelled."
            return
        endif
        call s:P4ShellCommandCurrentBuffer( "delete -c " . listnum )
        if v:errmsg != ""
            echoerr "Unable to mark file for deletion. " . v:errmsg
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
        call s:P4InitialBufferVariables()
    endif
    if b:action == ""
        if b:headrev == ""
            return "[Not in p4]" 
        elseif b:otheropen == ""
            return "[p4 unopened]"
        else
            return "[p4 " . b:otheraction . ":" . b:otheropen . "]"
        endif
    else
        return "[p4 " . b:action . b:changelist . "]"
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

    let b:changelist = matchstr( filestatus, "change [0-9]*\\C" )
    let b:changelist = strpart( b:changelist, 6 )

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
" Restore last position when re-opening a file 
" after edit or revert or sync
"----------------------------------------------------------------------------
function s:P4RestoreLastPosition()
    if line("'\"") > 0 && line("'\"") <= line("$") |
		 exe "normal g`\"" |
    endif
endfunction

"----------------------------------------------------------------------------
" Get info about a changelist
"----------------------------------------------------------------------------
function s:P4GetChangelistInfo()
    let listnum = ""
    let listnum = s:P4GetChangelist( "Current changelists:\n" . s:P4GetChangelists(1) . "\nEnter changelist number: ", b:changelist )
    if listnum == ""
        echomsg "No changelist specified. Cancelled."
        return
    endif
    let l = s:P4ShellCommand("changelist -o " . listnum)
    return l
endfunction

"----------------------------------------------------------------------------
" Get the current user's list of pending changelists
" sAll: Show changelists for all clients. Otherwise, only the pending
"   changelists in the current client is shown.
"----------------------------------------------------------------------------
function s:P4GetChangelists(sAll)
    let opt = ''
    if (a:sAll == 0)
        let opt = ' -c ' . $P4CLIENT
    endif
    let cmd = "changes -L -s pending -u " . $USER . opt
    let filestatus = s:P4ShellCommand(cmd)
    if v:errmsg != ""
        echoerr "Unable to get change lists. " . v:errmsg
        return ''
    endif
    let cllist = split(filestatus, "\n")
    let filestatus = ""
    let item = ''
    let info = ''
    for item in cllist
        if match(item, '^\s*$') != -1
            continue
        endif
        if match(item, '^Change') != -1
            if info != ''
                let filestatus = filestatus . info . "\n"
            endif
            let info = matchstr(item, "[0-9][0-9]*")
        else
            let info = info . ' ' . substitute(item, '^\s*', '', '')
        endif
    endfor
    if info != ''
        let filestatus = filestatus . info . "\n"
    endif
    return filestatus
endfunction

"----------------------------------------------------------------------------
" Get a changelist
"----------------------------------------------------------------------------
function s:P4GetChangelist(sPrompt, sDefault)
    let listnum = inputdialog( a:sPrompt, a:sDefault)
    if listnum != ""
        let b:changelist = listnum
    endif
    return listnum
endfunction

"----------------------------------------------------------------------------
" Create a changelist
"----------------------------------------------------------------------------
function s:P4CreateChangelist()
    let desc = ""
    let desc = inputdialog( "New changelist description: ")
    echo "\n"
    if desc != ""
        let cmd = s:P4GetShellCommand( "change -i" )
        let result = system ( cmd, "Description: " . desc . "\nChange: new")
        echo result
    endif
endfunction

"----------------------------------------------------------------------------
" Return list of files for a changelist
"----------------------------------------------------------------------------
function s:P4GetFiles()
    let listnum = ""
    let listnum = s:P4GetChangelist( "Current changelists:\n" . s:P4GetChangelists(0) . "\nEnter changelist number: ", b:changelist )
    if listnum == ""
        echomsg "No changelist specified. Cancelled."
        return
    endif
    let l = s:P4ShellCommand("opened -c " . listnum)
    if v:errmsg != ""
        echoerr "Unable to get list of files for changelist " .  listnum . ". "  . v:errmsg
        return ""
    endif
    let cllist = split(l, "\n")
    let l = ""
    for item in cllist
        let l = l . substitute(item, " change.*", "", "") . "\n"
    endfor
    return l
endfunction

"----------------------------------------------------------------------------
" Diff all files in current changelist
"----------------------------------------------------------------------------
function s:P4DiffFiles()
    let files = s:P4GetFiles()
    let cllist = split(files, "\n")
    let diffout = ""
    for item in cllist
        let f = substitute(item, " -.*", "", "")
        let diffout = diffout . "\n" . s:P4ShellCommand("diff -db " . f)
    endfor
    return diffout
endfunction

"----------------------------------------------------------------------------
" Unified diff all files in current changelist
"----------------------------------------------------------------------------
function s:P4UDiffFiles()
    let files = s:P4GetFiles()
    let cllist = split(files, "\n")
    let diffout = ""
    for item in cllist
        let f = substitute(item, " -.*", "", "")
        let diffout = diffout . "\n" . s:P4ShellCommand("diff -du -db " . f)
    endfor
    return diffout
endfunction

"----------------------------------------------------------------------------
" Delete a changelist
"----------------------------------------------------------------------------
function s:P4DeleteChangelist()
    let listnum = ""
    let listnum = s:P4GetChangelist( "Current changelists:\n" . s:P4GetChangelists(0) . "\nEnter changelist number: ", "")
    if listnum == ""
        echomsg "No changelist specified. Delete cancelled."
        return
    endif
    let action=confirm("Really p4 delete the changelist?" ,"&Yes\n&No", 1, "Question")
    if action == 1
        let result = s:P4ShellCommand("change -d " . listnum)
        if v:errmsg != ""
            echoerr "Unable to delete changelist " . listnum . ". " . v:errmsg
            return
        endif
    endif
endfunction

"----------------------------------------------------------------------------
" Submit current changelist
"----------------------------------------------------------------------------
function s:P4SubmitChangelist()
    let listnum = ""
    let listnum = s:P4GetChangelist( "Current changelists:\n" . s:P4GetChangelists(0) . "\nEnter changelist number: ", b:changelist )
    if listnum == ""
        echomsg "No changelist specified. Submit cancelled."
        return
    endif
    let action=confirm("Really checkin all the files?" ,"&Yes\n&No", 2, "Question")
    if action == 1
        let result = s:P4ShellCommand("submit -c " . listnum)
        if v:errmsg != ""
            echoerr "Unable to submit changelist " . listnum . ". " . v:errmsg
            return
         else
             e!
             call s:P4RestoreLastPosition()   
        endif
    endif
endfunction

"----------------------------------------------------------------------------
" Get general perforce info
"----------------------------------------------------------------------------
function s:P4GetInfo()
    let foo = s:P4ShellCommand("info")
    return foo
endfunction

"----------------------------------------------------------------------------
" Log in to perforce
"----------------------------------------------------------------------------
function s:P4Login()
    " s:P4ShellCommand( "login" )
    let cmd = "!" . s:PerforceExecutable . " login"
    :exec cmd
endfunction

"----------------------------------------------------------------------------
" Display help
"----------------------------------------------------------------------------
function s:P4Help()
    return "Format: <Leader>letter, where letter is one of:\n" .
    \ "\n" .
    \ "h - Display this help message\n" .
    \ "l - Login\n" .
    \ "<Leader> - Perforce info\n" .
    \ "\nCurrent File commands:\n" .
    \ "e - Edit/add file to a changelist\n" .
    \ "x - Mark file to changelist for deletion\n" .
    \ "r - Revert file\n" .
    \ "i - Get file info\n" .
    \ "s - Get file info\n" .
    \ "v - Show versions\n" .
    \ "d - Diff file\n" .
    \ "u - Unified diff file\n" .
    \ "z - Diff specific versions of file\n" .
    \ "p - Print depot file\n" .
    \ "a - Print file annotated\n" .
    \ "y - Sync file\n" .
    \ "\nChangelist commands:\n" .
    \ "C - Create a changelist\n" .
    \ "D - Diff all files in a changelist\n" .
    \ "U - Unified diff all files in a changelist\n" .
    \ "X - Delete a changelist\n" .
    \ "I - Print info about (current) changelist\n" .
    \ "L - List changelists\n" .
    \ "F - List files in (current) changelist\n" .
    \ "S - Submit (current) changelist\n" .
    \ ""
endfunction
