package Make::Rule::Vars;
use Carp;
use strict;
my $generation = 0; # lexical cross-package scope used!

# Package to handle 'magic' variables pertaining to rules e.g. $@ $* $^ $?
# by using tie to this package 'subsvars' can work with array of 
# hash references to possible sources of variable definitions.

sub TIEHASH
{
 my ($class,$rule) = @_;
 return bless \$rule,$class;
}

sub FETCH
{
 my $self = shift;
 local $_ = shift;
 my $rule = $$self;
 return undef unless (/^[\@^<?*]$/);
 # print STDERR "FETCH $_ for ",$rule->Name,"\n";
 return $rule->Name if ($_ eq '@');
 return $rule->Base if ($_ eq '*');
 return join(' ',$rule->exp_depend)  if ($_ eq '^');
 return join(' ',$rule->out_of_date) if ($_ eq '?');
 # Next one is dubious - I think $< is really more subtle ...
 return ($rule->exp_depend)[0] if ($_ eq '<');
 return undef;
}

package Make::Rule;
use Carp;
use strict;

# Bottom level 'rule' package 
# An instance exists for each ':' or '::' rule in the makefile.
# The commands and dependancies are kept here.

sub target
{
 return shift->{TARGET};
}

sub Name
{
 return shift->target->Name;
}

sub Base
{
 my $name = shift->target->Name;
 $name =~ s/\.[^.]+$//;
 return $name;
}

sub Info
{
 return shift->target->Info;
}       

sub depend
{
 my $self = shift;
 if (@_)
  {            
   my $name = $self->Name;
   my $dep = shift;
   confess "dependants $dep are not an array reference" unless ('ARRAY' eq ref $dep); 
   my $file;
   foreach $file (@$dep)
    {
     unless (exists $self->{DEPHASH}{$file})
      {    
       $self->{DEPHASH}{$file} = 1;
       push(@{$self->{DEPEND}},$file);
      }
    }
  }
 return (wantarray) ? @{$self->{DEPEND}} : $self->{DEPEND};
}

sub command
{
 my $self = shift;
 if (@_)
  {
   my $cmd = shift;
   confess "commands $cmd are not an array reference" unless ('ARRAY' eq ref $cmd); 
   if (@$cmd)
    {
     if (@{$self->{COMMAND}})
      {
       warn "Command for ".$self->Name," redefined";
       print STDERR "Was:",join("\n",@{$self->{COMMAND}}),"\n";
       print STDERR "Now:",join("\n",@$cmd),"\n";
      }
     $self->{COMMAND} = $cmd;
    }
   else
    {
     if (@{$self->{COMMAND}})
      { 
       # warn "Command for ".$self->Name," retained";
       # print STDERR "Was:",join("\n",@{$self->{COMMAND}}),"\n";
      }
    } 
  }
 return (wantarray) ? @{$self->{COMMAND}} : $self->{COMMAND};
}

#
# The key make test - is target out-of-date as far as this rule is concerned
# In scalar context - boolean value of 'do we need to apply the rule'
# In list context the things we are out-of-date with e.g. magic $? variable
#
sub out_of_date
{
 my $array = wantarray;
 my $self  = shift;
 my $info  = $self->Info;
 my @dep = ();
 my $tdate  = $self->target->date;
 my $dep;
 my $count = 0;
 foreach $dep ($self->exp_depend)
  {
   my $date = $info->date($dep);
   $count++;
   if (!defined($date) || !defined($tdate) || $date < $tdate)
    {       
     # warn $self->Name." ood wrt ".$dep."\n";
     return 1 unless $array;
     push(@dep,$dep);
    }
  }
 return @dep if $array;
 # Note special case of no dependencies means it is always  out-of-date!
 return !$count;
}

#
# Return list of things rule depends on with variables expanded
# - May need pathname and vpath processing as well
#
sub exp_depend
{
 my $self = shift;
 my $info = $self->Info;
 my @dep = map(split(/\s+/,$info->subsvars($_)),$self->depend);
 return (wantarray) ? @dep : \@dep;
}

