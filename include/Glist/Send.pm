#!/usr/bin/perl

=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*	Send.pm
* PURPOSE
*	A set of functions, methods and accessors for the send
*	daemon to work. Made for reusability.
* AUTHORS
*	Ask Solem Hoel <ask@unixmonks.net>
* ============================================================
* This file is a part of the glist mailinglist manager.
* (c) 2001 Ask Solem Hoel <http://www.unixmonks.net>
* (c) 2001 Gan Media AS <http://www.gan.no/media>
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

package Glist::Send;

use strict;
use English;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Glist;
use Glist::Admin;
use Queue;
use Fcntl qw(:flock);

@ISA = qw(Exporter);
@EXPORT = qw($VERSION);
@EXPORT_OK = qw($VERSION);
$VERSION = $Glist::VERSION;

############################################
# CONSTRUCTOR: new()
# DESCRIPTION:
#	Construct a new Send object.
#
sub new {
	my $glist = shift;
	my $q = new Queue ($glist);
	my %argv = @_;
	my $obj = { };

	bless $obj, 'Glist::Send';
	$obj->glist($glist);
	$obj->queue($q);

	# Get arguments and do some sanity checks.

	# store sendmail path
	if($argv{sendmail}) {
		$obj->sendmail_prog($argv{sendmail});
	}
	else {
		$glist->fatal("Missing sendmail prog!");
	};

	return $obj;
};

############################################
# ACCESSOR: glist()
# DESCRIPTION:
#	Glist object.
#
sub glist {
	my $self = shift;
	my $glist = shift;
	if($glist) {
		$self->{GLIST} = $glist;
	};
	return $self->{GLIST};
};
############################################
# ACCESSOR: queue()
# DESCRIPTION:
#	Queue object.
#
sub queue {
	my($self, $queue) = @_;
	$self->{QUEUE} = $queue if ref $queue;
	return $self->{QUEUE};
}

############################################
# ACCESSOR: sendmail_prog()
# DESCRIPTION:
#	Set or get the full path of sendmail(8)
sub sendmail_prog {
	my $self = shift;
	my $sendmail = shift;
	if($sendmail) {
		$self->{SENDMAIL} = $sendmail;
	};
	return $self->{SENDMAIL};
};

############################################
# METHOD: check_header($)
#
# SYNOPSIS:
#	$self->check_header($header) || die("Invalid header: $header\n");
#
# DESCRIPTION:
#	Check header against a list of valid headers.
#
sub check_header($$) {
	my $self = shift;
	my $header = shift;

	my $valid_header_name = {
		From 			=> 'sender',
		To			=> 'recipient',
		Cc			=> 'carbon',
		Subject		 	=> 'subject',
		"Resent-From"		=> 'resent_from',
		"X-Database"		=> 'database',
		"X-DB_Server"		=> 'db_server',
		"X-Push_list_id"	=> 'push_list_id',
		"X-File"		=> 'file',
		"X-List"		=> 'list',
	};

	return $valid_header_name->{$header};
};

############################################
# METHOD: handle_files()
# 
# DESCRIPTION:
#	Send the mails in the mailspool and remove them when (and if) they are done.
#
sub handle_files {
	my $self = shift;
	my $glist = $self->glist();
	my $q = $self->queue;
	my $files = $glist->get_spool_files($glist->outgoing());

	FILE:
	foreach my $file (@$files) {

		unless($q->fileisok($file)) {
			unlink $file;
			return undef;
		};
		unless($q->isinq($file)) {
			unless($q->gtr_introduce($file, $glist->outgoing())) {
				unlink $file;
				return undef;
			}
		};

		# Move the file as quickly as possible to the send spool,
		# so other daemon processes won't find it while we're working.
		$file = $q->gtr_setpos($file, $glist->send_spool()) unless $glist->no_action();

		my $mailobject = $glist->parsemail($file);
		my ($header, $body, $lock_rcpt) = @$mailobject;

		my $all_headers;	# All headers
		foreach my $cur_head (sort keys %$header) {
			$all_headers .= "$cur_head: $header->{$cur_head}\n";
		};
		$all_headers .= "\n", join("", @$body);

		my($status, $ar_sent_to) = $self->sendmail($header, $body, $file, $all_headers);
		if($status == 1) {
			if($self->send_summary_on('success', $header->{list})) {
				$self->send_summary(
					'success', $file, $header->{list}, $ar_sent_to
				);
			}
			$q->gtr_delete($file) unless $glist->no_action();
		}
		else {
			if($self->send_summary_on('error', $header->{list})) {
				$self->send_summary(
					'error', $file, $header->{list}, $ar_sent_to
				);
			}
			$glist->fatal("Couldn't send message $file");
			$q->gtr_setpos($file, $glist->deferred()) unless $glist->no_action();
		};
	};
	return 1;
};

