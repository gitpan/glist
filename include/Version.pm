#!/usr/bin/perl -w
# ###
# Version.pm - kernel/gnome like version library
# (c) 2001 - Ask Solem Hoel <ask@unixmonks.net>
# All rights reserved.
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License version 2
#   as published by the Free Software Foundation.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#####

package Version;
use Carp;
use Exporter;

@ISA = qw(@EXPORT @EXPORT_OK);

@EXPORT = qw(cmp_version);
@EXPORT_OK = qw();
%EXPORT_TAGS = ( all => qw(cmp_version) );



# ### Version new(char version)
# create new Version object with thre dotted version
# as argument.
#
sub new {
	my ($pkg, $version) = @_;
	my $self = {};
	bless $self, $pkg;
	$self->version($version);
	return $self;
};

# ### char version(char version)
# set version or get version currently set
#
sub version {
	my ($self, $version) = @_;
	# set version if we got version as argument.
	if($version) {
		($self->{MAJOR}, $self->{MINOR}, $self->{RELEA})
			= split('\.', $version);   
		$self->{VERSION} = $version;
	};
	return $self->{VERSION};
};

# ### accessors
sub major { $_[0]->{MAJOR} };
sub minor { $_[0]->{MINOR} };
sub relea { $_[0]->{RELEA} };

# ### char extended(void)
# get extended version information
#
sub extended {
	my $self = shift;
	my $su;
	# ### stable if even, unstable if odd.
	if($self->minor() % 2) {
		$su = "unstable";
	}
	else {
		$su = "stable";
	};
	return sprintf("%s (%s)", $self->version, $su);
};

# ### int check(char check_against, char operator)
# check current version against check_against with operator.
# example:
#	# ### check if version "1.1.0" is higher or equal to current version.
#	unless($version->check("1.1.0", ">=") {
#		die("Must have version higher than or equal to 1.1.0\n");
#	};
#
sub check {
	my($self, $check_against, $operator) = @_;
	# ###
	# operator can only be of the following characters:
	# >, <, =, !
	carp "Illegal characters in operator or missing operator."
		unless $operator =~ /^[\>\<\=\!]+$/;
	# ### 
	# remove the dots from the versions
	# i.e 2.4.0 and 2.2.0 becomes 240 and 220,
	# then we just check the two against the operator.
	$check_against =~ s/\.//g;
	my $version = $self->version();
	$version =~ tr/.//d;
	if(eval "return 1 if($check_against $operator $version)") {
		return 1;
	}
	else {
		return 0;
	};
};

# ### int check(char version1|Version version, version2);
# compare two versions. if first argument is reference to Version
# object it swaps version 1 with Version->version().
# returns equal, less than og higher than.
#
sub cmp_version {
	my($x, $y) = @_;
	my $version;
	if(ref $x) {
		# swap
		$self = $x;	
		$x = $self->version();
	}
	$x =~ tr/.//d; $y =~ tr/.//d;	
	return ($x - $y);
}

#%ifdef GENPP
1;
#%endif
