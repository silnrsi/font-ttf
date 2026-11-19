package Font::TTF::CFF_;

=head1 NAME

Font::TTF::CFF_ - Compact Font Format

=head1 SYNOPSYS

looks various tables in the cff.

 $topdict = $font->{'CFF '}->TopDICT;

creates subset font object with only the glyphs in @cid,
and gets the font stream.

 $subset = $font->{'CFF '}->subset(@cid);
 $font_stream = $subset->as_string;

dumps xml similar to "ttx -t CFF subset-font"

 my $d = Font::TTF::CFF_::Dumper->new;
 $d->dump_xml($subset);

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use vars qw(@ISA);

use Font::TTF::Table;
use Font::TTF::Utils;

@ISA = qw(Font::TTF::Table);

use List::Util qw(sum max min);
use Scalar::Util qw(blessed);
use POSIX qw(ceil);
use Clone qw(clone);
use File::Temp qw(tempfile);

use Carp;
#use feature 'say';
use Data::Dumper qw(Dumper);
$Data::Dumper::Indent = 1;
$Data::Dumper::Terse = 1;

use constant {
    T_SID     => 0,
    T_boolean => 1,
    T_number  => 2,
    T_offset  => 3,
    T_size_and_offset => 4,
    T_ROS     => 5,
    T_delta   => 6,
    T_array   => 7,
};


# Appendix H - CFF DICT Encoding
# One-byte CFF DICT Operators
use constant {
    D_version          =>  0,
    D_Notice           =>  1,
    D_FullName         =>  2,
    D_FamilyName       =>  3,
    D_Weight           =>  4,
    D_FontBBox         =>  5,
    D_BlueValues       =>  6,
    D_OtherBlues       =>  7,
    D_FamilyBlues      =>  8,
    D_FamilyOtherBlues =>  9,
    D_StdHW            => 10,
    D_StdVW            => 11,
    D_escape           => 12, # [1] First byte of a 2-byte operator.
    D_UniqueID         => 13,
    D_XUID             => 14,
    D_charset          => 15,
    D_Encoding         => 16,
    D_CharStrings      => 17,
    D_Private          => 18,
    D_Subrs            => 19,
    D_defaultWidthX    => 20,
    D_nominalWidthX    => 21,
    # -Reserved-       => 22 .. 27,
    D_shortint         => 28, # [2] First byte of a 3-byte sequence specifying a number.
    D_longint          => 29,
    D_BCD              => 30,
    # -Reserved-       => 31,
    # <numbers>        => 32 .. 246,
    # <numbers>        => 247 .. 254, [3] First byte of a 2-byte sequence specifying a number.
    # -Reserved-       => 255,
};

# Two-byte CFF DICT Operators
use constant {
    D_Copyright          =>  0,
    D_isFixedPitch       =>  1,
    D_ItalicAngle        =>  2,
    D_UnderlinePosition  =>  3,
    D_UnderlineThickness =>  4,
    D_PaintType          =>  5,
    D_CharstringType     =>  6,
    D_FontMatrix         =>  7,
    D_StrokeWidth        =>  8,
    D_BlueScale          =>  9,
    D_BlueShift          => 10,
    D_BlueFuzz           => 11,
    D_StemSnapH          => 12,
    D_StemSnapV          => 13,
    D_ForceBold          => 14,
    # -Reserved-         => 15 .. 16,
    D_LanguageGroup      => 17,
    D_ExpansionFactor    => 18,
    D_initialRandomSeed  => 19,
    D_SyntheticBase      => 20,
    D_PostScript         => 21,
    D_BaseFontName       => 22,
    D_BaseFontBlend      => 23,
    # -Reserved-         => 24 .. 29,
    D_ROS                => 30,
    D_CIDFontVersion     => 31,
    D_CIDFontRevision    => 32,
    D_CIDFontType        => 33,
    D_CIDCount           => 34,
    D_UIDBase            => 35,
    D_FDArray            => 36,
    D_FDSelect           => 37,
    D_FontName           => 38,
    # -Reserved-         => 39 .. 255,
};


use Class::Tiny qw(verbose debug gid_as_cid notdef_glyph padding maxpadding packing);
use Class::Tiny qw(disasm_print_enabled);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);
    $self->gid_as_cid(1);
    $self->notdef_glyph(0);
    $self;
}


sub read {
    my $self = shift;
    $self->SUPER::read or return $self;

    # Table 1 - CFF Data Layout
    $self->Header($self->read_Header);
    $self->Name_INDEX($self->read_INDEX);
    $self->TopDICT_INDEX($self->read_INDEX);
    $self->String_INDEX($self->read_INDEX);
    $self->GlobalSubr_INDEX($self->read_SubrINDEX);
    $self;
}


