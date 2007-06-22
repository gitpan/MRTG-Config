package MRTG::Config;

use 5.008008;
use strict;
use warnings;

#---------------------------------------------------------#
# Exporter stuff - I don't think I need this tho.

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use MRTG::Config ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);
#---------------------------------------------------------#
# Version

our $VERSION = '0.01';

#---------------------------------------------------------#
# Dependencies

use File::Spec;
use File::Basename;

#---------------------------------------------------------#
# Declarations for methods with checked-args
# (sometimes I like those)

sub loadparse($);


#---------------------------------------------------------#
# Constructor et. al.

# If you specify a filename as an argument, you don't have 
# to call loadparse separately.
sub new 
{
	my $class = shift;
	my $self  = {};
	
	$self->{DEBUG}       = 0;   # Debugging output level.
	
	# These hold the parsed data.
	$self->{GLOBALCFG}   = {};  # MRTG global config options
	$self->{TGTDEFAULTS} = {};  # Config options for the _ target are 
                                #  treated as if they were defined for all
                                #  targets unless explicitly overridden.
	$self->{TARGETS}     = {};  # Per-target config options.
	$self->{CONFIGLINES} = [];  # A list of arrays with info about each 
	                            # 'useful' line in the config file(s)
	
	# These are used if we turn on persistience:
	$self->{PERSIST_DB}   = undef; # Handle to the DBM DB.
	$self->{PERSIST_FILE} = "";    # File to store the DBM DB.
								
	bless ($self, $class);
	
	# If an argument is specified, try to load and parse it as an MRTG config file.
	if (@_) { $self->loadparse(shift) };
	
	return $self;
}


#---------------------------------------------------------#
# Public methods


#Loads and parses the given MRTG config file.
sub loadparse($)
{
    my $self = shift;
    return $self->_parse_cfg_file(shift);
}


sub rawdata
{
	my $self = shift;
	return (
		$self->{GLOBALCFG}, 
		$self->{TGTDEFAULTS}, 
		$self->{TARGETS},
		$self->{CONFIGLINES},
		);
}


# Toggles persistience - 
# Using a true value turns persistience on 
#   - return value is boolean for success.
# Using a false value turns it off
#   - return value is boolean for success.
# Using no argument returns boolean for status.
sub persist
{
	my $self = shift;
	return $self->{PERSIST_DB} ? 1 : 0 unless @_;
	if (shift) 
	{
		return $self->_persist_on();
	}
	else
	{
		return $self->_persist_off();
	}
	die 'WTF? This should *never* happen!';
}


# Returns a reference to the specified target's config hash,
# undef if it does not exist. I may change it to {} though,
# depending on how a loop might best be written.
sub target 
{
	my $self = shift;
	my $tgtId = shift;
	return exists $self->{TARGETS}{$tgtId} ? \$self->{TARGETS}{$tgtId} : undef ;
}

# Returns a list of ALL available target names. (NOT their hashes)
sub targets 
{
	my $self = shift;
	return (keys %{$self->{TARGETS}});
}


# Returns a reference to a hash of the global MRTG directives.
sub globals 
{
	my $self = shift;
	return $self->{GLOBALCFG};
}

# Sets or gets the file to be used for the persistience DBM DB.
# If setting, returns the previous value. If there was no 
# previous value, returns "".
sub persist_file
{
	my $self = shift;
	my $file = $self->{PERSIST_FILE};
	$self->{PERSIST_FILE} = shift if @_;;
	return $file; 
}

#---------------------------------------------------------#