sub remove_unwanted_headers {
	my $self = shift;
	my $headers = shift;

	my @header = split("\n", $headers);
	for(my $head_num = 0; $head_num < scalar(@header); $head_num++) {
		if($header[$head_num] =~ /^(.+?):\s+(.+?)$/) {
			my $current_header = $1;
			foreach my $unwanted_header (qw(
				From To X-File X-Push_list_id To Cc Bcc Resent-bcc
				X-Database X-DB_Server Subject Received Delivered-To X-List
			)) {
				$header[$head_num] = undef if $current_header eq $unwanted_header;
			};
		};
	};

	my $return_header;
	foreach my $header (@header) {
		next unless $header;
		next if $header =~ /^\s*$/;
		$return_header .= "$header\n";
	};

	return $return_header;
};
	
sub get_list_members_from_file {
	my $self = shift;
	my $file = shift;
	my $glist = $self->glist();
	my @members;

	unless(-f $file) {
		$glist->fatal("Couldn't find $file.");
		return undef;
	};

	open(LIST, $file)
		|| $glist->fatal("Couldn't open $file: $!")
		&& return undef;
	while(<LIST>) {
		chomp;
		next if /^\s*$/;
		push(@members, $_);
	};
	close(LIST);

	return \@members;
};

############################################
# METHOD: sendmail($$$)
# DESCRIPTION:
#	Takes three arguments (but the object):
#
#	1. Reference to hash with header => header_content
#	2. Message body
#	3. The current message file we're working on
#
#	It then gathers all the e-mail addresses for that mailinglist
#	from the SQL database and sends the mail.'
#
#	* Instead of sending one and one mail to each recipient
#	  we use the BCC header.
#
#	* We split the list of recipients into pieces of 63 e-mail
#	  e-mail addresses each.
#
#	* Sleep 1 second through each mail to give the server
#	  some time to process
#	
sub sendmail {
	my $self = shift;	
	my $h = shift; 		# header
	my $body = shift;	# body
	my $file = shift;	# file
	my $all_headers = shift;# rest of the headers
	my $glist = $self->glist();
	my $q = $self->queue();

	my @sent_to;

	$all_headers = $self->remove_unwanted_headers($all_headers);

	# get relative header names.
	foreach my $h_name (keys %$h) {
		my $rel_name = $self->check_header($h_name);
		if($rel_name) {
			$h->{$rel_name} = $h->{$h_name};
			delete $h->{$h_name};
		}
	}

	# do we have all required headers?
	my @required_headers = qw(
		sender recipient subject
	);
	foreach my $required_header (@required_headers) {
		unless($h->{$required_header}) {
			$glist->log("File $file is missing required header: $required_header.");
			$glist->log("Dropping file $file. Please remove or fix manually.");
			return (undef, \@sent_to);
		};
	};

	unless($body) {
		$glist->log("File $file has no message body.");
		$glist->log("Dropping file $file. Please remove or fix manually.");
		return (undef, \@sent_to);
	};

	my $members;
	unless($h->{file}) {
		$members = $self->get_list_members($h->{db_server}, $h->{database}, $h->{push_list_id}, $h->{list})
			|| return (undef, \@sent_to);
	}
	else {
		$members = $self->get_list_members_from_file($h->{file})
			|| return (undef, \@sent_to);
	};	
		

	my $SIZE_OF_CHUNK = $Glist::SIZE_OF_CHUNK;
	my $SECONDS_TO_SLEEP = $Glist::SECONDS_TO_SLEEP;

	my $count = 0;
	my $chunks = scalar(@$members) / $SIZE_OF_CHUNK;
	CHUNK:
	for($count = 0; $count < $chunks; $count++) {
		my @spliced_chunk = splice(@$members, 0, $SIZE_OF_CHUNK);
		last CHUNK unless defined($spliced_chunk[0]);
		
		# #####Generate the message
		# This is done in this format:
		#
		# From: 	<sender@domain>
		# To:		<recipient@domain>
		# Resent-bcc:	<recipient2@domain>,
		# 		<recipient3@domain>,
		#		...,
		#		<recipientN@domain>
		# Subject: 	Message subject
		#
		# Message body
		#

		my $message  = sprintf("From: %s\n", $h->{sender});
		$message .= sprintf("To: %s\n", $h->{recipient});
		if($h->{carbon}) {
			$message .= sprintf("Cc: %s\n", $h->{carbon});
		};
		if($h->{resent_from}) {
			$message .= sprintf("Resent-bcc: %s\n", $self->print_bcc(\@spliced_chunk));
		}
		else {
			$message .= sprintf("Bcc: %s\n", $self->print_bcc(\@spliced_chunk));
		};
		$message .= sprintf("Subject: %s\n", $h->{subject});
		$message .= sprintf("%s", $all_headers);
		$message .= sprintf("\n");
		$message .= join("\n", @$body);

		unless($glist->no_action()) {
			my $sendmail = $self->sendmail_prog();
			open(SENDMAIL, "|$sendmail") 
				|| $glist->fatal("Cannot fork sendmail: $!")
				&& return (undef, \@sent_to);
			print SENDMAIL $message;
			close(SENDMAIL) || $glist->fatal("Warning: sendmail did not exit nicely.");
			push(@sent_to, @spliced_chunk);

			sleep $SECONDS_TO_SLEEP if($count > 1);
			if($q->is_ref($file) < 0) {
				$glist->error("Quit Sending. The file $file has been removed from the queue.");
				return (undef, \@sent_to);
			}
		};
		my $stripped_file = $file;
		$stripped_file =~ s%.*/%%;
		$glist->log(sprintf("Sent message (file: '%s') (sender: '%s') (chunk: %.6d)", 
			$stripped_file, 
			$h->{sender}, 
			$count)
		);
	};

	return (1, \@sent_to);

};

