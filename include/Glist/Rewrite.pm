#!/usr/bin/perl

=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*	Rewrite.pm
* PURPOSE
*	A set of functions, methods and accessors for the rewrite
*	daemon to work. Made for reusability.
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

package Glist::Rewrite;

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
        my $obj = {};
        bless $obj, 'Glist::Rewrite';
        $obj->glist($glist);
	$obj->queue($q);
        return $obj;
};

# Reference to the Glist.pm object. For clean and readable code.
sub glist {
	my ($self, $glist) = @_;
	$self->{GLIST} = $glist if $glist;
	return $self->{GLIST};
};

sub queue {
	my($self, $queue) = @_;
	$self->{QUEUE} = $queue if $queue;
	return $self->{QUEUE};
}

sub list {
	my ($self, $list) = @_;
	$self->{LIST} = $list if $list;
	return $self->{LIST};
};

sub list_flush {
	my $self = shift;
	$self->{LIST} = undef;
	return 1;
};

# ### THE MAIN FILE HANDLER
sub handle_files {
	my $self = shift;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $q = $self->queue();

	# Get the files to be rewritten in the rewrite spool.
	my $files = $glist->get_spool_files( $glist->rewrite_spool );

	if(defined $config->{global}{rewrite_start_action}) {
		$glist->exec_handler(
			$config->{global}{rewrite_start_action}
		);
	};

	my %files_status;
	FILE:
	foreach my $file (@$files) {
		$self->list_flush(); # delete the temporary variable LIST

		# ### Log our discovery of a new message.
		my $basename = $file;
		$basename =~ s%.*/%%;
		$glist->log("Found new message (file: $basename) in rewrite spool.");

		# run user-defined rewrite handler
		if(defined $config->{ $self->list() }{rewrite_handler}) {
			$glist->exec_handler(
				$config->{ $self->list() }{rewrite_handler}, $file, $self->list()
			);
			next;
		}
		elsif(defined $config->{global}{rewrite_handler}) {
			$glist->exec_handler(
				$config->{global}{rewrite_handler}, $file, $self->list()
			);
			next;
		};

		unless($q->fileisok($file)) {
			$files_status{$file} = $glist->error();
			unlink $file;
			return undef;
		};
		unless($q->isinq($file)) {
			unless($q->gtr_introduce($file, $glist->rewrite_spool())) {
				$files_status{$file} = $glist->error();
				unlink $file;
				return undef;
			}
		};

		# rewrite the message and put into message.
		# if the rewrite fails, rewrite_headers() it self will take care of
		# the error and do the appropriate action (delete it/move it to the defer queue etc)
		my $msg = $self->rewrite_headers($file);
		unless($msg) {
			$files_status{$file}=$glist->error();
			next FILE;
		}

		# If rewrite_headers did not return anything (should never happen!)
		# defer the file and jump to next file.
		unless(defined $msg) {
			$files_status{$file} = $glist->error();
			$q->gtr_setpos($file, $self->deferred());
			next FILE;
		};

		# if the no_action bit is set we shouldn't really do anything...
		unless(defined $glist->no_action) {
			# ...though if everything is clear, save the file...
			open(FILE, ">$file") 
				|| $glist->fatal("Couldn't open $file: $!")
				&& return undef;
			flock(FILE, LOCK_EX);
			print FILE $msg;
			flock(FILE, LOCK_UN);
			close FILE
				|| $glist->fatal("Couldn't close $file: $!")
				&& return undef;

			# delete unwanted attachments
			$glist->check_attachments($file, $self->list());

			# ...and move it to the outgoing queue.
			$q->gtr_setpos($basename, $glist->outgoing());
		};
	};

	if(defined $config->{global}{rewrite_end_action}) {
		$glist->exec_handler(
			$config->{global}{rewrite_end_action},
			\%files_status
		);
	}	

	return 1;
};

