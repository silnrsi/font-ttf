        Perl Module: Font::TTF

Announcing:

The addition of many new tables including support for the OpenType
tables: GSUB, GDEF and GPOS and also a bunch of AAT tables. The module
now also supports XML output and a buggy XML input. All of these new
features should be considered as Alpha code and particularly the XML
language is liable to change for some of the more complex table types.

After a long wait, Name tables now try to return UTF8 strings where
possible. The deprecation period has now passed and by default the
Name.pm returns strings as utf8 where possible. See Name.pm for details.
To get old behaviour, set C<$Font::TTF::Name::utf8> to 0.

Solution to the installation problem for users on Win32, without make.
Use pmake instead. Wherever you see the command: make, in this document,
type: pmake instead.

=head1 Introduction

Perl module for TrueType font hacking. Supports reading, processing and
writing of the following tables: GDEF, GPOS, GSUB, LTSH, OS/2, PCLT,
bsln, cmap, cvt, fdsc, feat, fpgm, glyf, hdmx, head, hhea, hmtx, kern,
loca, maxp, mort, name, post, prep, prop, vhea, vmtx and the reading and
writing of all other table types.

In short, you can do almost anything with a standard TrueType font with
this module. Be Brave!

The module also includes various useful utilities:

check_attach    Checks an attachment point database against a font. See
                ttfbuilder for details
eurofix         Fixes fonts created for Win95 so that they work in Win98 and NT4
                sp4, Win2K and so on.
hackos2         This old favourite lets you do unspeakable things to your OS/2
                table, including sorting Unicode range bits and codepage bits
                (Perl 4)
psfix           Tidy up the postscript names in a font to be Postscript
                conformant
ttfbuilder      Build fonts from other fonts, including ligature building, etc.
                Has excellent explanatory POD
ttfname         Renames a font and allows access to name strings. This needs
                a rewrite (Perl 4)
ttfremap        Simpler font subsetter than ttfbuilder


Also included are the following example scripts. To use these you will need to
install them manually from the examples directory included in the distribution.

StripCmap       Strips a specified cmap from the given font
addpclt         Makes up values and adds a PCLT table to a font
makemono        Makes a font mono spaced (Perl 4)
symbol.rmp      Example remap file for ttfremap
ttfdeltable     Deletes a specified table from a font
ttfenc          Create .enc, .afm, .tfm and .map entry for a ttf file based on
                Unicode rather than postscript. Requires afm2tfm and ttf2afm.
ttfwidth        Create a table of interesting information regarding widths of
                characters. FRET is a much better tool for this now (Perl 4)
xmldump         Dumps a font as XML. The XML needs some work for some of the
                more complex tables
zerohyph        Create a zero width hyphen in place of the normal hyphen

Any suggestions, improvements, additions, subclasses, etc. would be gratefully
received and probably included in a future release. Please send them to me.

This module has been tested on Win32, Unix and Mac.

=head1 SYNOPSIS

Here is the regression test (you provide your own font). Run it once and then
again on the output of the first run. There should be no differences between
the outputs of the two runs.

    use Font::TTF::Font;

    $f = Font::TTF::Font->open($ARGV[0]);

    # force a read of all the tables
    $f->tables_do(sub { $_[0]->read; });

    # force read of all glyphs (use read_dat to use lots of memory!)
    # $f->{'loca'}->glyphs_do(sub { $_[0]->read; });
    $f->{'loca'}->glyphs_do(sub { $_[0]->read_dat; });
    # NB. no need to $g->update since $_[0]->{'glyf'}->out will do it for us

    $f->out($ARGV[1]);
    $f->DESTROY;               # forces close of $in and maybe memory reclaim!

=head1 PERL4 Utilities

As an aside, the following Perl4 system and utilities have been slung in:

perlmod.pl      This is the Perl4 library for these programs

addpclt         Create a PCLT table for a font with lots of junk in it
Hackos2         Do all sorts of unspeakable things to the OS/2 table
MakeMono        Force a font to be mono-spaced
Ttfname         Rename a font (and set any other name strings)
TTFWIDTH        Find the centre of every glyph in a font and print report

=head1 Installation

If you have received this package as part of an Activestate PPM style .zip file
then type

    ppm install Font-TTF.ppd

Otherwise.

To configure this module, cd to the directory that contains this README file
and type the following.

    perl Makefile.PL

Alternatively, if you plan to install Font::TTF somewhere other than
your system's perl library directory. You can type something like this:

    perl Makefile.PL PREFIX=/home/me/perl INSTALLDIRS=perl

Then to build you run make.

    make

If you have write access to the perl library directories, you may then
install by typing:

    make install

To tidy up, type:

    make realclean

Win32 users should use pmake instead of make. Alternatively installation can be
done on Win32 by typing:

    Setup

Or using the install feature in tools like WinZip.

=head1 CHANGES

=head2 Future Changes

I do not anticipate any more restructuring changes (but reserve the right to do so).
One area I am waiting to change is that of the Name table where I would like to 
pass strings using UTF-8. When the UTF-8 version of Perl is ported to Win32 then I
can start the changes and cross-mappings (for the Mac).

=head1 AUTHOR

Martin Hosken L<Martin_Hosken@sil.org>

Copyright Martin Hosken 1998 and following.

No warranty or expression of effectiveness for anything, least of all anyone's
safety, is implied in this software or documentation.

=head2 Licensing

The Perl TTF module is licensed under the Perl Artistic License.

