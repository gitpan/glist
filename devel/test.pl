#!/usr/bin/perl

use strict;
use lib '../include/';
use Glist;
use Queue;

my $glist = Glist::new(prefix=>'/opt/glist', sendmail=>'/usr/lib/sendmail -t');
my $queue = new Queue ($glist);

foreach(qw(1212 1313 1414 1515 1616 1717 1818 1919)) {
	$queue->gtr_introduce($_);
	$queue->gtr_setpos($_, $glist->incoming());
};
print "finished ok\n";
$queue->gtr_nicelist();


