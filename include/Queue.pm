#!/usr/bin/perl

=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*       Queue.pm
* PURPOSE
*       Give a set of functions and objects to work with the 
*	queue in a consistent way.
* AUTHORS
*       Ask Solem Hoel <ask@unixmonks.net>
* ============================================================
* This file is a part of the glist mailinglist manager.
* (c) 2001 Ask Solem Hoel <http://www.unixmonks.net>
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License version 2
* as published by the Free Software Foundation.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software
* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/
=cut

package Queue;

use strict;
use Exporter;
use File::Copy;
use Glist;
use DB_File;
use Carp;
use Fcntl qw(:flock);
use POSIX;

# ##################################
# @constructor: Queue Queue::new(Glist glist)
#
# @synopsis:
#	my $glist = Glist::new(%glist_options);
#	my $q = new Queue ($glist);
#
# @params: glist object.
# @returns: glist object.
#
# @description:
#	Creates a new Queue object.
#
sub new {
	my($self, $glist) = @_;
	confess "Missing glist object" unless $glist;
	Carp::cluck "Too many arguments" if @_ > 2;
	my $queue = { };
	bless $queue, 'Queue';
	$queue->glist($glist);
	$queue->set_queuedb();
	return $queue;
}

sub DBLOCKFH {
	my($self, $DBLOCKFH) = @_;
	$self->{DBLOCKFH} = $DBLOCKFH if $DBLOCKFH;
	return $self->{DBLOCKFH};
}

# ##################################
# @accessor: Glist glist(Glist glist)
# 
# @params: glist object reference (optional)
# @returns: glist object reference.
#
# @description: 
#	get/set glist object reference.
#
sub glist {
	my($self, $glist) = @_;
	if($glist) {
		confess "\$glist is not a reference" unless ref $glist;
		$self->{GLIST} = $glist if $glist;
	}
	return $self->{GLIST};
}

# ##################################
# @accessor: string queuedb(void)
#
# @description:
#	The full path to the queue database file.
#
# @see: set_queuedb()
#
sub queuedb {
	my $self = shift;
	return $self->{QUEUEDB};
}

# ##################################
# @accessor: tied_href queue(void)
#
# @description:
#	Gives us a reference to the DB_File tied hash
#	%queue, which is our queue database.
#
# @see: set_queue(), unset_queue(), openqueue(),
#	closequeue()
#
sub queue {
	my $self = shift;
	return $self->{QUEUE_HREF};
}

# ##################################
# @method: int set_queuedb(void)
#
# @description:
#	Finds the path to the queue database and stores it,
#	so we can access it with queuedb() later.
#
# @see: queuedb()
#
sub set_queuedb {
	my $self = shift;
	my $glist = $self->glist();
	my $queuedb = $glist->prefix() . '/var/run/queue.db';
	$glist->error("Warning: Queue DB does not exist. I'll try to create it.")
		unless -f $queuedb;
	$self->{QUEUEDB} = $queuedb;
	return 1;
}


# ##################################
# @method: int set_queue(tied_href queuedb)
#
# @description:
#	Sets the tied href that we get by using
#	the queue() accessor.
#
# @see: queue(), unset_queue(), openqueue(), 
#	closequeue()
#
sub set_queue {
	my($self, $qref) = @_;
	my $glist = $self->glist();
	if(ref $qref eq 'HASH') {
		$self->{QUEUE_HREF} = $qref;
	}
	else {
		confess "Something tried to set queue,
		but didn't give hash ref.";
		return undef;
	}
	return 1;
}

# ##################################
# @method: int unset_queue(void)
#
# @description:
#	Unsets the queue href.
#
# @see: set_queue(), queue(), openqueue(),
#	closequeue()
#
sub unset_queue {
	my $self = shift;
	$self->{QUEUE_HREF} = undef;
	return 1;
}

# ##################################
# @method: bool openqueue(void)
#
# @description:
#	dbmopen the queuedb and pass a ref to set_queue.
#
# @see: set_queue(), queue(), closequeue(),
#	unset_queue()
#
sub openqueue {
	my $self = shift;
	my $glist = $self->glist();
	open (DBFH, $self->queuedb())
		|| $glist->error("Couldn't open queuedb: $!")
		&& return undef;
	flock(DBFH, 2)
		|| $glist->error("Couldn't lock queuedb: $!")
		&& return undef;
	$self->DBLOCKFH(*DBFH);
	dbmopen my %queue, $self->queuedb(), 0600
		|| $glist->error("Couldn't open queuedb: $!")
		&& return undef;
	$self->set_queue(\%queue);
	return 1;
}		