#
# Return commands to apply rule with variables expanded
# - No pathname processing needed, commands should always chdir()
#   to logical place (at least till we get very clever at bourne shell parsing).
# - May need vpath processing
#
sub exp_command
{
 my $self   = shift;
 my $info   = $self->Info;
 my $base   = $self->Name;
 my %var;
 tie %var,'Make::Rule::Vars',$self;
 my @cmd  = map($info->subsvars($_,\%var),$self->command);
 return (wantarray) ? @cmd : \@cmd;
}

#
# clone creates a new rule derived from an existing rule, but 
# with a different target. Used when left hand side was a variable.
# perhaps should be used for dot/pattern rule processing too.
#
sub clone
{
 my ($self,$target) = @_;
 my %hash = %$self;
 $hash{TARGET} = $target;
 $hash{DEPEND} = [@{$self->{DEPEND}}];
 $hash{DEPHASH} = {%{$self->{DEPHASH}}};
 my $obj = bless \%hash,ref $self;
 return $obj;
}

sub new
{
 my $class = shift;
 my $target = shift;
 my $kind   = shift;
 my $self = bless { TARGET => $target,             # parent target (left hand side)
                    KIND => $kind,                 # : or ::
                    DEPEND => [], DEPHASH => {},   # right hand args
                    COMMAND => []                  # command(s)  
                  },$class;        
 $self->depend(shift) if (@_);
 $self->command(shift) if (@_);
 return $self;
}

#
# This code has to go somewhere but no good home obvious yet.
#  - only applies to ':' rules, but needs top level database
#  - perhaps in ->commands of derived ':' class?
#
sub find_commands
{
 my ($self) = @_;
 if (!@{$self->{COMMAND}} && @{$self->{DEPEND}})
  {
   my $info = $self->Info;
   my $name = $self->Name;
   my @dep  = $self->depend;
   my @rule = $info->patrule($self->Name);
   if (@rule)
    {
     $self->depend($rule[0]);
     $self->command($rule[1]);
    }
  }
}

#
# Spew a shell script to perfom the 'make' e.g. make -n 
#
sub Script
{
 my $self = shift;
 return unless $self->out_of_date;
 my @cmd = $self->exp_command;
 if (@cmd)
  {
   my $file;
  my $com = ($^O eq 'MSWin32') ? 'rem ': '# ';
   print  $com,$self->Name,"\n";
   foreach $file ($self->exp_command)
    {
     $file =~ s/^[\@\s-]*//;
     print "$file\n";
    }
  }
}

#
# Normal 'make' method
#
sub Make
{
 my $self = shift;
 my $file;
 return unless ($self->out_of_date);
 my @cmd = $self->exp_command;
 my $info = $self->Info;
 if (@cmd)
  {
   foreach my $file ($self->exp_command)
    {
     $file =~ s/^([\@\s-]*)//;
     my $prefix = $1;
     print  "$file\n" unless ($prefix =~ /\@/);
     my $code = $info->exec($file);
     if ($code && $prefix !~ /-/)
      {
       die "Code $code from $file";
      }
    }
  }
}

#
# Print rule out in makefile syntax 
# - currently has variables expanded as debugging aid.
# - will eventually become make -p 
# - may be useful for writing makefiles from MakeMaker too...
#
sub Print
{
 my $self = shift;
 my $file;
 print $self->Name,' ',$self->{KIND},' ';
 foreach $file ($self->depend)
  {
   print " \\\n   $file";
  }
 print "\n";
 my @cmd = $self->exp_command;
 if (@cmd)
  {
   foreach $file ($self->exp_command)
    {
     print "\t",$file,"\n";
    }
  }
 else
  {
   print STDERR "No commands for ",$self->Name,"\n" unless ($self->target->phony); 
  }
 print "\n";
}

package Make::Target;
use Carp;
use strict;
use Cwd;

#
# Intermediate 'target' package
# There is an instance of this for each 'target' that apears on 
# the left hand side of a rule i.e. for each thing that can be made.
# 
sub new
{
 my ($class,$info,$target) = @_;
 return bless { NAME => $target,     # name of thing
                MAKEFILE => $info,   # Makefile context 
                Pass => 0            # Used to determine if 'done' this sweep
              },$class;
}

