#!/usr/bin/perl

=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*	Pickup.pm
* PURPOSE
*	A set of functions, methods and accessors for the pickup
*	daemon to work properly. Made for reusability.
* AUTHORS
*	Ask Solem Hoel <ask@unixmonks.net>
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

package Glist::Pickup;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Glist;
use Queue;
use Fcntl qw(:flock);

@ISA = qw(Exporter);
@EXPORT = qw($VERSION);
@EXPORT_OK = qw($VERSION);
$VERSION = $Glist::VERSION;

sub new {
	my $glist = shift;
	my $q = new Queue ($glist);
	my $obj = { };
	bless $obj, 'Glist::Pickup';
	$obj->glist($glist);
	$obj->queue($q);
	return $obj;
}

sub glist {
	my ($self, $glist) = @_;
	$self->{GLIST} = $glist if $glist;
	return $self->{GLIST};
}

sub queue {
	my($self, $queue) = @_;
	$self->{QUEUE} = $queue if $queue;
	return $self->{QUEUE};
}

sub handle_files {
	my $self = shift;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $q = $self->queue();

	my $files = $glist->get_spool_files($glist->incoming());

	# run user-defined pickup start handler
	if(defined $config->{global}{pickup_start_action}) {
		$glist->exec_handler($config->{global}{pickup_start_action});
	}	

	my %files_status;
	FILE:
	foreach my $file (@$files) {
		$glist->log("(Pickup::handle_files) Found new message: $file") if $glist->verbose();

		# run user-defined pickupd handler if defined.
		if(defined $config->{global}{pickup_handler}) {
			$files_status{$file} = $glist->exec_handler($config->{global}{pickup_handler}, $file);
			next;
		}
			
		unless($glist->file_check($file, FC_FILE, FC_WRITE, [FC_MBO, FC_NOZERO])) {
			$files_status{$file} = 'file_check FC_FILE FC_WRITE [FC_MBO, FCNOZER] returned false';
			unlink $file;
			next FILE;
		};
		unless($q->fileisok($file)) {
			$files_status{$file} = 'fileisok returned false';
			unlink $file;
			next FILE;
		}		
		unless($q->isinq($file)) {
			unless($q->gtr_introduce($file, $glist->incoming())) {
				$files_status{$file} = 'couldn\'t introduce file to queue (gtr_introduce)';
				unlink $file;
				next FILE;
			}
		};

		unless($q->gtr_setpos($file, $glist->rewrite_spool())) {
			$files_status{$file} = 'couldn\'t set file position (gtr_setpos)';
			unlink $file;
			$q->gtr_delete($file);
			next FILE;
		}

		$files_status{$file} = 'success';
	};

	# run user-defined pickupd end handler	
	if(defined $config->{global}{pickup_end_action}) {
		$glist->exec_handler($config->{global}{pickup_end_action}, \%files_status);
	}	

	return 1;
}

1;
