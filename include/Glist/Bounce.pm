#!/usr/bin/perl
=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*	Bounce.pm
* PURPOSE
*	A set of functions, methods and accessors for the bounce
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

package Glist::Bounce;

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
	my %argv = @_;
	my $obj = { };
	bless $obj, 'Glist::Bounce';

	if($argv{sendmail}) {
		$obj->sendmail_prog($argv{sendmail});
	}
	else {
		$glist->fatal("Missing path to sendmail!");
	};

	$obj->glist($glist);
	$obj->queue($q);
	return $obj;
};

sub sendmail_prog {
	my ($self, $sendmail) = @_;
	$self->{SENDMAIL} = $sendmail if $sendmail;
	return $self->{SENDMAIL};
};

sub glist {
	my ($self, $glist) = @_;
	$self->{GLIST} = $glist if $glist;
	return $self->{GLIST};
};

sub queue {
	my($self, $queue) = @_;
	$self->{QUEUE} = $queue if ref $queue;
	return $self->{QUEUE};
}

sub mailinglist {
	my ($self, $mailinglist) = @_;
	$self->{MAILINGLIST} = $mailinglist if $mailinglist;
	return $self->{MAILINGLIST};
};

sub mailinglist_clear {
	my $self = shift;
	$self->{MAILINGLIST} = undef;
	return 1;
};

sub subject {
	my ($self, $subject) = @_;
	$self->{SUBJECT} = $subject if $subject;
	return $self->{SUBJECT};
};

sub subject_clear {
	my $self = shift;
	$self->{SUBJECT} = undef;
	return 1;	
};

sub sender {
	my ($self, $sender) = @_;
	$self->{SENDER} = $sender if $sender;
	return $self->{SENDER};
};

sub sender_clear {
	my $self = shift;
	$self->{SENDER} = undef;
	return 1;
};

sub flush_temporaries {
	my $self = shift;
	$self->mailinglist_clear;
	$self->subject_clear;
	$self->sender_clear;
	return 1;
};

sub bounce {
	my ($self, $message) = @_;
	my $glist = $self->glist();

	return undef unless $message;

	# do not send mail if no_action option set.
	unless($glist->no_action()) {
		# ... send the mail
		my $sendmail = $self->sendmail_prog();	
		open(SENDMAIL, "| $sendmail")
			|| $glist->fatal("Couldn't fork sendmail: $!")
			&& return undef;
		print SENDMAIL $message;
		close(SENDMAIL) || $glist->fatal("Warning: Sendmail did not exit nicely");
	};

	return 1;
};

sub get_sender_method1 {
	my ($self, $file) = @_;
	my $glist = $self->glist();
	my(	$boundary, 
		$boundary_count, 
		$in_boundary, 
		$line_count,
		@message,
		$sender
	);

	open(BOUNCE, $file) 
		|| $glist->fatal("Couldn't open file $file: $!")
		&& return undef;
	flock(BOUNCE, LOCK_EX);
	LINE:
	while(<BOUNCE>) {
		chomp;
		unless($boundary) {
			if(/\s*boundary="(.+)"\s*/) {
				$boundary = $1;
				$boundary_count = 0;
			};
		}
		else {
			last LINE if(/^--$boundary--$/);
			if($in_boundary) {
				$message[$boundary_count][$line_count] = $_. "\n";
				$line_count++;
			};
			if(/^--$boundary$/) {
				$boundary_count++;
				$in_boundary = 1;
				$line_count = 0;
			};
		};
	};
	flock(BOUNCE, LOCK_UN);
	close(BOUNCE);

	return undef unless @message;

	my $bounced_mail_no = scalar @message - 1;
	foreach my $line (@{$message[$bounced_mail_no]}) {
		chomp $line;
		if($line =~ /^From: (.+)/) {
			$sender = $1;
		};
	};

	return $sender;
};

sub get_sender_method2 {
	my ($self, $file) = @_;
	my $glist = $self->glist();
	my $in_original_message = 0;
	my $sender;
	open(BOUNCE, $file)
		|| $glist->fatal("Couldn't open file $file: $!")
		&& return undef;
	flock(BOUNCE, LOCK_EX);
	LINE:
	while(<BOUNCE>) {
		chomp;
		if($in_original_message) {
			if(/^From: (.+)/) {
				$sender = $1;
				return $sender;
			};
		}
		elsif(/^--- Below this line/) {
			$in_original_message = 1;
		};
	};
	flock(BOUNCE, LOCK_UN);
	close(BOUNCE);

	return undef;
};
		

sub handle_files {
	my $self = shift;
	my $glist = $self->glist();
	my $q = $self->queue();
	my $sender;
	my $error;

	my $files = $glist->get_spool_files($glist->deferred());

	FILE:
	foreach my $file (@$files) {

		$self->flush_temporaries();

		unless($glist->file_check($file, FC_FILE, FC_WRITE, [FC_MBO, FC_NOZERO])) {
			unlink $file;
			$q->gtr_remove($file);
			next FILE;
		};
		unless($q->fileisok($file)) {
			unlink $file;
			return undef;
		};
		unless($q->isinq($file)) {
			unless($q->gtr_introduce($file, $glist->deferred())) {
				unlink $file;
				return undef;
			}
		}

		# Move the file as quickly as possible to the send spool, 
		# so other daemon processes won't find it while we're working.
		$file = $q->gtr_setpos($file, $glist->send_spool()) unless $glist->no_action();

		my $basename = $file;
		$basename =~ s%.*/%%;
	
		$error = $self->get_error($file);
		if($error) {
			$self->bounce(
				$self->bounce_error(
					$self->mailinglist(), 
					$self->subject(), 
					$error,
					$self->sender()
				)
			);
		}
		else {
			$sender = $self->get_sender_method1($file);
			if($sender) {
				$self->bounce($self->bounce_mail($sender, $file));
			}
			else {
				$sender = $self->get_sender_method2($file);
				if($sender) {
					$self->bounce($self->bounce_mail($sender, $file));
				}
				else {
					$self->bounce($self->unknown_error($file));
				};
			};
		};

		$glist->log("Message $basename bounced");
		$q->gtr_delete($basename) unless $glist->no_action();
	
	};

	return 1;
};