sub date
{
 my $self = shift;
 my $info = $self->Info;
 return $info->date($self->Name);
}

sub phony
{
 my $self = shift;
 return $self->Info->phony($self->Name);
}   


sub colon
{
 my $self = shift;
 if (@_)
  {
   if (exists $self->{COLON})
    {
     my $dep = $self->{COLON};
     if (@_ == 1)
      {            
       # merging an existing rule
       my $other = shift;
       $dep->depend(scalar $other->depend);
       $dep->command(scalar $other->command);
      }
     else
      {
       $dep->depend(shift);
       $dep->command(shift);
      }
    }
   else
    {
     $self->{COLON} = (@_ == 1) ? shift->clone($self) : Make::Rule->new($self,':',@_);
    }
  }
 if (exists $self->{COLON})
  {
   return (wantarray) ? ($self->{COLON}) : $self->{COLON};
  }
 else
  {
   return (wantarray) ? () : undef;
  }
}

sub dcolon
{
 my $self = shift;
 if (@_)
  {
   my $rule = (@_ == 1) ? shift->clone($self) : Make::Rule->new($self,'::',@_);
   $self->{DCOLON} = [] unless (exists $self->{DCOLON});
   push(@{$self->{DCOLON}},$rule);
  }
 return (exists $self->{DCOLON}) ? @{$self->{DCOLON}} : ();
}

sub Name
{
 return shift->{NAME};
}

sub Info
{
 return shift->{MAKEFILE};
}

sub ProcessColon
{
 my ($self) = @_;
 my $c = $self->colon;
 $c->find_commands if $c;
}

sub ExpandTarget
{
 my ($self) = @_;
 my $target = $self->Name;
 my $info   = $self->Info;
 my $colon  = delete $self->{COLON};
 my $dcolon = delete $self->{DCOLON};
 foreach my $expand (split(/\s+/,$info->subsvars($target)))
  {
   next unless defined($expand);
   my $t = $info->Target($expand);
   if (defined $colon)
    {
     $t->colon($colon); 
    }
   foreach my $d (@{$dcolon})
    {
     $t->dcolon($d);
    }
  }
}

sub done
{
 my $self = shift;
 my $info = $self->Info;
 my $pass = $info->pass;
 return 1 if ($self->{Pass} == $pass);
 $self->{Pass} = $pass;
 return 0;
}

sub recurse
{
 my ($self,$method,@args) = @_;
 my $info = $self->Info;
 my $rule;
 my $i = 0;
 foreach $rule ($self->colon,$self->dcolon)
  {
   my $dep;
   my $j = 0;
   foreach $dep ($rule->exp_depend)
    {
     my $t = $info->{Depend}{$dep};
     if (defined $t)
      {
       $t->$method(@args) 
      }
     else
      {
       unless ($info->exists($dep))
        {
         my $dir = cwd();                                      
         die "Cannot recurse $method - no target $dep in $dir" 
        }
      }
    }
  }
}

sub Script
{
 my $self = shift;
 my $info = $self->Info;
 my $rule = $self->colon;
 return if ($self->done);
 $self->recurse('Script');
 foreach $rule ($self->colon,$self->dcolon)
  {
   $rule->Script;
  }
}

sub Make
{
 my $self = shift;
 my $info = $self->Info;
 my $rule = $self->colon;
 return if ($self->done);
 $self->recurse('Make');
 foreach $rule ($self->colon,$self->dcolon)
  {
   $rule->Make;
  }
}

sub Print
{
 my $self = shift;
 my $info = $self->Info;
 return if ($self->done);
 my $rule = $self->colon;
 foreach $rule ($self->colon,$self->dcolon)
  {
   $rule->Print;
  }
 $self->recurse('Print');
}

package Make;
use 5.005;  # Need look-behind assertions
use Carp;
use strict;
use Config;
use Cwd;
use File::Spec;
use vars qw($VERSION);
$VERSION = '1.00';

