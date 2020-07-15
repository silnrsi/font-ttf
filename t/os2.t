#!/usr/bin/perl

use Test::Simple tests => 6;
use Font::TTF::Font;

$f = Font::TTF::Font->open("t/testfont.ttf");
ok($f);
# Add SMP-encoded glyph and verify OS2 changes
$os2 = $f->{'OS/2'}->read;
ok($os2);
ok($os2->{'usLastCharIndex'} < 0xFFFF and !($os2->{'ulUnicodeRange2'} & ~0x2000000));
# double-encode first char in plane 15 PUA
$cmap = $f->{'cmap'};
ok($cmap);
$map = $cmap->find_ms;
ok($map);
$map->{'val'}{0xF0000} = $map->{'val'}{$os2->{'usFirstCharIndex'}};
$cmap->dirty;
$os2->update;
# recheck OS2
ok($os2->{'usLastCharIndex'} == 0xFFFF and $os2->{'ulUnicodeRange2'} & 0x2000000);
