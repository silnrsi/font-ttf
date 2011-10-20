package Font::TTF::Silf;

=head1 NAME

Font::TTF::Silf - The main Graphite table

=head1 DESCRIPTION

yadayadaya

=head1 INSTANCE VARIABLES

=over 4

=item SILF

There are multiple graphite descriptions in a single Silf table. Each is held
as an item in the SILF array

=over 4

=item PASS

The core of Silf description is the sequence of passes that are executed on the
glyph string.


=back

=back

=cut

use Font::TTF::Table;
use Font::TTF::Utils;
use strict;
use vars qw(@ISA);

@ISA = qw(Font::TTF::Table);

=head2 read

Reads the Silf table into the internal data structure

=cut

sub read
{
    my ($self) = @_;
    my ($dat, $d);
    my ($fh) = $self->{' INFILE'};
    my ($moff) = $self->{' OFFSET'};
    my ($numsilf, @silfo);
    
    $self->SUPER::read or return $self;
    $fh->read($dat, 4);
    ($self->{'Version'}) = TTF_Unpack("v", $dat);
    if ($self->{'Version'} >= 3)
    {
        $fh->read($dat, 4);
        ($self->{'Compiler'}) = TTF_Unpack("v", $dat);
    }
    $fh->read($dat, 4);
    ($numsilf) = TTF_Unpack("S", $dat);
    $fh->read($dat, $numsilf * 4);
    foreach my $i (0 .. $numsilf - 1)
    { push (@silfo, TTF_Unpack("L", substr($dat, $i * 4, 4))); }

    foreach my $sili (0 .. $numsilf - 1)
    {
        my ($silf) = {};
        my (@passo, @classo, $classbase, $numJust, $numCritFeatures, $numScript, $numPasses, $numPseudo, $i);

        push (@{$self->{'SILF'}}, $silf);
        $fh->seek($moff + $silfo[$sili], 0);
        if ($self->{'Version'} >= 3)
        {
            $fh->read($dat, 8);
            ($silf->{'Version'}) = TTF_Unpack("v", $dat);
        }
        $fh->read($dat, 20);
        ($silf->{'maxGlyphID'}, $silf->{'Ascent'}, $silf->{'Descent'},
         $numPasses, $silf->{'substPass'}, $silf->{'posPass'}, $silf->{'justPass'}, $silf->{'bidiPass'},
         $silf->{'Flags'}, $silf->{'maxPreContext'}, $silf->{'maxPostContext'}, $silf->{'attrPseudo'},
         $silf->{'attrBreakWeight'}, $silf->{'attrDirectionality'}, $d, $d, $numJust) = 
            TTF_Unpack("SssCCCCCCCCCCCCCC", $dat);
        if ($numJust)
        {
            foreach my $j (0 .. $silf->{'numJust'} - 1)
            {
                my ($just) = {};
                push (@{$silf->{'JUST'}}, $just);
                $fh->read($dat, 8);
                ($just->{'attrStretch'}, $just->{'attrShrink'}, $just->{'attrStep'}, $just->{'attrWeight'},
                 $just->{'runto'}) = TTF_Unpack("CCCCC", $dat);
            }
        }
        $fh->read($dat, 10);
        ($silf->{'numLigComp'}, $silf->{'numUserAttr'}, $silf->{'maxCompPerLig'}, $silf->{'direction'},
         $d, $d, $d, $d, $numCritFeatures) = TTF_Unpack("SCCCCCCCC", $dat);
        if ($numCritFeatures)
        {
            $fh->read($dat, $numCritFeatures * 2);
            $silf->{'CRIT_FEATURE'} = [TTF_Unpack("S$numCritFeatures", $dat)];
        }
        $fh->read($dat, 2);
        ($d, $numScript) = TTF_Unpack("CC", $dat);
        if ($numScript)
        {
            $fh->read($dat, $numScript * 4);
            foreach (0 .. $numScript - 1)
            { push (@{$silf->{'scripts'}}, unpack('a4', substr($dat, $_ * 4, 4))); }
        }
        $fh->read($dat, 2);
        ($silf->{'lbGID'}) = TTF_Unpack("S", $dat);
        $fh->read($dat, $numPasses * 4 + 4);
        @passo = unpack("N*", $dat);
        $fh->read($dat, 8);
        ($numPseudo) = TTF_Unpack("S", $dat);
        if ($numPseudo)
        {
            $fh->read($dat, $numPseudo * 6);
            foreach (0 .. $numPseudo - 1)
            {
                my ($uni, $gid) = TTF_Unpack("LS", substr($dat, $_ * 6, 6));
                $silf->{'pseudos'}{$uni} = $gid;
            }
        }
        $classbase = $fh->tell();
        $fh->read($dat, 4);
        my ($numClasses, $numLinearClasses) = TTF_Unpack("SS", $dat);
        $fh->read($dat, $numClasses * 2 + 2);
        @classo = unpack("n*", $dat);
        $fh->read($dat, $classo[-1] - $classo[0]);
        for ($i = 0; $i < $numLinearClasses; $i++)
        {
            my ($c) = 0;
            push (@{$silf->{'classes'}}, { map {$_ => $c++} 
                                                unpack("n*", substr($dat, $classo[$i] - $classo[0], 
                                                            $classo[$i+1] - $classo[$i])) }); 
        }
        for ($i = $numLinearClasses; $i < $numClasses; $i++)
        {
            push (@{$silf->{'classes'}}, { unpack("n*",
                substr($dat, $classo[$i] - $classo[0] + 8, $classo[$i+1] - $classo[$i] - 8)) });
        }
        foreach (0 .. $numPasses - 1)
        { $self->read_pass($fh, $passo[$_], $moff + $silfo[$sili], $silf); }
    }
    return $self;
}

