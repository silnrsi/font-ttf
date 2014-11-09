#! /usr/bin/perl
use strict;

use Test::Simple tests => 6;
use Font::TTF::OTTags qw( %tttags %ttnames %iso639 readtagsfile);

ok($tttags{'SCRIPT'}{'Cypriot Syllabary'} eq 'cprt', 'tttags{SCRIPT}');

ok($ttnames{'LANGUAGE'}{'AFK '} eq 'Afrikaans', 'ttnames{LANGUAGE}');

ok($ttnames{'LANGUAGE'}{'DHV '} eq 'Divehi (Dhivehi, Maldivian) (deprecated)' && $ttnames{'LANGUAGE'}{'DIV '} eq 'Divehi (Dhivehi, Maldivian)', 'ttnames{LANGUAGE} Dhivehi');

ok($ttnames{'FEATURE'}{'cv01'} eq 'Character Variants 01', 'ttnames{FEATURE}');

ok($iso639{'atv'} eq 'ALT ', 'iso639{atv}');

ok($iso639{'ALT '}->[0] eq 'atv' && $iso639{'ALT '}->[1] eq 'alt', 'iso639{ALT}');