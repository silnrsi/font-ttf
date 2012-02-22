#!/usr/bin/perl

use Test::Simple tests => 4;
use File::Compare;
use Font::TTF::Font;

$f = Font::TTF::Font->open("t/testfont.ttf");
ok($f);
$f->tables_do(sub { $_[0]->read; });
$f->{'loca'}->glyphs_do(sub {$_[0]->read_dat; });
$f->out("t/temp.ttf");
$res = compare("t/temp.ttf", "t/testfont.ttf");
ok(!$res);
unlink "t/temp.ttf" unless ($res);

# same test with WOFF input:
$f = Font::TTF::Font->open("t/testfont.woff");
ok($f);
$f->tables_do(sub { $_[0]->read; });
$f->{'loca'}->glyphs_do(sub {$_[0]->read_dat; });
$f->out("t/temp2.ttf");
$res = compare("t/temp2.ttf", "t/testfont.ttf");
ok(!$res);
unlink "t/temp2.ttf" unless ($res);