sub subset {
    my $self = shift;

    # setup an empty cff font to store the subset font.
    my $tmp = tempfile(CLEANUP => 1, SUFFIX => '.cff');
    my $cff = $self->new(INFILE => $tmp, OFFSET => 0);
    $cff->$_($self->$_) for qw/debug verbose padding maxpadding/;

    if (@_) {
        $self->gid(@_);
    } elsif (!$self->gid) {
        $self->gid(1 .. $self->nGlyphs - 1);
    }

    # The first 5 data of the cff font, the data occupying fixed
    # positions, are clones of the original font.
    $cff->Header(clone $self->Header);
    $cff->Name_INDEX(clone $self->Name_INDEX);
    bless $cff->Name_INDEX, "Font::TTF::CFF_::INDEX";
    $cff->TopDICT(clone $self->TopDICT);
    #$cff->TopDICT->{CharstringType} = 1;

    # strings_index can be reduced by subsetting, but the effect is small.
    # For now, copying should be sufficient.

    # $cff->String_INDEX(clone $self->String_INDEX);
    # bless $cff->String_INDEX, "Font::TTF::CFF_::INDEX";
    # $cff->padding(8) unless $cff->padding;
    $cff->String_INDEX(Font::TTF::CFF_::INDEX->new);
    $cff->padding(8 + $self->String_INDEX->offset->[-1]) unless $cff->padding;

    # Prevents FDArray() from calling get_FDArray().
    $cff->FDArray([]);

    my @cid = (0);
    my $charset = $self->Charset;
    if ($self->gid_as_cid) {
        my $cid2gid;
        for (0 .. $#{$charset->{code}}) {
            my $cid = $charset->{code}->[$_];
            $cid2gid->{$cid} = $_;
        }
        for my $cid ($self->gid) {
            if (defined $cid2gid->{$cid}) {
                push @cid, $cid;
            } else {
                warn "ignore cid $cid (not defined in charset)\n";
            }
        }
        $self->gid(map $cid2gid->{$_}, @cid[1 .. $#cid]);
    } else {
        my @gid;
        for my $gid ($self->gid) {
            if (defined (my $cid = $charset->{code}->[$gid])) {
                push @cid, $cid;
                push @gid, $gid;
            } else {
                warn "ignore gid $gid (not defined in charset)\n";
            }
        }
        $self->gid(@gid);
    }
    $cff->Charset({ code => \@cid });

    $cff->CharStrings_INDEX($cff->new_subr_index);
    $cff->GlobalSubr_INDEX($cff->new_subr_index);

    my %fdindex2fdindex;
    my $free_fdindex = 0;
    my @gid2fdindex;
    my $new_gid = 0;

    if ($cff->TopDICT->{ROS}) {

        for my $gid (0, $self->gid) {

            # FDSelect($gid) gets the FD (Font DICT) index of the $gid.
            my $fdindex = $self->FDSelect($gid);
            unless (defined $fdindex) {
                warn "ignoring gid $gid: undefined FD index selected\n";
                next;
            }

            # FontDICT() sets up PrivateDICT and LocalSubr_INDEX (if present).
            $self->FontDICT($fdindex);

            # %fdindex2fdindex maps new FD index (for subset) from original FD index.
            my $new_fdindex = $fdindex2fdindex{$fdindex} //= $free_fdindex++;

            # sets up the FDArray
            unless (defined $cff->FDArray->[$new_fdindex]) {
                $cff->FDArray->[$new_fdindex] = clone $self->FDArray->[$fdindex];
                $cff->FDArray->[$new_fdindex]->{'*Private'} = clone $self->PrivateDICT;
                $cff->FDArray->[$new_fdindex]->{'*Private'}{'*Subrs'} = $cff->new_subr_index;
                $cff->FDArray->[$new_fdindex]->{'Private'} = undef;
                $cff->FDArray->[$new_fdindex]->{'*Private'}{'Subrs'} = undef;
            }
            $cff->FontDICT($new_fdindex);

            # the subset font is created by the glyphs (CharStrings) specified
            # by gids and the subrs (LocalSubr and GlobalSubr) called.
            my $class = 'CharStrings_INDEX';
            my $code = $self->$class->data($gid);
            $code = pack "C*", 14 if !$self->notdef_glyph && $gid == 0; # endchar
            my $disasm = $self->disasm({ class => $class, id => $gid }, $code, $cff);
            $cff->CharStrings_INDEX->add($disasm);
            $gid2fdindex[$new_gid] = $new_fdindex;
            $new_gid++;

        }

    } else {

        $self->setup_PrivateDICT_and_LocalSubr_INDEX("PrivateDICT", $self->TopDICT);
        $cff->PrivateDICT(clone $self->PrivateDICT);
        $cff->LocalSubr_INDEX($cff->new_subr_index);

        for my $gid (0, $self->gid) {
            my $class = 'CharStrings_INDEX';
            my $code = $self->$class->data($gid);
            $code = pack "C*", 14 if !$self->notdef_glyph && $gid == 0; # endchar
            my $disasm = $self->disasm({ class => $class, id => $gid }, $code, $cff);
            $cff->CharStrings_INDEX->add($disasm);
            $new_gid++;
        }

    }

    $cff->gid(1 .. $new_gid - 1);

    $cff->GlobalSubr_INDEX->commit;
    $cff->GlobalSubr_INDEX->remap('hintmask', 'GlobalSubr_INDEX');
    if ($cff->TopDICT->{ROS}) {
        for my $fdindex (keys %fdindex2fdindex) {
            my $new_fdindex = $fdindex2fdindex{$fdindex};
            $cff->FontDICT($new_fdindex);
            $cff->LocalSubr_INDEX->commit;
            $cff->LocalSubr_INDEX->remap('hintmask', 'LocalSubr_INDEX');
        }
    } else {
        $cff->LocalSubr_INDEX->commit;
        $cff->LocalSubr_INDEX->remap('hintmask', 'LocalSubr_INDEX');
    }
    $cff->CharStrings_INDEX->commit;
    $cff->CharStrings_INDEX->remap('hintmask', 'CharStrings_INDEX');

    $cff->{FDSelect}{gid2fdindex} = \@gid2fdindex;
    $cff->nGlyphs($cff->CharStrings_INDEX->count);

    my ($p1end, $p2end, $last_p1end);

    $self->packing(0);

  p1:
    # Outputs the first five data (data occupying fixed positions)
    # in the cff font.

    $self->packing($self->packing + 1);
    $cff->maxpadding($cff->padding + 8)
        if !defined $cff->maxpadding || $cff->maxpadding <= $cff->padding;

    $tmp->seek(0, 0);
    $tmp->print($cff->pack_Header);
    $tmp->print($cff->pack_INDEX($cff->Name_INDEX));
    my $topdict_pos = $tmp->tell;
    my $topdict_packed = $cff->pack_DICT("TopDICT", $cff->TopDICT);
    my $topdict_index = $cff->make_INDEX($topdict_packed);
    $cff->TopDICT_INDEX($topdict_index);
    bless $cff->TopDICT_INDEX, "Font::TTF::CFF_::INDEX";
    delete $cff->TopDICT_INDEX->{offSize};
    $tmp->print($cff->pack_INDEX($cff->TopDICT_INDEX));
    $cff->String_INDEX->commit;
    $tmp->print($cff->pack_INDEX($cff->String_INDEX));
    $tmp->print($cff->pack_INDEX($cff->GlobalSubr_INDEX));

    # outputs padding so that even if the five pieces of data occupying
    # fixed positions at the beginning of the font are updated,
    # subsequent data is less likely to be overwritten.
    $p1end = $tmp->tell;
    $tmp->print(chr(0) x $cff->padding) if $cff->padding;
    my $p2start = $tmp->tell;

  p2:
    # The following data is accessed using the offsets described in
    # TopDICT:

    if ($cff->TopDICT->{ROS}) {
        # Since cid fonts do not have encoding data, we store encoding
        # ID 0 (standard encoding) here.
        $cff->TopDICT->{Encoding} = 0;
    } else {
        # Otherwise (non-cid font): First, store the offset of the
        # encoding data in Encoding in TopDICT.
        $cff->TopDICT->{Encoding} = $tmp->tell;
        # Next, pack and output the encoding data.  However, if it is
        # determined to be Standard Encoding or Expert Encoding, do not
        # output the packed data, and store the encoding ID in TopDICT.
        for ($cff->pack_Encoding($self->Encoding->{code})) {
            $tmp->print($_) if defined;
        }
    }

    # The Charset, FDSelect, FDSelect, and CharStrings data follow.  All
    # of these are the same as the Encoding data.
    $cff->TopDICT->{charset} = $tmp->tell;
    for ($cff->pack_Charset) {
        $tmp->print($_) if defined;
    }

    $cff->TopDICT->{FDSelect} = $tmp->tell;
    for ($cff->pack_FDSelect) {
        $tmp->print($_) if defined;
    }

    $cff->TopDICT->{"CharStrings"} = $tmp->tell;
    for ($cff->pack_INDEX($cff->CharStrings_INDEX)) {
        $tmp->print($_) if defined;
    }

    if ($cff->TopDICT->{ROS}) {
        if (my $fdict = $cff->FDArray) {
            for my $i (0 .. $#{$fdict}) {
                $cff->FontDICT($i);
                $fdict->[$i]->{Private} = [
                    $cff->output_PrivateDICT_and_LocalSubr_INDEX($tmp, "FontDICT.$i.Private"),
                ];
            }
            my @fdict_packed;
            for my $i (0 .. $#{$fdict}) {
                $fdict_packed[$i] = $cff->pack_DICT("FontDICT.$i", $fdict->[$i]);
            }
            $cff->TopDICT->{FDArray} = $tmp->tell;
            my $fdarray_index = $cff->make_INDEX(@fdict_packed);
            $tmp->print($cff->pack_INDEX($fdarray_index));
        }
    } else {
        $cff->TopDICT->{Private} = [
            $cff->output_PrivateDICT_and_LocalSubr_INDEX($tmp, "TopDICT.Private"),
        ];
    }
    $p2end = $tmp->tell;

  make_topdict:
    my $topdict_packed2 = $cff->pack_DICT("TopDICT", $cff->TopDICT);
    my $topdict_index2 = $cff->make_INDEX($topdict_packed2);
    $cff->TopDICT_INDEX($topdict_index2);
    $tmp->seek($topdict_pos, 0);
    $tmp->print($cff->pack_INDEX($cff->TopDICT_INDEX));
    $cff->String_INDEX->commit;
    $tmp->print($cff->pack_INDEX($cff->String_INDEX));
    $tmp->print($cff->pack_INDEX($cff->GlobalSubr_INDEX));
    my $p1end_updated = $tmp->tell;
    if ($p1end_updated > $p2start) {
        warn $cff->Name_INDEX->data(0), ": p1 overlaps p2 ",
            "(p1 $p1end_updated, p2 $p2start, padding ", $cff->padding, ")\n",
            "redo packing...\n" if $self->verbose;
        $cff->padding(8);
        goto p1;
    }
    if ($p2start - $p1end_updated > $cff->maxpadding) {
        warn $cff->Name_INDEX->data(0), ": gap between p1 and p2: ",
            $p2start - $p1end_updated, "\n",
            "redo packing...\n" if $self->verbose;
        $cff->padding(8);
        $cff->maxpadding(0);    # auto fit
        goto p1;
    }
    $tmp->truncate($p2end);
    $cff->{' LENGTH'} = $p2end;

    $cff;
}


sub output_PrivateDICT_and_LocalSubr_INDEX {
    my $self = shift;
    my $tmp = shift;
    my $dict_name = shift // "PrivateDICT";
    my $pdict = shift // $self->PrivateDICT;
    my $lsubr_index = shift // $self->LocalSubr_INDEX;
    my $pdict_pos = $tmp->tell;
  rewrite_pdict:
    my $pdict_packed = $self->pack_DICT($dict_name, $pdict);
    for ($pdict_packed) {
        $tmp->print($_) if defined;
    }
    my $lsubrs_pos = $tmp->tell;
    if ($lsubr_index && $lsubr_index->count == 0) {
        if (defined $pdict->{Subrs}) {
            delete $pdict->{Subrs};
            $tmp->seek($pdict_pos, 0);
            goto rewrite_pdict;
        }
    } else {
        # $pdict->{Subrs} is the offset to local subrs
        if (!defined $pdict->{Subrs} || $pdict->{Subrs} != $lsubrs_pos - $pdict_pos) {
            $pdict->{Subrs} = $lsubrs_pos - $pdict_pos;
            $tmp->seek($pdict_pos, 0);
            goto rewrite_pdict;
        }
        my $lsubr_index_packed = $self->pack_INDEX($lsubr_index);
        for ($lsubr_index_packed) {
            $tmp->print($_) if defined;
        }
    }
    (length $pdict_packed, $pdict_pos);
}


sub gid {
    my $self = shift;
    if (@_) {
        if (ref $_[0] eq 'ARRAY') {
            $self->gid(@{$_[0]} > 0? @$_[0] : undef);
        } else {
            my %seen;
            if (my @gid = grep defined && $_ > 0 && !$seen{$_}++, @_) {
                $self->{gid} = \@gid;
            } else {
                $self->{gid} = undef;
            }
        }
    }
    if (wantarray) {
        return ref $self->{gid} eq 'ARRAY' ? @{$self->{gid}} : ();
    } else {
        return $self->{gid};
    }
}


sub as_string {
    my ($self) = @_;
    my $fd = $self->{' INFILE'};
    $fd->seek($self->{' OFFSET'}, 0);
    $fd->read(my $dat, $self->{' LENGTH'});
    return $dat;
}


=begin comment

The argument subr# of callsubr (10) and callgsubr (29) changes its bias
depending on the number of subroutines stored in LocalSubr_INDEX and
GlobalSubr_INDEX. Therefore, in subset font, *Subr_INDEX->commit should be
called after storing subroutines in each INDEX.

=end comment

=cut

# The CFF 2 Charstring Format (OpenType 1.8)
# https://learn.microsoft.com/en-us/typography/opentype/otspec180/cff2charstr
sub disasm {
    my $self = shift;
    my $f = shift if @_ && ref $_[0] eq 'HASH';
    $f->{init} //= 1;
    my $packed_code = shift // '';
    my $cff = shift;
    my @new_code;
    my $code = [ unpack "C*", $packed_code ];
    our $DISASM;

    if ($f->{init}) {
        $f->{init} = 0;
        $DISASM = [];
        $self->{transient_array} = [];
        $self->{v}  = [];
        $self->{w}  = undef;
        $self->{hs} = [];
        $self->{vs} = [];
    } else {
        $self->disasm_print("\n");
    }

    my $hstem = sub {
        my ($q, $r) = idiv(scalar @{$self->{v}}, 2);
        push @{$self->{hs}}, splice @{$self->{v}}, -($q * 2);
        $self->{w} = pop @{$self->{v}} unless defined $self->{w} && $r;
    };
    my $vstem = sub {
        my ($q, $r) = idiv(scalar @{$self->{v}}, 2);
        push @{$self->{vs}}, splice @{$self->{v}}, -($q * 2);
        $self->{w} = pop @{$self->{v}} unless defined $self->{w} && $r;
    };
    my $hintmask = sub {
        my ($c) = @_;
        my $n = @{$self->{hs}} + @{$self->{vs}};
        my $s = int(($n + 1) / 2);
        my $m = int(($s + 7) / 8);
        $m;
    };
    my $getmask = sub {
        my $m = shift;
        my $mask = 0;
        if ($m >= 1) {
            for (1 .. $m) {
                $mask <<= 8;
                $new_code[-1] .= pack "C*", my $c = shift @$code;
                $mask |= $c;
            }
        }
        sprintf "%0*b", 8*$m, $mask;
    };

    while (@{$code} > 0) {
        my $c = shift @{$code};
        push @new_code, pack "C*", $c;
        if ($c >= 32) {
            # 32 - 246: result = v–139
            if ($c >= 32 && $c <= 246) {
                my $int = $c - 139;
                $self->disasm_print($int);
                push @{$self->{v}}, $int;
            }
            # 247 - 250: with next byte, w, result = (v–247)*256+w+108
            elsif ($c >= 247 && $c <= 250) {
                $new_code[-1] .= pack "C*", my $c1 = shift @{$code};
                my $int = ($c - 247) * 256 + $c1 + 108;
                $self->disasm_print($int);
                push @{$self->{v}}, $int;
            }
            # 251 - 254: with next byte, w, result = –[(v–251)*256]–w–108.
            elsif ($c >= 251 && $c <= 254) {
                $new_code[-1] .= pack "C*", my $c1 = shift @{$code};
                my $int = -($c - 251) * 256 - $c1 - 108;
                $self->disasm_print($int);
                push @{$self->{v}}, $int;
            }
            # 255: next 4 bytes interpreted as a 32-bit two's-complement number
            elsif ($c == 255) {
                my ($c1, $c2, $c3, $c4) = splice @{$code}, 0, 4;
                $new_code[-1] .= pack "C*", $c1, $c2, $c3, $c4;
                my $int = $c1 << 24 | $c2 << 16 | $c3 << 8 | $c4;
                # 16-bit signed integer with 16 bits of fraction.
                $int = -((~$int & 0xffff_ffff) + 1) if $int & 0x8000_0000;
                $int /= 1 << 16;
                $self->disasm_print($int);
                push @{$self->{v}}, $int;
            }
        }
        # 28: following 2 bytes interpreted as a 16-bit two's complement number
        elsif ($c == 28) {
            my ($c1, $c2) = splice @{$code}, 0, 2;
            $new_code[-1] .= pack "C*", $c1, $c2;
            my $int = $c1 << 8 | $c2;
            $int = -((~$int & 0xffff) + 1) if $int & 0x8000;
            $self->disasm_print($int);
            push @{$self->{v}}, $int;
        } else {
            # 0 - 11: operators
            if ($c == 1) {
                # |- y dy {dya dyb}* hstem (1) |-
                $self->disasm_print("hstem");
                &$hstem unless @{$self->{hs}};
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 3) {
                # |- x dx {dxa dxb}* vstem (3) |-
                $self->disasm_print("vstem");
                &$vstem unless @{$self->{vs}};
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 4) {
                # |- dy1 vmoveto (4) |-
                $self->disasm_print("vmoveto");
                #my @args = pop @{$self->{v}};
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 5) {
                # |- {dxa dya}+ rlineto (5) |-
                $self->disasm_print("rlineto");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 2);
                #my @args = splice @{$self->{v}}, -($q * 2);
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 6) {
                # |- dx1 {dya dxb}* hlineto (6) |-
                # |- {dxa dyb}+ hlineto (6) |-
                $self->disasm_print("hlineto");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 2);
                #my @args = splice @{$self->{v}}, -($q * 2 + $r);
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 7) {
                # |- dy1 {dxa dyb}* vlineto (7) |-
                # |- {dya dxb}+ vlineto (7) |-
                $self->disasm_print("vlineto");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 2);
                #my @args = splice @{$self->{v}}, -($q * 2 + $r);
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 8) {
                # |- {dxa dya dxb dyb dxc dyc}+ rrcurveto (8) |-
                $self->disasm_print("rrcurveto");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 6);
                #my @args = splice @{$self->{v}}, -($q * 6);
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 10) {
                # subr# callsubr (10) –
                $self->disasm_print("callsubr");
                my $subr = pop @{$self->{v}};
                my $class = 'LocalSubr_INDEX';
                my $cs = $self->$class;
                my $index = $subr + $cs->bias;
                if ($cff) {
                    if (defined $f->{id} && defined $f->{class}) {
                        $cff->$class->{hintmask}{$index} = $cff->{$f->{class}}->{hintmask}{$f->{id}};
                    }
                    my $new_cs = $cff->$class;
                    local $DISASM = [];
                    my $code = $cs->data($index);
                    my $tmp_code = $self->disasm({ %$f, class => $class, id => $index }, $code, $cff);
                    $new_cs->subr($index, $tmp_code);
                    $new_code[-2] = sub {
                        my $new_index = $new_cs->{map}{$index};
                        my $new_subr = $new_index - $new_cs->bias;
                        encode_number($new_subr);
                    };
                } else {
                    local $DISASM = [];
                    my $code = $cs->data($index);
                    $self->disasm({ %$f, class => $class, id => $index }, $code);
                }
            }
            elsif ($c == 11) {
                # – return (11) –
                $self->disasm_print("return");
                $self->disasm_print("\n");
                #last;
            }
            elsif ($c == 12) {
                #last unless @$code >= 1;
                $new_code[-1] .= pack "C*", my $c2 = shift @$code;

=begin comment

                if ($c2 == 0) {
                    $self->disasm_print("dotsection");
                    # |– dotsection (12 0) |–

                    # This is an obsolete form of hint substitution (actually
                    # hint suspension) that has always been treated as a no-op
                    # by Adobe ATM renderers.

                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                elsif ($c2 == 1) {
                    $self->disasm_print("vstem3");
                    # |- x0 dx0 x1 dx1 x2 dx2 vstem3 (12 1) |- T1_SPEC.pdf
                    #my ($x0, $dx0, $x1, $dx1, $x2, $dx2) = splice @{$self->{v}}, -6;
                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                elsif ($c2 == 2) {
                    $self->disasm_print("hstem3");
                    # |- y0 dy0 y1 dy1 y2 dy2 hstem3 (12 2) |- T1_SPEC.pdf
                    push @{$self->{hs}}, splice @{$self->{v}}, -6;
                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                elsif ($c2 == 3) {
                    # num1 num2 and (12 3) 1_or_0
                    $self->disasm_print("and");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $bool = $num1 && $num2;
                    push @{$self->{v}}, $bool;
                }
                elsif ($c2 == 4) {
                    # num1 num2 or (12 4) 1_or_0
                    $self->disasm_print("or");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $bool = $num1 || $num2;
                    push @{$self->{v}}, $bool;
                }
                elsif ($c2 == 5) {
                    # num1 not (12 5) 1_or_0
                    $self->disasm_print("not");
                    my $num1 = pop @{$self->{v}};
                    my $bool = !$num1;
                    push @{$self->{v}}, $bool;
                }
                elsif ($c2 == 6) {
                    $self->disasm_print("seac");
                    # |- asb adx ady bchar achar seac (12 6) |-
                }
                elsif ($c2 == 7) {
                    $self->disasm_print("sbw");
                    # |- sbx sby wx wy sbw (12 7) |-
                }
                elsif ($c2 == 8) {
                    warn "store ($c $c2) reserved";
                }
                elsif ($c2 == 9) {
                    # num abs (12 9) num2
                    $self->disasm_print("abs");
                    my $num = pop @{$self->{v}};
                    my $num2 = $num < 0 ? -$num : $num;
                    push @{$self->{v}}, $num2;
                }
                elsif ($c2 == 10) {
                    # num1 num2 add (12 10) sum
                    $self->disasm_print("add");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $sum = $num1 + $num2;
                    push @{$self->{v}}, $sum;
                }
                elsif ($c2 == 11) {
                    # num1 num2 sub (12 11) difference
                    $self->disasm_print("sub");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $difference = $num1 - $num2;
                    push @{$self->{v}}, $difference;
                }
                elsif ($c2 == 12) {
                    # num1 num2 div (12 12) quotient
                    $self->disasm_print("div");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $quotient = $num1 / $num2;
                    push @{$self->{v}}, $quotient;
                }
                elsif ($c2 == 13) {
                    warn "load ($c $c2) reserved";
                }
                elsif ($c2 == 14) {
                    # num neg (12 14) num2
                    $self->disasm_print("neg");
                    my $num = pop @{$self->{v}};
                    my $num2 = -$num;
                    push @{$self->{v}}, $num2;
                }
                elsif ($c2 == 15) {
                    # num1 num2 eq (12 15) 1_or_0
                    $self->disasm_print("eq");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $bool = $num1 == $num2;
                    push @{$self->{v}}, $bool;
                }
                elsif ($c2 == 16) {
                    $self->disasm_print("callothersubr");
                }
                elsif ($c2 == 17) {
                    $self->disasm_print("pop");
                    my $x = pop @{$self->{v}};
                }
                elsif ($c2 == 18) {
                    # num drop (12 18)
                    $self->disasm_print("drop");
                    # removes the top element num from the Type 2 argument
                    # stack.
                    my $num = pop @{$self->{v}};
                }
                elsif ($c2 == 20) {
                    # The storage operators utilize a transient array and
                    # provide facilities for storing and retrieving transient
                    # array data. The transient array provides non-persistent
                    # storage for intermediate values. There is no provision
                    # to initialize this array, except explicitly using the
                    # put operator, and values stored in the array do not
                    # persist beyond the scope of rendering an individual
                    # character. The number of elements in the transient array
                    # is specified in Appendix B, “Type 2 Charstring
                    # Implementation Limits”.
                    #     val i put (12 20)
                    # stores val into the transient array at the location given by i.
                    $self->disasm_print("put");
                    my $i = pop @{$self->{v}};
                    my $val = pop @{$self->{v}};
                    $self->{transient_array}->[$i] = $val;
                }
                elsif ($c2 == 21) {
                    #    i get (12 21) val
                    # retrieves the value stored in the transient array at the
                    # location given by i and pushes the value onto the
                    # argument stack. If get is executed prior to put for i
                    # during execution of the current charstring, the value
                    # returned is undefined.
                    $self->disasm_print("get");
                    my $i = pop @{$self->{v}};
                    my $val = $self->{transient_array}->[$i];
                    push @{$self->{v}}, $val;
                }
                elsif ($c2 == 22) {
                    # s1 s2 v1 v2 ifelse (12 22) s1_or_s2
                    $self->disasm_print("ifelse");
                    my $v2 = pop @{$self->{v}};
                    my $v1 = pop @{$self->{v}};
                    my $s2 = pop @{$self->{v}};
                    my $s1 = pop @{$self->{v}};
                    if ($v1 <= $v2) {
                        push @{$self->{v}}, $s1;
                    } else {
                        push @{$self->{v}}, $s2;
                    }
                }
                elsif ($c2 == 23) {
                    # random (12 23) num2
                    $self->disasm_print("random");
                    # a pseudo random number num2 in the range (0,1], that is,
                    # greater than zero and less than or equal to one.
                    my $num2 = 1 - rand(1);
                    push @{$self->{v}}, $num2;
                }
                elsif ($c2 == 24) {
                    # num1 num2 mul (12 24) product
                    $self->disasm_print("mul");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    my $product = $num1 * $num2;
                    push @{$self->{v}}, $product;
                }
                elsif ($c2 == 26) {
                    # num sqrt (12 26) num2
                    $self->disasm_print("sqrt");
                    my $num = pop @{$self->{v}};
                    my $num2 = sqrt($num);
                    push @{$self->{v}}, $num2;
                }
                elsif ($c2 == 27) {
                    # any dup (12 27) any any
                    $self->disasm_print("dup");
                    my $any = pop @{$self->{v}};
                    push @{$self->{v}}, $any, $any;
                }
                elsif ($c2 == 28) {
                    # num1 num2 exch (12 28) num2 num1
                    $self->disasm_print("exch");
                    my $num2 = pop @{$self->{v}};
                    my $num1 = pop @{$self->{v}};
                    push @{$self->{v}}, $num2, $num1;
                }
                elsif ($c2 == 29) {
                    # numX ... num0 i index (12 29) numX ... num0 numi

                    # retrieves the element i from the top of the argument stack
                    # and pushes a copy of that element onto that stack.
                    # If i is negative, the top element is copied.
                    # If i is greater than X, the operation is undefined.
                    $self->disasm_print("index");
                    my $i = pop @{$self->{v}};
                    my $num_i = $self->{v}->[-($i + 1)];
                    push @{$self->{v}}, $num_i;
                }
                elsif ($c2 == 30) {
                    # num(N–1) ... num0 N J roll (12 30) num((J–1) mod N) ... num0
                    # num(N–1) ... num(J mod N)

                    # performs a circular shift of the elements num(N–1) ... num0
                    # on the argument stack by the amount J.
                    # Positive J indicates upward motion of the stack;
                    # negative J indicates downward motion.
                    # The value N must be a non-negative integer,
                    # otherwise the operation is undefined.
                    $self->disasm_print("roll");
                    my $J = pop @{$self->{v}};
                    my $N = pop @{$self->{v}};
                    if ($J) {
                        my @tmp = splice @{$self->{v}}, 0, scalar @{$self->{v}} - $N;
                        if ($J > 0) {
                            my @num = splice @{$self->{v}}, -$J;
                            unshift @{$self->{v}}, @num;
                        } else {
                            my @num = splice @{$self->{v}}, 0, -$J;
                            push @{$self->{v}}, @num;
                        }
                        unshift @{$self->{v}}, @tmp;
                    }
                }
                elsif ($c2 == 33) {
                    $self->disasm_print("setcurrentpoint");
                }
                els

=end comment

=cut

                if ($c2 == 34) {
                    # |- dx1 dx2 dy2 dx3 dx4 dx5 dx6 hflex (12 34) |-
                    $self->disasm_print("hflex");
                    #my @args = splice @{$self->{v}}, 0, -7;
                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                elsif ($c2 == 35) {
                    # |- dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 dx5 dy5 dx6 dy6 fd flex (12 35) |-
                    $self->disasm_print("flex");
                    #my @args = splice @{$self->{v}}, 0, -13;
                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                elsif ($c2 == 36) {
                    # |- dx1 dy1 dx2 dy2 dx3 dx4 dx5 dy5 dx6 hflex1 (12 36) |-
                    $self->disasm_print("hflex1");
                    #my @args = splice @{$self->{v}}, 0, -9;
                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                elsif ($c2 == 37) {
                    # |- dx1 dy1 dx2 dy2 dx3 dy3 dx4 dy4 dx5 dy5 d6 flex1 (12 37) |-
                    $self->disasm_print("flex1");
                    #my @args = splice @{$self->{v}}, 0, -11;
                    #$self->disasm_print("|-") if @{$self->{v}} != 0;
                    $self->{v} = []; # clear
                }
                else {
                    $self->disasm_print("unknown_$c,$c2");
                }
            }
            elsif ($c == 14) {
                $self->disasm_print("endchar");
                # – endchar (14) |–
                $self->{w} = pop @{$self->{v}} unless defined $self->{w};
                #my $advance = $self->PrivateDICT->{defaultWidthX};
                #if (defined $self->{w}) {
                #    $advance = $self->PrivateDICT->{nominalWidthX};
                #    $advance += $self->{w};
                #}
                #$self->disasm_print("#advance $advance\n");
                $self->{v} = []; # clear
                $self->disasm_print("\n");
                #last;
            }
            elsif ($c == 18) {
                # |- y dy {dya dyb}* hstemhm (18) |-
                $self->disasm_print("hstemhm");
                &$hstem unless @{$self->{hs}};
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 19) {
                # |- hintmask (19 + mask) |-
                $self->disasm_print("hintmask");
                &$vstem unless @{$self->{vs}};
                my $m = do {
                    my $m;
                    if (defined (my $class = $f->{class}) && defined (my $id = $f->{id})) {
                        if (my $env = $cff // $self) {
                            if ($env->can($class)) {
                                $m = $env->$class->{hintmask}{$id} //= &$hintmask;
                            }
                        }
                    }
                    $m //= &$hintmask;
                };
                my $bitmask = &$getmask($m);
                $self->disasm_print($bitmask);
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 20) {
                # |- cntrmask (20 + mask) |-
                $self->disasm_print("cntrmask");
                &$vstem unless @{$self->{vs}};
                my $m = do {
                    my $m;
                    if (defined (my $class = $f->{class}) && defined (my $id = $f->{id})) {
                        if (my $env = $cff // $self) {
                            if ($env->can($class)) {
                                $m = $env->$class->{hintmask}{$id} //= &$hintmask;
                            }
                        }
                    }
                    $m //= &$hintmask;
                };
                my $bitmask = &$getmask($m);
                $self->disasm_print($bitmask);
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 21) {
                # |- dx1 dy1 rmoveto (21) |-
                $self->disasm_print("rmoveto");
                #my @args = splice @{$self->{v}}, -2 if @{$self->{v}} >= 2;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 22) {
                # |- dx1 hmoveto (22) |-
                $self->disasm_print("hmoveto");
                #my @args = pop @{$self->{v}};
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 23) {
                # |- x dx {dxa dxb}* vstemhm (23) |-
                $self->disasm_print("vstemhm");
                &$vstem unless @{$self->{vs}};
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 24) {
                # |- {dxa dya dxb dyb dxc dyc}+ dxd dyd rcurveline (24) |-
                $self->disasm_print("rcurveline");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 6);
                #my @args = splice @{$self->{v}}, -($q * 6 + $r) if $r == 2;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 25) {
                # |- {dxa dya}+ dxb dyb dxc dyc dxd dyd rlinecurve (25) |-
                $self->disasm_print("rlinecurve");
                #my ($q, $r) = idiv(scalar @{$self->{v}} - 6, 2);
                #my @args = splice @{$self->{v}}, -($q * 2 + 6)  if @{$self->{v}} >= 8;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 26) {
                # |- dx1? {dya dxb dyb dyc}+ vvcurveto (26) |-
                $self->disasm_print("vvcurveto");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 4);
                #my @args = splice @{$self->{v}}, -($q * 4 + $r) if $r == 0 || $r == 1;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 27) {
                # |- dy1? {dxa dxb dyb dxc}+ hhcurveto (27) |-
                $self->disasm_print("hhcurveto");
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 4);
                #my @args = splice @{$self->{v}}, -($q * 4 + $r) if $r == 0 || $r == 1;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            # 28: following 2 bytes interpreted as a 16-bit two's complement number
            elsif ($c == 29) {
                # globalsubr# callgsubr (29) –
                $self->disasm_print("callgsubr");
                my $subr = pop @{$self->{v}};
                my $class = 'GlobalSubr_INDEX';
                my $cs = $self->$class;
                my $index = $subr + $cs->bias;
                if ($cff) {
                    if (defined $f->{id} && defined $f->{class}) {
                        $cff->$class->{hintmask}{$index} = $cff->{$f->{class}}->{hintmask}{$f->{id}};
                    }
                    my $new_cs = $cff->$class;
                    local $DISASM = [];
                    my $code = $cs->data($index);
                    my $tmp_code = $self->disasm({ %$f, class => $class, id => $index }, $code, $cff);
                    $new_cs->subr($index, $tmp_code);
                    $new_code[-2] = sub {
                        my $new_index = $new_cs->{map}{$index};
                        my $new_subr = $new_index - $new_cs->bias;
                        encode_number($new_subr);
                    };
                } else {
                    local $DISASM = [];
                    my $code = $cs->data($index);
                    $self->disasm({ %$f, class => $class, id => $index }, $code);
                }
            }
            elsif ($c == 30) {
                $self->disasm_print("vhcurveto");
                # |- dy1 dx2 dy2 dx3 {dxa dxb dyb dyc dyd dxe dye dxf}* dyf? vhcurveto (30) |-
                # |- {dya dxb dyb dxc dxd dxe dye dyf}+ dxf? vhcurveto (30) |-
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 8);
                #my @args = splice @{$self->{v}}, -($q * 8 + $r)
                #    if $r == 0 || $r == 1 || $r == 4 || $r == 5;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            elsif ($c == 31) {
                $self->disasm_print("hvcurveto");
                # |- dx1 dx2 dy2 dy3 {dya dxb dyb dxc dxd dxe dye dyf}* dxf? hvcurveto (31) |-
                # |- {dxa dxb dyb dyc dyd dxe dye dxf}+ dyf? hvcurveto (31) |-
                #my ($q, $r) = idiv(scalar @{$self->{v}}, 8);
                #my @args = splice @{$self->{v}}, -($q * 8 + $r)
                #    if $r == 4 || $r == 5 || $r == 0 || $r == 1;
                #$self->disasm_print("|-") if @{$self->{v}} != 0;
                $self->{v} = []; # clear
            }
            else {
                $self->disasm_print("unknown_$c");
            }
            $self->disasm_print("\n");
        }
    }

    \@new_code;
}


sub idiv {
    my $q = int($_[0] / $_[1]);
    my $r = $_[0] - $_[1] * $q;
    ($q, $r);
}


sub disasm_print {
    my $self = shift;
    return unless $self->disasm_print_enabled;
    our $DISASM;
    for (@_) {
        $DISASM = [] if !defined $DISASM;
        push @{$DISASM}, [] if !defined $DISASM->[-1] || /\n/;
        my $chunk = $_;
        unless ($self->verbose) {
            $chunk =~ s/\s*#.*$//;
            $chunk =~ s/\s*(?:\([^)]*?\)|\|-)\s*$//;
        }
        if (my @chunk = split /\n/, $chunk) {
            push @{$DISASM->[-1]}, shift @chunk;
            if (@chunk) {
                push @{$DISASM}, [];
                $self->disasm_print(@chunk);
            }
        }
    }
    if (defined wantarray) {
        my $lines;
        if (ref $DISASM) {
            $lines = [ grep { /./ } map { join ' ', @$_ } @{$DISASM} ];
            $DISASM = [];
        } else {
            $lines = [];
        }
        wantarray ? @$lines : join "\n", @$lines, "";
    } else {
        undef;
    }
}


=begin comment

Table 2 -  CFF Data Types

Name    Range           Description
Card8   0..255          1-byte unsigned number
Card16  0..65535        2-byte unsigned number
Offset  varies          1, 2, 3, or 4 byte offset (specified by OffSize field)
OffSize 1..4            1-byte unsigned number specifies the size of an Offset field or fields
SID     0..64999        2-byte string identifier

=end comment

=cut


# Table 3
sub decode_number {
    my $data = shift;
    my $b0 = shift @{$data};
    if ($b0 >= 32 && $b0 <= 246) {
        return $b0 - 139;
    } elsif ($b0 >= 247 && $b0 <= 250) {
        my $b1 = shift @{$data};
        return ($b0 - 247) * 256 + $b1 + 108;
    } elsif ($b0 >= 251 && $b0 <= 254) {
        my $b1 = shift @{$data};
        return -($b0 - 251) * 256 - $b1 - 108
    } elsif ($b0 == 255) {
        my ($b1, $b2, $b3, $b4) = splice @{$data}, 0, 4;
        my $int = $b1 << 24 | $b2 << 16 | $b3 << 8 | $b4;
        $int = -((~$int & 0xffff_ffff) + 1) if $int & 0x8000_0000;
        #return $int / 0x1_0000 / 0x1_0000;
        return $int / 1 << 16;
    } elsif ($b0 == D_shortint) {
        my ($b1, $b2) = splice @{$data}, 0, 2;
        my $int = $b1 << 8 | $b2;
        $int = -((~$int & 0xffff) + 1) if $int & 0x8000;
        return $int;
    } elsif ($b0 == D_longint) {
        my ($b1, $b2, $b3, $b4) = splice @{$data}, 0, 4;
        my $int = $b1 << 24 | $b2 << 16 | $b3 << 8 | $b4;
        $int = -((~$int & 0xffff_ffff) + 1) if $int & 0x8000_0000;
        return $int;
#    } elsif ($b0 == D_BCD) {
#       return decode_BCD($data);
    } else {
        unshift @{$data}, $b0;
        return undef;
    }
}



sub encode_number {
    my $data = shift;
    croak "no data" unless defined $data; # xxxxxx
    confess "data = ''" if $data eq '';
    if ($data =~ /E|[.]/) {
        return encode_BCD($data);
    } elsif ($data >= -107 && $data <= 107) {
        return pack "C*", $data + 139;
    } elsif ($data >= 108 && $data <= 1131) {
        my $b1 = ($data - 108) % 256;
        my $b0 = int(($data - $b1 - 108) / 256) + 247;
        return pack "C*", $b0, $b1;
    } elsif ($data >= -1131 && $data <= -108) {
        my $b1 = (-$data - 108) % 256;
        my $b0 = int((-$data - $b1 - 108) / 256) + 251;
        return pack "C*", $b0, $b1;
    } elsif ($data >= -32768 && $data <= 32767) {
        my $b1 = $data & 0xff;
        my $b0 = ($data >> 8) & 0xff;
        return pack "C*", D_shortint, $b0, $b1;
    } else {
        my $b3 = $data & 0xff;
        my $b2 = ($data >> 8) & 0xff;
        my $b1 = ($data >> 16) & 0xff;
        my $b0 = ($data >> 24) & 0xff;
        return pack "C*", D_longint, $b0, $b1, $b2, $b3;
    }
}


sub test_number_encoding {

    # Table 4 - Integer Format Examples
    my @ints = (
        0 => [0x8b],
        100 => [0xef],
        -100 => [0x27],
        1000 => [0xfa, 0x7c],
        -1000 => [0xfe, 0x7c],
        10000 => [0x1c, 0x27, 0x10],
        -10000 => [0x1c, 0xd8, 0xf0],
        100000 => [0x1d, 0x00, 0x01, 0x86, 0xa0],
        -100000 => [0x1d, 0xff, 0xfe, 0x79, 0x60],
    );
    my @floats = (
        '-2.25' => [0x1e, 0xe2, 0xa2, 0x5f],
        '0.140541E-3' => [0x1e, 0x0a, 0x14, 0x05, 0x41, 0xc3, 0xff],
    );

    while (my ($v, $e) = splice @ints, 0, 2) {
        my $h1 = join ', ', map sprintf("0x%02x", $_), @$e;
        my $e1 = pack "C*", @$e;
        my $d = decode_number($e) // decode_BCD($e);
        croak "could not decode_number [ $h1 ] => $d" unless $d == $v;
        my $r1 = join ', ', map sprintf("0x%02x", $_), @$e;
        croak "could not finish decode_number [ $h1 ] => [ $r1 ]" unless @{$e} == 0;
        my $e2 = encode_number($v);
        my $h2 = join ', ', map sprintf("0x%02x", $_), unpack "C*", $e2;
        print STDERR "encode_number($v) => [ $h2 ]\n";
        croak "could not encode_number $v => [ $h2 ]" unless $e1 eq $e2;
    }
    while (my ($v, $e) = splice @floats, 0, 2) {
        my $h1 = join ', ', map sprintf("0x%02x", $_), @$e;
        my $e1 = pack "C*", @$e;
        my $d = decode_number($e) // decode_BCD($e);
        croak "could not decode_number [ $h1 ] => $d" unless $d eq $v;
        my $r1 = join ', ', map sprintf("0x%02x", $_), @$e;
        croak "could not finish decode_number [ $h1 ] => [ $r1 ]" unless @{$e} == 0;
        my $e2 = encode_number($v);
        my $h2 = join ', ', map sprintf("0x%02x", $_), unpack "C*", $e2;
        print STDERR "encode_number($v) => [ $h2 ]\n";
        croak "could not encode_number $v => [ $h2 ]" unless $e1 eq $e2;
    }

    0;
}


# Table 5 - Nibble Definitions
sub decode_BCD {
    my $data = shift;
    my $f = '';
    if ($data->[0] == 30) {
        shift @{$data};
    } else {
        return undef;
    }
    while (1) {
        my $b = shift @{$data};
        last unless defined $b;
        for ($b >> 4, $b & 15) {
            $f .= chr(ord('0') + $_), next if $_ >= 0 && $_ <= 9;
            $f .= '.', next                if $_ == 0x0a;
            $f .= 'E', next                if $_ == 0x0b;
            $f .= 'E-', next               if $_ == 0x0c;
            $f = '-'.$f, next              if $_ == 0x0e;
            return $f                      if $_ == 0x0f;
            croak sprintf "decode_BCD_operand: could not decode; nibble 0x%0x.\n", $_;
        }
    }
    die "decode_BCD_operand: missing end of number.\n";
}


sub encode_BCD {
    my $data = shift;
    local $_ = "$data";
    s/E-/\xC/;
    y/[0-9\.E\-]/[\x00-\x09\x0A\x0B\x0E]/;
    my @bcd = unpack "C*";
    push @bcd, 0xf;
    push @bcd, 0xf if @bcd & 1;
    my $bcd;
    while (my ($hi, $lo) = splice(@bcd, 0, 2)) {
        $bcd .= chr($hi << 4 | $lo);
    }
    chr(D_BCD) . $bcd;
}


=begin comment

# Table 6 - Operand Types

Type    Description
number  Integer or real number
boolean Integer type with the values 0 (false) and 1 (true)
SID     String id (see section 10)
array   One or more numbers
delta   A number or a delta-encoded array of numbers (see below)


# Table 7 - INDEX Format

Type    Name    Description
Card16  count   Number of objects stored in INDEX
OffSize offSize Offset array element size
Offset  offset [count+1]        Offset array (from byte preceding object data)
Card8   data [<varies>] Object data

=end comment

=cut