sub rewrite_headers {
	my ($self, $file) = @_;

	# Get the configuration reference
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $q = $self->queue();
	my $basename = $file;
	$basename =~ s%.*/%%;

	# until $error is unset, we have an error.
	my $error = 1;

	my $mail_object = $glist->parsemail($file);
	my ($header, $body, $locked_to) = @$mail_object;
	$body = join("\n", @$body);

	# Keep some of the original headers.
	my $original_to = $header->{To};
	my $original_cc = $header->{Cc} if $header->{Cc};
	my $original_from = $header->{From};

	# Concatenate To and Cc
	$header->{To} .= ", $header->{Cc}" if $header->{Cc};
	$glist->log("Message is to: $header->{To}") if $glist->verbose();

	# Get the addresses in To: into an array.
	if(defined $$locked_to) {
		$header->{To} = [$$locked_to];
		$glist->log("Message has a locked recipient: $$locked_to. This is good.");
	}
	else {
		$glist->log("Warning: Message has no locked recipient. Please give argument to gfetch");
		$header->{To} = $self->parse_address($header->{To});
	};

	# Get the address in From:
	$header->{From} = $self->parse_from($header->{From}, $file);

	if($header->{From} =~ /^MAILER-DAEMON\@/) {
		$glist->error("Message looks like a bounce, deferring.");
		$q->gtr_setpos($basename, $glist->deferred());
		return undef;
	};

	my $stripped_content_type;
	if($header->{"Content-Type"}) {
		if(index($header->{"Content-Type"}, ";")) {
			$stripped_content_type = [split(/\s*;\s*/, $header->{"Content-Type"})]->[0];
		};
	};

	# Filename without leading path.	
	my $filename_without_path = $file;
	$filename_without_path =~ s%.*/%%;

	TO:	# loop through all the addresses in the To: header.
	foreach my $r_t (@{$header->{To}}) {
		if($glist->is_list($r_t)) { # If this address is a glist mailing list

			# Store the list
			$self->list($r_t);

			# Just remove the file if this mail already has been sent by us.
			if($self->is_sent_by_us($r_t, $header->{"X-Mailing-List"})) {
				$q->gtr_remove($basename);
				return undef;
			};

			# ####### add some headers... ######## #

			# sending of original can be turned off in the configuration file
			if(defined $config->{$r_t}{hide_sender}) {
				if($config->{$r_t}{hide_sender} eq 'yes') {
					# if we want to hide the sender, we must remove
					# the Reply-To and Message-Id headers.
					# Because outlook adds a Reply-To header as standard :(
					delete $header->{"Reply-To"};
					delete $header->{"Message-Id"};
				}
				else {
					$header->{"X-Original-Sender"} = $header->{From};
				};
			};

			# if an reply-to address has been configured in the configuration file
			# add that.
			if(defined $config->{$r_t}{reply_to}) {
				$header->{"Reply-To"} = $config->{$r_t}{reply_to};
			};

			# Precedence of this mail is list.
			$header->{"Precedence"} = 'list';

			# Prints out which mailing list this mail came from with the file.
			$header->{"X-Mailing-List"} = "<$r_t> $filename_without_path";

			# Don't really want the message to come back to us.
			$header->{"Resent-Sender"} = $header->{From};
			$header->{"Resent-From"} = $r_t;
			$header->{"X-Loop"} = $r_t;
			$header->{"X-List"} = $r_t;

			# nerd marketing :)
			$header->{"X-Mailinglist-Software"} = sprintf("glist v/%s", $Glist::VERSION);

			# Check if the sender has priviliges to send to this list.
			unless($self->priv_to_send($header->{From}, $r_t)) {
				my $error = "Sender $header->{From} does not have priviliges to send to $r_t";
				$glist->error($error);
				$glist->rewrite_with_error($file, $error, $r_t, $header->{From});
				$q->gtr_setpos($basename, $glist->deferred());
				return undef;
			};
			# Check if the sender is blacklisted
			if($glist->in_blacklist($header->{From}, $r_t)) {
				my $error = "Sender $header->{From} is in the blacklist for $r_t";
				$glist->error($error);
				$glist->rewrite_with_error($file, $error, $r_t, $header->{From});
				$q->gtr_setpos($basename, $glist->deferred());
				return undef;
			};
			# Check if the message size is OK.
			unless($glist->size_ok($file, $r_t)) {
				my $size_limit = $Glist::DEFAULT_SIZE_LIMIT;
				$size_limit = $config->{$r_t}{size_limit}
					if(defined $config->{$r_t}{size_limit});
				my $error = "Maximum message body length exceeded (>$size_limit)";	
				$glist->error($error);
				$glist->rewrite_with_error($file, $error, $r_t, $header->{From});
				$q->gtr_setpos($basename, $glist->deferred());
				return undef;
			};
			# ### Check header filters
			unless($self->header_checks($r_t, $header)) {
				$glist->error("$file matches a filter and will be removed from spool.");
				$glist->rewrite_with_error(
					$file, 
					"Message matches a filter and cannot be sent",
					$r_t,
					$header->{From}
				);	
				$q->gtr_setpos($basename, $glist->deferred());
				return undef;
			};
			# ### Check body filters
			unless($self->body_checks($r_t, $body)) {
				$glist->error("$file matches a filter and will be removed from spool.");
				$glist->rewrite_with_error(
					$file, 
					"Message matches a filter and cannot be sent",
					$r_t,
					$header->{From}
				);	
				$q->gtr_setpos($basename, $glist->deferred());
				return undef;
			};
			# ### Check content type
			if($stripped_content_type) {
				unless($glist->check_content_type($stripped_content_type, $r_t)) {
					$glist->error(sprintf("$file has illegal content-type: %s", $stripped_content_type));
					$glist->rewrite_with_error(
						$file,
						sprintf("Illegal content-type: %s", $stripped_content_type),
						$r_t,
						$header->{From}
					);
					$q->gtr_setpos($basename, $glist->deferred());
					return undef;
				};
				if($glist->check_content_deny($stripped_content_type, $r_t)) {
					$glist->error(sprintf("$file has illegal content-type: %s", $stripped_content_type));
					$glist->rewrite_with_error(
						$file,
						sprintf("Illegal content-type: %s", $stripped_content_type),
						$r_t,
						$header->{From}
					);
					$q->gtr_setpos($basename, $glist->deferred());
					return undef;
				};
			};

			# If custom sender has been configured, rewrite that.
			if(defined $config->{$r_t}{sender}) {
				$header->{From} = $config->{$r_t}{sender};
			}
			else {
				$header->{From} = $original_from;
			};

			# Add subject prefix if that is configured for this list.
			if($config->{$r_t}{subject_prefix}) {
				my $subject_prefix = quotemeta $config->{$r_t}{subject_prefix};
				unless($header->{Subject} =~ /$subject_prefix/) {
					unless($header->{Subject} =~ /(Re|Fw):/i) {
						$header->{Subject} = sprintf("%s %s",
							$config->{$r_t}{subject_prefix},
							$header->{Subject}
						);
					};
				};
			};

			# Restore the original To: and Cc: headers.
			$header->{To} = $original_to;
			$header->{Cc} = $original_cc if $original_cc;

			# If a custom recipient is configured, rewrite that.
			if(defined $config->{$r_t}{recipient}) {
				$header->{To} =~ s/$r_t/$config->{$r_t}{recipient}/;
				$header->{Cc} =~ s/$r_t/$config->{$r_t}{recipient}/
					if $header->{Cc};
			};

			# Then decide if this is a file or SQL based list
			if($config->{$r_t}{type} eq 'file') {
				$header->{"X-File"} = $config->{$r_t}{file};
			}
			elsif($config->{$r_t}{type} =~ /sql/) {
				$header->{"X-DB_Server"} = $config->{$r_t}{server};
				$header->{"X-Database"} = $config->{$r_t}{database};
				$header->{"X-Push_list_id"} = $config->{$r_t}{push_list_id};
			};

			# Add header if any
			my $body_header = $glist->get_header($r_t);
			$body = "$body_header\n$body" if $body_header;

			# Add footer if any
			my $body_footer = $glist->get_footer($r_t);
			$body .= "\n$body_footer" if $body_footer;

			$error = 0;
			last TO;
		};
	};

	if($error) {
		$glist->error("Unknown mailinglist destination");
		$self->list_flush();
		$q->gtr_setpos($basename, $glist->deferred());
		return undef;
	};

	# Generate the new message out of the new headers.
	my $message;
	foreach my $curr_header (sort keys %$header) {
		$message .= sprintf("%s: %s\n", $curr_header, $header->{$curr_header});
	};
	$message .= sprintf("\n%s", $body);

	return $message;
};

