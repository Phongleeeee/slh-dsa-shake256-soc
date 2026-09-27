# One canonical file list shared by project generation and simulation.
proc slh_read_manifest {root name} {
    set path [file join $root hardware manifests $name]
    set fd [open $path r]
    set lines [split [read $fd] "\n"]
    close $fd
    set result {}
    foreach line $lines {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} {continue}
        set source [file normalize [file join $root $line]]
        if {![file isfile $source]} {error "Missing manifest source: $source"}
        lappend result $source
    }
    if {[llength $result] == 0} {error "Empty RTL manifest: $path"}
    return $result
}