############################################
# METHOD: get_list_members($$$)
#
# DESCRIPTION:
#	Get the members of a given list
#
sub get_list_members($$$$) {
	my ($self, $server, $db, $push_list, $list) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $sendmail = $self->sendmail_prog();
	my $adm = $glist->Glist::Admin::new(
		sendmail	=>	$sendmail
	);

	unless($glist->use_sql()) {
		$glist->fatal("Not configured to handle SQL lists.\n");
		return undef;
	};

	my $pw_ent = $glist->get_pw_ent($server, $db)
		|| $glist->log($glist->error())
		&& return undef;
	my($db_server, $dbase, $user, $pw, $dbtype) = @$pw_ent;

	$pw = $adm->decrypt($pw);

	my ($dsn, $query, @members);
	use DBI;
	if($dbtype eq 'pgsql') {
		$dsn = "dbi:Pg:dbname=$db";
	}
	elsif($dbtype eq 'db2') {
		$dsn = "dbi:DB2:$db";
	}
	elsif($dbtype eq 'msql') {
		$dsn = "dbi:mSQL:database=$db:host=$db_server";
	}
	elsif($dbtype eq 'mysql') {
		$dsn = "dbi:mysql:database=$db:host=$db_server";
	}
	else {
		$glist->fatal("Unknown db type: $dbtype\n");
		return undef;
	};

	# Connect to database:
	my $dbh = DBI->connect(
		$dsn, $user, $pw, {
			PrintError=>0,
			RaiseError=>0,
		}
	) || $glist->log("Couldn't connect to db: $DBI::errstr")
	  && return undef;
	
	if(defined $config->{$list}{sql_query}) {
		if($config->{$list}{sql_query} =~ /\%s/) {
			$query = sprintf($config->{$list}{sql_query}, $push_list);
		}
		else {
			$query = $config->{$list}{sql_query};
		}
	}
	else {
		$query = sprintf("
			SELECT sendto FROM push_list_member 
				WHERE approved_member=1
				AND type=1
				AND push_list=%d
			ORDER BY id",
			$push_list
		);
	};

	my $sth = $dbh->prepare($query)
		|| $glist->log("Can't prepare SQL statement: $DBI::errstr")
		&& return undef;
	$sth->execute()
		|| $glist->log("Can't execute SQL statement: $DBI::errstr")
		&& return undef;

	while(my ($cur_member) = $sth->fetchrow_array()) {
		next unless $cur_member;
		push(@members, $cur_member);
	};
	
	$sth->finish();
	$dbh->disconnect() 
		|| $glist->log("Can't disconnect from db: $DBI::errstr")
		&& return undef;

	return \@members;

	return 1;
};

