#!/usr/bin/perl -w
use strict;
use lib '../include';
use Glist;
use Glist::Bounce;
use Glist::Admin;

my $gl = Glist::new(prefix=>'/opt/glist', sendmail=>'/usr/lib/sendmail -t');
my $b = $gl->Glist::Bounce::new(sendmail=>'/usr/lib/sendmail -t');
my $a = $gl->Glist::Admin::new(sendmail=>'/usr/lib/sendmail -t');

my $file = $ARGV[0];
die unless $file;



if(ref(my $mail_obj = $gl->parsemail($file))) {
	my ($rh_header, $rl_body) = @$mail_obj;

	foreach my $key(sort keys %$rh_header) {
		print("$key: $rh_header->{$key}\n");
	};
}
else {
	print STDERR ("Couldn't parse mailfile $file: $!\n");
	exit(1);
};

sub parsemail {
	# ### Take file as argument.
	my($file) = @_;
	my(	@header, 	# array with headers.
		@body, 		# array with body lines
		$in_body, 	# we're finished with header section and
				# in the body.
		$ch,		# $current header data.
		$ic,		# in a header comment (1++/0)
		%h,		# final header hash.
		$w,		# instead of setting $^W if $^W not set;
		$t,		# to set $w to an undefined variable.
	);
	# turn off warnings if warnings are on.
	$^W && $w++,$^W++;

	open(MAIL, $file) || return -1;
	for(my $linecount = 0; <MAIL>; $linecount++) {
		chomp;
		# ### header section is over. mmm, body,
		if($in_body) {
			push(@body, $_);
		}
		else {
			# ### header section is over if hit an empty line.
			$in_body = 1, next unless length;
			my $ch; # current header

			# ### 
			# get rid of the header comments,
			# the Subject header can have "(" + ")", though.
			if(lc !~ /^subject:/) {
				for(my $pos = 0; $pos < length($_); $pos++) {
					my $chr = substr($_, $pos, 1);	
					$ic++ if $chr eq '(';
					$ch .= $chr unless $ic;
					$ic-- if $chr eq ')';
				};
			}
			else {
				$ch = $_;
			};
			
			# ###
			# if this is a wrapped line (starts with whitespace)
			# concatenate it to the last element in the list.
			$header[$linecount - 1] .= $ch, next
				if($ch =~ s/^\s+/ / && $header[$linecount - 1]);
			push(@header, $ch);
		};
	};
	close(MAIL);

	# ###
	# assemble the header. split them all by : into a fresh hash.
	foreach(@header) {
		my($key, $value) = split(/:\s*/, $_, 2);
		next unless $value;
		print("key: $key value: $value\n");
		$h{$key} = $value;
	};

	# Turn warnings on again.
	$w && $^W++; 

	# ###
	# we return a reference to a list with references to
	# header hash and body array.
	return [ \%h, \@body ];
};