sub chopcode
{
    my ($dest, $dat, $offsets) = @_;
    my ($last) = $offsets->[-1];
    my ($i);

    for ($i = $#{$offsets} - 1; $i >= 0; $i--)
    {
        if ($offsets->[$i])
        {
            unshift(@{$dest}, substr($dat, $offsets->[$i], $last - $offsets->[$i]));
            $last = $offsets->[$i];
        }
        else
        { unshift(@{$dest}, ""); }
    }
}


sub read_pass
{
    my ($self, $fh, $offset, $base, $silf) = @_;
    my ($pass) = {};
    my ($d, $dat, $i, @orulemap, @oconstraints, @oactions, $numRanges);

    $fh->seek($offset + $base, 0);
    push (@{$silf->{'PASS'}}, $pass);
    $fh->read($dat, 40);
    ($pass->{'flags'}, $pass->{'maxRuleLoop'}, $pass->{'maxRuleContext'}, $pass->{'maxBackup'},
     $pass->{'numRules'}, $d, $d, $d, $d, $d, $pass->{'numRows'}, $pass->{'numTransitional'},
     $pass->{'numSuccess'}, $pass->{'numColumns'}, $numRanges) =
        TTF_Unpack("CCCCSSLLLLSSSSS", $dat);
    $fh->read($dat, $numRanges * 6);
    foreach $i (0 .. $numRanges - 1)
    {
        my ($first, $last, $col) = TTF_Unpack('SSS', substr($dat, $i * 6, 6));
        foreach ($first .. $last)
        { $pass->{'colmap'}{$_} = $col; }
    }
    $fh->read($dat, $pass->{'numSuccess'} * 2 + 2);
    @orulemap = unpack("n*", $dat);
    $fh->read($dat, $orulemap[-1] * 2);
    foreach (0 .. $pass->{'numSuccess'} - 1)
    { push (@{$pass->{'rulemap'}}, [unpack("n*", substr($dat, $orulemap[$_] * 2, ($orulemap[$_+1] - $orulemap[$_]) * 2))]); }
    $fh->read($dat, 2);
    ($pass->{'minRulePreContext'}, $pass->{'maxRulePreContext'}) = TTF_Unpack("CC", $dat);
    $fh->read($dat, ($pass->{'maxRulePreContext'} - $pass->{'minRulePreContext'} + 1) * 2);
    $pass->{'startStates'} = [unpack('n*', $dat)];
    $fh->read($dat, $pass->{'numRules'} * 2);
    $pass->{'ruleSortKeys'} = [unpack('n*', $dat)];
    $fh->read($dat, $pass->{'numRules'});
    $pass->{'rulePreContexts'} = [unpack('C*', $dat)];
    $fh->read($dat, 3);
    ($d, $pass->{'pConstraintLen'}) = TTF_Unpack("CS", $dat);
    $fh->read($dat, ($pass->{'numRules'} + 1) * 2);
    @oconstraints = unpack('n*', $dat);
    $fh->read($dat, ($pass->{'numRules'} + 1) * 2);
    @oactions = unpack('n*', $dat);
    foreach (0 .. $pass->{'numTransitional'} - 1)
    {
        $fh->read($dat, $pass->{'numColumns'} * 2);
        push (@{$pass->{'fsm'}}, [unpack('n*', $dat)]);
    }
    $fh->read($dat, 1);
    if ($pass->{'passConstraintLen'})
    { $fh->read($pass->{'passConstraintCode'}, $pass->{'passConstraintLen'}); }
    $fh->read($dat, $oconstraints[-1]);
    $pass->{'constraintCode'} = [];
    chopcode($pass->{'constraintCode'}, $dat, \@oconstraints);
    $fh->read($dat, $oactions[-1]);
    $pass->{'actionCode'} = [];
    chopcode($pass->{'actionCode'}, $dat, \@oactions);
    return $pass;
}

sub chopranges
{
    my ($map) = @_;
    my ($dat, $numRanges);
    my (@keys) = sort {$a <=> $b} keys %{$map};
    my ($first, $last, $col, $g);

    $first = -1;
    $last = -1;
    $col = -1;
    foreach $g (@keys)
    {
        if ($g != $last + 1 || $map->{$g} != $col)
        {
            if ($col != -1)
            {
                $dat .= pack("SSS", $first, $last, $col);
                $numRanges++;
            }
            $first = $last = $g;
            $col = $map->{$g};
        }
    }
    if ($col != -1)
    {
        $dat .= pack("SSS", $first, $last, $col);
        $numRanges++;
    }
    return ($numRanges, $dat);
}

sub packcode
{
    my ($code) = @_;
    my ($dat, $c, $res);

    foreach (@{$code})
    {
        if ($_)
        {
            push(@{$res}, $c);
            $dat .= $_;
            $c += length($_);
        }
        else
        { push(@{$res}, 0); }
    }
    push(@{$res}, $c);
    return ($res, $dat);
}

sub out_pass
{
    my ($self, $fh, $pass, $silf, $subbase) = @_;
    my (@orulemap, $dat, $actiondat, $numRanges, $c);
    my (@offsets, $res, $pbase);

    $pbase = $fh->tell();
    $fh->print(TTF_Pack("CCCCSSLLLLSSSS", $pass->{'flags'}, $pass->{'maxRuleLoop'}, $pass->{'maxRuleContext'},
                $pass->{'maxBackup'}, $pass->{'numRules'}, 24, 0, 0, 0, 0, $pass->{'numRows'},
                $pass->{'numTransitional'}, $pass->{'numSuccess'}, $pass->{'numColumns'}));
    ($numRanges, $dat) = chopranges($pass->{'colmap'});
    $fh->print(TTF_Pack("SSSS", TTF_bininfo($numRanges)));
    $fh->print($dat);
    $dat = "";
    $c = 0;
    foreach (@{$pass->{'rulemap'}})
    {
        push(@orulemap, $c);
        $dat .= pack("n*", @{$_});
        $c += @{$_};
    }
    push (@orulemap, $c);
    $fh->print(pack("n*", @orulemap));
    $fh->print($dat);
    $fh->print(TTF_Pack("CC", $pass->{'minRulePreContext'}, $pass->{'maxRulePreContext'}));
    $fh->print(pack("n*", @{$pass->{'startStates'}}));
    $fh->print(pack("n*", @{$pass->{'ruleSortKeys'}}));
    $fh->print(pack("C*", @{$pass->{'rulePreContexts'}}));
    $fh->print(TTF_Pack("CS", 0, $pass->{'passConstraintLen'}));
    my ($oconstraints, $dat) = packcode($pass->{'constraintCode'});
    my ($oactions, $actiondat) = packcode($pass->{'actionCode'});
    $fh->print(pack("n*", @{$oconstraints}));
    $fh->print(pack("n*", @{$oactions}));
    foreach (@{$pass->{'fsm'}})
    { $fh->print(pack("n*", @{$_})); }
    $fh->print(pack("C", 0));
    push(@offsets, $fh->tell() - $subbase);
    $fh->print($pass->{'passConstraintCode'});
    push(@offsets, $fh->tell() - $subbase);
    $fh->print($dat);
    push(@offsets, $fh->tell() - $subbase);
    $fh->print($actiondat);
    push(@offsets, 0);
    $res = $fh->tell();
    $fh->seek($pbase + 8, 0);
    $fh->print(pack("n*", @offsets));
    $fh->seek($res, 0);
}

sub out
{
    my ($self, $fh) = @_;
    my ($silf);

    return $self->SUPER::out($fh) unless ($self->{' read'});
    if ($self->{'Version'} >= 3)
    { $fh->print(TTF_Pack("vvSS", $self->{'Version'}, $self->{'Compiler'}, $#{$self->{'SILF'}} + 1, 0)); }
    else
    { $fh->print(TTF_Pack("vSS", $self->{'Version'}, $#{$self->{'SILF'}} + 1, 0)); }
    foreach $silf (@{$self->{'SILF'}})
    {
        my ($subbase) = $fh->tell();
        my ($numlin, $i, @opasses, $oPasses, $oPseudo, $ooPasses, $end);
        if ($self->{'Version'} > 3)
        { $fh->print(TTF_Pac("vSS", $silf->{'Version'}, $oPasses, $oPseudo)); }
        $fh->print(TTF_Pack("SssCCCCCCCCCCCCCC", 
             $silf->{'maxGlyphID'}, $silf->{'Ascent'}, $silf->{'Descent'},
             $silf->{'numPasses'}, $silf->{'substPass'}, $silf->{'posPass'}, $silf->{'justPass'}, $silf->{'bidiPass'},
             $silf->{'Flags'}, $silf->{'maxPreContext'}, $silf->{'maxPostContext'}, $silf->{'attrPseudo'},
             $silf->{'attrBreakWeight'}, $silf->{'attrDirectionality'}, 0, 0, $#{$silf->{'JUST'}} + 1));
        foreach (@{$silf->{'JUST'}})
        { $fh->print(TTF_Pack("CCCCCCCC", $_->{'attrStretch'}, $_->{'attrShrink'}, $_->{'attrStep'},
                        $_->{'attrWeight'}, $_->{'runto'}, 0, 0, 0)); }
        
        $fh->print(TTF_Pack("SCCCCCCCC", $silf->{'numLigComp'}, $silf->{'numUserAttr'}, $silf->{'maxCompPerLig'},
                        $silf->{'direction'}, 0, 0, 0, 0, $#{$silf->{'CRIT_FEATURE'}} + 1));
        $fh->print(pack("n*", @{$silf->{'CRIT_FEATURE'}}));
        $fh->print(TTF_Pack("CC", 0, $#{$silf->{'scripts'}} + 1));
        foreach (@{$self->{'scripts'}})
        { $fh->print(pack("a4", $_)); }
        $fh->print(TTF_Pack("S", $silf->{'lbGID'}));
        $ooPasses = $fh->tell();
        $fh->print(pack("N*", (0) x @{$silf->{'PASS'}}));
        $fh->print(TTF_Pack("SSSS", TTF_bininfo(@{$silf->{'pseudos'}})));
        $oPseudo = $fh->tell() - $subbase;
        while (my ($k, $v) = each %{$silf->{'pseudos'}})
        { $fh->print(TTF_Pack("LS", $k, $v)); }
        $numlin = -1;
        foreach (0 .. $#{$silf->{'classes'}})
        {
            if (@{$silf->{'classes'}[$_]} > 8)          # binary search vs linear search crosses at 8 elements
            {
                $numlin = $_;
                last;
            }
        }
        $numlin = @{$silf->{'classes'}} if ($numlin < 0);
        $fh->print(TTF_Pack("SS", scalar @{$silf->{'classes'}}, $numlin));
        for ($i = 0; $i < $numlin; $i++)
        { $fh->print(pack("n*", sort {$silf->{'classes'}[$i]{$a} <=> $silf->{'classes'}[$i]{$b}} keys %{$silf->{'classes'}[$i]})); }
        for ($i = $numlin; $i < @{$silf->{'classes'}}; $i++)
        {
            foreach (sort {$a <=> $b} keys %{$silf->{'classes'}[$i]})
            { $fh->print(TTF_Pack("SS", $_, $silf->{'classes'}[$i]{$_})); }
        }
        $oPasses = $fh->tell() - $subbase;
        push (@opasses, $oPasses);
        foreach (@{$silf->{'PASS'}})
        { push(@opasses, $self->out_pass($fh, $_, $silf, $subbase) - $subbase); }
        $end = $fh->tell();
        $fh->seek($ooPasses, 0);
        $fh->print(pack("N*", @opasses));
        if ($self->{'Version'} >= 3)
        {
            $fh->seek($subbase + 4, 0);
            $fh->print(TTF_Pack("SS", $oPasses, $oPseudo));
        }
        $fh->seek($end, 0);
    }
}

sub XML_element
{
    my ($self, $context, $depth, $k, $val) = @_;
    my ($fh) = $context->{'fh'};
    my ($i);

    return $self if ($k eq 'LOC');

    if ($k eq 'classes')
    {
        $fh->print("$depth<classes>\n");
        foreach $i (0 .. @{$val})
        {
            $fh->printf("$depth    <class num='%d'>\n", $i);
            foreach (sort {$a <=> $b} keys %{$val->[$i]})
            { $fh->printf("%s        <glyph id='%d' index='%d'/>\n", $depth, $_, $val->[$i]{$_}); }
            $fh->print("$depth    </class>\n");
        }
        $fh->print("$depth</classes>\n");
    }
    elsif ($k eq 'fsm')
    {
        $fh->print("$depth<fsm>\n");
        foreach (@{$val})
        { $fh->print("$depth    <row>" . join(" ", @{$_}) . "</row>\n"); }
        $fh->print("$depth</fsm>\n");
    }
    elsif ($k eq 'colmap')
    {
        my ($i);
        $fh->print("$depth<colmap>");
        while (my ($k, $v) = each %{$val})
        {
            if ($i++ % 8 == 0)
            { $fh->print("\n$depth  "); }
            $fh->printf(" %d=%d", $k, $v);
        }
        $fh->print("\n$depth</colmap>\n");
    }
    else
    { return $self->SUPER::XML_element($context, $depth, $k, $val); }

    $self;
}