sub read_INDEX {
    my $self = shift;
    my $index = $self->read_INDEX_without_data(@_);
    return undef unless $index;
    if (my $length = $index->offset->[-1] - $index->offset->[0]) {
        my ($fh) = $self->{' INFILE'};
        $fh->read(my $dat, $length);
        $index->{data} = $dat;
    }
    $index;
}


sub read_SubrINDEX {
    my $self = shift;
    my $index = $self->read_INDEX(@_);
    $index->TopDICT($self->TopDICT);
    $index;
}


sub read_INDEX_without_data {
    my $self = shift;
    my $pos = shift;

    my ($dat);
    my ($fh) = $self->{' INFILE'};
    $fh->seek($self->{' OFFSET'} + $pos, 0) if defined $pos;
    $fh->read($dat, 3);
    my ($count, $offSize) = unpack "nC", $dat;
    return Font::TTF::CFF_::INDEX->new(count => $count, offSize => $offSize) unless $count;
    confess "offSize $offSize is not in [ 1 .. 4 ]"
        unless $offSize >= 1 && $offSize <= 4;
    $fh->read($dat, $offSize * ($count + 1));
    my @offset;
    my %u = (1 => "C*", 2 => "n*", 4 => "N*");
    if (my $u = $u{$offSize}) {
        push @offset, unpack $u, $dat;
    } elsif ($offSize == 3) {
        my @b = unpack "C*", $dat;
        for (0 .. $count) {
            push @offset, $b[0] << 16 | $b[1] << 8 | $b[2];
            splice @b, 0, 3;
        }
    } else {
        confess "offSize $offSize is not in [ 1 .. 4 ]";
        my @b = unpack "C*", $dat;
        for (0 .. $count) {
            my $offset = 0;
            for (1 .. $offSize) {
                $offset <<= 8;
                $offset += shift @b;
            }
            push @offset, $offset;
        }
    }

    croak "INDEX: must have at least 2 offsets." unless @offset >= 2;
    croak "INDEX: The first offset must be 1." unless $offset[0] == 1;

    my $index = Font::TTF::CFF_::INDEX->new(
        count => $count,
        offSize => $offSize,
        offset => \@offset,
        data => '',
    );

    #$fh->read($dat, $offset[-1] - $offset[0]);

    # Offset    offset [count+1]        Offset array (from byte preceding object data)
    # Card8     data [<varies>] Object data

    $index;
}


sub pack_INDEX {
    my ($self, $index) = @_;

    confess "can't call commit" unless blessed $index && $index->can('commit');
    $index->commit;

    do {
        my $a = $index->count + 1;
        my $b = @{$index->offset};
        confess "check \$index->count + 1 ($a) == \@{\$index->offset} ($b)";
    } unless $index->count +1 == @{$index->offset};

    my %u = (1 => "C", 2 => "n", 4 => "N");
    if (my $u = $u{$index->offSize}) {
        my $h =  pack "n1C1$u*",
            $index->count,
            $index->offSize,
            @{$index->offset};
        return $h . $index->data;
    } elsif ($index->offSize == 3) {
        my $h = pack "n1C1(CCC)*",
            $index->count,
            $index->offSize,
            map { ($_ >> 16) & 0xff, ($_ >> 8) & 0xff, ($_) & 0xff }
            @{$index->offset};
        return $h . $index->data;
    } else {
        confess "offSize ".$index->offSize." is not in [ 1 .. 4 ]";
    }

    undef;
}



=begin comment

# Table 8 - Header Format

Type    Name    Description
Card8   major   Format major version (starting at 1)
Card8   minor   Format minor version (starting at 0)
Card8   hdrSize Header size (bytes)
OffSize offSize Absolute offset (0) size

=end comment

=cut

use Class::Tiny qw(Header);

sub read_Header {
    my $self = shift;
    my ($dat, $header);
    my ($fh) = $self->{' INFILE'};
    $fh->seek($self->{' OFFSET'}, 0);
    $fh->read($dat, 4);
    @{$header}{qw/minor major hdrSize offSize/} = unpack "CCCC", $dat;
    $header;
}


sub pack_Header {
    my ($self, $header) = @_;
    $header //= $self->Header;
    pack "C4", @{$header}{qw/minor major hdrSize offSize/};
}

use Class::Tiny qw(Name_INDEX TopDICT_INDEX);


# Table 9 - Top DICT Operator Entries

sub TopDICT_Entries {
    my $self = shift;
    $self->{TopDICT_Entries} //= $self->get_TopDICT_Entries;
}

sub get_TopDICT_Entries {
    my (%e, %e2);

    #   [ Name Operand(s) Default notes ],
    for (
        [ version => T_SID, undef, 'FontInfo' ],
        [ Notice => T_SID, undef, 'FontInfo' ],
        [ FullName => T_SID, undef, 'FontInfo' ],
        [ FamilyName => T_SID, undef, 'FontInfo' ],
        [ Weight => T_SID, undef, 'FontInfo' ],
        [ UniqueID => T_number, undef, ],
        [ FontBBox => T_array, [ 0, 0, 0, 0 ] ],
        [ XUID => T_array,  undef, ],
        [ charset => T_offset,  0, 'charset offset (0)' ],
        [ Encoding => T_offset,  0, 'encoding offset (0)' ],
        [ CharStrings => T_offset, undef, 'CharStrings offset (0)' ],
        [ Private => T_size_and_offset, undef, 'Private DICT size and offset (0)' ],
    ) {
        my $v = eval "D_$_->[0]";
        croak "D_$_->[0] is not defined" unless defined $v;
        $e{$v} = $_;
    }

    for (
        [ Copyright => T_SID, undef, 'FontInfo' ],
        [ isFixedPitch => T_boolean, 0, 'FontInfo' ],
        [ ItalicAngle => T_number, 0, 'FontInfo' ],
        [ UnderlinePosition => T_number, -100, 'FontInfo' ],
        [ UnderlineThickness => T_number,  50, 'FontInfo' ],
        [ PaintType => T_number, 0, ],
        [ CharstringType => T_number, 2, ],
        [ FontMatrix => T_array, [ 0.001, 0, 0, 0.001, 0, 0 ] ],
        [ StrokeWidth => T_number, 0, ],
        [ SyntheticBase => T_number, undef, 'synthetic base font index', ],
        [ PostScript => T_SID, undef, 'embedded PostScript language code' ],
        [ BaseFontName => T_SID, undef, '(added as needed by Adobe-based technology)' ],
        [ BaseFontBlend => T_delta, undef, '(added as needed by Adobe-based technology)' ],
    ) {
        my $v = eval "D_$_->[0]";
        croak "D_$_->[0] is not defined" unless defined $v;
        $e2{$v} = $_;
    }

    $e{eval D_escape} = \%e2;
    \%e;
}


# Table 10
sub CIDFont_Operator_Extensions
{
    my $self = shift;
    $self->{CIDFont_Operator_Extensions} //= $self->get_CIDFont_Operator_Extensions;
}

sub get_CIDFont_Operator_Extensions
{
    my (%e, %e2);

    #   [ Name Operand(s) Default notes ],
    for (
        [ ROS => T_ROS, undef, 'Registry Ordering Supplement' ],
        [ CIDFontVersion => T_number, 0, ],
        [ CIDFontRevision => T_number, 0, ],
        [ CIDFontType => T_number, 0, ],
        [ CIDCount => T_number, 8720, ],
        [ UIDBase => T_number, undef, ],
        [ FDArray => T_offset, undef, 'Font DICT (FD) INDEX offset (0)' ],
        [ FDSelect => T_offset, undef, 'FDSelect offset (0)' ],
        [ FontName => T_SID, undef, 'FD FontName' ],
    ) {
        my $v = eval "D_$_->[0]";
        croak "D_$_->[0] is not defined" unless defined $v;
        $e2{$v} = $_;
    }

    $e{eval D_escape} = \%e2;
    \%e;
}


sub TopDICT {
    my $self = shift;
    $self->{TopDICT} = shift if @_;
    $self->{TopDICT} //= $self->get_TopDICT;
    $self->{TopDICT};
}


sub get_TopDICT {
    my $self = shift;
    my $index = shift // $self->TopDICT_INDEX;
    my @data = unpack "C*", $index->{data};
    $self->DICT_Data('TopDICT', $self->DICT_operators, \@data);
}