sub bounce_error {
	my $self = shift;
	my $mailinglist = shift;
	my $subject = shift;
	my $error = shift;
	my $sender = shift;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};

	return undef unless $glist->is_list($mailinglist);

	my $rcpt = $config->{$mailinglist}{owner};

	$glist->log("Bounce sent to $rcpt (bounce_error)");

	my $message  = sprintf("From: MAILER-DAEMON@%s (Glist mailinglist manager)\n", $hostname);
	   $message .= sprintf("Subject: Message with subject '%s' got an error.\n", $subject);
	   $message .= sprintf("To: %s\n", $rcpt);
	   $message .= sprintf("Cc: %s\n", $sender);
	   $message .= sprintf("Precedence: Bulk\n");
	   $message .= sprintf("\n");
	   $message .= sprintf("Hi,\n\n");
	   $message .= sprintf("This is the glist mailinglist manager at %s.\n", $hostname);
	   $message .= sprintf("The message you sent with subject '%s', could\n", $subject);
	   $message .= sprintf("not be processed.\n\n");
	   $message .= sprintf("Error: %s\n\n", $error);
	   $message .= sprintf("Please do not respond to this message.\n");

	return $message;
};
	

sub bounce_mail {
	my $self = shift;
	my $sender = shift;
	my $file = shift;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $file_content;
	open(FILE, $file) or return undef;
	flock(FILE, LOCK_EX);
	while(<FILE>) {
		$file_content .= $_;
	};
	flock(FILE, LOCK_UN);
	close(FILE);

	return undef unless $glist->is_list($sender);

	my $rcpt = $config->{$sender}{owner};

	$glist->log("Bounce sent to $rcpt (bounce_mail)");

	my $message  = sprintf("From: MAILER-DAEMON@%s (Glist mailinglist manager)\n", $hostname);
	   $message .= sprintf("Subject: Undeliverable Mail Returned To Sender\n");
	   $message .= sprintf("To: %s\n", $rcpt);
	   $message .= sprintf("Importance: High\n");
	   $message .= sprintf("\n");
	   $message .= sprintf("Hi,\n\n");
	   $message .= sprintf("This is the glist mailinglist manager at %s.\n", $hostname);
	   $message .= sprintf("This is message is forwarded to us by an external SMTP server,\n");
	   $message .= sprintf("Please check the error message and try to correct this by verifying\n");
	   $message .= sprintf("your mailinglist configuration.\n\n");
	   $message .= sprintf("--- Below this line is the original message:\n\n");
	   $message .= sprintf("%s\n", $file_content);

	 return $message;
};

sub unknown_error {
	my $self = shift;
	my $file = shift;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $admin = $config->{global}{admin};
	my $file_content;

	$glist->log("Bounce sent to $admin (unknown_error)");

	open(FILE, $file) || return undef;
	flock(FILE, LOCK_EX);	
	while(<FILE>) {
		$file_content .= $_;
	};
	flock(FILE, LOCK_UN);
	close(FILE);

	my $message  = sprintf("From: MAILER-DAEMON@%s (Glist mailinglist manager)\n", $hostname);
	   $message .= sprintf("To: %s\n", $admin);
	   $message .= sprintf("Subject: Undeliverable Bounce Returned To Admin\n");
	   $message .= sprintf("Importance: Low\n");
	   $message .= sprintf("\n");
	   $message .= sprintf("Hi,\n\n");
	   $message .= sprintf("This is the glist mailinglist manager at %s.\n", $hostname);
	   $message .= sprintf("By some reason the following message could not be sent\n");
	   $message .= sprintf("or bounced back to the original sender in any way.\n\n");
	   $message .= sprintf("File: %s\n\n", $file);
	   $message .= sprintf("This file has now been deleted from the deferred queue.\n");
	   $message .= sprintf("Please do not reply to this message.\n\n");
	   $message .= sprintf("--- Below this line is the original message:\n\n");
	   $message .= sprintf("%s\n", $file_content);

	 return $message;
};

sub get_error {
	my $self = shift;
	my $file = shift;
	my $glist = $self->glist();

	my($error, $mailinglist, $subject, $sender);

	open(FILE, $file)
		|| $glist->error("Couldn't open file $file: $!")
		&& return undef;
	flock(FILE, LOCK_EX);
	while(<FILE>) {
		if(/^X-GL-Error:\s+(.+?)\s*$/) {
			$error = $1;
		}
		elsif(/^X-Mailinglist:\s+(.+?)\s*$/) {
			$mailinglist = $1;
		}
		elsif(/^Subject:\s+(.+?)\s*$/) {
			$subject = $1;
		}
		elsif(/^X-Original-Sender:\s+(.+?)\s*$/) {
			$sender = $1;
		}
		elsif(/^$/) {
			last;
		}
		else {
			next;
		};
	};
	flock(FILE, LOCK_UN);
	close(FILE);

	if($error) {
		if($mailinglist) {
			$self->mailinglist($mailinglist);
		}
		else {
			$self->mailinglist("unknown error");
		};
		if($subject) {
			$self->subject($subject);
		}
		else {
			$self->subject("unknown subject");
		};
		if($sender) {
			$self->sender($sender);
		}
		else {
			$self->sender(" ");
		};
		return $error;
	}
	else {
		return undef;
	};
};
		

1;
