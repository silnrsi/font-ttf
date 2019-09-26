#!perl

use strict;

my $font;
BEGIN {
    ($font) = grep -f, (
        "/usr/share/fonts/opentype/ipaexfont-gothic/ipaexg.ttf", # ubuntu
        "/usr/local/share/fonts/OTF/ipaexg.otf", # freebsd
    );
}

use Test::Simple $font ? (tests => 3) : (skip_all => "Cannot find a font containing a format 14");
use Font::TTF::Font;
use File::Temp qw/tempfile/;

my $f = Font::TTF::Font->open($font);
ok $f, "open font: $font";
$f->{'cmap'}->read;

my ($tmp, $tempfile) = tempfile();
$f->{'cmap'}->out($tmp);

my $g = Font::TTF::Font->open($font);
ok $g, "use $tempfile instead of format 14";

$g->{'cmap'}{' INFILE'} = $tmp;
$g->{'cmap'}{' LENGTH'} = $tmp->tell();
$g->{'cmap'}{' OFFSET'} = 0;
$g->{'cmap'}{' ZLENGTH'} = 0;
$g->{'cmap'}{' INFILE'}->seek(0, 0);
$g->{'cmap'}->read;

my $unmatch = 0;
for (sort keys %{$f->{cmap}->find_uvs->{val}}) {
    my $fid = $f->{cmap}->uvs_lookup($_);
    my $gid = $g->{cmap}->uvs_lookup($_);
    $unmatch++ unless $fid == $gid;
}
for (sort keys %{$g->{cmap}->find_uvs->{val}}) {
    my $fid = $f->{cmap}->uvs_lookup($_);
    my $gid = $g->{cmap}->uvs_lookup($_);
    $unmatch++ unless $fid == $gid;
}
ok !$unmatch, 'match: table of format 14, read() after out()';

unlink $tempfile;