# ##################################
# @method: bool closequeue(void)
#
# @description:
#	dbmclose the href we get from queue(),
#	and unset Glist::{QUEUE_HREF} with unset_queue().
#
# @see: openqueue(), unset_queue(), set_queue(),
#	queue()
#
sub closequeue {
	my $self = shift;
	my $queue = $self->queue();
	my $glist = $self->glist();
	dbmclose %$queue || $glist->warning("Couldn't dbmclose queue: $!");
	$self->unset_queue();
	close($self->DBLOCKFH()) || $glist->warning("Couldn't close queuelock: $!");
	return 1;

}

# ##################################
# @method: bool gtr_introduce(string filename, string spool)
#
# @param: $filename, the new file to add to the queue.
#
# @param: $spool, the directory the file is currently in.
# 
# @description:
#	Introduce a file to the queue. Save it's record
#	to the queuedb so we can use the other queue functions on it.
#
sub gtr_introduce {
	my($self, $filename, $spool) = @_;
	# ### 
	# These functions are usually in almost every function in Queue,
	# so these are only commented once.
	#
	  # Get the glist objectref, for cleaner code.
	  my $glist = $self->glist();

	  # Remove the directory part of the file 
	  # (if there are any, and we hope there are...)
	  $filename =~ s%.*/%%;
	 
	  # True if this function opened the queue,
	  # so we can clean up after us when we're done.
	  my $iopenedq = 0;

	  # We have no queue? Open it then.
	  unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	  }
	  my $queue = $self->queue;
	###### 

	$queue->{$filename} = "$spool|0|0|";
	$glist->warning("Introduced $filename to queue");

	# if we opened the queue we know that noone else have use for it,
	# so close it.
	$self->closequeue if $iopenedq;

	return 1;
}

# ##################################
sub is_ref {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;
	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;

	unless($queue->{$filename}) {
		$glist->error("No such queue entry $filename.");
		return -1;
	}
	my ($s, $p, $h, $r) = split /\|/, $queue->{$filename}, 4;

	$self->closequeue if $iopenedq;

	# try catch infinite loops, not actually good enough,
	# but it will work if it's referring to itself.
	return -2 if $r eq $filename;
	
	$r ? return $r : return undef;
}

# ##################################
sub gtr_setpos {
	my($self, $filename, $spool) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;

	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;
	my $ent = $self->fetch($filename) or return undef;
	$glist->move_to_newspool("$ent->[0]/$filename", $spool)
		or return undef;
	$ent->[0] = $spool;
	$self->store($filename, $ent);
	$self->closequeue if $iopenedq;
	return "$spool/$filename";
}

# ##################################
sub fetch {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	my $queue = $self->queue();
	$filename =~ s%.*/%%;
	my ($ent, @ent);
	my $is_ref = $self->is_ref($filename);
	return undef if $is_ref < 0;
	if($is_ref) {
		$ent = $self->fetch($is_ref);
		return $ent;
	}
	@ent = split /\|/, $queue->{$filename}, 4;
	return \@ent;
}

# ##################################
sub store {
	my($self, $filename, $ar_ent) = @_;
	my $queue = $self->queue();
	$filename =~ s%.*/%%;
	$queue->{$filename} = join '|', @$ar_ent;
	return 1;
}

# ##################################
sub gtr_rename {
	my($self, $oldfile, $newfile) = @_;
	my $glist = $self->glist();
	my $iopenedq = 0;

	$oldfile =~ s%.*/%%; $newfile =~ s%.*/%%;

	# open the queue
	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;
	
	# ### 
	# bail out if the new entry already exists.
	if($self->fetch($newfile)) {
		$glist->error("Entry $newfile already exists");
		return undef;
	}

	my $is_ref = $self->is_ref($oldfile);
	return undef if $is_ref < 0;
	if($is_ref) {
		$self->gtr_rename($is_ref, $newfile);
		return 1;
	}

	# get the existing entry.
	my $ent = $self->fetch($oldfile) or return undef;

	# move the file.
	move("$ent->[0]/$oldfile", "$ent->[0]/$newfile")
		|| $glist->error("Couldn't move $oldfile => $newfile: $!") 
		&& return undef;

	# copy it to a new array.
	my $new_ent = $ent;

	# introduce the new entry
	$self->store($newfile, $new_ent);

	# ### 
	# store the old entry with reference 
	# to the new entry.
	$ent->[3] = $newfile;
	$self->store($oldfile, $ent);

	# ### close the queue.
	$self->closequeue if $iopenedq;
	
	return 1;
}

