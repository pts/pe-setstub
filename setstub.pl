#! /bin/sh
eval '(exit $?0)' && eval 'PERL_BADLANG=x;PATH="$PATH:.";export PERL_BADLANG\
 PATH;exec perl -x -S -- "$0" ${1+"$@"};#'if 0;eval 'setenv PERL_BADLANG x\
;setenv PATH "$PATH":.;exec perl -x -S -- "$0" $argv:q;#'.q
#!perl -w
+push@INC,'.';$0=~/(.*)/s;do(index($1,"/")<0?"./$1":$1);die$@if$@__END__+if 0
;#Don't touch/remove lines 1--7: http://pts.github.io/Magic.Perl.Header
#
# setstub.pl: replace DOS stub in Win32 PE .exe
# by pts@fazekas.hu at Sat Aug  1 15:42:27 CEST 2020
#
# setstub.pl is a Perl script to replace the DOS stub in a Win32 PE .exe file.
# It works with DOS stubs of any size (even larger than 200 KiB), and the
# output .exe remains compatibile with all versions of Windows
# (Windows NT 3.1 ... Windows 10) and Wine and Win32s as well.
#
# Limitation: If the code uses the header mapped at ImageBase, then the
# output .exe will not work, because setstub.pl moves the PE header and also
# truncates it at the end of the section headers. PE .exe files generated by
# most C and C++ compilers (e.g. OpenWatcom V2, MinGW GCC, TCC) just work fine.
#
BEGIN { $^W = 1 }
use integer;
use strict;

my $may_split_stub = 1;
while (@ARGV) {
  if ($ARGV[0] eq "--nosplit")  { $may_split_stub = 0; shift @ARGV; }
  elsif ($ARGV[0] !~ m@-@) { last }
  elsif ($ARGV[0] eq "--") { shift @ARGV; last }
}
die "setstub.pl: replace DOS stub in Win32 PE .exe\n" .
    "This is free software, GNU GPL >=2.0. There is NO WARRANTY. " .
    "Use at your risk.\n" .
    "Usage: $0: [--nosplit] <in-pe.exe> <stub.bin> <out-pe.exe>\n" if
   @ARGV != 3;
die "$0: fatal: input and output file must be different\n" if
    $ARGV[0] eq $ARGV[2];

sub fixfnws($) { $_[0] =~ m@\A\s@ ? "./$_[0]" : $_[0] }

die "$0: fatal: open for reading: $ARGV[0]: $!\n" if
    !open(INPE, "< " . fixfnws($ARGV[0]));
binmode(INPE);
my $h;
die "$0: fatal: error reading PE header offset: $ARGV[0]\n" if
    (sysread(INPE, $h, 64) or 0) != 64;
my $pehd_ofs = unpack("V", substr($h, 60, 4));
die "$0: fatal: bad PE header offset: $ARGV[0]: $pehd_ofs\n" if
    $pehd_ofs < 64 or $pehd_ofs >> 24;  # 24 (16 MiB) is just for sanity.
die "$0: fatal: error reading old stub: $ARGV[0]\n" if
    (sysread(INPE, $h, $pehd_ofs - 64) or 0) != $pehd_ofs - 64;
$h = ""; # Save memory.
die "$0: fatal: error reading PE header: $ARGV[0]\n" if
    (sysread(INPE, $h, 24) or 0) != 24;
die "$0: fatal: PE signature not found: $ARGV[0]\n" if $h !~ m@\APE\0\0@;
my $opthd_size = unpack("v", substr($h, 20, 2));
# 200 is for IMAGE_DIRECTORY_ENTRY_IMPORT.
die "$0: fatal: bad optional header size: $ARGV[0]: $opthd_size\n" if
    $opthd_size < 112 or $opthd_size >> 11;
die "$0: fatal: error reading PE header: $ARGV[0]\n" if
    (sysread(INPE, $h, $opthd_size, 24) or 0) != $opthd_size;
my $nrs = unpack("V", substr($h, 116, 4));
# 2 is for IMAGE_DIRECTORY_ENTRY_IMPORT.
die "$0: fatal: bad NumberOfRvaAndSizes: $ARGV[0]: $nrs\n" if
    $nrs < 2 or $nrs > 24;  # 16 is defined by the PE spec, >24 is overkill.