my %date;

sub phony
{
 my ($self,$name) = @_;
 return exists $self->{PHONY}{$name};
}

sub suffixes
{
 my ($self) = @_;
 return keys %{$self->{'SUFFIXES'}};
}

#
# Construct a new 'target' (or find old one)
# - used by parser to add to data structures
#
sub Target
{
 my ($self,$target) = @_;
 unless (exists $self->{Depend}{$target})
  {
   my $t = Make::Target->new($self,$target);
   $self->{Depend}{$target} = $t;
  if ($target =~ /%/)
   {
    $self->{Pattern}{$target} = $t;
   }
  elsif ($target =~ /^\./)
   {
    $self->{Dot}{$target} = $t;
   }
  else
   {
    push(@{$self->{Targets}},$t);
   }
  }
 return $self->{Depend}{$target};
}

#
# Utility routine for patching %.o type 'patterns'
#
sub patmatch
{
 my $key = shift;
 local $_ = shift;
 my $pat = $key;
 $pat =~ s/\./\\./;
 $pat =~ s/%/(\[^\/\]*)/;
 if (/$pat$/)
  {
   return $1;
  }
 return undef;
}

#
# old vpath lookup routine 
#
sub locate
{
 my $self = shift;
 local $_ = shift;
 return $_ if (-r $_);
 my $key;
 foreach $key (keys %{$self->{vpath}})
  {
   my $Pat;
   if (defined($Pat = patmatch($key,$_)))
    {
     my $dir;
     foreach $dir (split(/:/,$self->{vpath}{$key}))
      {
       return "$dir/$_"  if (-r "$dir/$_");
      }
    }
  }
 return undef;
}

#
# Convert traditional .c.o rules into GNU-like into %o : %c
#
sub dotrules
{
 my ($self) = @_;
 my $t;
 foreach $t (keys %{$self->{Dot}})
  {
   my $e = $self->subsvars($t);
   $self->{Dot}{$e} = delete $self->{Dot}{$t} unless ($t eq $e);
  }
 my (@suffix) = $self->suffixes;
 foreach $t (@suffix)
  {
   my $d;
   my $r = delete $self->{Dot}{$t};
   if (defined $r)
    {
     my @rule = ($r->colon) ? ($r->colon->depend) : ();
     if (@rule)
      {
       delete $self->{Dot}{$t->Name};
       print STDERR $t->Name," has dependants\n";
       push(@{$self->{Targets}},$r);
      }
     else
      {
       # print STDERR "Build \% : \%$t\n";                   
       $self->Target('%')->dcolon(['%'.$t],scalar $r->colon->command);
      }
    }
   foreach $d (@suffix)
    {
     $r = delete $self->{Dot}{$t.$d};
     if (defined $r)
      {
       # print STDERR "Build \%$d : \%$t\n";
       $self->Target('%'.$d)->dcolon(['%'.$t],scalar $r->colon->command);
      }
    }
  }
 foreach $t (keys %{$self->{Dot}})
  {
   push(@{$self->{Targets}},delete $self->{Dot}{$t});
  }
}

#
# Return 'full' pathname of name given directory info. 
# - may be the place to do vpath stuff ?
#               

my %pathname;

sub pathname
{
 my ($self,$name) = @_;
 my $hash = $self->{'Pathname'}; 
 unless (exists $hash->{$name})
  {
   if (File::Spec->file_name_is_absolute($name))
    {
     $hash->{$name} = $name;
    }
   else
    {
     $name =~ s,^\./,,;                             
     $hash->{$name} = File::Spec->catfile($self->{Dir},$name);
    }
  }
 return $hash->{$name};
 
}

#
# Return modified date of name if it exists
# 
sub date
{
 my ($self,$name) = @_;
 my $path = $self->pathname($name);
 unless (exists $date{$path})
  {
   $date{$path} = -M $path;
  }
 return $date{$path};
}

