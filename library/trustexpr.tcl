# trust.tcl
#
# Plugin Trust modules utility functions
#
# SCCS: @(#) trustexpr.tcl 1.1 97/06/24 13:25:46
# RCS:  @(#) $Id$
#
# Author:  Laurent Demailly     (Laurent.Demailly@sun.com, dl@mail.box.eu.org)
#
# Please contact us directly for questions, comments and enhancements.
#
# Copyright (c) 1997 by Sun Microsystems, Inc.
# Copyright (c) 2000 by Scriptics Corporation.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
# 


######
# trust_translate_expr
#
# Translates trust control expressions into tcl expressions
#
# Takes a string like "(a && b) || c"
# and translate it into a Tcl expression 
# "([${prefix}a${suffix}] && [${prefix}b${suffix}]) || [${prefix}c${suffix}]"
# so if called like in
#     trust_translate_exp "(a && b) || c" trust_ { $val}
# ->  ([trust_a $val] && [trust_b $val]) || [trust_c $val]
# We assume and (&&) where no operator is found
# so called with "a b c" returns "[a]&&[b]&&[c]"
#
# Returns a string ready for "expr" evalutation
#
proc trust_translate_expr {expr {prefix ""} {suffix ""}} {
    # white spaces
    set ws "\r\n\t ";
    # operators chars list :
    # (^ must be first for use in "not in set [^...]" regexp)
    set opc "^|&+!=+-/<>" ;
    set re [subst -nocommands {([^$opc])([$ws]+)([^$opc])}];
    # while is needed because of "a b c" test case...
    while {[regsub -all $re $expr {\1\&\&\3} expr]} {};
    regsub -all -nocase {[a-z][a-z0-9_]*} $expr "\[${prefix}&${suffix}\]" expr;
    return $expr;
}