my $ns = unpack("v", substr($h, 6, 2));
die "$0: fatal: bad NumberOfSections: $ARGV[0]: $nrs\n" if
    $ns < 1 or $ns >> 10;  # 1 is needed, 1024 is overkill.
my $s;
die "$0: fatal: error reading section headers: $ARGV[0]\n" if
    (sysread(INPE, $s, $ns * 40) or 0) != $ns * 40;
my $ptrd_min = 0;  my $va_min = 0;
for (my $si = 0; $si < length($s); $si += 40) {
  my $va = unpack("V", substr($s, $si + 12, 4));  # VirtualAddress.
  die "$0: bad VirtualAddress: $ARGV[0]: $va\n" if !$va;
  die "$0: unaligned VirtualAddress: $ARGV[0]: $va\n" if $va & 4095;
  my $ptrd = unpack("V", substr($s, $si + 20, 4));  # PointerToRawData.
  die "$0: unaligned PointerToRawData: $ARGV[0]: $ptrd\n" if $ptrd & 511;
  $ptrd_min = $ptrd if $ptrd > 0 and (!$ptrd_min or $ptrd < $ptrd_min);
  $va_min = $va if $va > 0 and (!$va_min or $va < $va_min);
}
die "$0: positive PointerToRawData not found: $ARGV[0]\n" if !$ptrd_min;
die "$0: positive VirtualAddress not found: $ARGV[0]\n" if !$va_min;
{ my $g;
  my $gap_size = $ptrd_min - ($pehd_ofs + length($h) + length($s));
  die "$0: gap before first secton too small: $ARGV[0]\n" if $gap_size < 0;
  die "$0: bad gap before first secton: $ARGV[0]\n" if $gap_size >> 24;
  die "$0: error reading gap before first section: $ARGV[0]: $!\n" if
      (sysread(INPE, $g, $gap_size) or 0) != $gap_size;
}

die "$0: fatal: open for reading: $ARGV[1]: $!\n" if
    !open(STUB, "< " . fixfnws($ARGV[1]));
binmode(STUB);
my $stub = join("", <STUB>);
close(STUB);
die "$0: fatal: bad stub: $ARGV[1]\n" if length($stub) < 64 or $stub !~m@\AMZ@;
$stub .= "\0" x (-length($stub) & 3);  # Align to 4.
my $trylshs = length($stub) + length($h) + length($s);
$trylshs += -$trylshs & 511;  # Align to 512.
# Stub after the PE header (including section headers). It can be
# arbitrarily large (tested with 0x30000), as long as it's divisible by
# 0x200, even on Win32s.
my $stub2 = "";
if ($trylshs > 0x800 or  # Required by Win32s.
     # Required by Windows NT 3.51, Windows XP etc. Wine 5.0 works without it.
    $trylshs > $va_min) {  # Split the stub to 32 bytes + rest.
  my $stub_size = length($stub);
  my $max_stub_size = ($va_min < 0x800 ? 0x800 : $va_min) -
      length($h) - length($s);
  # TODO(pts): Allow taking a stub from an existing PE .exe.
  # TODO(pts): Make splitting idempotent.
  if ($may_split_stub) {
    # Beginning of DOS MZ .exe header.
    my($mz_signature, $image_size_lo, $image_size_hi, $relocation_count,
       $hd_paragraph_size) = unpack("v5", substr($stub, 0, 10));
    die "$0: fatal: stub is too long " .
        "($stub_size > $max_stub_size) " .
        "(trylshs = $trylshs > $va_min), and has relocations: $ARGV[1]\n" if
        $relocation_count;
    die "$0: fatal: bad image_size_hi in stub: $ARGV[1]: 0\n" if
        !$image_size_hi;
    my $image_size = ($image_size_hi << 9) - ((-$image_size_lo) & 511);
    die "$0: fatal: code too short in stub: $ARGV[1]\n" if
         $image_size <= ($hd_paragraph_size << 4);
    my $newlshs = 32 + length($h) + length($s);
    $stub2 = ("\0" x (-$newlshs & 15)) . substr($stub, $hd_paragraph_size << 4);
    my $orig_hd_paragraph_size = $hd_paragraph_size;
    $hd_paragraph_size = ($newlshs + 15) >> 4;
    my $stub_size_delta = ($hd_paragraph_size - $orig_hd_paragraph_size) << 4;
    $image_size = $newlshs + length($stub2);
    $image_size_hi = ($image_size + 511) >> 9;
    $image_size_lo = $image_size & 511;
    $stub = pack("v5a22", $mz_signature, $image_size_lo, $image_size_hi,
        $relocation_count, $hd_paragraph_size, substr($stub, 10, 22));
    # Also adjust the $overlay_number in case the DOS stub stores its own size
    # there.
    substr($stub, 26, 2, pack("v", unpack("v", substr($stub, 26, 2)) +
                                   $stub_size_delta));
    substr($stub2, 0, 32) = substr($stub, 0, 32) if
        $orig_hd_paragraph_size == 0;
    substr($stub2, 0, 16) = substr($stub, 0, 16) if
        $orig_hd_paragraph_size == 1;
  } else {
    print STDERR "$0: warning: stub is too long " .
        "($stub_size > $max_stub_size) " .
        "(trylshs = $trylshs > $va_min), will work in Wine only: $ARGV[1]\n";
  }
}
if (length($stub) >= 64) {
  substr($stub, 60, 4, pack("V", length($stub)));
} elsif (length($stub) == 32) {  # If the stub was split.
  # This changes SizeOfCode to 32. The change is harmless, because most PE
  # loaders ignore SizeOfCode.
  substr($h, 60 - length($stub), 4, pack("V", length($stub)));
}
my $ptrd_delta = length($stub) + length($h) + length($s) + length($stub2);
$ptrd_delta += (-$ptrd_delta & 511) - $ptrd_min;
if ($opthd_size < 160 + 8 - 24 or !unpack("V", substr($h, 160, 4))) {
  # IMAGE_DIRECTORY_ENTRY_BASERELOC.
  print STDERR "$0: warning: base relocations missing, " .
      "will not work on Win32s: $ARGV[0]\n";
}
if (unpack("v", substr($h, 22, 2)) & 1) {
  # IMAGE_FILE_RELOCS_STRIPPED in Characteristics.
  print STDERR "$0: warning: relocations stripped, " .
      "will not work on Win32s: $ARGV[0]\n";
}