#
# Check to see if name is a target we can make or an existing
# file - used to see if pattern rules are valid
# - Needs extending to do vpath lookups
#
sub exists
{
 my ($self,$name) = @_;
 return 1 if (exists $self->{Depend}{$name});
 return 1 if defined $self->date($name);
 # print STDERR "$name '$path' does not exist\n";
 return 0;
}

#
# See if we can find a %.o : %.c rule for target
# .c.o rules are already converted to this form 
#
sub patrule
{
 my ($self,$target) = @_;
 my $key;
 # print STDERR "Trying pattern for $target\n";
 foreach $key (keys %{$self->{Pattern}})
  {
   my $Pat;
   if (defined($Pat = patmatch($key,$target)))
    {
     my $t = $self->{Pattern}{$key};
     my $rule;
     foreach $rule ($t->dcolon)
      {
       my @dep = $rule->exp_depend;
       if (@dep)
        {
         my $dep = $dep[0];
         $dep =~ s/%/$Pat/g;
         # print STDERR "Try $target : $dep\n";
         if ($self->exists($dep)) 
          {
           foreach (@dep)
            {
             s/%/$Pat/g;
            }
           return (\@dep,scalar $rule->command);
          }
        }
      }
    }
  }
 return ();
}

#
# Old code to handle vpath stuff - not used yet
#
sub needs
{my ($self,$target) = @_;
 unless ($self->{Done}{$target})
  {
   if (exists $self->{Depend}{$target})
    {
     my @depend = split(/\s+/,$self->subsvars($self->{Depend}{$target}));
     foreach (@depend)
      {
       $self->needs($_);
      }
    }
   else
    {
     my $vtarget = $self->locate($target);
     if (defined $vtarget)
      {
       $self->{Need}{$vtarget} = $target;
      }
     else
      {
       $self->{Need}{$target}  = $target;
      }
    }
  }
}

