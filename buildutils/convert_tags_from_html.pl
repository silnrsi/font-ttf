# This utility script interprets HTML files from MS's version of the OT spec
# to generate tags script for OTTags.pm
# The three files processed are scripttags.htm, featurelist.htm, and languagetags.htm
# These files are assumed to be in "C:\Reference\Microsoft\OpenType 1.6" unless
#   a folder name is supplied as the sole argument on the command name.
#
# Output (to stdout) is in perl syntax for the hash initialization, e.g.:
#	    "Arabic" => "arab",
#	    "Armenian" => "armn",
# This output can the be transferred to Tags.pm
#
# Bob Hallissy 2010-09-16

use strict;

use File::Spec::Functions;
use HTML::Parser;

my $dir = ($ARGV[0] ? $ARGV[0] : "/Reference/Microsoft/OpenType 1.6");

die "Cannot locate .HTM files in '$dir'.\n" unless (
	-f catfile($dir, "languagetags.htm") and 
	-f catfile($dir, "featurelist.htm") and 
	-f catfile($dir, "scripttags.htm")
	);

my $filename;
my $which;		# either LANGUAGE, FEATURE, or SCRIPT

my $curText;	# Text accumulator.
my $curCol;		# Which column of the table we're processing -- reset to 0 by <tr>
my $td;			# ref to array of text from a <tr> containing <td>

my (%tttags, %iso639list);   # Accumulated data

sub text
{
	my ($self, $text) = @_;
	$curText .= $text;
}

sub start
{
	my ($self, $tagname) = @_;
	$curText = '';
	if ($tagname eq 'tr')
	{
		$curCol = 0;
		undef $td;
	}
}	
	
sub end
{
	my ($self, $tagname) = @_;
	if ($tagname eq 'th')
	{
		if ($curCol++ == 0)
		{
			# confirm which table we have:
			$curText =~ /^(\S+)/;
			$which = uc($1);
			die "Unexpected table header '$curText' in '$filename'./n" unless $filename =~ /^${which}/i;
		}
	}
	elsif ($tagname eq 'td')
	{
		# trip leading and trailing whitespace and quotes:
		$curText =~ s/[\s']+$//;
		$curText =~ s/^[\s']+//;
		# fold dashes to hyphen-minus:
		$curText =~ s/[\x{2010}-\x{201F}]/-/g;
		$td->[$curCol++] = $curText;
	}
	elsif ($tagname eq 'tr' && defined $td)
	{
		# Ok -- got a complete row of data to work with
		
		# Feature table is reversed with tag being first:
		$td = [ reverse @{$td} ] if $which eq "FEATURE";
		
		# So now
		#    $td->[0] is the name (of script, language, or feature(s))
		#    $td->[1] is the tag name plus possibly extra stuff
		#    $td->[3], if exists, is comma-separated iso639 language codes
		
		my ($name, $tag, $iso639list) = @{$td};
		
		if ($tag =~ /^(\S+)\s+(.+)$/)
		{
			# Extra text after the tag name, such as Dhivehi has "(deprecated)" after the "DHV " tag -- move it to name.
			$tag = $1;
			$name .= " $2";
		}
		
		if ($tag =~ /^(.{1,4})-(.{1,4})$/)
		{
			# Special handling for feature names like 'cv01-cv99'
			my ($tag1, $tag2) = ($1, $2);
			for my $tag ($tag1 .. $tag2)
			{
				$tag =~ /(\d+)$/;
				my $index = $1;
				$tag .= ' ' x (4 - length($tag));	# pad tag
				$tttags{$which}{"$name $index"} = "$tag";
			}
		}
		else
		{
			# Normal tags	
			# Pad the tag:
			$tag .= ' ' x (4 - length($tag));
			$tttags{$which}{$name} = $tag;
		}

		if (defined $iso639list)
		{
			$iso639list =~ s/[, ]+/ /g;  # Strip commas, leaving space.
			$iso639list{$tag} = $iso639list # Save for later
		}
	}
}

sub VerifyAnsi
{
	my $str = shift;
	my $strA = $str;
	$strA =~ s/[^\x00-\x7F]/?/g;
	print STDERR "Wide data:\n$strA\n$str\n" if $str ne $strA;
}

my  $p = HTML::Parser->new(
	api_version => 3,
	start_h => [\&start, 'self,tagname'],
	end_h   => [\&end,   'self,tagname'],
	text_h   => [\&text, 'self,text'],
	report_tags => [qw(table th tr td)],
	);

foreach (qw (scripttags.htm languagetags.htm featurelist.htm))
{
	$filename = $_;
	my $fh;
	open($fh, "<:utf8", catfile($dir, $filename)) || die "cannot open '$filename': $!/n";
	$p->parse_file($fh);
	close $fh;
}

print <<EOF;
# All data below derived Microsoft OpenType specification 1.6

%tttags = (

EOF

for $which (qw (SCRIPT LANGUAGE FEATURE))
{
	print "'$which' => {\n"; 
	# Alpha order by name (not tag)
	foreach my $name (sort keys (%{$tttags{$which}}))
	{
		VerifyAnsi "$name => $tttags{$which}{$name}";
		print "    \"$name\" => '$tttags{$which}{$name}',\n";
	}
	print "    },\n\n";	
}
print ");\n\n";

print "\%iso639 = (\n";
foreach my $tag (sort keys(%iso639list))
{
	VerifyAnsi "$tag => $iso639list{$tag}";
	printf "    '$tag' => '$iso639list{$tag}',\n";
}
print ");\n";

=head1 AUTHOR

Bob Hallissy L<http://scripts.sil.org/FontUtils>.

=head1 LICENSING

Copyright (c) 1998-2014, SIL International (http://www.sil.org)

This script is released under the terms of the Artistic License 2.0.
For details, see the full text of the license in the file LICENSE.

=cut 