sub parse_from {
	my ($self, $header_value, $file, $list) = @_;
	my $glist = $self->glist();

	if($header_value =~ /\<(.+?)\>/) {
		$header_value = $1;
	};

	$header_value =~ /\s*(.+?)\@(.+?)(\s+|$)/;
	$header_value = sprintf "%s\@%s", $1, $2;

	return $header_value;
};	

sub parse_address {
	my ($self, $header_value) = @_;
	my @recipient = split(/\s*,\s*/, $header_value);
	for(my $rcpt_no = 0; $rcpt_no < scalar @recipient; $rcpt_no++) {
		if($recipient[$rcpt_no] =~ /\<(.+?)\>/) {
			$recipient[$rcpt_no] = $1;
		};
		$recipient[$rcpt_no] =~ /\s*(.+?)\@(.+?)(\s+|$)/;
		$recipient[$rcpt_no] = sprintf("%s\@%s", $1, $2);
	};

	return \@recipient;
};

sub priv_to_send {
	my ($self, $sender, $list) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();

	return undef unless $sender;
	return undef unless $list;

	if(defined $config->{$list}{send_allow}) {
		my @privileged = split(/\s*,\s*/, $config->{$list}{send_allow});
		foreach my $priv (@privileged) {
			$priv = quotemeta $priv;
			if($priv eq 'on_list') {
				return 1 if $self->priv_to_send_list($sender, $list);
			}
			else {
				return 1 if ($sender =~ /$priv/i);
			};
		};
		return undef;
	}
	else {
		return 1;
	};
};