#
# Substitute $(xxxx) and $x style variable references
# - should handle ${xxx} as well
# - recurses till they all go rather than doing one level,
#   which may need fixing
#
sub subsvars
{
 my $self = shift;
 local $_ = shift;
 my @var = @_;
 push(@var,$self->{Override},$self->{Vars},\%ENV);
 croak("Trying to subsitute undef value") unless (defined $_); 
 while (/(?<!\$)\$\(([^()]+)\)/ || /(?<!\$)\$([<\@^?*])/)
  {
   my ($key,$head,$tail) = ($1,$`,$');
   my $value;
   if ($key =~ /^([\w._]+|\S)(?::(.*))?$/)
    {
     my ($var,$op) = ($1,$2);
     foreach my $hash (@var)
      {
       $value = $hash->{$var};
       if (defined $value)
        {
         last; 
        }
      }
     unless (defined $value)
      {
       die "$var not defined in '$_'" unless (length($var) > 1); 
       $value = '';
      }
     if (defined $op)
      {
       if ($op =~ /^s(.).*\1.*\1/)
        {
         local $_ = $self->subsvars($value);
         $op =~ s/\\/\\\\/g;
         eval $op.'g';
         $value = $_;
        }
       else
        {
         die "$var:$op = '$value'\n"; 
        }   
      }
    }
   elsif ($key =~ /wildcard\s*(.*)$/)
    {
     $value = join(' ',glob($self->pathname($1)));
    }
   elsif ($key =~ /shell\s*(.*)$/)
    {
     $value = join(' ',split('\n',`$1`));
    }
   elsif ($key =~ /addprefix\s*([^,]*),(.*)$/)
    {
     $value = join(' ',map($1 . $_,split('\s+',$2)));
    }
   elsif ($key =~ /notdir\s*(.*)$/)
    {
     my @files = split(/\s+/,$1);
     foreach (@files)
      {
       s#^.*/([^/]*)$#$1#;
      }
     $value = join(' ',@files);
    }
   elsif ($key =~ /dir\s*(.*)$/)
    {
     my @files = split(/\s+/,$1);
     foreach (@files)
      {
       s#^(.*)/[^/]*$#$1#;
      }
     $value = join(' ',@files);
    }
   elsif ($key =~ /^subst\s+([^,]*),([^,]*),(.*)$/)
    {
     my ($a,$b) = ($1,$2);
     $value = $3;
     $a =~ s/\./\\./;
     $value =~ s/$a/$b/; 
    }
   elsif ($key =~ /^mktmp,(\S+)\s*(.*)$/)
    {
     my ($file,$content) = ($1,$2);
     open(TMP,">$file") || die "Cannot open $file:$!";
     $content =~ s/\\n//g;
     print TMP $content;
     close(TMP);
     $value = $file;
    }
   else
    {
     warn "Cannot evaluate '$key' in '$_'\n";
    }
   $_ = "$head$value$tail";
  }
 s/\$\$/\$/g;
 return $_;
}

#
# Split a string into tokens - like split(/\s+/,...) but handling
# $(keyword ...) with embedded \s
# Perhaps should also understand "..." and '...' ?
#
sub tokenize
{
 local $_ = $_[0];
 my @result = ();
 s/\s+$//;
 while (length($_))
  {
   s/^\s+//;
   last unless (/^\S/);
   my $token = "";
   while (/^\S/)
    {
     if (s/^\$([\(\{])//)
      {
       $token .= $&; 
       my $paren = $1 eq '(';
       my $brace = $1 eq '{';
       my $count = 1;
       while (length($_) && ($paren || $brace))
        {
         s/^.//;
         $token .= $&; 
         $paren += ($& eq '(');
         $paren -= ($& eq ')');
         $brace += ($& eq '{');
         $brace -= ($& eq '}');
        }
       die "Mismatched {} in $_[0]" if ($brace);
       die "Mismatched () in $_[0]" if ($paren);
      }
     elsif (s/^(\$\S?|[^\s\$]+)//)
      {
       $token .= $&;
      }
    }
   push(@result,$token);
  }
 return (wantarray) ? @result : \@result;
}


#
# read makefile (or fragment of one) either as a result
# of a command line, or an 'include' in another makefile.
# 
sub makefile
{
 my ($self,$makefile,$name) = @_;
 local $_;
 print STDERR "Reading $name\n";
Makefile:
 while (<$makefile>)
  {
   last unless (defined $_);
   chomp($_);
   if (/\\$/)
    {
     chop($_);
     s/\s*$//;
     my $more = <$makefile>;
     $more =~ s/^\s*/ /; 
     $_ .= $more;
     redo;
    }
   next if (/^\s*#/);
   next if (/^\s*$/);
   s/#.*$//;
   s/^\s+//;
   if (/^(-?)include\s+(.*)$/)
    {
     my $opt = $1;
     my $file;
     foreach $file (tokenize($self->subsvars($2)))
      {
       local *Makefile;
       my $path = $self->pathname($file);
       if (open(Makefile,"<$path"))
        {
         $self->makefile(\*Makefile,$path);
         close(Makefile);
        }
       else
        {
         warn "Cannot open $path:$!" unless ($opt eq '-') ;
        }
      }
    }
   elsif (/^\s*([\w._]+)\s*:?=\s*(.*)$/)
    {
     $self->{Vars}{$1} = (defined $2) ? $2 : "";
#    print STDERR "$1 = ",$self->{Vars}{$1},"\n";
    }
   elsif (/^vpath\s+(\S+)\s+(.*)$/)
    {my ($pat,$path) = ($1,$2);
     $self->{Vpath}{$pat} = $path;
    }
   elsif (/^\s*([^:]*)(::?)\s*(.*)$/)
    {
     my ($target,$kind,$depend) = ($1,$2,$3);
     my @cmnds;
     if ($depend =~ /^([^;]*);(.*)$/)
      {
       ($depend,$cmnds[0])  = ($1,$2);
      }
     while (<$makefile>)
      {
       next if (/^\s*#/);
       next if (/^\s*$/);
       last unless (/^\t/);
       chop($_);         
       if (/\\$/)        
        {                
         chop($_);
         $_ .= ' ';
         $_ .= <$makefile>;
         redo;           
        }                
       next if (/^\s*$/);
       s/^\s+//;
       push(@cmnds,$_);
      }
     $depend =~ s/\s\s+/ /;
     $target =~ s/\s\s+/ /;
     my @depend = tokenize($depend);
     foreach (tokenize($target))
      {
       my $t = $self->Target($_);
       my $index = 0;
       if ($kind eq '::' || /%/)
        {
         $t->dcolon(\@depend,\@cmnds);
        }
       else
        {
         $t->colon(\@depend,\@cmnds);
        }
      }
     redo Makefile;
    }
   else
    {
     warn "Ignore '$_'\n";
    }
  }
}

sub pseudos
{
 my $self = shift;
 my $key;
 foreach $key (qw(SUFFIXES PHONY PRECIOUS PARALLEL))
  {
   my $t = delete $self->{Dot}{'.'.$key};
   if (defined $t)
    {
     my $dep;
     $self->{$key} = {};
     foreach $dep ($t->colon->exp_depend)
      {
       $self->{$key}{$dep} = 1;
      }
    }
  }
}


sub ExpandTarget
{
 my $self = shift;
 foreach my $t (@{$self->{'Targets'}})
  {
   $t->ExpandTarget;
  }
 foreach my $t (@{$self->{'Targets'}})
  {
   $t->ProcessColon;
  }
}

sub parse
{
 my ($self,$file) = @_;
 if (defined $file)
  {
   $file = $self->pathname($file);
  }
 else
  {
   my @files = qw(makefile Makefile);
   unshift(@files,'GNUmakefile') if ($self->{GNU});
   my $name;
   foreach $name (@files)
    {
     $file = $self->pathname($name);
     if (-r $file)
      {
       $self->{Makefile} = $name;
       last; 
      }
    }
  }
 local (*Makefile);
 open(Makefile,"<$file") || croak("Cannot open $file:$!");
 $self->makefile(\*Makefile,$file);
 close(Makefile);

 # Next bits should really be done 'lazy' on need.

 $self->pseudos;         # Pull out .SUFFIXES etc. 
 $self->dotrules;        # Convert .c.o into %.o : %.c
}

sub PrintVars
{
 my $self = shift;
 local $_;
 foreach (keys %{$self->{Vars}})
  {
   print "$_ = ",$self->{Vars}{$_},"\n";
  }
 print "\n";
}

sub exec
{
 my $self = shift;
 undef %date;
 $generation++;
 if ($^O eq 'MSWin32')
  {
   my $cwd = cwd();
   my $ret;
   chdir $self->{Dir};
   $ret = system(@_);
   chdir $cwd;
   return $ret;
  }
 else
  {
   my $pid  = fork;
   if ($pid)
    {
     waitpid $pid,0;
     return $?;
    }
   else
    {
     my $dir = $self->{Dir}; 
     chdir($dir) || die "Cannot cd to $dir";
     # handle leading VAR=value here ?
     # To handle trivial cases like ': libpTk.a' force using /bin/sh
     exec("/bin/sh","-c",@_) || confess "Cannot exec ".join(' ',@_);
    }
  }
}

sub NextPass { shift->{Pass}++ }
sub pass     { shift->{Pass} }

sub apply
{
 my $self = shift;
 my $method = shift;
 $self->NextPass;
 my @targets = ();
 # print STDERR join(' ',Apply => $method,@_),"\n";
 foreach (@_)
  {
   if (/^(\w+)=(.*)$/)
    {
     # print STDERR "OVERRIDE: $1 = $2\n";
     $self->{Override}{$1} = $2;
    }
   else
    {
     push(@targets,$_);
    }
  }
 #
 # This expansion is dubious as it alters the database
 # as a function of current values of Override.
 # 
 $self->ExpandTarget;    # Process $(VAR) : 
 @targets = ($self->{'Targets'}[0])->Name unless (@targets);
 # print STDERR join(' ',Targets => $method,map($_->Name,@targets)),"\n";
 foreach (@targets)
  {
   my $t = $self->{Depend}{$_};
   unless (defined $t)
    {
     print STDERR join(' ',$method,@_),"\n";
     die "Cannot `$method' - no target $_" 
    }
   $t->$method();
  }
}