# Initialize the DBM DB and store the MRTG data in it.
# Make the Class member hashes point to the apropriate
# locations in the DB. Return true on success, undef on failure.
# I thought about calling die on failure, but I've repented
# and decided to simply return undef. Failure can be handled
# somewhere higher up in the code, since it's not fatal to
# the usage of this module!
sub _persist_on
{
	my $self = shift;
	use DBM::Deep;
	$self->{PERSIST_DB} = 
		new DBM::Deep($self->{PERSIST_FILE})
		|| return undef;
		
	my $persist_db = $self->{PERSIST_DB};
	
	# We really shouldn't persist $self->{CONFIGLINES} -- 
	# especially before loading the MRTG config. I do some
	# nasty stuff to that array and DBM::Deep doesn't like
	# very much at all.; :)
	
	# Also, there's really no need to persist $self->{TGTDEFAULTS}, AFAIC.
	
	# Bless our humble hashes - exists line just added... needs to be tested.
	$persist_db->{GLOBALCFG} = {} unless exists $persist_db->{GLOBALCFG};
	#$persist_db->{TGTDEFAULTS} = {} unless exists $persist_db->{TGTDEFAULTS};
	$persist_db->{TARGETS} = {} unless exists $persist_db->{TARGETS};
	#$persist_db->{CONFIGLINES} = [] unless exists $persist_db->{CONFIGLINES};
	
	# Import the data... DBM::Deep will call die() if something goes wrong.
	$persist_db->{GLOBALCFG}   = $self->{GLOBALCFG}   if $self->{GLOBALCFG};
	#$persist_db->{TGTDEFAULTS} = $self->{TGTDEFAULTS} if $self->{TGTDEFAULTS};
	$persist_db->{TARGETS}     = $self->{TARGETS}     if $self->{TARGETS};
	#$persist_db->{CONFIGLINES}-> import(@{$self->{CONFIGLINES}}); 
	
	# Now, swap our pointers!
	$self->{GLOBALCFG}   = $persist_db->{GLOBALCFG};
	#$self->{TGTDEFAULTS} = $persist_db->{TGTDEFAULTS};
	$self->{TARGETS}     = $persist_db->{TARGETS};
	#$self->{CONFIGLINES} = $persist_db->{CONFIGLINES};
	
	return 1;
}


sub _persist_off
{
	die "Feature not implemented (Yet!)\n";
}



