! Copyright (C) 2008 Doug Coleman.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors alien.c-types alien.strings alien.syntax
combinators io.backend io.files io.files.info io.files.unix kernel math
sequences system unix unix.getfsstat.openbsd grouping
unix.statfs.openbsd unix.statvfs.openbsd unix.types
specialized-arrays.direct.uint arrays io.files.info.unix
classes.struct ;
IN: io.files.unix.openbsd

TUPLE: freebsd-file-system-info < unix-file-system-info
io-size sync-writes sync-reads async-writes async-reads 
owner ;

M: openbsd new-file-system-info freebsd-file-system-info new ;

M: openbsd file-system-statfs
    \ statfs <struct> [ statfs io-error ] keep ;

M: openbsd statfs>file-system-info ( file-system-info statfs -- file-system-info' )
    {
        [ f_flags>> >>flags ]
        [ f_bsize>> >>block-size ]
        [ f_iosize>> >>io-size ]
        [ f_blocks>> >>blocks ]
        [ f_bfree>> >>blocks-free ]
        [ f_bavail>> >>blocks-available ]
        [ f_files>> >>files ]
        [ f_ffree>> >>files-free ]
        [ f_favail>> >>files-available ]
        [ f_syncwrites>> >>sync-writes ]
        [ f_syncreads>> >>sync-reads ]
        [ f_asyncwrites>> >>async-writes ]
        [ f_asyncreads>> >>async-reads ]
        [ f_fsid>> 2 <direct-uint-array> >array >>id ]
        [ f_namemax>> >>name-max ]
        [ f_owner>> >>owner ]
        [ f_fstypename>> alien>native-string >>type ]
        [ f_mntonname>> alien>native-string >>mount-point ]
        [ f_mntfromname>> alien>native-string >>device-name ]
    } cleave ;

M: openbsd file-system-statvfs ( normalized-path -- statvfs )
    \ statvfs <struct> [ statvfs io-error ] keep ;

M: openbsd statvfs>file-system-info ( file-system-info statvfs -- file-system-info' )
    f_frsize>> >>preferred-block-size ;

M: openbsd file-systems ( -- seq )
    f 0 0 getfsstat dup io-error
    statfs <c-type-array> dup dup length 0 getfsstat io-error 
    statfs heap-size group 
    [ f_mntonname>> alien>native-string file-system-info ] map ;
