#!/usr/bin/perl -w

use strict;

die("Missing changelog") unless @ARGV;

my $changelog = shift @ARGV;

my $in_day = 0;

my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %entries;

my $ennum = 0;
my $elnum = 0;

my $in_el = 0;

open(CL, $changelog) || die("Couldn't open $changelog: $!\n");
while(<CL>) {
	chomp;
	if(/^\s*--\s+(\d\d\d\d)-(\d\d)-(\d\d)\s+(.+?)\s+(.+?)\s+(.+?)\s*$/) {
		$entries{$ennum}->{year} = $1;
		$entries{$ennum}->{month} = $2;
		$entries{$ennum}->{strmonth} = $months[$2 - 1];
		$entries{$ennum}->{day} = $3;
		$entries{$ennum}->{version} = $4;
		$entries{$ennum}->{author} = $5;
		$entries{$ennum}->{mail} = $6;
		$ennum++ if $elnum;
	}
	elsif(/^\s*\*\s*(.+?)\s*$/) {
		if($entries{$ennum}->{year}) {
			my $t = $1;
			$t =~ s%([\w\d\/\_\-\.]+\.(pm|pl))%<font color="blue">$1</font>%g;
			$t =~ s%([\w\d\/\_\-\.]+\(\))%<font color="red">$1</font>%g;
			$t =~ s%([\w\d\/\_\-\.]+::[\w\d\/\_\-\.]+)%<font color="red">$1</font>%g;
			$t =~ s%((\$|\@|\%)[\w\d\_]+)%<font color="green">$1</font>%g;
			$t =~ s%\s+((;|:|=)\))%<font color="orange"><b>$1</b></font>%g;
			$t =~ s%(\*.+?\*)%<b>$1</b>%g;
			$in_el = 1;
			$entries{$ennum}->{content}->{$elnum} = $t;
		};
	}
	elsif($in_el) {
		s/^\s*//;
		s/\s*$//;
		unless(length) {
			$elnum++;
			next;
		};
		s/^\*\s*//;
		s%([\w\d\/\_\-\.]+\.(pm|pl))%<font color="blue">$1</font>%g;
		s%([\w\d\/\_\-\.]+\(\))%<font color="red">$1</font>%g;
		s%([\w\d\/\_\-\.]+::[\w\d\/\_\-\.]+)%<font color="red">$1</font>%g;
		s%((\$|\@|\%)[\w\d\_]+)%<font color="green">$1</font>%g;
		s%\s+((;|:|=)\))%<font color="orange"><b>$1</b></font>%g;
		s%(\*.+?\*)%<b>$1</b>%g;
		$entries{$ennum}->{content}->{$elnum} .= $_;
		$elnum++;
	}
};
close(CL);

exit;
print <<EOF
<html>
	<head><title>glist changelog</title></head>
	<body>
	<h1>Glist changelog</h1>
	<hr>

EOF
;
foreach my $entry (sort { $a <=> $b } keys %entries) {
	next unless $entries{$entry}->{day};
	print <<"	EOF"
	<table border=0 width=600>
	<tr>
		<th bgcolor="#aaaaaa">Date</th>
		<th bgcolor="#aaaaaa">Version</th>
		<th bgcolor="#aaaaaa">Author</th>
		<th bgcolor="#aaaaaa">Authors e-mail</th>
	</tr>
	<tr>
		<td align="center">$entries{$entry}->{day} $entries{$entry}->{strmonth} $entries{$entry}->{year}</td>
		<td align="center">$entries{$entry}->{version}</td>
		<td align="center">$entries{$entry}->{author}</td>
		<td align="center"><a href="mailto:$entries{$entry}->{mail}">$entries{$entry}->{mail}</a></td>
	</tr>
	<tr>
		<table border=0 width=600>
	EOF
	;
	foreach my $element (sort { $a <=> $b } keys %{$entries{$entry}->{content}}) {
		print <<"		EOF"
		<tr>
			<td><ul><li>$entries{$entry}->{content}->{$element}</li></ul></td>
		</tr>
		EOF
		;
	};
	print <<"	EOF"
		</table>
	</tr>
	</table>
	EOF
	;
};
print <<EOF
	</body>
</html>
EOF
;
__END__	