sub priv_to_send_list {
	my ($self, $sender, $list) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();

	return undef unless $sender;
	return undef unless $list;

	if($config->{$list}{type} eq 'file') {
		$glist->log("Type is file") if $glist->verbose();
		my $file = $config->{$list}{file};
		open(FILE, $file)
			|| $glist->fatal("Couldn't open list file $file: $!")
			&& return undef;
		flock(FILE, LOCK_SH);
		while(<FILE>) {
			chomp;
			$_ = quotemeta $_;
			return 1 if $sender =~ /$_/i;
		};
		flock(FILE, LOCK_UN);
		close(FILE);
	};

	return undef;
};


sub is_sent_by_us {
	my ($self, $curr_list, $m_header) = @_;

	if($m_header) {
		my ($list, $file) = split(/\s+/, $m_header);
		$list =~ s/[<>]//g;
	
		if($curr_list eq $list) {
			return 1;
		};
	};
	return undef;
};

sub header_checks {
	my ($self, $list, $head) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();

	if(defined $config->{$list}{header_checks}) {
		my $header_checks = $config->{$list}{header_checks};
		my @header;
		foreach(keys %$head) {
			push(@header, "$_: $head->{$_}");
		}
		close(FH);
		open(HC, $header_checks) 
			|| $glist->fatal("Couldn't open $header_checks: $!") 
			&& return 1;
		while(<HC>) {
			chomp;
			next if /^\s*#/;
			next if /^\s*$/;
			my $check = quotemeta $_;
			$check = lc $check;
			foreach my $header_line (@header) {
				$header_line = lc $header_line;
				if($header_line =~ /$check/) {
					$glist->error("Header matches header_check: '$check'");
					return undef;
				};
			};
		};
		close(HC);
		return 1;
	}
	else {
		return 1;
	};
};

sub body_checks {
	my ($self, $list, $body) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();

	if(defined $config->{$list}{body_checks}) {
		my $body_checks = $config->{$list}{body_checks};
		my $in_body;
		close(FH);
		open(HC, $body_checks) 
			|| $glist->error("Couldn't open $body_checks: $!") 
			&& return 1;
		while(<HC>) {
			chomp;
			next if /^\s*#/;
			next if /^\s*$/;
			my $check = quotemeta $_;
			$check = lc $check;
			foreach my $body_line (@$body) {
				$body_line = lc $body_line;
				if($body_line =~ /$check/) {
					$glist->error("Body matches body_check: '$check'");
					return undef;
				};
			};
		};
		close(HC);
		return 1;
	}
	else {
		return 1;
	};
};

1;