############################################
# METHOD: print_bcc(*)
#
# DESCRIPTION:
#	Print correctly formatted list
#	of addresses in a BCC field from reference to array.
#
sub print_bcc($$) {
	my $self = shift;
	my $r_chunk = shift;
	my $glist = $self->glist();

	my $formatted;
	for(my $elem = 0; $elem < scalar(@$r_chunk); $elem++) {
		$r_chunk->[$elem] =~ tr/<>//d; # s/(\<)|(\>)//g;
		$glist->log("(Send::print_bcc) Recipient: $r_chunk->[$elem]") if $glist->verbose();
		if($elem == (scalar(@$r_chunk) - 1)) {
			$formatted .= "\t<$r_chunk->[$elem]>\n";
		}
		elsif($elem == 0) {
			$formatted .= "<$r_chunk->[$elem]>, \n";
		}
		else {
			$formatted .= "\t<$r_chunk->[$elem]>, \n";
		};
	};
	chomp($formatted);
	return $formatted;
};

sub send_summary_on {
	my($self, $action, $list) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();

	$glist->log("Sending summary for $config->{$list}{send_summary_on}");

	if(defined $config->{$list}{send_summary_on}) {
		my %sso = map {$_ => 1} split /\s*,\s*/,
			$config->{$list}{send_summary_on};
		return 1 if $sso{all};
		foreach my $sso (keys %sso) {
			return 1 if $sso eq $action;
		}
	}
	return undef;
}

sub send_summary {
	my($self, $action, $file, $list, $ar_sent) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $sendmail = $self->sendmail_prog();

	$file =~ s%.*/%%;

	my $recipient = undef;
	if(defined $config->{$list}{send_summary_to}) {
		$recipient = $config->{$list}{send_summary_to};
	}
	elsif(defined $config->{$list}{owner}) {
		$recipient = $config->{$list}{owner};
	}
	else {
		$glist->log("Couldn't find a recipient for summaries on list $list");
		return undef;
	}

	my $hostname = $config->{global}{hostname};

	my $message = "";
	$message .= "From: Mailinglist daemon <glist\@$hostname>\n";
	$message .= "To: $recipient\n";
	$message .= "Subject: [$action] Message to $list summary\n";
	$message .= "\n";
	$message .= "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+\n";
	$message .= "|         Glist post summary        |\n";
	$message .= "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+\n";
	$message .= "\n";
	$message .= "The final status of the sending was: $action\n";
	$message .= "The message filename/id was: $file\n";
	$message .= "The destination list of the message was: $list\n";
	$message .= "The message was sent to the following recipients:\n";
	$message .= "\n";
	$message .= join "\n", sort @$ar_sent;
	$message .= "\n\n";
	$message .= "-- \n";
	$message .= "Please do not reply to this message.\n";

	open(SM, "|$sendmail") or $glist->error("Couldn't open sendmail: $!");
	print SM $message;
	close(SM);

	$glist->log("Sent summary for file $file to $recipient");
	
	return 1;
}	

1;