sub DICT_Data {
    my $self = shift;
    my $dict_name = shift;
    my $entries = shift;
    my $data = shift;

    my $DICT = $self->DICT_defaults($entries);
    while (1) {
        last if @{$data} == 0;
        my @last_data = @{$data};
        my (@v, $ent);
        my ($k, $k2);
        while (@$data) {
            my $v = decode_number($data) // decode_BCD($data);
            if (defined $v) {
                push @v, $v;
            } else {
                $k = shift @{$data};
                $ent = $entries->{$k};
                confess "unknown ent: $k" unless ref $ent;
                if (ref $ent eq 'HASH') {
                    $k2 = shift @{$data};
                    $ent = $ent->{$k2};
                    confess "unknown ent: $k, $k2" unless ref $ent;
                    die "$dict_name: @v, $k, $k2" unless defined $ent;
                }
                last;
            }
        }

        my ($name, $operand, $default, $note) = @{$ent};
        print STDERR "$dict_name: $name, @v = ",
            "[ ", join(', ', map sprintf("0x%02x", $_),
                       @last_data[0..($#last_data - @{$data})]), " ]\n"
            if $self->verbose && $self->verbose >= 2; # xxxx
        if ($operand == T_SID) {
            $DICT->{$name} = $self->toString($v[0]) // $v[0];
            $DICT->{"_$name"} = $v[0];
        } elsif ($operand == T_number ||
                 $operand == T_offset ||
                 $operand == T_boolean) {
            $DICT->{$name} = $v[0];
        } elsif ($operand == T_delta) {
            $DICT->{$name} = [ decode_delta(@v) ];
        } elsif ($operand == T_array ||
                 $operand == T_size_and_offset) {
            $DICT->{$name} = \@v;
        } elsif ($operand == T_ROS) {
            $DICT->{$name} = [
                $self->toString($v[0]) // $v[0],
                $self->toString($v[1]) // $v[1],
                $v[2],
            ];
            $DICT->{"_$name"} = \@v;
        } else {
            croak "$dict_name: unknown operand #$operand\n";
        }
    }
    $DICT;
}


sub decode_delta {
    my @list = shift;
    push @list, $list[-1] + $_ for @_;
    @list;
}


sub DICT_defaults {
    my $self = shift;
    my $entries = shift;
    my $defaults;
    for my $i (keys %{$entries}) {
        my $ent = $entries->{$i};
        if (ref $ent eq 'HASH') {
            for my $j (keys %{$ent}) {
                my ($name, $operand, $default, $note) = @{$ent->{$j}};
                $defaults->{$name} = $default;
            }
        } else {
            my ($name, $operand, $default, $note) = @{$ent};
            $defaults->{$name} = $default;
        }
    }
    $defaults;
}


sub make_INDEX {
    my $self = shift;
    my @data = @_;
    if (@data == 1 && ref $data[0] eq 'ARRAY') {
        @data = @{$data[0]};
    }

    my @offset = (1);
    my $data = '';
    for (@data) {
        if (defined) {
            $data .= $_;
            push @offset, $offset[-1] + length;
        } else {
            push @offset, $offset[-1] + 0;
        }
    }

    my $index = Font::TTF::CFF_::INDEX->new(
        count => scalar(@offset) - 1,
        offset => \@offset,
        data => $data,
    );

}


sub DICT_name2value {
    my $self = shift;
    $self->{DICT_name2value} //= $self->get_DICT_name2value;
}


sub get_DICT_name2value {
    my $self = shift;

    my $escape = D_escape;
    my $op = $self->DICT_operators;

    my $name2value;
    for (keys %$op) {
        if ($_ == $escape) {
            for (keys %{$op->{$escape}}) {
                my ($name, $operand, $default, $note) = @{$op->{$escape}{$_}};
                $name2value->{$name} = [ $escape, $_ ];
            }
        } else {
            my ($name, $operand, $default, $note) = @{$op->{$_}};
            $name2value->{$name} = [ $_ ];
        }
    }

    $name2value;
}


sub DICT_operators {
    my $self = shift;
    $self->{DICT_operators} //= $self->get_DICT_operators;
}


sub get_DICT_operators {
    my $self = shift;

    my $escape = D_escape;
    my %operators = (
        %{$self->TopDICT_Entries},
        %{$self->CIDFont_Operator_Extensions},
        %{$self->PrivateDICT_Operators},
        ($escape => {
            %{$self->TopDICT_Entries->{$escape}},
            %{$self->CIDFont_Operator_Extensions->{$escape}},
            %{$self->PrivateDICT_Operators->{$escape}},
        }),
    );

    \%operators;
}


sub pack_DICT {
    my $self = shift;
    my $dict_name = shift;
    my $dict = shift;

    my $operators = $self->DICT_operators;
    my $name2value = $self->DICT_name2value;

    confess "Not a HASH reference" if ref $dict ne 'HASH';
    my @keys = map $name2value->{$_} // (), grep !/^[*_]/, keys %$dict;

=begin comment

    my $ord = 0;
    my %order;
    $order{join $;, D_escape, D_ROS} = $ord++; # 1
    $order{join $;, D_version} = $ord++;
    $order{join $;, D_escape, D_Copyright} = $ord++;
    $order{join $;, D_Notice} = $ord++;     # 2
    $order{join $;, D_FullName} = $ord++;   # 3
    $order{join $;, D_FamilyName} = $ord++; # 4
    $order{join $;, D_Weight} = $ord++;     # 5
    $order{join $;, D_escape, D_isFixedPitch} = $ord++;
    $order{join $;, D_escape, D_ItalicAngle} = $ord++;
    $order{join $;, D_escape, D_UnderlinePosition} = $ord++; # 6
    $order{join $;, D_escape, D_UnderlineThickness} = $ord++;
    $order{join $;, D_escape, D_PaintType} = $ord++;
    $order{join $;, D_escape, D_CharstringType} = $ord++;
    $order{join $;, D_escape, D_FontMatrix} = $ord++;
    $order{join $;, D_UniqueID} = $ord++;
    $order{join $;, D_FontBBox} = $ord++; # 7
    $order{join $;, D_escape, D_StrokeWidth} = $ord++;
    $order{join $;, D_XUID} = $ord++;
    $order{join $;, D_escape, D_CIDFontVersion} = $ord++; # 8
    $order{join $;, D_escape, D_CIDFontRevision} = $ord++;
    $order{join $;, D_escape, D_CIDFontType} = $ord++;
    $order{join $;, D_escape, D_CIDCount} = $ord++; # 9
    $order{join $;, D_escape, D_UIDBase} = $ord++;
    $order{join $;, D_escape, D_FontName} = $ord++; # fd.1
    $order{join $;, D_charset} = $ord++; # 10
    $order{join $;, D_Encoding} = $ord++;
    $order{join $;, D_CharStrings} = $ord++; # 11
    $order{join $;, D_escape, D_FDSelect} = $ord++; # 12
    $order{join $;, D_escape, D_FDArray} = $ord++;  # 13
    $order{join $;, D_Private} = $ord++;
    $order{join $;, D_escape, D_SyntheticBase} = $ord++;
    $order{join $;, D_escape, D_PostScript} = $ord++;
    $order{join $;, D_escape, D_BaseFontName} = $ord++;
    $order{join $;, D_escape, D_BaseFontBlend} = $ord++;
    $order{join $;, D_BlueValues} = $ord++;
    $order{join $;, D_OtherBlues} = $ord++;
    $order{join $;, D_FamilyBlues} = $ord++;
    $order{join $;, D_FamilyOtherBlues} = $ord++;
    $order{join $;, D_escape, D_BlueScale} = $ord++;
    $order{join $;, D_escape, D_BlueShift} = $ord++;
    $order{join $;, D_escape, D_BlueFuzz} = $ord++;
    $order{join $;, D_StdHW} = $ord++;
    $order{join $;, D_StdVW} = $ord++;
    $order{join $;, D_escape, D_StemSnapH} = $ord++;
    $order{join $;, D_escape, D_StemSnapV} = $ord++;
    $order{join $;, D_escape, D_ForceBold} = $ord++;
    $order{join $;, D_escape, D_LanguageGroup} = $ord++;
    $order{join $;, D_escape, D_ExpansionFactor} = $ord++;
    $order{join $;, D_escape, D_initialRandomSeed} = $ord++;
    $order{join $;, D_Subrs} = $ord++;
    $order{join $;, D_defaultWidthX} = $ord++;
    $order{join $;, D_nominalWidthX} = $ord++;

    @keys = sort {
        my $oa = $order{join $;, @$a};
        my $ob = $order{join $;, @$b};
        $oa <=> $ob || $a->[0] <=> $b->[0] || ($a->[1] // '') <=> ($b->[1] // '')
    } @keys;

=end comment

=cut

    #my $fixes;
    my $data = '';
    confess "Not a HASH reference" if ref $dict ne 'HASH';
    for (@keys) {
        my $ent =
            ref && @$_ == 1 ? $operators->{$_->[0]} :
            ref && @$_ == 2 ? $operators->{$_->[0]}{$_->[1]} :
            undef;
        if (defined (my $packed = $self->pack_dict_item($dict_name, $dict, $ent))) {
            $packed .= chr($_) for @$_;
            #$fixes->{$ent->[0]} = [ length $data, length $packed, ];
            $data .= $packed;
        }
    }
    #wantarray ? ($data, $fixes) : $data;
    $data;
}


sub pack_dict_item {
    my ($self, $dict_name, $dict, $ent) = @_;
    return undef unless $ent;
    my ($name, $operand, $default, $note) = @{$ent};
    my $v = $dict->{$name};
    #my $_v = $dict->{"_$name"};

    my $s;
    if ($self->verbose && $self->verbose >= 2) {
        ($s = Dumper($v)) =~ s/\s+/ /g;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 3;
    }
    return undef unless defined $v;
    return undef if ref $v eq 'ARRAY' && @$v == 0;
    #return undef if defined $v && defined $default && "$v" eq "$default";

    if ($operand == T_SID) {
        #my $v = $_v // $self->toSID($v);
        my $v = $self->toSID($v);
        return undef if defined $default && $v == $default;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        return encode_number($v);
    } elsif ($operand == T_number ||
             $operand == T_boolean) {
        return undef if defined $default && $v == $default;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        return encode_number($v);
    } elsif ($operand == T_delta) {
        return undef if cmp_array($v, $default) == 0;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        return join '', encode_delta(@$v);
    } elsif ($operand == T_array) {
        return undef if cmp_array($v, $default) == 0;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        return join '', encode_array(@$v);
    } elsif ($operand == T_ROS) {
        #my $v = $_v // [map +($self->toSID($_->[0]), $self->toSID($_->[1]), $_->[2]), $v ];
        my $v = [ map +($self->toSID($_->[0]), $self->toSID($_->[1]), $_->[2]), $v ];
        return undef if cmp_array($v, $default) == 0;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        return join '', encode_array(@$v);
    } elsif ($operand == T_offset) {
        return undef if defined $default && $v == $default;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        return join '', encode_number($v);
    } elsif ($operand == T_size_and_offset) {
        return undef if cmp_array($v, $default) == 0;
        print STDERR "pack $dict_name: $name: $s\n" if $self->verbose && $self->verbose == 2;
        my ($size, $offset) = @$v;
        return join '', encode_number($size), encode_number($offset);
    } else {
        croak "pack $dict_name: unknown operand #$operand\n";
    }
    undef;
}


sub encode_offset {
    my ($size, $data) = @_;
    my @data;
    for (1 .. $size) {
        unshift @data, $data & 0xff;
        $data >>= 8;
    }
    return pack "C*", @data;
}


use Class::Tiny qw(String_INDEX);


sub toString {
    my $self = shift;
    return undef unless defined(my $sid = shift);
    my $nStandardStrings = @{$self->StandardStrings};
    return $self->StandardStrings->[$sid] if $sid < $nStandardStrings;
    my $i = $sid - $nStandardStrings;
    return undef if $i >= $self->String_INDEX->count;
    return $self->String_INDEX->data($i);
}


sub toSID {
    my $self = shift;
    my $string = shift;
    my $nStandardStrings = @{$self->StandardStrings};
    unless ($self->{String}) {
        for (0 .. $nStandardStrings - 1) {
            $self->{String}{$self->StandardStrings->[$_]} = $_;
        }
        for (0 .. $self->String_INDEX->count - 1) {
            $self->{String}{$self->String_INDEX->data($_)} = $_ + $nStandardStrings;
        }
    }
    my $sid = $self->{String}{$string};
    unless (defined $sid) {
        my $i = $self->String_INDEX->add($string);
        $sid = $self->{String}{$string} = $i + $nStandardStrings;
    }
    $sid;
}


use Class::Tiny qw(GlobalSubr_INDEX);


# Table 11, 12, 13, 14, 15, 16
sub Encoding {
    my $self = shift;
    $self->{Encoding} = shift if @_;
    $self->{Encoding} //= $self->get_Encoding;
    $self->{Encoding};
}


sub get_Encoding {
    my $self = shift;

    my $pos = $self->TopDICT->{Encoding};

    # An encoding is an array of codes associated with glyphs in a font, and
    # a charset is an array of "names" for all glyphs in the font.
    # (In CFF these names are actually SIDs or CIDs, which must be unique.)

    my $encoding;

    # Table 16
    if ($pos == 0) {
        $encoding = {
            format => undef,
            Id => $pos,
            code => $self->StandardEncoding,
        };
    } elsif ($pos == 1) {
        $encoding = {
            format => undef,
            Id => $pos,
            code => $self->ExpertEncoding,
        };
    } elsif (($pos & ~3) == 0) {
        return undef;
    } else {
        my @code = (0); # as SID or CID
        my ($dat);
        my ($fh) = $self->{' INFILE'};
        $fh->seek($self->{' OFFSET'} + $pos, 0) if defined $pos;
        $fh->read($dat, 2);
        my ($format, $n) = unpack "CC", $dat;
        my $mask = 15;
        if (($format & $mask) == 0) {
            # Table 11
            my $nCodes = $n;
            $fh->read($dat, $n);
            push @code, unpack "C*", $dat;
            $encoding = {
                format => $format,
                nCodes => $n,
                code => \@code,
            };
        } elsif (($format & $mask) == 1) {
            # Table 12
            my $nRanges = $n;

            # Table 13 - first, nLeft
            $fh->read($dat, 2 * $n);
            my @Range = unpack "CC" x $n, $dat;
            while (my ($first, $nLeft) = splice @Range, 0, 2) {
                push @code, $first;
                push @code, map $first + $_, 1 .. $nLeft if $nLeft >= 1;
            }
            $encoding = {
                format => $format,
                nRanges => $n, Ranges => \@Range,
                code => \@code,
            };
        } else {
            croak "Encoding: unknown format $format";
        }

        # A few fonts have multiply-encoded glyphs which are not
        # supported directly by any of the above formats (Table 11,
        # 12, 13). This situation is indicated by setting the
        # high-order bit in the format byte and supplementing the
        # encoding, regardless of format type, as shown in #Table 14.

        if ($format & ~$mask) {
            # Table 14
            $fh->read($dat, 1);
            my $nSups = unpack "C", $dat;

            # Table 15 - code, glyph
            croak "encoding is null" unless $encoding;
            $encoding->{nSups} = $nSups;
            $fh->read($dat, 3 * $nSups);
            my @Supplement = unpack "Cn" x $nSups, $dat;
            while (my ($code, $glyph) = splice @Supplement, 0, 2) {
                $encoding->{code}->[$glyph] = $code;
            }
        }
    }

    $encoding;
}


sub pack_Encoding {
    my $self = shift;
    for (shift // $self->Encoding) {
        if (ref eq 'HASH') {
            if (defined $_->{Id}) {
                $self->TopDICT->{Encoding} = $_->{Id};
                return '';
            }
            $_ = $_->{code} if defined $_->{code};
        }
        if (ref eq 'ARRAY') {
            my $enc = pack "n*", @$_;
            if ($enc eq pack "n*", @{$self->StandardEncoding}) {
                print STDERR "pack_Encoding: StandardEncoding\n" if $self->verbose && $self->verbose >= 2;
                $self->TopDICT->{Encoding} = 0;
                return '';
            }
            if ($enc eq pack "n*", @{$self->ExpertEncoding}) {
                print STDERR "pack_Encoding: ExpertEncoding\n" if $self->verbose && $self->verbose >= 2;
                $self->TopDICT->{Encoding} = 1;
                return '';
            }
            my @range = encode_seqlen($_);
            if (@range * 2 >= @$_) {
                # format 0
                return pack "CCC*", 0, scalar @$_, @$_;
            } else {
                # format 1
                return pack "CCC*", 1, scalar @range, map @$_, @range;
            }
        }
    }
    die "cant pack_Encoding";
}


sub encode_seqlen {
    my $arr = shift;
    my $i = shift // 0;
    my $m = @{$arr};
    while (!defined $arr->[$m - 1]) {
        $m--;
    }
    my $j = $i;
    my @range;
    while ($i < $m) {
        $j = $arr->[$i];
        #last unless defined $j;
        my $n = 0;
        while (defined $arr->[$i + $n + 1]) {
            last unless $j + $n + 1 == $arr->[$i + $n + 1];
            $n++;
        }
        push @range, [ $arr->[$i], $n ];
        $i += $n + 1;
        $j += $n + 1;
    }
    @range;
}


# Table 17, 18, 19, 20, 21, 22
sub Charset {
    my $self = shift;
    $self->{Charset} = shift if @_;
    $self->{Charset} //= $self->get_Charset;
    $self->{Charset};
}


sub get_Charset {
    my $self = shift;

    my $charset;
    # Table 22
    my $pos = $self->TopDICT->{charset};
    if ($pos == 0) {
        $charset = {
            format => undef,
            Id => $pos,
            code => $self->ISOAdobeCharset,
        };
    } elsif ($pos == 1) {
        $charset = {
            format => undef,
            Id => $pos,
            code => $self->ExpertCharset,
        };
    } elsif ($pos == 2) {
        $charset = {
            format => undef,
            Id => $pos,
            code => $self->ExpertSubsetCharset,
        };
    } else {
        return undef unless my $nGlyphs = $self->nGlyphs;
        my ($dat);
        my ($fh) = $self->{' INFILE'};
        $fh->seek($self->{' OFFSET'} + $pos, 0) if defined $pos;
        $fh->read($dat, 1);
        my ($format) = unpack "C", $dat;
        my @code = (0);
        if ($format == 0) {
            # Table 17
            $fh->read($dat, 2 * ($nGlyphs - 1));
            push @code, unpack "n*", $dat;
        } else {
            # Table 18 + Table 19 ... (Format 1)
            # Table 20 + Table 21 ... (Format 2)
            my %u = (1 => [ "nC", 3, 'Card8' ], 2 => [ "nn", 4, 'Card16' ]);
            if (my $u = $u{$format}) {
                my $count = $nGlyphs - 1;
                while ($count > 0) {
                    $fh->read($dat, $u->[1]);
                    my ($first, $nLeft) = unpack $u->[0], $dat;
                    push @code, $first;
                    push @code, map $first + $_, 1 .. $nLeft if $nLeft >= 1;
                    $count -= 1 + $nLeft;
                }
            } else {
                croak "Charset: unknown format #$format";       # xxxxx
                $format = undef;
            }
        }
        $charset = {
            format => $format,
            code => \@code,
        };
    }

    $charset;
}


sub pack_Charset {
    my $self = shift;
    for (shift // $self->Charset) {
        if (ref eq 'HASH') {
            if (defined $_->{Id}) {
                $self->TopDICT->{charset} = $_->{Id}; # xxxxx
                return '';
            }
            $_ = $_->{code} if defined $_->{code};
        }
        if (ref eq 'ARRAY') {
            # cid 0 .notdef glyph is omitted.
            my $start = 0;
            $start++ if $_->[$start] == 0;
            my $cs = pack "n*", @{$_}[$start..$#{$_}];
            if ($cs eq pack "n*", @{$self->ISOAdobeCharset}) {
                print STDERR "pack_Charset: ISOAdobeCharset\n" if $self->verbose && $self->verbose >= 2;
                $self->TopDICT->{Charset} = 0;
                return '';
            }
            if ($cs eq pack "n*", @{$self->ExpertCharset}) {
                print STDERR "pack_Charset: ExpertCharset\n" if $self->verbose && $self->verbose >= 2;
                $self->TopDICT->{Charset} = 1;
                return '';
            }
            if ($cs eq pack "n*", @{$self->ExpertSubsetCharset}) {
                print STDERR "pack_Charset: ExpertSubsetCharset\n" if $self->verbose && $self->verbose >= 2;
                $self->TopDICT->{Charset} = 2;
                return '';
            }
            my @range = encode_seqlen($_, $start);
            my $n = scalar @range;
            my $m = max map $_->[1], @range;
            if ($n && $m <= 255 && $n * 3 <= @{$_}) {
                # format 1
                return pack "C(nC)$n", 1, map @$_, @range;
            } elsif (@range && $m >= 255 && @range * 4 <= @{$_}) {
                # format 2
                return pack "C(nn)$n", 2, map @$_, @range;
            } else {
                my @code;
                for my $i (1 .. $#{$_}) {
                    push @code, $_->[$i] // 0;
                }
                # format 0
                return pack "Cn*", 0, @code;
            }
        }
    }
    die "cant pack_Charset";
}


sub nGlyphs {
    my $self = shift;
    $self->{nGlyphs} = shift if @_;
    $self->{nGlyphs} //= $self->get_nGlyphs;
}


sub get_nGlyphs {
    my $self = shift;
    my ($dat);
    my ($fh) = $self->{' INFILE'};
    if ($self->CharStrings_INDEX) {
        return $self->CharStrings_INDEX->count;
    } else {
        my $lastpos = $fh->tell;
        my $index = $self->read_INDEX_without_data($self->TopDICT->{CharStrings});
        $fh->seek($lastpos, 0);
        return $index->count;
    }
}


sub FDSelect {
    my $self = shift;
    $self->{FDSelect} //= $self->get_FDSelect;
    my $gid = shift;
    if (defined $gid) {
        $self->{FDSelect}{gid2fdindex}->[$gid];
    } else {
        $self->{FDSelect};
    }
}


sub get_FDSelect {
    my $self = shift;

    my $pos = $self->TopDICT->{FDSelect};
    return undef unless defined $pos;

    my ($dat);
    my ($fh) = $self->{' INFILE'};

    my $FDSelect = {};
    $fh->seek($self->{' OFFSET'} + $pos, 0);
    $fh->read($dat, 1);
    my $format = unpack "C", $dat;
    $FDSelect->{format} = $format;
    if ($format == 0) {
        return undef unless my $nGlyphs = $self->nGlyphs;
        $fh->read($dat, 1 * $nGlyphs);
        my @gid2fdindex = unpack "C*", $dat;
        $FDSelect->{gid2fdindex} = \@gid2fdindex;
    } elsif ($format == 3) {
        $fh->read($dat, 2);
        my $nRanges = unpack "n", $dat;
        $fh->read($dat, (2 + 1) * $nRanges + 2);
        my @gid2fdindex;
        my @Range3 = unpack "(nC)${nRanges}n1", $dat;
        for (0 .. $nRanges - 1) {
            my $i = $_ * 2;
            my $first = $Range3[$i];
            my $fd    = $Range3[$i + 1];
            my $last  = $Range3[$i + 2] - 1;
            for ($first .. $last) {
                $gid2fdindex[$_] = $fd;
            }
        }
        $FDSelect->{gid2fdindex} = \@gid2fdindex;
    } else {
        confess "FDSelect: unknown format #$format";
        $format = undef;
    }
    $FDSelect;
}


sub pack_FDSelect {
    my $self = shift;
    for (shift // $self->FDSelect) {
        if (ref eq 'HASH') {
            if (defined $_->{format} && ref $_->{gid2fdindex} eq 'ARRAY') {
                return $self->pack_FDS0($_->{gid2fdindex}) if $_->{format} == 0;
                return $self->pack_FDS3($_->{gid2fdindex}) if $_->{format} == 3;
            }
            $_ = $_->{gid2fdindex} if defined $_->{gid2fdindex};
        }
        if (ref $_ eq 'ARRAY') {
            my $fds0 = $self->pack_FDS0($_);
            my $fds3 = $self->pack_FDS3($_);
            return $fds0 if length $fds0 < length $fds3;
            return $fds3;
        }
    }
    die "cant pack_FDSelect";
}


sub pack_FDS0 {
    my $self = shift;
    my $fds = shift;
    my @fds;
    my $tmp;
    for (@$fds) {
        next unless defined;
        $tmp = $_;
        last;
    }
    for (@$fds) {
        $tmp = $_ if defined;
        push @fds, $tmp;
    }
    pack "CC*", 0, @fds;
}


sub pack_FDS3 {
    my $self = shift;
    my $gid2fdindex = shift;
    my $nRanges = 0;
    my $ranges;
    my $i = 0;
    while ($i < @{$gid2fdindex}) {
        next if !defined $gid2fdindex->[$i];
        my $j = $i + 1;
        while ($j < @{$gid2fdindex}) {
            last if defined $gid2fdindex->[$j] && $gid2fdindex->[$i] != $gid2fdindex->[$j];
            $j++;
        }
        $nRanges++;
        $ranges .= pack "nC", $i, $gid2fdindex->[$i];
        $i = $j;
    }
    my $raw = pack "C", 3;
    $raw .= pack "n", $nRanges;
    $raw .= $ranges;
    $raw .= pack "n", $i;
    $raw;
}


sub CharStrings_INDEX {
    my $self = shift;
    $self->{CharStrings_INDEX} = shift if @_;
    $self->{CharStrings_INDEX} //= $self->read_SubrINDEX($self->TopDICT->{CharStrings});
    $self->{CharStrings_INDEX};
}


sub pack_CharStrings {
    my $self = shift;
    $self->pack_INDEX($self->CharStrings_INDEX);
}


sub FontDICT {
    my $self = shift;
    if (@_) {
        my $index = shift;
        unless (defined $self->FDArray->[$index]->{'*Private'}) {
            $self->setup_PrivateDICT_and_LocalSubr_INDEX("FontDICT.$index", $self->FDArray->[$index]);
            $self->FDArray->[$index]->{'*Private'} = $self->PrivateDICT;
            $self->FDArray->[$index]->{'*Private'}{'*Subrs'} = $self->LocalSubr_INDEX;
        }
        for ($self->{FontDICT} = $self->FDArray->[$index]) {
            $self->PrivateDICT($_->{'*Private'});
            $self->LocalSubr_INDEX($_->{'*Private'}{'*Subrs'});
        }
    }
    $self->{FontDICT};
}


sub setup_PrivateDICT_and_LocalSubr_INDEX {
    my $self = shift;
    my $dict_name = shift;
    my $dict = shift;

    if (my $private = $dict->{Private}) {
        my ($size, $offset) = @$private;
        if ($size && $offset) {
            my ($fh) = $self->{' INFILE'};
            $fh->seek($self->{' OFFSET'} + $offset, 0);
            $fh->read(my ($dat), $size);
            my @data = unpack "C*", $dat;
            my $pdict = $self->DICT_Data($dict_name, $self->DICT_operators, \@data);
            $self->PrivateDICT($pdict);
            if (my $subrs = $pdict->{Subrs}) {
                my $lsubr_index = $self->read_SubrINDEX($offset + $subrs);
                $self->LocalSubr_INDEX($lsubr_index);
                return ($pdict, $lsubr_index);
            }
            return $pdict;
        }
    }
    undef;
}


sub FDArray {
    my $self = shift;
    $self->{FDArray} = shift if @_;
    $self->{FDArray} //= $self->get_FDArray;
    $self->{FDArray};
}


sub get_FDArray {
    my $self = shift;
    my @font_dict;
    if (my $index = $self->FDArray_INDEX) {
        for (0 .. $index->count - 1) {
            my @data = unpack "C*", $index->data($_);
            $font_dict[$_] = $self->DICT_Data("FontDICT.$_", $self->DICT_operators, \@data);
        }
    }
    \@font_dict;
}


sub FDArray_INDEX {
    my $self = shift;
    $self->{FDArray_INDEX} = shift if @_;
    $self->{FDArray_INDEX} //= $self->read_INDEX($self->TopDICT->{FDArray});
    $self->{FDArray_INDEX};
}


# Private DICT Data

use Class::Tiny qw(PrivateDICT LocalSubr_INDEX);

=begin comment

sub test_cmp_array {
    for (
        { a => [ 0, 1, 2 ], b => [ 0, 1, 3 ] },
        { a => [ 0 ], b => [ 0, 1 ] },
        { a => [ 1, 2 ], b => [ 0, 1 ] },
    ) {
        my $a = $_->{a};
        my $b = $_->{b};
        my $c = cmp_array($a, $b);
        print STDERR Dumper({
            a => ref $a ? "[ ".join(', ', @$a)." ]" : $a,
            b => ref $b ? "[ ".join(', ', @$b)." ]" : $b,
            c => $c == 0 ? "a == b" : $c < 0 ? "a < b" : "a > b ",
        });
    }
}

=end comment

=cut

sub cmp_array {
    my ($a, $b) = @_;

    return  0 if !defined $a && !defined $b;
    return +1 if  defined $a && !defined $b;
    return -1 if !defined $a &&  defined $b;

    confess Dumper({ cmp_array => { a => $a, b => $b } }) unless
        defined $a && ref $a eq 'ARRAY' &&
        defined $b && ref $b eq 'ARRAY';
    my @a = @$a;
    my @b = @$b;
    my $c;
    if (@a == 0 || @b == 0) {
        $c = @a <=> @b;
        return $c if $c;
    }
    return  0 if !defined $a[0] && !defined $b[0];
    return +1 if  defined $a[0] && !defined $b[0];
    return -1 if !defined $a[0] &&  defined $b[0];
    $c = $a[0] <=> $b[0];
    return $c if $c;
    shift @a;
    shift @b;
    cmp_array(\@a, \@b);
}


sub encode_array {
    map encode_number($_), @_;
}


sub encode_delta {
    # The length of array or delta types is determined by counting the
    # operands preceding the operator. The second and subsequent
    # numbers in a delta are encoded as the difference between
    # successive values. For example, an array a0, a1, ..., an would
    # be encoded as: a0 (a1–a0) (a2–a1) ..., (an–a(n–1)).

    my @list;
    for (0 .. @_ - 1) {
        push @list, ($_ > 0)? $_[$_] - $_[$_ - 1] : $_[$_];
    }
    encode_array(@list);
}



# Table 23
sub PrivateDICT_Operators {
    my $self = shift;
    $self->{PrivateDICT_Operators} //= $self->get_PrivateDICT_Operators;
}

sub get_PrivateDICT_Operators {
    my (%e, %e2);

    #   [ Name Operand(s) Default notes ],
    for (
        [ BlueValues => T_delta ],
        [ OtherBlues => T_delta ],
        [ FamilyBlues => T_delta ],
        [ FamilyOtherBlues => T_delta ],
        [ StdHW => T_number ],
        [ StdVW => T_number ],
        [ Subrs => T_number, undef, 'Offset (self) to local subrs' ],
        [ defaultWidthX => T_number, 0, 'see below' ],
        [ nominalWidthX => T_number, 0, 'see below' ],
    ) {
        my $v = eval "D_$_->[0]";
        croak "D_$_->[0] is not defined" unless defined $v;
        $e{$v} = $_;
    }

    for (
        [ BlueScale => T_number, 0.039625],
        [ BlueShift => T_number, 7 ],
        [ BlueFuzz => T_number,  1 ],
        [ StemSnapH => T_delta ],
        [ StemSnapV => T_delta ],
        [ ForceBold => T_boolean, 0 ],
        [ LanguageGroup => T_number, 0 ],
        [ ExpansionFactor => T_number, 0.06],
        [ initialRandomSeed => T_number, 0],
    ) {
        my $v = eval "D_$_->[0]";
        croak "D_$_->[0] is not defined" unless defined $v;
        $e2{$v} = $_;
    }

    $e{eval D_escape} = \%e2;
    \%e;
}


# Appendix A -  Standard Strings
sub StandardStrings {
    my $self = shift;
    $self->{StandardStrings} //= $self->get_StandardStrings;
}


sub get_StandardStrings {
    my @list = (
#    sid/name
qw/
       0 .notdef                 21 four                    42 I
       1 space                   22 five                    43 J
       2 exclam                  23 six                     44 K
       3 quotedbl                24 seven                   45 L
       4 numbersign              25 eight                   46 M
       5 dollar                  26 nine                    47 N
       6 percent                 27 colon                   48 O
       7 ampersand               28 semicolon               49 P
       8 quoteright              29 less                    50 Q
       9 parenleft               30 equal                   51 R
      10 parenright              31 greater                 52 S
      11 asterisk                32 question                53 T
      12 plus                    33 at                      54 U
      13 comma                   34 A                       55 V
      14 hyphen                  35 B                       56 W
      15 period                  36 C                       57 X
      16 slash                   37 D                       58 Y
      17 zero                    38 E                       59 Z
      18 one                     39 F                       60 bracketleft
      19 two                     40 G                       61 backslash
      20 three                   41 H                       62 bracketright

      63 asciicircum             92 braceleft              121 ellipsis
      64 underscore              93 bar                    122 perthousand
      65 quoteleft               94 braceright             123 questiondown
      66 a                       95 asciitilde             124 grave
      67 b                       96 exclamdown             125 acute
      68 c                       97 cent                   126 circumflex
      69 d                       98 sterling               127 tilde
      70 e                       99 fraction               128 macron
      71 f                      100 yen                    129 breve
      72 g                      101 florin                 130 dotaccent
      73 h                      102 section                131 dieresis
      74 i                      103 currency               132 ring
      75 j                      104 quotesingle            133 cedilla
      76 k                      105 quotedblleft           134 hungarumlaut
      77 l                      106 guillemotleft          135 ogonek
      78 m                      107 guilsinglleft          136 caron
      79 n                      108 guilsinglright         137 emdash
      80 o                      109 fi                     138 AE
      81 p                      110 fl                     139 ordfeminine
      82 q                      111 endash                 140 Lslash
      83 r                      112 dagger                 141 Oslash
      84 s                      113 daggerdbl              142 OE
      85 t                      114 periodcentered         143 ordmasculine
      86 u                      115 paragraph              144 ae
      87 v                      116 bullet                 145 dotlessi
      88 w                      117 quotesinglbase         146 lslash
      89 x                      118 quotedblbase           147 oslash
      90 y                      119 quotedblright          148 oe
      91 z                      120 guillemotright         149 germandbls

     150 onesuperior            179 Ecircumflex            208 ecircumflex
     151 logicalnot             180 Edieresis              209 edieresis
     152 mu                     181 Egrave                 210 egrave
     153 trademark              182 Iacute                 211 iacute
     154 Eth                    183 Icircumflex            212 icircumflex
     155 onehalf                184 Idieresis              213 idieresis
     156 plusminus              185 Igrave                 214 igrave
     157 Thorn                  186 Ntilde                 215 ntilde
     158 onequarter             187 Oacute                 216 oacute
     159 divide                 188 Ocircumflex            217 ocircumflex
     160 brokenbar              189 Odieresis              218 odieresis
     161 degree                 190 Ograve                 219 ograve
     162 thorn                  191 Otilde                 220 otilde
     163 threequarters          192 Scaron                 221 scaron
     164 twosuperior            193 Uacute                 222 uacute
     165 registered             194 Ucircumflex            223 ucircumflex
     166 minus                  195 Udieresis              224 udieresis
     167 eth                    196 Ugrave                 225 ugrave
     168 multiply               197 Yacute                 226 yacute
     169 threesuperior          198 Ydieresis              227 ydieresis
     170 copyright              199 Zcaron                 228 zcaron
     171 Aacute                 200 aacute                 229 exclamsmall
     172 Acircumflex            201 acircumflex            230 Hungarumlautsmall
     173 Adieresis              202 adieresis              231 dollaroldstyle
     174 Agrave                 203 agrave                 232 dollarsuperior
     175 Aring                  204 aring                  233 ampersandsmall
     176 Atilde                 205 atilde                 234 Acutesmall
     177 Ccedilla               206 ccedilla               235 parenleftsuperior
     178 Eacute                 207 eacute                 236 parenrightsuperior

     237 twodotenleader         266 ff                     295 Vsmall
     238 onedotenleader         267 ffi                    296 Wsmall
     239 zerooldstyle           268 ffl                    297 Xsmall
     240 oneoldstyle            269 parenleftinferior      298 Ysmall
     241 twooldstyle            270 parenrightinferior     299 Zsmall
     242 threeoldstyle          271 Circumflexsmall        300 colonmonetary
     243 fouroldstyle           272 hyphensuperior         301 onefitted
     244 fiveoldstyle           273 Gravesmall             302 rupiah
     245 sixoldstyle            274 Asmall                 303 Tildesmall
     246 sevenoldstyle          275 Bsmall                 304 exclamdownsmall
     247 eightoldstyle          276 Csmall                 305 centoldstyle
     248 nineoldstyle           277 Dsmall                 306 Lslashsmall
     249 commasuperior          278 Esmall                 307 Scaronsmall
     250 threequartersemdash    279 Fsmall                 308 Zcaronsmall
     251 periodsuperior         280 Gsmall                 309 Dieresissmall
     252 questionsmall          281 Hsmall                 310 Brevesmall
     253 asuperior              282 Ismall                 311 Caronsmall
     254 bsuperior              283 Jsmall                 312 Dotaccentsmall
     255 centsuperior           284 Ksmall                 313 Macronsmall
     256 dsuperior              285 Lsmall                 314 figuredash
     257 esuperior              286 Msmall                 315 hypheninferior
     258 isuperior              287 Nsmall                 316 Ogoneksmall
     259 lsuperior              288 Osmall                 317 Ringsmall
     260 msuperior              289 Psmall                 318 Cedillasmall
     261 nsuperior              290 Qsmall                 319 questiondownsmall
     262 osuperior              291 Rsmall                 320 oneeighth
     263 rsuperior              292 Ssmall                 321 threeeighths
     264 ssuperior              293 Tsmall                 322 fiveeighths
     265 tsuperior              294 Usmall                 323 seveneighths

     324 onethird               353 AEsmall                382 001.003
     325 twothirds              354 Ccedillasmall          383 Black
     326 zerosuperior           355 Egravesmall            384 Bold
     327 foursuperior           356 Eacutesmall            385 Book
     328 fivesuperior           357 Ecircumflexsmall       386 Light
     329 sixsuperior            358 Edieresissmall         387 Medium
     330 sevensuperior          359 Igravesmall            388 Regular
     331 eightsuperior          360 Iacutesmall            389 Roman
     332 ninesuperior           361 Icircumflexsmall       390 Semibold
     333 zeroinferior           362 Idieresissmall
     334 oneinferior            363 Ethsmall
     335 twoinferior            364 Ntildesmall
     336 threeinferior          365 Ogravesmall
     337 fourinferior           366 Oacutesmall
     338 fiveinferior           367 Ocircumflexsmall
     339 sixinferior            368 Otildesmall
     340 seveninferior          369 Odieresissmall
     341 eightinferior          370 OEsmall
     342 nineinferior           371 Oslashsmall
     343 centinferior           372 Ugravesmall
     344 dollarinferior         373 Uacutesmall
     345 periodinferior         374 Ucircumflexsmall
     346 commainferior          375 Udieresissmall
     347 Agravesmall            376 Yacutesmall
     348 Aacutesmall            377 Thornsmall
     349 Acircumflexsmall       378 Ydieresissmall
     350 Atildesmall            379 001.000
     351 Adieresissmall         380 001.001
     352 Aringsmall             381 001.002
/);

    my @sid_name;
    while (my ($sid, $name) = splice @list, 0, 2) {
        $sid_name[$sid] = $name;
    }
    \@sid_name;
}


# Appendix B - Predefined Encodings (Standard Encoding)
sub StandardEncoding {
    my $self = shift;
    $self->{StandardEncoding} //= $self->get_StandardEncoding;
}

sub get_StandardEncoding {
    my @list = (
#code/SID/name
qw/
   0   0 .notdef             21   0 .notdef             42  11 asterisk
   1   0 .notdef             22   0 .notdef             43  12 plus
   2   0 .notdef             23   0 .notdef             44  13 comma
   3   0 .notdef             24   0 .notdef             45  14 hyphen
   4   0 .notdef             25   0 .notdef             46  15 period
   5   0 .notdef             26   0 .notdef             47  16 slash
   6   0 .notdef             27   0 .notdef             48  17 zero
   7   0 .notdef             28   0 .notdef             49  18 one
   8   0 .notdef             29   0 .notdef             50  19 two
   9   0 .notdef             30   0 .notdef             51  20 three
  10   0 .notdef             31   0 .notdef             52  21 four
  11   0 .notdef             32   1 space               53  22 five
  12   0 .notdef             33   2 exclam              54  23 six
  13   0 .notdef             34   3 quotedbl            55  24 seven
  14   0 .notdef             35   4 numbersign          56  25 eight
  15   0 .notdef             36   5 dollar              57  26 nine
  16   0 .notdef             37   6 percent             58  27 colon
  17   0 .notdef             38   7 ampersand           59  28 semicolon
  18   0 .notdef             39   8 quoteright          60  29 less
  19   0 .notdef             40   9 parenleft           61  30 equal
  20   0 .notdef             41  10 parenright          62  31 greater

  63  32 question            92  61 backslash          121  90 y
  64  33 at                  93  62 bracketright       122  91 z
  65  34 A                   94  63 asciicircum        123  92 braceleft
  66  35 B                   95  64 underscore         124  93 bar
  67  36 C                   96  65 quoteleft          125  94 braceright
  68  37 D                   97  66 a                  126  95 asciitilde
  69  38 E                   98  67 b                  127   0 .notdef
  70  39 F                   99  68 c                  128   0 .notdef
  71  40 G                  100  69 d                  129   0 .notdef
  72  41 H                  101  70 e                  130   0 .notdef
  73  42 I                  102  71 f                  131   0 .notdef
  74  43 J                  103  72 g                  132   0 .notdef
  75  44 K                  104  73 h                  133   0 .notdef
  76  45 L                  105  74 i                  134   0 .notdef
  77  46 M                  106  75 j                  135   0 .notdef
  78  47 N                  107  76 k                  136   0 .notdef
  79  48 O                  108  77 l                  137   0 .notdef
  80  49 P                  109  78 m                  138   0 .notdef
  81  50 Q                  110  79 n                  139   0 .notdef
  82  51 R                  111  80 o                  140   0 .notdef
  83  52 S                  112  81 p                  141   0 .notdef
  84  53 T                  113  82 q                  142   0 .notdef
  85  54 U                  114  83 r                  143   0 .notdef
  86  55 V                  115  84 s                  144   0 .notdef
  87  56 W                  116  85 t                  145   0 .notdef
  88  57 X                  117  86 u                  146   0 .notdef
  89  58 Y                  118  87 v                  147   0 .notdef
  90  59 Z                  119  88 w                  148   0 .notdef
  91  60 bracketleft        120  89 x                  149   0 .notdef

 150   0 .notdef            179 113 daggerdbl          208 137 emdash
 151   0 .notdef            180 114 periodcentered     209   0 .notdef
 152   0 .notdef            181   0 .notdef            210   0 .notdef
 153   0 .notdef            182 115 paragraph          211   0 .notdef
 154   0 .notdef            183 116 bullet             212   0 .notdef
 155   0 .notdef            184 117 quotesinglbase     213   0 .notdef
 156   0 .notdef            185 118 quotedblbase       214   0 .notdef
 157   0 .notdef            186 119 quotedblright      215   0 .notdef
 158   0 .notdef            187 120 guillemotright     216   0 .notdef
 159   0 .notdef            188 121 ellipsis           217   0 .notdef
 160   0 .notdef            189 122 perthousand        218   0 .notdef
 161  96 exclamdown         190   0 .notdef            219   0 .notdef
 162  97 cent               191 123 questiondown       220   0 .notdef
 163  98 sterling           192   0 .notdef            221   0 .notdef
 164  99 fraction           193 124 grave              222   0 .notdef
 165 100 yen                194 125 acute              223   0 .notdef
 166 101 florin             195 126 circumflex         224   0 .notdef
 167 102 section            196 127 tilde              225 138 AE
 168 103 currency           197 128 macron             226   0 .notdef
 169 104 quotesingle        198 129 breve              227 139 ordfeminine
 170 105 quotedblleft       199 130 dotaccent          228   0 .notdef
 171 106 guillemotleft      200 131 dieresis           229   0 .notdef
 172 107 guilsinglleft      201   0 .notdef            230   0 .notdef
 173 108 guilsinglright     202 132 ring               231   0 .notdef
 174 109 fi                 203 133 cedilla            232 140 Lslash
 175 110 fl                 204   0 .notdef            233 141 Oslash
 176   0 .notdef            205 134 hungarumlaut       234 142 OE
 177 111 endash             206 135 ogonek             235 143 ordmasculine
 178 112 dagger             207 136 caron              236   0 .notdef
 237   0 .notdef            244   0 .notdef            251 149 germandbls
 238   0 .notdef            245 145 dotlessi           252   0 .notdef
 239   0 .notdef            246   0 .notdef            253   0 .notdef
 240   0 .notdef            247   0 .notdef            254   0 .notdef
 241 144 ae                 248 146 lslash             255   0 .notdef
 242   0 .notdef            249 147 oslash
 243   0 .notdef            250 148 oe
/);

    my @code;
    while (my ($code, $sid, $name) = splice @list, 0, 3) {
        $code[$code] = $sid;
    }
    \@code;
}

# Appendix B - Predefined Encodings (Expert Encoding)
sub ExpertEncoding {
    my $self = shift;
    $self->{ExpertEncoding} //= $self->get_ExpertEncoding;
}

sub get_ExpertEncoding {
    my @list = (
#code/SID/name
qw/
   0   0 .notdef             18   0 .notdef             36 231 dollaroldstyle
   1   0 .notdef             19   0 .notdef             37 232 dollarsuperior
   2   0 .notdef             20   0 .notdef             38 233 ampersandsmall
   3   0 .notdef             21   0 .notdef             39 234 Acutesmall
   4   0 .notdef             22   0 .notdef             40 235 parenleftsuperior
   5   0 .notdef             23   0 .notdef             41 236 parenrightsuperior
   6   0 .notdef             24   0 .notdef             42 237 twodotenleader
   7   0 .notdef             25   0 .notdef             43 238 onedotenleader
   8   0 .notdef             26   0 .notdef             44  13 comma
   9   0 .notdef             27   0 .notdef             45  14 hyphen
  10   0 .notdef             28   0 .notdef             46  15 period
  11   0 .notdef             29   0 .notdef             47  99 fraction
  12   0 .notdef             30   0 .notdef             48 239 zerooldstyle
  13   0 .notdef             31   0 .notdef             49 240 oneoldstyle
  14   0 .notdef             32   1 space               50 241 twooldstyle
  15   0 .notdef             33 229 exclamsmall         51 242 threeoldstyle
  16   0 .notdef             34 230 Hungarumlautsmall   52 243 fouroldstyle
  17   0 .notdef             35   0 .notdef             53 244 fiveoldstyle
  54 245 sixoldstyle         83 264 ssuperior          112 289 Psmall
  55 246 sevenoldstyle       84 265 tsuperior          113 290 Qsmall
  56 247 eightoldstyle       85   0 .notdef            114 291 Rsmall
  57 248 nineoldstyle        86 266 ff                 115 292 Ssmall
  58  27 colon               87 109 fi                 116 293 Tsmall
  59  28 semicolon           88 110 fl                 117 294 Usmall
  60 249 commasuperior       89 267 ffi                118 295 Vsmall
  61 250 threequartersemdash 90 268 ffl                119 296 Wsmall
  62 251 periodsuperior      91 269 parenleftinferior  120 297 Xsmall
  63 252 questionsmall       92   0 .notdef            121 298 Ysmall
  64   0 .notdef             93 270 parenrightinferior 122 299 Zsmall
  65 253 asuperior           94 271 Circumflexsmall    123 300 colonmonetary
  66 254 bsuperior           95 272 hyphensuperior     124 301 onefitted
  67 255 centsuperior        96 273 Gravesmall         125 302 rupiah
  68 256 dsuperior           97 274 Asmall             126 303 Tildesmall
  69 257 esuperior           98 275 Bsmall             127   0 .notdef
  70   0 .notdef             99 276 Csmall             128   0 .notdef
  71   0 .notdef            100 277 Dsmall             129   0 .notdef
  72   0 .notdef            101 278 Esmall             130   0 .notdef
  73 258 isuperior          102 279 Fsmall             131   0 .notdef
  74   0 .notdef            103 280 Gsmall             132   0 .notdef
  75   0 .notdef            104 281 Hsmall             133   0 .notdef
  76 259 lsuperior          105 282 Ismall             134   0 .notdef
  77 260 msuperior          106 283 Jsmall             135   0 .notdef
  78 261 nsuperior          107 284 Ksmall             136   0 .notdef
  79 262 osuperior          108 285 Lsmall             137   0 .notdef
  80   0 .notdef            109 286 Msmall             138   0 .notdef
  81   0 .notdef            110 287 Nsmall             139   0 .notdef
  82 263 rsuperior          111 288 Osmall             140   0 .notdef
 141   0 .notdef            170 311 Caronsmall         199   0 .notdef
 142   0 .notdef            171   0 .notdef            200 326 zerosuperior
 143   0 .notdef            172 312 Dotaccentsmall     201 150 onesuperior
 144   0 .notdef            173   0 .notdef            202 164 twosuperior
 145   0 .notdef            174   0 .notdef            203 169 threesuperior
 146   0 .notdef            175 313 Macronsmall        204 327 foursuperior
 147   0 .notdef            176   0 .notdef            205 328 fivesuperior
 148   0 .notdef            177   0 .notdef            206 329 sixsuperior
 149   0 .notdef            178 314 figuredash         207 330 sevensuperior
 150   0 .notdef            179 315 hypheninferior     208 331 eightsuperior
 151   0 .notdef            180   0 .notdef            209 332 ninesuperior
 152   0 .notdef            181   0 .notdef            210 333 zeroinferior
 153   0 .notdef            182 316 Ogoneksmall        211 334 oneinferior
 154   0 .notdef            183 317 Ringsmall          212 335 twoinferior
 155   0 .notdef            184 318 Cedillasmall       213 336 threeinferior
 156   0 .notdef            185   0 .notdef            214 337 fourinferior
 157   0 .notdef            186   0 .notdef            215 338 fiveinferior
 158   0 .notdef            187   0 .notdef            216 339 sixinferior
 159   0 .notdef            188 158 onequarter         217 340 seveninferior
 160   0 .notdef            189 155 onehalf            218 341 eightinferior
 161 304 exclamdownsmall    190 163 threequarters      219 342 nineinferior
 162 305 centoldstyle       191 319 questiondownsmall  220 343 centinferior
 163 306 Lslashsmall        192 320 oneeighth          221 344 dollarinferior
 164   0 .notdef            193 321 threeeighths       222 345 periodinferior
 165   0 .notdef            194 322 fiveeighths        223 346 commainferior
 166 307 Scaronsmall        195 323 seveneighths       224 347 Agravesmall
 167 308 Zcaronsmall        196 324 onethird           225 348 Aacutesmall
 168 309 Dieresissmall      197 325 twothirds          226 349 Acircumflexsmall
 169 310 Brevesmall         198   0 .notdef            227 350 Atildesmall

 228 351 Adieresissmall     238 361 Icircumflexsmall   248 371 Oslashsmall
 229 352 Aringsmall         239 362 Idieresissmall     249 372 Ugravesmall
 230 353 AEsmall            240 363 Ethsmall           250 373 Uacutesmall
 231 354 Ccedillasmall      241 364 Ntildesmall        251 374 Ucircumflexsmall
 232 355 Egravesmall        242 365 Ogravesmall        252 375 Udieresissmall
 233 356 Eacutesmall        243 366 Oacutesmall        253 376 Yacutesmall
 234 357 Ecircumflexsmall   244 367 Ocircumflexsmall   254 377 Thornsmall
 235 358 Edieresissmall     245 368 Otildesmall        255 378 Ydieresissmall
 236 359 Igravesmall        246 369 Odieresissmall
 237 360 Iacutesmall        247 370 OEsmal
/);

    my @code;
    while (my ($code, $sid, $name) = splice @list, 0, 3) {
        $code[$code] = $sid;
    }
    \@code;
}


# Appendix C - Predefined Charsets (ISOAdobe)
# All charsets are presented in GID order beginning with GID 1. (The
# .notdef glyph is implicitly GID 0 and is therefore not shown.)

sub ISOAdobeCharset {
    my $self = shift;
    $self->{ISOAdobeCharset} //= $self->get_ISOAdobeCharset;
}


sub get_ISOAdobeCharset {
    my @list = (
#   SID/name
qw/
       1 space                   21 four                    41 H
       2 exclam                  22 five                    42 I
       3 quotedbl                23 six                     43 J
       4 numbersign              24 seven                   44 K
       5 dollar                  25 eight                   45 L
       6 percent                 26 nine                    46 M
       7 ampersand               27 colon                   47 N
       8 quoteright              28 semicolon               48 O
       9 parenleft               29 less                    49 P
      10 parenright              30 equal                   50 Q
      11 asterisk                31 greater                 51 R
      12 plus                    32 question                52 S
      13 comma                   33 at                      53 T
      14 hyphen                  34 A                       54 U
      15 period                  35 B                       55 V
      16 slash                   36 C                       56 W
      17 zero                    37 D                       57 X
      18 one                     38 E                       58 Y
      19 two                     39 F                       59 Z
      20 three                   40 G                       60 bracketleft

      61 backslash               93 bar                    125 acute
      62 bracketright            94 braceright             126 circumflex
      63 asciicircum             95 asciitilde             127 tilde
      64 underscore              96 exclamdown             128 macron
      65 quoteleft               97 cent                   129 breve
      66 a                       98 sterling               130 dotaccent
      67 b                       99 fraction               131 dieresis
      68 c                      100 yen                    132 ring
      69 d                      101 florin                 133 cedilla
      70 e                      102 section                134 hungarumlaut
      71 f                      103 currency               135 ogonek
      72 g                      104 quotesingle            136 caron
      73 h                      105 quotedblleft           137 emdash
      74 i                      106 guillemotleft          138 AE
      75 j                      107 guilsinglleft          139 ordfeminine
      76 k                      108 guilsinglright         140 Lslash
      77 l                      109 fi                     141 Oslash
      78 m                      110 fl                     142 OE
      79 n                      111 endash                 143 ordmasculine
      80 o                      112 dagger                 144 ae
      81 p                      113 daggerdbl              145 dotlessi
      82 q                      114 periodcentered         146 lslash
      83 r                      115 paragraph              147 oslash
      84 s                      116 bullet                 148 oe
      85 t                      117 quotesinglbase         149 germandbls
      86 u                      118 quotedblbase           150 onesuperior
      87 v                      119 quotedblright          151 logicalnot
      88 w                      120 guillemotright         152 mu
      89 x                      121 ellipsis               153 trademark
      90 y                      122 perthousand            154 Eth
      91 z                      123 questiondown           155 onehalf
      92 braceleft              124 grave                  156 plusminus

     157 Thorn                  181 Egrave                 205 atilde
     158 onequarter             182 Iacute                 206 ccedilla
     159 divide                 183 Icircumflex            207 eacute
     160 brokenbar              184 Idieresis              208 ecircumflex
     161 degree                 185 Igrave                 209 edieresis
     162 thorn                  186 Ntilde                 210 egrave
     163 threequarters          187 Oacute                 211 iacute
     164 twosuperior            188 Ocircumflex            212 icircumflex
     165 registered             189 Odieresis              213 idieresis
     166 minus                  190 Ograve                 214 igrave
     167 eth                    191 Otilde                 215 ntilde
     168 multiply               192 Scaron                 216 oacute
     169 threesuperior          193 Uacute                 217 ocircumflex
     170 copyright              194 Ucircumflex            218 odieresis
     171 Aacute                 195 Udieresis              219 ograve
     172 Acircumflex            196 Ugrave                 220 otilde
     173 Adieresis              197 Yacute                 221 scaron
     174 Agrave                 198 Ydieresis              222 uacute
     175 Aring                  199 Zcaron                 223 ucircumflex
     176 Atilde                 200 aacute                 224 udieresis
     177 Ccedilla               201 acircumflex            225 ugrave
     178 Eacute                 202 adieresis              226 yacute
     179 Ecircumflex            203 agrave                 227 ydieresis
     180 Edieresis              204 aring                  228 zcaron
/);

    my @charset = (0);      # .notdef
    while (my ($sid, $name) = splice @list, 0, 2) {
        push @charset, $sid;
    }
    \@charset;
}


# Appendix C - Predefined Charsets (Expert)
sub ExpertCharset {
    my $self = shift;
    $self->{ExpertCharset} //= $self->get_ExpertCharset;
}

sub get_ExpertCharset {
    my @list = (
#    SID/name
qw/
       1 space                  233 ampersandsmall         238 onedotenleader
     229 exclamsmall            234 Acutesmall              13 comma
     230 Hungarumlautsmall      235 parenleftsuperior       14 hyphen
     231 dollaroldstyle         236 parenrightsuperior      15 period
     232 dollarsuperior         237 twodotenleader          99 fraction

     239 zerooldstyle           267 ffi                    299 Zsmall
     240 oneoldstyle            268 ffl                    300 colonmonetary
     241 twooldstyle            269 parenleftinferior      301 onefitted
     242 threeoldstyle          270 parenrightinferior     302 rupiah
     243 fouroldstyle           271 Circumflexsmall        303 Tildesmall
     244 fiveoldstyle           272 hyphensuperior         304 exclamdownsmall
     245 sixoldstyle            273 Gravesmall             305 centoldstyle
     246 sevenoldstyle          274 Asmall                 306 Lslashsmall
     247 eightoldstyle          275 Bsmall                 307 Scaronsmall
     248 nineoldstyle           276 Csmall                 308 Zcaronsmall
      27 colon                  277 Dsmall                 309 Dieresissmall
      28 semicolon              278 Esmall                 310 Brevesmall
     249 commasuperior          279 Fsmall                 311 Caronsmall
     250 threequartersemdash    280 Gsmall                 312 Dotaccentsmall
     251 periodsuperior         281 Hsmall                 313 Macronsmall
     252 questionsmall          282 Ismall                 314 figuredash
     253 asuperior              283 Jsmall                 315 hypheninferior
     254 bsuperior              284 Ksmall                 316 Ogoneksmall
     255 centsuperior           285 Lsmall                 317 Ringsmall
     256 dsuperior              286 Msmall                 318 Cedillasmall
     257 esuperior              287 Nsmall                 158 onequarter
     258 isuperior              288 Osmall                 155 onehalf
     259 lsuperior              289 Psmall                 163 threequarters
     260 msuperior              290 Qsmall                 319 questiondownsmall
     261 nsuperior              291 Rsmall                 320 oneeighth
     262 osuperior              292 Ssmall                 321 threeeighths
     263 rsuperior              293 Tsmall                 322 fiveeighths
     264 ssuperior              294 Usmall                 323 seveneighths
     265 tsuperior              295 Vsmall                 324 onethird
     266 ff                     296 Wsmall                 325 twothirds
     109 fi                     297 Xsmall                 326 zerosuperior
     110 fl                     298 Ysmall                 150 onesuperior

     164 twosuperior            343 centinferior           361 Icircumflexsmall
     169 threesuperior          344 dollarinferior         362 Idieresissmall
     327 foursuperior           345 periodinferior         363 Ethsmall
     328 fivesuperior           346 commainferior          364 Ntildesmall
     329 sixsuperior            347 Agravesmall            365 Ogravesmall
     330 sevensuperior          348 Aacutesmall            366 Oacutesmall
     331 eightsuperior          349 Acircumflexsmall       367 Ocircumflexsmall
     332 ninesuperior           350 Atildesmall            368 Otildesmall
     333 zeroinferior           351 Adieresissmall         369 Odieresissmall
     334 oneinferior            352 Aringsmall             370 OEsmall
     335 twoinferior            353 AEsmall                371 Oslashsmall
     336 threeinferior          354 Ccedillasmall          372 Ugravesmall
     337 fourinferior           355 Egravesmall            373 Uacutesmall
     338 fiveinferior           356 Eacutesmall            374 Ucircumflexsmall
     339 sixinferior            357 Ecircumflexsmall       375 Udieresissmall
     340 seveninferior          358 Edieresissmall         376 Yacutesmall
     341 eightinferior          359 Igravesmall            377 Thornsmall
     342 nineinferior           360 Iacutesmall            378 Ydieresissmall
/);

    my @charset = (0);      # .notdef
    while (my ($sid, $name) = splice @list, 0, 2) {
        push @charset, $sid;
    }
    \@charset;
}


# Appendix C - Predefined Charsets (Expert Subset)

sub ExpertSubsetCharset {
    my $self = shift;
    $self->{ExpertSubsetCharset} //= $self->get_ExpertSubsetCharset;
}


sub get_ExpertSubsetCharset {
    my @list = (
#   SID/name
qw/
       1 space                  239 zerooldstyle            28 semicolon
     231 dollaroldstyle         240 oneoldstyle            249 commasuperior
     232 dollarsuperior         241 twooldstyle            250 threequartersemdash
     235 parenleftsuperior      242 threeoldstyle          251 periodsuperior
     236 parenrightsuperior     243 fouroldstyle           253 asuperior
     237 twodotenleader         244 fiveoldstyle           254 bsuperior
     238 onedotenleader         245 sixoldstyle            255 centsuperior
      13 comma                  246 sevenoldstyle          256 dsuperior
      14 hyphen                 247 eightoldstyle          257 esuperior
      15 period                 248 nineoldstyle           258 isuperior
      99 fraction                27 colon                  259 lsuperior

     260 msuperior              314 figuredash             330 sevensuperior
     261 nsuperior              315 hypheninferior         331 eightsuperior
     262 osuperior              158 onequarter             332 ninesuperior
     263 rsuperior              155 onehalf                333 zeroinferior
     264 ssuperior              163 threequarters          334 oneinferior
     265 tsuperior              320 oneeighth              335 twoinferior
     266 ff                     321 threeeighths           336 threeinferior
     109 fi                     322 fiveeighths            337 fourinferior
     110 fl                     323 seveneighths           338 fiveinferior
     267 ffi                    324 onethird               339 sixinferior
     268 ffl                    325 twothirds              340 seveninferior
     269 parenleftinferior      326 zerosuperior           341 eightinferior
     270 parenrightinferior     150 onesuperior            342 nineinferior
     272 hyphensuperior         164 twosuperior            343 centinferior
     300 colonmonetary          169 threesuperior          344 dollarinferior
     301 onefitted              327 foursuperior           345 periodinferior
     302 rupiah                 328 fivesuperior           346 commainferior
     305 centoldstyle           329 sixsuperior
/);

    my @charset = (0);      # .notdef
    while (my ($sid, $name) = splice @list, 0, 2) {
        push @charset, $sid;
    }
    \@charset;
}


sub new_subr_index {
    my $self = shift;
    Font::TTF::CFF_::INDEX->new(TopDICT => $self->TopDICT, @_);
}


package Font::TTF::CFF_::INDEX;

use strict;
use warnings;
use Carp;
use parent -norequire, 'Font::TTF::CFF_';
use POSIX qw(ceil);
use List::Util qw(max min);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    # Strings start at 1, arrays start at 0.
    my $self = bless { offset => [ 1 ], data => '', @_, stage => [], }, $class;
    $self;
}

# subr - registers a subroutine. The subroutine number (index) in $code is
# determined after commit, so it is expressed as sub {} and evaled at commit
# time.  $self->{map} is the hash that maps old and new indexes.

sub subr {
    my ($self, $index, $code) = @_;
    if (defined $index && defined $code) {
        #$self->{count} = undef;
        #$self->{offSize} = undef;
        $self->{subr}{$index} = $code;
        $self->{map}{$index} = undef;
    }
    $self->{subr};
}


# remap - rearranges the hash given by $name with a new index.

sub remap {
    my $self = shift;
    my $name = shift;
    my @opt = @_;
    if (defined (my $h = $self->{$name})) {
        $self->{$name} = {};
        for my $index (keys %{$self->{map}}) {
            my $new_index = $self->{map}{$index};
            if (defined (my $m = $h->{$index})) {
                $self->{$name}{$new_index} = $m;
                #print STDERR "#remap @opt $name $m, $index => $new_index\n";
            }
        }
    }
}


# add - moves the passed item to stage and returns the offset index that will
# be used when the item is registered in data.

sub add {
    my $self = shift;
    if (@_) {
        $self->{count} = undef;
        $self->{offSize} = undef;
        my $i = $#{$self->offset};
        $i += @{$self->stage} if $self->stage;
        my $n = @_;
        $self->stage(@_);
        wantarray? ($i .. ($i + $n - 1)) : $i;
    } else {
        undef;
    }
}


sub stage {
    my $self = shift;
    if (@_) {
        $self->{stage} //= [];
        push @{$self->{stage}}, @_;
    }
    $self->{stage};
}


sub commit {
    my $self = shift;
    if (defined $self->{subr}) {
        for (sort { $a <=> $b } keys %{$self->{subr}}) {
            if (!defined $self->{map}{$_}) {
                $self->{map}{$_} = $self->add($self->{subr}{$_});
            }
        }
        delete $self->{subr};
    }
    if ($self->stage) {
        for (@{$self->stage}) {
            if (ref eq 'ARRAY') {
                for (@$_) {
                    if (ref eq 'CODE') {
                        for (&$_) {
                            $self->{data} .= $_ if defined;
                        }
                    } else {
                        $self->{data} .= $_ if defined;
                    }
                }
            } else {
                $self->{data} .= $_ if defined && length > 0;
            }
            push @{$self->{offset}}, 1 + length $self->{data};
        }
        $self->{count} = $#{$self->offset};
        delete $self->{stage};
    }
}


sub data {
    my $self = shift;
    $self->commit;
    if (@_) {
        my $i = shift;  # $i = 0: indicates the first element.
        if ($i >= 0 && $i <= $self->count - 1) {
            if ($i >= (my $n = $#{$self->{offset}})) {
                if ((my $j = $i - $n) < @{$self->stage}) {
                    return $self->stage->[$j];
                }
            }
            my $j0 = $self->{offset}->[$i];
            my $j1 = $self->{offset}->[$i + 1];
            confess "Perhaps \"out of range\" subscripts are used " .
                "on \$self->{offset}->[$i + 1]; count is " . $self->count
                unless (defined $j1);
            my $n = $j1 - $j0;
            return substr $self->{data}, $j0 - 1, $n;
        } else {
            confess "index $i is out of range [0 .. " . ($self->count - 1) . "]";
        }
    } else {
        return $self->{data};
    }
}


sub offset {
    my $self = shift;
    $self->{offset};
}


sub count {
    my $self = shift;
    return $self->{count} if defined $self->{count};
    my $count = 0;
    for (keys %{$self->{subr}}) {
        if (!defined $self->{map}{$_}) {
            $count++;
        }
    }
    $count += scalar @{$self->stage} if exists $self->{stage} && ref $self->stage;
    $self->{count} = $count;
}


use Class::Tiny qw(TopDICT);


sub bias {
    my $self = shift;
    my $count = shift // $self->count;
    if (defined $self->TopDICT && $self->TopDICT->{CharstringType} == 1) {
        return 0;
    } elsif ($count < 1240) {
        return 107;
    } elsif ($count < 33900) {
        return 1131;
    } else {
        return 32768;
    }
}


sub offSize {
    my $self = shift;
    return $self->{offSize} if defined $self->{offSize};
    $self->commit;
    $self->{offSize} = max(1, ceil(log($self->offset->[-1] + 1) / log(256)));
}


package Font::TTF::CFF_::Dumper;

use strict;
use warnings;
use parent -norequire, 'Font::TTF::CFF_';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = bless { file => \*STDERR, @_ };
}


sub dump_xml {
    my $self = shift;
    my $cff = shift;

    my $disasm = $cff->disasm_print_enabled;
    $cff->disasm_print_enabled(1);

    $self->p(qq<?xml version="1.0" encoding="UTF-8"?>);
    $self->p(qq<font_ttf>);
    $self->_p;
    $self->p(qq<CFF>);
    for (qw/major minor/) {
        my $value = $cff->Header->{$_};
        $self->p(qq<$_ value="$value"/>);
    }
    my $fontname = $cff->Name_INDEX->data(0);
    $self->p(qq<CFFFont name="$fontname">);
    for my $tag (qw/ROS/) {
        for ($cff->TopDICT->{$tag}) {
            $self->p(qq[<$tag Registry="$_->[0]" Order="$_->[1]" Supplement="$_->[2]"/>]);
        }
    }
    for my $tag (qw( Notice FullName FamilyName Weight isFixedPitch ItalicAngle
                     UnderlinePosition UnderlineThickness PaintType CharstringType
                     FontMatrix FontBBox StrokeWidth XUID CIDFontVersion
                     CIDFontRevision CIDFontType CIDCount )) {
        for ($cff->TopDICT->{$tag}) {
            if (defined) {
                if (ref) {
                    $self->p(qq[<$tag value="@$_"/>]);
                } else {
                    $self->p(qq[<$tag value="$_"/>]);
                }
            }
        }
    }

    $self->p(qq<!-- charset is dumped separately as the 'GlyphOrder' element -->);
    for my $tag (qw/FDSelect/) {
        for (qw/format/) {
            my $value = $cff->{FDSelect}->{$_} // "";
            $self->p(qq<$tag $_="$value"/>);
        }
    }
    $self->p(qq<FDArray>);
    for my $index (0 .. $#{$cff->FDArray}) {
        $self->p(qq<FontDict index="$index">);
        my $fdict = $cff->FontDICT($index);
        for (qw/FontName/) {
            my $value = $fdict->{$_} // "";
            $self->p(qq<$_ value="$value"/>);
        }
        if ($cff->PrivateDICT) {
            $self->p(qq<Private>);
            for my $tag (qw( BlueValues OtherBlues BlueScale BlueShift BlueFuzz
                             StdHW StdVW StemSnapH StemSnapV ForceBold
                             LanguageGroup ExpansionFactor initialRandomSeed
                             defaultWidthX nominalWidthX )) {
                for ($cff->PrivateDICT->{$tag}) {
                    if (defined) {
                        if (ref) {
                            $self->p(qq[<$tag value="@$_"/>]);
                        } else {
                            $self->p(qq[<$tag value="$_"/>]);
                        }
                    }
                }
            }
            $self->dump_xml_subrs($cff, 'LocalSubr_INDEX', 'Subrs');
            $self->p(qq</Private>);
        }
        $self->p(qq</FontDict>);
    }
    $self->p(qq</FDArray>);
    $self->dump_xml_charstrings($cff);
    $self->p(qq</CFFFont>);
    $self->_p;
    $self->dump_xml_subrs($cff, 'GlobalSubr_INDEX', 'GlobalSubrs');
    $self->p(qq</CFF>);
    $self->_p;
    $self->p(qq</font_ttf>);

    $cff->disasm_print_enabled($disasm);
}


sub dump_xml_charstrings {
    my $self = shift;
    my $cff = shift;
    my $class = 'CharStrings_INDEX';
    $self->p(qq<CharStrings>);
    for my $gid (0, $cff->gid) {
        my $index = $cff->{FDSelect}{gid2fdindex}->[$gid];
        my $cid = $cff->Charset->{code}->[$gid];
        #my $psname = $cff->toString($cid) // sprintf "cid%05d", $cid;
        my $psname = $cid == 0 ? ".notdef" : sprintf "cid%05d", $cid;
        $self->p(qq<CharString name="$psname" fdSelectIndex="$index">);
        my $fdict = $cff->FontDICT($index);
        $cff->PrivateDICT($fdict->{'*Private'});
        if (my $private = $cff->PrivateDICT) {
            $cff->LocalSubr_INDEX($private->{'*Subrs'});
        }
        my $code = $cff->$class->data($gid);
        $cff->disasm({ class => $class, id => $gid }, $code);
        $self->_p($_) for $cff->disasm_print();
        $self->p(qq</CharString>);
    }
    $self->p(qq</CharStrings>);
}


sub dump_xml_subrs {
    my $self = shift;
    my $cff = shift;
    my $class = shift; #'LocalSubr_INDEX';
    my $tag = shift // $class;
    my $subrs = $cff->$class;
    if ($subrs && $subrs->count > 0) {
        $self->p(qq<$tag>);
        $self->_p(qq(<!-- The 'index' attribute is only for humans; it is ignored when parsed. -->));
        for my $i (0 .. $subrs->count - 1) {
            #my $subr = $i - $subrs->bias;
            #$self->p(qq<CharString index="$i" subr="$subr">);
            $self->p(qq<CharString index="$i">);
            my $code = $cff->$class->data($i);
            $cff->disasm({ class => $class, id => $i }, $code);
            $self->_p($_) for $cff->disasm_print();
            $self->p(qq</CharString>);
        }
        $self->p(qq</$tag>);
    }
}


sub p {
    my $self = shift;
    my $text = "@_";
    my ($lp, $rp) = $text =~ s/^(<)(.*?)(>)$/$2/ ? ($1, $3) : ('<', '>');
    my $rs = $text =~ s/(\/)$// ? $1 : '';
    my $ls = $text =~ s/^(\/)// ? $1 : '';
    my $cm = $text =~ /^(!--.*?--|[?].*?[?])$/;
    $self->{p_indent}-- if $ls;
    $self->_p($lp, $ls, $text, $rs, $rp);
    $self->{p_indent}++ if !$ls && !$rs && !$cm;
}


sub _p {
    my $self = shift;
    if (@_) {
        my $in = "  " x ($self->{p_indent} // 0);
        print {$self->{file}} $in, @_;
    }
    print {$self->{file}} "\n";
}

1;
