@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S "%0" %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/local/bin/perl -w
#line 15
use 5.005;  # Need look-behind assertions

use Getopt::Std;
use Make;

my %opt;

getopts('Dgnpf:j:C:',\%opt);

my $info = Make->new(GNU      => $opt{'g'}, 
                     Override => { MAKE => "$^X $0" },
                     Makefile => $opt{'f'}, 
                     Jobs     => $opt{'j'},
                     Dir      => $opt{'C'});

if ($opt{'D'})
 {
  require Data::Dumper;
  print Data::Dumper::DumperX($info);
  exit;
 }

if ($opt{'p'})
 {
  $info->Print(@ARGV);  
  exit;
 }
if ($opt{'n'})
 {
  $info->Script(@ARGV);
 }
else
 {
  $info->Make(@ARGV);
 }

=head1 NAME

pmake - a perl 'make' replacement

=head1 SYNOPSIS

	pmake [-n] [-g] [-p] [-C directory] targets

=head1 DESCRIPTION

Performs the same function as make(1) but is written entirely in perl.
A subset of GNU make extensions is supported.
For details see L<Make> for the underlying perl module.

=head1 BUGS

=item *

No B<-k> flag

I strongly suspect there are lots more.

=head1 SEE ALSO

L<Make>, make(1)

=head1 AUTHOR

Nick Ing-Simmons 

=cut


__END__
:endofperl
