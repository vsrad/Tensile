use strict;

my $usage = << "ENDOFUSAGE";
Usage: $0 [<options>] <hcc_source>
    hcc_source          the source c++ file
    options
        -bs <size>      debug buffer size (mandatory)
        -ba <address>   debug buffer address (mandatory)
        -l <line>       line number to break (mandatory)
        -o <file>       output to the <file> rather than STDOUT
        -w <watches>    extra watches supplied colon separated in quotes;
                        watch type can be present
                        (like -w "a:b:c:i")
        -t <value>      target value for the loop counter
        -h              print usage information
ENDOFUSAGE

use POSIX;

my $fo      = *STDOUT;
my @watches;
my $line    = 0;
my $output  = 0;
my $bufsize;
my $bufaddr;
my $target  = 0;
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
  if ($str eq "-t")   {  $target  =            shift @ARGV;  next;   }
  if ($str eq "-h")   {  print "$usage\n";                   last;   }

  open $input, '<', $str || die "$usage\nCould not open '$str: $!";
}

die $usage unless $line && $input;

my $n_user_vars = scalar @watches;
my $n_vars = $n_user_vars + 1; # include system variable (hw regs)

my $counter_def = "volatile unsigned int counter = 0;\n";

my $plug = << "PLUG";
if (counter++ == $target) {
    uint32_t system, system_tmp;

    asm volatile(
        "v_mov_b32 \%0, 0x7777777 \\n "         // system[0] = buffer marker
        "s_getreg_b32 \%1, hwreg(HW_REG_HW_ID, 0, 32) \\n "
        "v_writelane_b32 \%0, \%1, 5 \\n "      // system[5] = HW_REG_HW_ID
        "s_getreg_b32 \%1, hwreg(HW_REG_GPR_ALLOC, 0, 32) \\n "
        "v_writelane_b32 \%0, \%1, 6 \\n "      // system[6] = HW_REG_GPR_ALLOC
        "s_getreg_b32 \%1, hwreg(HW_REG_LDS_ALLOC, 0, 32) \\n "
        "v_writelane_b32 \%0, \%1, 7 \\n "      // system[7] = HW_REG_LDS_ALLOC
        "v_writelane_b32 \%0, exec_lo, 8 \\n "  // system[8] = exec_lo
        "v_writelane_b32 \%0, exec_hi, 9"       // system[9] = exec_hi
        : "=v"(system) , "=s"(system_tmp) : );

    uint64_t offset = hc_get_workitem_id(0) +
        hc_get_workitem_id(1) * hc_get_group_size(0) +
        hc_get_workitem_id(2) * hc_get_group_size(1) * hc_get_group_size(2);
    offset += hc_get_group_id(0) * hc_get_group_size(0) +
        hc_get_group_id(1) * hc_get_group_size(0) * hc_get_group_size(1) +
        hc_get_group_id(2) * hc_get_group_size(0) * hc_get_group_size(1) * hc_get_group_size(2);
    offset *= $n_vars * sizeof(uint32_t);

    uint32_t* debug_buffer = reinterpret_cast<uint32_t*>($bufaddr + offset);
    debug_buffer[0] = system;
PLUG

while (my ($i, $watch) = each @watches) {
    $plug .= "  auto debug_watch_$i = $watch;\n";
    $plug .= "  debug_buffer[$i + 1] = *reinterpret_cast<uint32_t*>(&debug_watch_$i);\n";
}

$plug .= << "END";
    asm volatile("s_endpgm");
}
END

my $current_line = 0;
while (<$input>) {
  if (/Allocate Resources/) {
    print $fo $counter_def;
  }
  elsif ($current_line == $line) {
    print $fo "$plug\n$_";
  }
  else {
    print $fo $_;
  }
  $current_line++;
}

die "Break line out of range" if $current_line < $line;
