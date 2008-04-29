! Copyright (C) 2008 Doug Coleman.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors kernel math namespaces sequences random
strings
math.bitfields.lib namespaces.lib db db.tuples db.types
math.intervals ;
IN: db.queries

TUPLE: query tuple order group having ;

GENERIC: where ( specs obj -- )

: maybe-make-retryable ( statement -- statement )
    dup in-params>> [ generator-bind? ] contains? [
        make-retryable
    ] when ;

: query-make ( class quot -- )
    >r sql-props r>
    [ 0 sql-counter rot with-variable ] { "" { } { } } nmake
    <simple-statement> maybe-make-retryable ; inline

M: db begin-transaction ( -- ) "BEGIN" sql-command ;
M: db commit-transaction ( -- ) "COMMIT" sql-command ;
M: db rollback-transaction ( -- ) "ROLLBACK" sql-command ;

: where-primary-key% ( specs -- )
    " where " 0%
    find-primary-key dup column-name>> 0% " = " 0% bind% ;

M: db <update-tuple-statement> ( class -- statement )
    [
        "update " 0% 0%
        " set " 0%
        dup remove-id
        [ ", " 0% ] [ dup column-name>> 0% " = " 0% bind% ] interleave
        where-primary-key%
    ] query-make ;

M: random-id-generator eval-generator ( singleton -- obj )
    drop
    system-random-generator get [
        63 [ 2^ random ] keep 1 - set-bit
    ] with-random ;

: interval-comparison ( ? str -- str )
    "from" = " >" " <" ? swap [ "= " append ] when ;

: fp-infinity? ( float -- ? )
    dup float? [
        double>bits -52 shift 11 2^ 1- [ bitand ] keep =
    ] [
        drop f
    ] if ;

: where-interval ( spec obj from/to -- )
    over first fp-infinity? [
        3drop
    ] [
        pick column-name>> 0%
        >r first2 r> interval-comparison 0%
        bind#
    ] if ;

: in-parens ( quot -- )
    "(" 0% call ")" 0% ; inline

M: interval where ( spec obj -- )
    dup [ from>> ] [ to>> ] bi
    [ first fp-infinity? ] bi@ and [
        2drop
        " 1 = 1 " 0% ! dummy
    ] [
        [
            [ from>> "from" where-interval ] [
                nip [ from>> ] [ to>> ] bi
                [ first fp-infinity? ] bi@ or [ " and " 0% ] unless
            ] [ to>> "to" where-interval ] 2tri
        ] in-parens
    ] if ;

M: sequence where ( spec obj -- )
    [
        [ " or " 0% ] [ dupd where ] interleave drop
    ] in-parens ;

: object-where ( spec obj -- )
    over column-name>> 0% " = " 0% bind# ;

M: object where ( spec obj -- ) object-where ;

M: integer where ( spec obj -- ) object-where ;

M: string where ( spec obj -- ) object-where ;

: where-clause ( tuple specs -- )
    " where " 0% [
        " and " 0%
    ] [
        2dup slot-name>> swap get-slot-named where
    ] interleave drop ;

M: db <delete-tuple-statement> ( tuple table -- sql )
    [
        "delete from " 0% 0%
        dupd
        [ slot-name>> swap get-slot-named ] with filter
        dup empty? [ 2drop ] [ where-clause ] if ";" 0%
    ] query-make ;

M: db <select-by-slots-statement> ( tuple class -- statement )
    [
        "select " 0%
        over [ ", " 0% ]
        [ dup column-name>> 0% 2, ] interleave

        " from " 0% 0%
        dupd
        [ slot-name>> swap get-slot-named ] with filter
        dup empty? [ 2drop ] [ where-clause ] if ";" 0%
    ] query-make ;
