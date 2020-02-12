use strict;

my $usage = << "ENDOFUSAGE";
Usage: $0 [<options>] <gcnasm_source>
    gcnasm_source          the source s file
    options
        -bs <size>      debug buffer size (mandatory)
        -ba <address>   debug buffer address (mandatory)
        -l <line>       line number to break (mandatory)
        -o <file>       output to the <file> rather than STDOUT
        -w <watches>    extra watches supplied colon separated in quotes;
                        watch type can be present
                        (like -w "a:b:c:i")
        -e <command>    instruction to insert after the injection
                        instead of "s_endpgm"; if "NONE" is supplied
                        then none is added
        -t <value>      target value for the loop counter
        -h              print usage information
ENDOFUSAGE

use POSIX;

my $fo      = *STDOUT;
my @watches;
my $endpgm  = "s_endpgm";
my $line    = 0;
my $output  = 0;
my $bufsize;
my $bufaddr;
my $target;
my $input;

while (scalar @ARGV) {
  my $str = shift @ARGV;
  if ($str eq "-bs")  {  $bufsize =            shift @ARGV;  next;   }
  if ($str eq "-ba")  {  $bufaddr =            shift @ARGV;  next;   }
  if ($str eq "-l")   {  $line    =            shift @ARGV;  next;   }
  if ($str eq "-o")   {  $_ = shift @ARGV;
                          open $fo, '>', $_ || die "$usage\nCould not open '$_': $!\n";
                                                              next;   }
  if ($str eq "-w")   {  @watches = split /:/, shift @ARGV;  next;   }
  if ($str eq "-e")   {  $endpgm  =            shift @ARGV;  next;   }
  if ($str eq "-t")   {  $target  =            shift @ARGV;  next;   }
  if ($str eq "-h")   {  print "$usage\n";                   last;   }

  open $input, '<', $str || die "$usage\nCould not open '$str: $!";
}

die $usage unless $line && $input;

my $n_var   = scalar @watches;
my $to_dump = join ', ', @watches;

my $loopcounter = << "LOOPCOUNTER";
        s_cbranch_scc1 debug_dumping_loop_counter_lab1_\\\@
        s_add_u32       s[sgprDbgCounter], s[sgprDbgCounter], 1
        s_cmp_eq_u32    s[sgprDbgCounter], $target
        s_cbranch_scc0  debug_dumping_loop_counter_lab_\\\@
debug_dumping_loop_counter_lab1_\\\@\:
        s_add_u32       s[sgprDbgCounter], s[sgprDbgCounter], 1
        s_cmp_lt_u32    s[sgprDbgCounter], $target
        s_cbranch_scc1  debug_dumping_loop_counter_lab_\\\@
LOOPCOUNTER
$loopcounter = "" unless $target;

my $dump_vars = "$watches[0]";
for (my $i = 1; $i < scalar @watches; $i += 1) {
  $dump_vars = "$dump_vars, $watches[$i]";
}

my $plug_macro = << "PLUGMACRO";
// debug plug resource allocation
//n_var    = $n_var
//vars     = $dump_vars

debug_init_start:
s_mul_i32 s[sgprDbgSoff], s[sgprWorkGroup0], 8 //waves_in_group
v_readfirstlane_b32 s[sgprDbgCounter], v0
s_lshr_b32 s[sgprDbgCounter], s[sgprDbgCounter], 6 //wave_size_log2
s_add_u32 s[sgprDbgSoff], s[sgprDbgSoff], s[sgprDbgCounter]
s_mul_i32 s[sgprDbgSoff], s[sgprDbgSoff], 64 * (1 + $n_var) * 4

s_mov_b32 s[sgprDbgCounter], 0
debug_init_end:

.macro m_debug_plug vars:vararg
//  debug dumping dongle begin
$loopcounter

    v_save   = vgprDbg
    s_srd    = sgprDbgSrd
    s_grp    = sgprDbgSoff

    // construct sgprDbgSrd
    s_mov_b32 s[sgprDbgSrd+0], 0xFFFFFFFF & $bufaddr
    s_mov_b32 s[sgprDbgSrd+1], ($bufaddr >> 32)
    s_mov_b32 s[sgprDbgSrd+3], 0x804fac
    // TODO: change n_var to buffer size
    s_add_u32 s[sgprDbgSrd+1], s[sgprDbgSrd+1], (($n_var + 1) << 18)

    s_mov_b32 s[sgprDbgStmp], exec_lo
    s_mov_b32 s[sgprDbgCounter], exec_hi
    v_mov_b32       v[v_save], 0x7777777
    v_writelane_b32 v[v_save], s[s_srd+0], 1
    v_writelane_b32 v[v_save], s[s_srd+1], 2
    v_writelane_b32 v[v_save], s[s_srd+2], 3
    v_writelane_b32 v[v_save], s[s_srd+3], 4
    s_getreg_b32    s[sgprDbgStmp], hwreg(4, 0, 32)   //  fun stuff
    v_writelane_b32 v[v_save], s[sgprDbgStmp], 5
    s_getreg_b32    s[sgprDbgStmp], hwreg(5, 0, 32)
    v_writelane_b32 v[v_save], s[sgprDbgStmp], 6
    s_getreg_b32    s[sgprDbgStmp], hwreg(6, 0, 32)
    v_writelane_b32 v[v_save], s[sgprDbgStmp], 7
    v_writelane_b32 v[v_save], exec_lo, 8
    v_writelane_b32 v[v_save], exec_hi, 9
    s_mov_b64 exec, -1

    buffer_store_dword v[v_save], off, s[s_srd:s_srd+3], s[s_grp] offset:0

    //var to_dump = [$to_dump]
    .if $n_var > 0
      buf_offset\\\@ = 0
      .irp var, \\vars
        buf_offset\\\@ = buf_offset\\\@ + 4
        v_mov_b32 v[v_save], \\var
        buffer_store_dword v[v_save], off, s[s_srd:s_srd+3], s[s_grp] offset:0+buf_offset\\\@
      .endr
    .endif

    s_mov_b32 exec_lo, s[sgprDbgStmp]
    s_mov_b32 exec_hi, s[sgprDbgCounter]

    $endpgm
  debug_dumping_loop_counter_lab_\\\@\:
//  debug dumping_dongle_end_:
.endm
PLUGMACRO

my $vgprs_used = 1;
my $sgprs_used = 7;
my $sgprs;
my $vgprs;

my $current_line = 0;
while (<$input>) {
  if (/workitem_vgpr_count/) {
    print $fo s/(\d+)/$1 + $vgprs_used/er;
    $vgprs = $1;
  }
  elsif (/wavefront_sgpr_count/) {
    print $fo s/(\d+)/$1 + $sgprs_used/er;
    $sgprs = $1;
  }
  elsif (/compute_pgm_rsrc1_vgprs/) {
    my $vrs = floor(($vgprs + $vgprs_used - 1) / 4);
    print $fo s/= \d+/"= $vrs"/er;
  }
  elsif (/compute_pgm_rsrc1_sgprs/) {
    my $srs = floor(($sgprs + $sgprs_used - 1) / 8);
    print $fo s/= \d+/"= $srs"/er;
  }
  elsif (/Num VGPR=/) {
    print $fo ".set vgprDbg, " . $vgprs . "\n$_";
  }
  elsif (/max SGPR=/) {
    my @single_sgprs = qw(sgprDbgStmp sgprDbgSoff sgprDbgCounter);
    while ($sgprs_used) {
      if ($sgprs_used >= 4 && $sgprs % 4 == 0) {
        print $fo ".set sgprDbgSrd, " . $sgprs . "\n";
        $sgprs += 4;
        $sgprs_used -= 4;
      }
      else {
        my $sgpr = shift @single_sgprs;
        print $fo ".set " . $sgpr . ", " . $sgprs . "\n";
        $sgprs += 1;
        $sgprs_used -= 1;
      }
    }
    print $fo $_;
  }
  elsif (/Allocate Resources/) {
    print $fo "$plug_macro\n$_";
  }
  elsif ($current_line == $line) {
    print $fo "m_debug_plug $dump_vars\n$_";
  }
  else {
    print $fo $_;
  }
  $current_line++;
}

die "Break line out of range" if $current_line < $line;