# ##################################
sub gtr_delete {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;

	# open the queue
	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;

	my $is_ref = $self->is_ref($filename);
	return undef if $is_ref < 0;
	# ###
	# and delete everything this entry is a reference to.
	if($is_ref) {
		$self->gtr_delete($is_ref);
	}
	# delete the file.
	my $ent = $self->fetch($filename);
	if($ent->[2]) {
		$glist->error("Cannot delete entry that is on hold. Restart it first.");
		return undef;
	}
	if(-f "$ent->[0]/$filename") {
		unlink "$ent->[0]/$filename"
			|| $glist->error("Couldn't remove $filename: $!")
			&& return undef;
	}
	delete $queue->{$filename};

	# ### 
	# delete all the entries that are referreing to this entry.
	foreach my $qent (keys %$queue) {
		my $qisref = $self->is_ref($qent);
		if($qent != $filename && $qisref == $filename) {
			$self->gtr_delete($qent)
		}
	}
	$self->closequeue() if $iopenedq;

	$glist->error("Deleted $filename from queue and filesystem.");

	return 1;
}

# ##################################
sub gtr_getpos {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;

	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;
	my $is_ref = $self->is_ref($filename);	

	return undef if $is_ref < 0;
	if($is_ref) {
		return $self->gtr_getpos($is_ref);
	};

	my @ent = split /\|/, $queue->{$filename}, 4;

	$self->closequeue if $iopenedq;

	return $ent[0];	
}

# ##################################
sub gtr_raise {
	my($self, $filename) = @_;
	$filename =~ s%.*/%%;
	return $self->gtr_setprio($filename, -1);
}

# ##################################
sub gtr_lower {
	my($self, $filename) = @_;
	$filename =~ s%.*/%%;
	return $self->gtr_setprio($filename, +1);
}

# ##################################
sub gtr_setprio {
	my($self, $filename, $prio) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;

	if($prio > 5 || $prio < -5) {
		$glist->error("Illegal priority, must be between -5 and +5");
		return undef;
	}

	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;

	my $is_ref = $self->is_ref($filename);
	return undef if $is_ref < 0;
	if($is_ref) {
		return $self->gtr_setprio($is_ref, $prio);
	}
	my $pic = 0; # place in queue.
	my $tic = 1; # total in queue, (start on 1, not 0)
	my $nch = 0; # number of chunks of <= 10 each.
	my $ptb = 0; # our new wanted position in the q.
	my @sorted = sort {$a <=> $b} keys %$queue;
	for(my $qe = 0; $qe < scalar @sorted; $qe++) {
		if($sorted[$qe] eq $filename) {
			$pic = $qe + 1;
		}
		$tic++;
	};
	$tic < 10 ? $nch = 1 : $nch = ceil($tic / 10);
	$ptb = floor($prio * $nch + $pic);
	$ptb = 1 if $ptb <= 0;
	$ptb = $tic if $ptb > $tic;

	# already at wanted position
	return 1 if $pic == $ptb;

	my $fop = $sorted[$ptb - 1]; # file on our wanted position.

	# print "Hi! My name is $filename, I'm currently at position $pic\n";
	# print "My master wants to raise my priority with $prio, that means\n";
	# print "I have to get to position $ptb where $fop currently is.\n"; 
	
	my $newfile = $fop;
	while(grep /^$newfile$/, @sorted) {
		if($ptb > $pic) {
			$newfile++;
		}
		else {
			$newfile--;
		}
	}
	return undef unless $newfile;
	# print "This means i have to rename myself to $newfile\n";
	$self->closequeue if $iopenedq;
	return $self->gtr_rename($filename, $newfile);
}

