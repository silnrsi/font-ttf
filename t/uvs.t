#!perl

use strict;

my $font;
BEGIN {
    ($font) = grep -f, (
        #"../noto/SauceHanSansJP-Regular.TTF",
        "/usr/share/fonts/opentype/ipaexfont-gothic/ipaexg.ttf", # ubuntu
        "/usr/local/share/fonts/OTF/ipaexg.otf", # freebsd
    );
}

use Test::More $font ? (tests => 4) : (skip_all => "Cannot find a font containing a format 14");
use Font::TTF::Font;
use File::Temp qw/tempfile/;

my $f = Font::TTF::Font->open($font);
ok $f, "open font: $font";
$f->{'cmap'}->read;

ok $f->{'cmap'}->find_uvs, "$font has uvstable";

my ($tmp, $tempfile) = tempfile();
$f->{'cmap'}->out($tmp);

my $g = Font::TTF::Font->open($font);
ok $g, "open font: $font";

# setup $tempfile for cmap
$g->{'cmap'}{' INFILE'} = $tmp;
$g->{'cmap'}{' LENGTH'} = $tmp->tell();
$g->{'cmap'}{' OFFSET'} = 0;
$g->{'cmap'}{' ZLENGTH'} = 0;
$g->{'cmap'}{' INFILE'}->seek(0, 0);
$g->{'cmap'}->read;

my $unmatch = 0;
for my $uvs (keys %{$f->{cmap}->find_uvs->{val}}) {
    for my $uni (keys %{$f->{cmap}->find_uvs->{val}{$uvs}}) {
        my $fid = $f->{cmap}->uvs_lookup($uvs, $uni);
        my $gid = $g->{cmap}->uvs_lookup($uvs, $uni);
        $unmatch++ unless $fid == $gid;
    }
}
for my $uvs (keys %{$g->{cmap}->find_uvs->{val}}) {
    for my $uni (keys %{$g->{cmap}->find_uvs->{val}{$uvs}}) {
        my $fid = $f->{cmap}->uvs_lookup($uvs, $uni);
        my $gid = $g->{cmap}->uvs_lookup($uvs, $uni);
        $unmatch++ unless $fid == $gid;
    }
}

ok !$unmatch, 'match: table of format 14, read() after out()';

unlink $tempfile;