sub Script
{
 shift->apply(Script => @_);
}

sub Print
{
 shift->apply(Print => @_);
}

sub Make
{
 shift->apply(Make => @_);
}

sub new
{
 my ($class,%args) = @_;
 unless (defined $args{Dir})
  {
   chomp($args{Dir} = getcwd());
  }
 my $self = bless { %args, 
                   Pattern  => {},  # GNU style %.o : %.c 
                   Dot      => {},  # Trad style .c.o
                   Vpath    => {},  # vpath %.c info 
                   Vars     => {},  # Variables defined in makefile
                   Depend   => {},  # hash of targets
                   Targets  => [],  # ordered version so we can find 1st one
                   Pass     => 0,   # incremented each sweep
                   Pathname => {},  # cache of expanded names
                   Need     => {},
                   Done     => {},
                 },$class;
 $self->{Vars}{CC}     = $Config{cc};
 $self->{Vars}{AR}     = $Config{ar};
 $self->{Vars}{CFLAGS} = $Config{optimize};
 $self->makefile(\*DATA,__FILE__);
 $self->parse($self->{Makefile});
 return $self;
}

=head1 NAME

Make - module for processing makefiles 

=head1 SYNOPSIS

	require Make;
	my $make = Make->new(...);
	$make->parse($file);   
	$make->Script(@ARGV)
	$make->Make(@ARGV)
	$make->Print(@ARGV)

        my $targ = $make->Target($name);
        $targ->colon([dependancy...],[command...]);
        $targ->dolon([dependancy...],[command...]);
        my @depends  = $targ->colon->depend;
        my @commands = $targ->colon->command;

