#!/usr/bin/perl

use strict;
use lib '../include/';
use Glist;
use Queue;
use Carp;

my $glist = Glist::new(prefix=>'/opt/glist', sendmail=>'/usr/lib/sendmail -t');
my $queue = new Queue ($glist);
$queue->gtr_setprio(1414, 3);
$queue->gtr_nicelist();