# TODO(pts): Warn for Win32s incompatibility if
# IMAGE_DIRECTORY_ENTRY_BASERELOC.VirtualAddress is 0.
die "$0: fatal: open for writing: $ARGV[2]: $!\n" if
    !open(OUTPE, "> " . fixfnws($ARGV[2]));
binmode(OUTPE);
die "$0: error writing stub to: $ARGV[2]: $!\n" if
    (syswrite(OUTPE, $stub, length($stub)) or 0) != length($stub);
# Set *SubsystemVersion to 3.10 for Windows NT 3.1 compatibility. All other
# systems use 4.0 by default, but they also work with 3.10.
substr($h, 72, 4, pack("vv", 3, 10));  # *SubsystemVersion.
# Wine 5.0 ignores SizeOfHeaders, but fails if SizeOfImage is too small. We
# play it safe by adjusting SizeOfImage if it was too small.
my $midlshs = length($stub) + length($h) + length($s);
substr($h, 84, 4, pack("V", $midlshs));  # SizeOfHeaders.
my $oldsi = unpack("V", substr($h, 80, 4));  # SizeOfImage.
substr($h, 80, 4, pack("V", $midlshs)) if $oldsi < $midlshs;  # SizeOfImage.
die "$0: error writing PE header to: $ARGV[2]: $!\n" if
    (syswrite(OUTPE, $h, length($h)) or 0) != length($h);
for (my $si = 0; $si < length($s); $si += 40) {
  my $ptrd = unpack("V", substr($s, $si + 20, 4));  # PointerToRawData.
  substr($s, $si + 20, 4, pack("V", $ptrd + $ptrd_delta));
}
$s .= $stub2;
$s .= "\0" x (-(length($stub) + length($h) + length($s)) & 511);
die "$0: error writing PE section header to: $ARGV[2]: $!\n" if
    (syswrite(OUTPE, $s, length($s)) or 0) != length($s);

$s = "";
for (;;) {
  my $got = sysread(INPE, $s, 8192);
  die "$0: error reading PE image: $ARGV[0]: $!\n" if !defined($got);
  last if !$got;
  die "$0: error writing PE image: $ARGV[2]: $!\n" if
      (syswrite(OUTPE, $s, length($s)) or 0) != length($s);
}

close(OUTPE); close(INPE);
__END__