=head1 DESCRIPTION

Make->new creates an object if C<new(Makefile =E<gt> $file)> is specified
then it is parsed. If not the usual makefile Makefile sequence is 
used. (If GNU => 1 is passed to new then GNUmakefile is looked for first.) 

C<$make-E<gt>Make(target...)> 'makes' the target(s) specified
(or the first 'real' target in the makefile).

C<$make-E<gt>Print> can be used to 'print' to current C<select>'ed stream
a form of the makefile with all variables expanded. 

C<$make-E<gt>Script(target...)> can be used to 'print' to 
current C<select>'ed stream the equivalent bourne shell script
that a make would perform i.e. the output of C<make -n>.

There are other methods (used by parse) which can be used to add and 
manipulate targets and their dependants. There is a hierarchy of classes
which is still evolving. These classes and their methods will be documented when
they are a little more stable.

The syntax of makefile accepted is reasonably generic, but I have not re-read
any documentation yet, rather I have implemented my own mental model of how
make works (then fixed it...).

In addition to traditional 

	.c.o : 
		$(CC) -c ...

GNU make's 'pattern' rules e.g. 

	%.o : %.c 
		$(CC) -c ...

Likewise a subset of GNU makes $(function arg...) syntax is supported.

Via pmake Make has built perl/Tk from the C<MakeMaker> generated Makefiles...

=head1 BUGS

At present C<new> must always find a makefile, and
C<$make-E<gt>parse($file)> can only be used to augment that file.

More attention needs to be given to using the package to I<write> makefiles.

The rules for matching 'dot rules' e.g. .c.o   and/or pattern rules e.g. %.o : %.c
are suspect. For example give a choice of .xs.o vs .xs.c + .c.o behaviour
seems a little odd.

Variables are probably substituted in different 'phases' of the process
than in make(1) (or even GNU make), so 'clever' uses will probably not
work.

UNIXisms abound. 

=head1 SEE ALSO 

L<pmake>

=head1 AUTHOR

Nick Ing-Simmons

=cut 

1;
#
# Remainder of file is in makefile syntax and constitutes
# the built in rules
#
__DATA__

.SUFFIXES: .o .c .y .h .sh .cps

.c.o :
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $< 

.c   :
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

.y.o:
	$(YACC) $<
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ y.tab.c
	$(RM) y.tab.c

.y.c:
	$(YACC) $<
	mv y.tab.c $@