# Parses the directives from the MRTG config file, 
# loading and parsing any Included files along the way.
# Populates the Class hash vars GLOBALCFG, 
# TGTDEFAULTS, and TARGETS. Returns 1. Dies if 
# anything goes wrong.
sub _parse_cfg_file
{
    my $self = shift;
    my $cfgFileName = shift;

    # Grab the directives from the config file
    my $directiveLines = $self->_read_cfg_file($cfgFileName);
    push @{$self->{CONFIGLINES}}, @$directiveLines;
	$directiveLines = $self->{CONFIGLINES};
    
    # These are the hashes we're building:
    my $Global = $self->{GLOBALCFG};        
    my $TgtDefaults = $self->{TGTDEFAULTS}; 
    my $Targets = $self->{TARGETS};         

    
    # Using a for-loop to force the condition check on each 
    # iteration -- If we encounter an Include directive additional 
    # lines could be inserted into @$directiveLines, changing it's
    # size! 
    for (my $idx = 0; $idx <= $#$directiveLines; $idx++)
    {
        my $line = $directiveLines->[$idx];
        my $lineText = $line->[0];
        my $lineNum  = $line->[1];
        my $lineFile = $line->[2];
    
		
        # Parse the basic directive and value from the line
        $lineText =~ /\s*(.*?)\s*:\s*(.*)\s*/s;
        my $directive = $1;
        my $value = $2;
    
    
        # If the regex didn't match both, something's wrong.
        unless (defined $directive and defined $value)
        {
            warn "Error parsing line $lineNum:\n";
            warn "$lineText\n";
            die "LOLDEAD\n";
        }
        
        
        # If the directive is an Include directive, we've got 
        # some _special_ work to do...
        if ($directive =~ /^Include$/) 
        {
            my $incFileName = $value;
            print "Include directive found: $incFileName\n" if $self->{DEBUG} > 1;
            unless (File::Spec->file_name_is_absolute($incFileName))
            {
                my (undef,$cfgFileBaseDir,undef) = fileparse($cfgFileName);
                my $baseDirPath = File::Spec->catfile($cfgFileBaseDir, $incFileName);
                my $curDirPath = File::Spec->catfile(File::Spec->curdir(), $incFileName);
                print "Possible include locations:\n" if $self->{DEBUG} > 2;
                print "  $baseDirPath\n" if $self->{DEBUG} > 2;
                print "  $curDirPath\n" if $self->{DEBUG} > 2;
                print "  $incFileName\n" if $self->{DEBUG} > 2;
                if (-e $baseDirPath) { $incFileName = $baseDirPath }
                elsif (-e $curDirPath) { $incFileName = $curDirPath } 
            }
            my $includeLines = $self->_read_cfg_file($incFileName);
            splice @$directiveLines, $idx+1,0, @$includeLines;
            next;
        }
        
        
        
        # Determine the type of directive: Global, Target, or TgtDefaults
        # Then store it and it's value in the proper place.
        if ($directive =~ /\[_\]$/)  # TgtDefaults directive
        {
            $directive =~ s/\[_\]//;
            $TgtDefaults->{$directive} = $value;
        }    
        elsif ($directive =~ /\[.*\]$/) # Target directive
        {
            # Target-specific directives contain the directive name ($dname)
            # and the target name ($tname). The code for parsing this is a 
            # little longer than I like to put in an if-block.
            my ($dname, $tname) = $self->_parse_directive_name($directive);
            
            # Just to get them out of the way, and hopefully better simulate
    	    # The 'Official' MRTG code, let's apply any known TgtDefaults
			# directives to the current Target
    	    while (my ($tdDname, $tdValue) = each %$TgtDefaults)
    	    {
    	        # Don't clobber directives that were already set.
    	        $Targets->{$tname}{$tdDname} = $tdValue unless 
    	           exists $Targets->{$tname}{$tdDname};
    	    }
            
            # If we want to have any special handling of the data in $value
    	    # based on the Directive name or any other accessible criterion,
			# here's where it would be done. (by calling another subroutine,
			# of course. Keep the code clean... as much as possible...)
			$value = $self->_process_td_value($value, $dname, $tname, $line);
    	    
    	    $Targets->{$tname}{$dname} = $value;
        }
        elsif ($directive !~ /\[/) # Global directive
        {
            $Global->{$directive} = $value;
        }
        elsif ($directive =~ /\[\^\$\]$/) # pre and post - see MRTG docs.
        {
            # I don't know what to do with these so I'll just do nothing.
        }
        else  # Something else? That's not right.
        {
            warn "Invalid directive name at line $lineNum: $directive\n";
            die "LOLDEAD\n";
        }
    }
    return 1;
}


#---------------------------------------------------------#

# If we need to sanity-check or otherwise validate or process
# directives, and it can be done on the first pass through the
# config files, this is where it's done.
sub _process_td_value
{   
	my $self = shift;
	my ($value, $dname, $tname, $line) = @_;
	#use Data::Dumper;
	#print Dumper($value, $dname, $tname, $line); exit;
	return $value;
}



# Opens the specified file and returns a reference to an
# array of MRTG config directives from it's contents.
# The returned data structure will be a two-level array...
# Each sub-array is two elements, the first being the line 
# number of the beginning of the directive in the file, 
# and the second being the directive and data as a string.
sub _read_cfg_file 
{
    my $self = shift;

    # Open the specified file.
    my $cfgFileName = shift ||
        die "You need to specify the path to an MRTG cfg file.\n"; 
    
    
    
    my $cfgFh;
    open $cfgFh, "<$cfgFileName" ||
        die "Couldn't open $cfgFileName for read access.\n";
    # TODO This doesn't die on win32... is it broke on Linux, too? ...yep.
        
        
    my $lineCount = 0;           # How many lines in the file
    my $directiveLineCount = 0;  # How many lines used by directives
    my @directiveLines = ();     # Each element in this array is a 
                                 #  directive, which may span more 
                                 #  than one line (separated by \n)
	
	
    # Read in the file, parsing out all the MRTG directives
    # irregardles of validity... we're assuming that they're 
    # valid since these are the same config files MRTG is 
    # already using for polling. 
    while (<$cfgFh>)
    {
    	$lineCount++;
    
    	# Ignore blank and comment lines.
    	next if /^\s*$/;
    	next if /^\s*#/;
    	
    	my $line = $_;
    	
    	# If this line begins with whitespace append it to the previous line.
    	# I'm not sure how perl will handle it if there are no previous lines!
    	if ($line =~ /^\s+/)
    	{
    	   $directiveLines[-1][0] .= $line;
    	} 
    	else
    	{
    	    push @directiveLines, [$line,$lineCount,$cfgFileName];
			
    	}
    	$directiveLineCount++;
    }
    
    close $cfgFh;
    
    # Clean up those messy trailing new-lines.
    chomp $_->[0] for @directiveLines;
    
    print "Loaded file: $cfgFileName\n" if $self->{DEBUG} > 1;
    print "  Total lines: $lineCount\n" if $self->{DEBUG} > 1;
    print "  Directives found: $#directiveLines\n" if $self->{DEBUG} > 1;
    print "  Directive lines: $directiveLineCount\n" if $self->{DEBUG} > 1;
    print "  Ignored lines: " . ($lineCount - $directiveLineCount) . "\n" if $self->{DEBUG} > 1;
    
    return \@directiveLines;
}


#---------------------------------------------------------#



# Parse the directive name and the target name out of a 
# 'raw' Target-specific directive string. Returns the 
# directive and target names as a two-element list.
sub _parse_directive_name 
{
    my $self = shift; 
    my $directive = shift;
    
    # Parse the Target and Directive names from $directive
    $directive =~ /(.*)\[(.*)\]/;
    my $dname = $1;
    my $tname = $2;
    
    # If the regex didn't match both, something's wrong.
    unless ($dname and $tname)
    {
        warn "Error parsing Target and Directive names from:\n";
        warn "$directive\n";
        die "LOLDEAD\n";
    }
    
    return ($dname, $tname);
}

#---------------------------------------------------------#



1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

MRTG::Config - Perl module for parsing MRTG configuration files

=head1 SYNOPSIS

I plan on adding to this documentation and making it better 
organized soon, but I'm willing to answer questions directly 
in the mean time.

  use MRTG::Config;

  my $cfgFile = 'mrtg.cfg';
  my $persist_file = 'mrtg.cfg.db'; 
  
  my $mrtgCfg = new MRTG::Config;
  
  $mrtgCfg->loadparse($cfgFile);
  $mrtgCfg->persist_file($persist_file);
  $mrtgCfg->persist(1);
  
  foreach my $tgtName (@{$mrtgCfg->targets()}) {
    my $tgtCfg = $mrtgCfg->target($tgtName);
	print $tgtCfg->{Title} . "\n"; # Let's assume every target has a Title.
  }
  
  my $globalCfg = $mrtgCfg->globals();
  print $globalCfg->{WorkDir} . "\n"; # Let's assume WorkDir is set.

=head1 DESCRIPTION -or- LOTS OF WORDS ABOUT A LITTLE MODULE

I couldn't find any modules on CPAN that would parse MRTG config files,
and Tobi's code in MRTG_lib is too slow and too complicated for my needs.

This module will load a given MRTG configuration file, following Include
statements, and build a set of hashes representing the confiration 
keywords, targets, and values.

It's _much_ faster than Tobi's code, but it also does not build a data
structure _nearly_ as deep and complex.

It *does*, however, properly handle a number of facilities of the MRTG 
configuration file format that are specified in the MRTG documentation.

The parsing code correctly handles directives where the value spans 
multiple lines (sucessive lines after the first begin with whitespace).
Each line of the value is contatenated together, including newlines.

Include directives are also handled. When an Include is encountered, the
value is used as the name of another MRTG configuration file to parse.
Like in MRTG_lib, if the path is not absolute (beginning with / or C:\
or whatever your system uses) this file is looked for first in the same
directory as the original configuration file, and then in the current
working directory.

When an Included file is loaded, it's lines are inserted into the current 
position in the parsing buffer and then parsing continues, as if the 
contents of the included file were simply copied into that position in 
the original file.

While I have not yet tested it, I believe 'nested' includes are followed,
and the same search and loading rules apply. The path of the _first_
config file is _always_ used when looking for included files.

WARNING: There is *no* loop-checking code. If File A includes File B and
File B includes File A, the parser will run until your system goes p00f,
eating up memory the whole way.

This module understands directives for the [_] (default) target and will
interpolate these directives into all the targets that follow the 
definition of a [_] directive and do not explicitly define the given 
directive.

From what I can tell, in Tobi's implementation, [_] directives are only 
applied to targets that follow the definition of that particular directive.
This module does likewise. Also, if a [_] directive is redefined later in
the configuration, it's new value is used for all future targets. Targets
that have already had that directive interpolated are *not* updated.

Also, if a particular target has a directive or directives defined more 
than once, the last definition in the file 'wins'. The same applies to 
the [_] target, and also to global directives.

This module is capable of some degree of persistience, by way of DBM::Deep.
Using persistience will allow you to do all sorts of interesting things, 
which I will not get into right now, but if you're creative I'll bet you've
already thought of some! Right now, only Global and target-specific 
directives are persisted.

Please note - I've found that performance with DBM::Deep varies WIDELY 
depending on what version of DBM::Deep you are using, and wether or 
not you allow cpan to upgrade it's dependencies - When I allowed cpan
to update everything, performance dropped by AN ORDER OF MAGNITUDE.

For best performance, I suggest using DBM::Deep .94 and whatever 
versions of various core modules that come with Perl 5.8.8.

Most of my testing has been done on a stock Ubuntu 7.04. Some 
testing has been done on Windows XP SP2 with ActiveState Perl 5.8.8

=head2 SUPPORT

Please email me if you have *any* questions, complaints, comments, 
compliments, suggestions, requests, patches, or alcoholic beverages 
you'd like to share. The more feedback I can get, the better I can
make this module!

=head2 EXPORT

None by default.

=head1 SEE ALSO

http://oss.oetiker.ch/mrtg/ or http://www.mrtg.org/

=head1 AUTHOR

Stephen R. Scaffidi

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Stephen R. Scaffidi

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut