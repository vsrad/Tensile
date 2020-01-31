﻿my $usage = << "ENDOFUSAGE";
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
        -a              use "auto's"; the script would not look for auto
                        watch variables (kicks in by itself if -w is empty)
        -s <N_sgpr>     number of the SGPR to use for SRD, must be 4-aligned
        -v <N_vgpr>     number of the temporary VGPR (not destroyed)
        -g <N_grp_id>   number of the SGPR containing group ID
        -r <N_vgpr>     number of the SGPR to use for loop counter
        -t <value>      target value for the loop counter
        -h              print usage information
ENDOFUSAGE

use Text::Balanced qw {extract_bracketed};
use List::MoreUtils qw(uniq);

my $args    = 0;
my $fo      = *STDOUT;
my @watches;
my $endpgm  = "s_endpgm";
my @lines;
my $line    = 0;
my $auto    = 0;
my $condit  = "1";
my $output  = 0;
my $gid     = 8;
my $sgpr    = 0;
my $vgpr    = 31;
my $counter;
my $target;
my $bufsize;
my $bufaddr;

while (scalar @ARGV) {
    my $str = shift @ARGV;
    if ($str eq "-bs")  {   $bufsize =            shift @ARGV;  next;   }
    if ($str eq "-ba")  {   $bufaddr =            shift @ARGV;  next;   }
    if ($str eq "-l")   {   $line    =            shift @ARGV;  next;   }
    if ($str eq "-o")   {   $_ = shift @ARGV;
                            open $fo, '>', $_ || die "$usage\nCould not open '$_': $!\n";
                            $output  = 1;                       next;   }
    if ($str eq "-w")   {   @watches = split /:/, shift @ARGV;  next;   }
    if ($str eq "-e")   {   $endpgm  =            shift @ARGV;  next;   }
    if ($str eq "-a")   {   $auto    = 1;                       next;   }
    if ($str eq "-s")   {   $sgpr    =            shift @ARGV;  next;   }
    if ($str eq "-v")   {   $vgpr    =            shift @ARGV;  next;   }
    if ($str eq "-g")   {   $gid     =            shift @ARGV;  next;   }
    if ($str eq "-r")   {   $counter =            shift @ARGV;  next;   }
    if ($str eq "-t")   {   $target  =            shift @ARGV;  next;   }
    if ($str eq "-h")   {   print "$usage\n";                   last;   }

    open my $df, '<', $str || die "$usage\nCould not open '$str: $!";
    push @lines, <$df>;
    close $df;
}

die $usage unless scalar (@lines) && $line;

my @done = @watches;

my $n_var   = scalar @done;
my $to_dump = join ', ', @done;
   $sgpr = 0;

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

my $dump_vars = "$done[0]";
for (my $i = 1; $i < scalar @done; $i += 1) {
	$dump_vars = "$dump_vars, $done[$i]";
}

$bufsize =  defined $ENV{'ASM_DBG_BUF_SIZE'} ? $ENV{'ASM_DBG_BUF_SIZE'} : 1048576; # 1 MB
$bufaddr =  defined $ENV{'ASM_DBG_BUF_ADDR'} ? $ENV{'ASM_DBG_BUF_ADDR'} : 0;

my $plug_macro = << "PLUGMACRO";
//n_var    = $n_var
//vars     = $dump_vars

.macro m_dbg_init gidx
	debug_init_start:
	s_mul_i32 s[sgprDbgSoff], s[\\gidx], 8 //waves_in_group
	v_readfirstlane_b32 s[sgprDbgCounter], v0
	s_lshr_b32 s[sgprDbgCounter], s[sgprDbgCounter], 6 //wave_size_log2
	s_add_u32 s[sgprDbgSoff], s[sgprDbgSoff], s[sgprDbgCounter]
	s_mul_i32 s[sgprDbgSoff], s[sgprDbgSoff], 64 * (1 + $n_var) * 4

	s_mov_b32 s[sgprDbgCounter], 0
	debug_init_end:
.endm

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
.endif
PLUGMACRO

my $insert  = << "PREAMBLE";
m_debug_plug $dump_vars
PREAMBLE

my @m = @lines [0..$line-1] if $line > 0;
my @merge = (@m, $insert, @lines [$line..scalar @lines - 1]);
foreach(@merge) {
	$_ .= "\n" . $plug_macro . qq(\nm_dbg_init sgprWorkGroup0\n) if $_ =~ /Allocate Resources/;
}

print $fo @merge;
