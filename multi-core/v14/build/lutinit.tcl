# lut_init K BODY -- INIT string for a K-input LUT whose output is BODY evaluated with variables i0..i(K-1)
proc lut_init {k body} {
    set n [expr {1 << $k}]; set bits ""
    for {set idx [expr {$n - 1}]} {$idx >= 0} {incr idx -1} {
        for {set j 0} {$j < $k} {incr j} { set i$j [expr {($idx >> $j) & 1}] }
        append bits [expr $body]
    }
    set hex ""
    for {set p 0} {$p < $n} {incr p 4} { append hex [format %X [expr "0b[string range $bits $p [expr {$p + 3}]]"]] }
    return "${n}'h$hex"
}
# counter bit b: inputs i0 = this bit, i1 = valid, i2 = ready, i3.. = lower bits; next = bit XOR (valid AND ready AND all lower bits)
proc cnt_body {b} { set t "(\$i1 & \$i2"; for {set j 0} {$j < $b} {incr j} { append t " & \$i[expr {3 + $j}]" }; return "(\$i0 ^ $t))" }
# latched state match: i0 = flag, i1..i4 = state bits 0..3; next = flag OR (state == pattern, pattern given msb first)
proc state_body {pat} { set t "\$i0 | ("; set terms {}; for {set j 0} {$j < 4} {incr j} { set bit [string index $pat [expr {3 - $j}]]; lappend terms [expr {$bit ? "\$i[expr {1 + $j}]" : "!\$i[expr {1 + $j}]"}] }; return "$t[join $terms { && }])" }