# ##################################
sub gtr_stop {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;

	# open the queue
	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;

	my $is_ref = $self->is_ref($filename);	
	return undef if $is_ref < 0;
	if($is_ref) {
		$glist->error("$filename is a reference to $is_ref");
		$self->gtr_stop($is_ref);
		return 1;
	}
	
	my $ent = $self->fetch($filename);

	if($ent->[2] == 1) {
		$glist->error("$filename is already on hold");
		return undef;
	}
	$glist->move_to_newspool("$ent->[0]/$filename", $glist->hold())
		or return undef;
	$ent->[2] = 1;
	$self->store($filename, $ent);
	$self->closequeue if $iopenedq;

	return 1;
}

# ##################################
sub gtr_restart {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;
	# open the queue
	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;

	my $is_ref = $self->is_ref($filename);	
	return undef if $is_ref < 0;
	if($is_ref) {
		$glist->error("$filename is a reference to $is_ref");
		$self->gtr_restart($is_ref);
		return 1;
	}
	
	my $ent = $self->fetch($filename);

	if($ent->[2] == 0) {
		$glist->error("$filename is not on hold");
		return undef;
	}
	$glist->move_to_newspool($glist->hold()."/$filename", $ent->[0])
		or return undef;
	$ent->[2] = 0;
	$self->store($filename, $ent);
	$self->closequeue if $iopenedq;

	return 1;
}

# ##################################
sub gtr_nicelist {
	my ($self, $list) = @_;
	my $glist = $self->glist();
	my $iopenedq = 0;


	my($c_qn, $c_qs, $c_qp, $c_qh, $c_qr) = undef;

	format QUEUE_TOP =
Filename				Spool			Hold	Reference
--------------------------------------------------------------------------------------
.

	format QUEUE =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<	@<<<<<<<<<<<<<<<<<<<	@<<<<<	@<<<<<<<<<<<<<<<<<<<<<
$c_qn,					$c_qs,			$c_qh,	$c_qr
.

	$^ = "QUEUE_TOP";
	$~ = "QUEUE";

	unless($self->queue) {
		$self->openqueue() or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue();
	my $prefix = $glist->prefix();
	my @list;
	if($list) {
		@list = sort {$a <=> $b} @$list;
	}
	else {
		@list = sort {$a <=> $b} keys %$queue;
	}
	my $count = 0;
	foreach $c_qn (@list) {
		++$count;
		my $ar_ent = $self->fetch($c_qn);
		#unless(ref $ar_ent) {
		#	($c_qs, $c_qr) = ("-defect-", "-defect-");
		#}
		#else {
			($c_qs, $c_qp, $c_qh, $c_qr) 
				= split /\|/, $queue->{$c_qn}, 4;
			$c_qs =~ s%^$prefix/?%%;
			$c_qr or $c_qr="-original-";
			$c_qs or $c_qs="-missing-";
		#}
		if($c_qh == 1) {
			$c_qh = "yes";
		}
		else {
			$c_qh = "no";
		};
		$c_qp or $c_qp=0;
		write;
	}
	if(!$count) {
		print "No files in queue.\n";
	}
	$self->closequeue if $iopenedq;
	return 1;
}

sub isinq {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	$filename =~ s%.*/%%;
	my $iopenedq = 0;

	unless($self->queue) {
		$self->openqueue or return undef;
		$iopenedq++;
	}
	my $queue = $self->queue;
	unless($queue->{$filename}) {
		$self->closequeue if $iopenedq;
		return undef;
	}
	$self->closequeue if $iopenedq;
	return 1;
}

sub fileisok {
	my($self, $filename) = @_;
	my $glist = $self->glist();
	my $basename = $filename;
	$basename =~ s%.*/%%;
	if($basename =~ /^\s*$/) {
		$glist->error("No filename??? I Received -->$basename<--");
		return undef;
	};
	if($basename =~ /[^0-9]/) {
		$glist->error("The file '$basename' has illegal ".
			"characters. Please don't mess with my queue");
		return undef;
	};
	my ($odev, $oinod) = stat($filename);
	open(FH, $filename)
		or  confess("(fileisok) Couldn't open file $filename: $!")
		and return undef;
	my ($ndev, $ninod) = stat(FH);
	close(FH);
	
	if($ndev != $odev || $ninod != $oinod) {
		$glist->error("Hmm.. Something is strange about this file. I don't like it,".
			" so I'll drop it.");
		return undef;
	}
				
	return 1;
}

1;
