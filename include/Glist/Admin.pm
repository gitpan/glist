#!/usr/bin/perl

=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*       Admin.pm
* PURPOSE
*       A set of functions, methods and accessors for subscribing,
*       unsubscribing etc by e-mail commands.
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

package Glist::Admin;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Glist;
use Fcntl qw(:flock);
use DB_File;
use Crypt::TripleDES;

@ISA = qw(Exporter);
@EXPORT = qw($VERSION);
@EXPORT_OK = qw($VERSION);
$VERSION = $Glist::VERSION;

# ######### CONSTRUCTORS      ######### #

# #######################################
# @name
# 	new
# @type
# 	constructor 	 
# @arguments
#	object: Glist
# 	hash: sendmail => '/path/to/sendmail'
# @description
#	Creates a new Glist::Admin object	
# @comment
#
# #######################################
sub new {
        my $glist = shift;
        my %argv = @_;
        my $obj = { };
        bless $obj, 'Glist::Admin';
        $obj->glist($glist);
	if($argv{sendmail}) {
		$obj->sendmail_prog($argv{sendmail});
	}
        return $obj;
};

# ######### ACCESSORS         ######### #

# #######################################
# @name
# 	glist
# @type
# 	accessor
# @arguments
#	object: Glist::Admin
# 	reference: Glist object
# @description
#	Shortcut to the Glist object.
# @comment
#
# #######################################
sub glist {
	my ($self, $glist) = @_;
	$self->{GLIST} = $glist if $glist;
	return $self->{GLIST};
};

# #######################################
# @name
# 	sendmail_prog
# @type
# 	accessor
# @arguments
#	object: Glist::Admin
#	string: Full path to the sendmail executable
# @description
#	Full path to the program we use to send mail
# @comment
#
# #######################################
sub sendmail_prog {
	my ($self, $sendmail) = @_;
        $self->{SENDMAIL} = $sendmail if $sendmail;
        return $self->{SENDMAIL};
};

# ######### METHODS           ######### #

# #######################################
# @name
# 	sendmail
# @type
# 	method
# @arguments
#	object: Glist::Admin
#	string: message to be sent
# @description
#	Send a message through $self->sendmail_prog();
# @comment
#	Will not do anything if no_action option set.
# #######################################
sub sendmail {
	my ($self, $message) = @_;
        my $glist = $self->glist();

        return undef unless $message;

        # do not send mail if no_action option set.
        unless(defined $glist->no_action) {
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


# #######################################
# @name
# 	error
# @type
# 	method
# @arguments
#	object: Glist::Admin
#	string: error message
#	array reference: 0: mailinglist 1: original sender 2: address
# @description
#	Send a message error message back to the sender
# @comment
#
# #######################################
sub error {
	my ($self, $msg, $arg) = @_;
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $request = $config->{global}{request};

	$glist->error("${$arg->[1]} for ${$arg->[2]} got error: $msg");


	my $message = <<"	EOF"
From: $request
To: ${$arg->[1]}
Subject: glist command error.

Hi,
this is the glist list manager at $hostname.

The command you requested returned the following error:
__________________________________________________________

$msg
__________________________________________________________

You can get help on glists mail administration commands by
sending a message to $request with the following text in the body, 

help

If you have forgotten your list password you can obtain this by
sending a message to $request with the following text in the body,

remind ${$arg->[1]}

-- 
Please do not reply to this message.

	EOF
	;

	$self->sendmail($message);
	return 1;
};

sub subscribe {
	my ($self, $addr, $list, $sender) = @_;
	my @argv = \($list, $addr, $sender);
	
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $request = $config->{global}{request};


	unless($config->{$list}{adm_by_mail} eq 'yes') {
		$self->error("Sorry. You cannot subscribe to this list (1: $list) by e-mail.", \@argv);
		return undef;
	};

	unless($glist->subscribe_allowed($sender, $list)) {
		$self->error("Sorry. You cannot subscribe to this list (2: $list) by e-mail.", \@argv);
		return undef;
	};

	my $sid = $self->set_session_id($addr, $list);

	my $message = <<"	EOF"
From: $request
To: $addr
Subject: [$list] Confirmation request

Hi,
this is the glist list manager at $hostname.

We have received your request for subscription to the $list mailing list.
To complete the subscription process you must reply to this message
with the following text in the body of the message:
______________________________________________________________________

auth $addr $sid <my-password> <my-password-confirmed> $list
______________________________________________________________________

This password will be the password for all the lists you
subscribe to here at $hostname.

If you already have a password you must enter this password.

If you dont specify any password, a random password will be
generated for you. You can fetch this later by issuing the
remind command.

NOTE: 
glist will not recognize commands after valid e-mail signatures.
(all text under the line '-- \\n').
If your signature is not valid you can stop all command processing 
with the command 'end'.

	EOF
	;

	$glist->log("$sender sent subscription request to $list for $addr");

	$self->sendmail($message);
	return 1;
};
	

sub auth {
	my $self = shift;
	my $addr = shift;
	my $sid = shift;
	my $passwd = shift;
	my $confirm = shift;
	my $list = shift;
	my $sender = shift;

	my @arg = \($list, $addr, $sender, $passwd, $confirm);

	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $request = $config->{global}{request};

	unless($config->{$list}{adm_by_mail} eq 'yes') {
		$self->error("Sorry. You cannot subscribe to this list by e-mail.", \@arg);
		return undef;
	};

	my $orig_sid = $self->get_session_id($addr, $list);

	unless($sid eq $orig_sid) {
		$self->error("Session ID does not match", \@arg);
		return undef;
	};

	if(!$passwd || !$confirm) {
		$self->error("Missing password.", \@arg);
		return undef;
	};

	if($passwd ne $confirm) {
		$self->error("Passwords does not match.", \@arg);
		return undef;
	};

	if($glist->is_list($list)) {
		if($config->{$list}{type} eq 'file') {
		
			my $existing_password = $self->get_password($addr);
			unless($existing_password) {	
				$self->set_password($addr, $passwd, \@arg)
					or return undef;
			}
			else {
				if($existing_password ne $passwd) {
					$self->error("Wrong password for $addr");
					return undef;
				};
			};
					
			my $file = $config->{$list}{file};
			unless($glist->file_check($file, FC_FILE, FC_READ)) {
				return undef;
			};
			open(LH, $file)
				|| $glist->fatal("Couldn't open list file $file: $!")
				&& return undef;
			while(<LH>) {
				chomp;
				if($_ eq $addr) {
					$self->error("Recipient $addr is already subscribed to $list.", \@arg);
					return undef;
				};
			};
			close(LH);

			unless($glist->file_check($file, FC_FILE, FC_WRITE)) {
				return undef;
			};
			open(LH, ">>$file")
				|| $glist->fatal("Couldn't open list file $file for writing: $!")
				&& return undef;
			flock(LH, LOCK_EX);
			print LH $addr, "\n";
			flock(LH, LOCK_UN);
			close LH;

			$glist->log("$addr subscribed to $list (auth sent by $sender)");
			
			my $message = << "			EOF"
From: $request
To: $addr
Subject: [$list] $addr subscribed

$addr was sucessfully added to $list

To unsubscribe send an e-mail to $request with
the text,
_________________________________________________

unsubscribe $addr $passwd $list
_________________________________________________

in the message body.

-- 
please do not reply to this message.

			EOF
			;

			$self->sendmail($message);

			if($config->{$list}{hello_file}) {
				my $hello_file = $config->{$list}{hello_file};
				if($glist->file_check($hello_file, FC_FILE, FC_READ, [FC_NOZERO])) {
					my $message = "From: $request\nTo: $addr\nSubject: Welcome to $list\n\n";
					open(HF, $hello_file)
						|| $glist->error("Couldn't open hello file $file: $!")
						&& return undef;
					while(<HF>) {
						$message .= $_;
					};
					close(HF);
					$self->sendmail($message);
				};
			};

			return 1;
		};
		$glist->log("$list: Admin.pm does not yet support sql based lists.");
	};

	return undef;
};

sub info {
	my ($self, $list, $sender) = @_;

	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $request = $config->{global}{request};

	my $message = "From: $request\nTo: $sender\nSubject: Info request\n\n";

	if($glist->file_check($config->{$list}{info}, FC_FILE, FC_READ, [FC_NOZERO])) {
		my $info = $config->{$list}{info};
		open(INFO, $info) 
			|| $glist->error("Couldn't open info: $!") 
			&& return undef;
		while(<INFO>) {
			$message .= $_;
		};
		close(INFO);
	}
	else {
		$message .= "Sorry no information on this list\n";
	};

	$glist->log("$sender sent info request for $list");

	$self->sendmail($message);

	return 1;
};

sub remind {
	my ($self, $addr, $sender) = @_;

	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $request = $config->{global}{request};

	$glist->log("$sender sent remind request for $addr");

	my @arg = \($addr, $sender);

	my $password = $self->get_password($addr);
	if($password) {
		my $message = <<"	EOF"
From: $request
To: $addr
Subject: Password reminder for $addr
		
Password for recipient $addr is: '$password'
(without the quotes)

Please delete this message.

	EOF
	;
		$self->sendmail($message);
	}
	else {
		$self->error("$addr is not a registred recipient.", \@arg);
		return undef;
	};

	return 1;
};	

sub disable {
	my ($self, $addr, $password, $list, $sender) = @_;

	my @arg = \($list, $addr, $sender);

	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $request = $config->{global}{request};

	if(!$password) {
		$self->error("Missing password.", \@arg);
		return undef;
	};

	my $existing_password = $self->get_password($addr);

	unless($password eq $existing_password) {
		$self->error("Password incorrect.", \@arg);
		return undef;
	};

	if($glist->is_list($list)) {
		if($config->{$list}{type} eq 'file') {
			my $file = $config->{$list}{file};

			unless($glist->file_check($file, FC_FILE, FC_READ, [FC_NOZERO])) {
				return undef;
			};
			
			my @file_contents;
			my $found = 0;
			open(LH, $file)
				|| $glist->fatal("Couldn't open file $file: $!")
				&& return undef;
			while(<LH>) {
				chomp;
				if(/^\s*$addr\s*$/) {
					push(@file_contents, "#DISABLED;$addr");
					$found = 1;
				}
				else {
					push(@file_contents, $_);
				};
			};
			close(LH);
			
			unless($found) {
				$self->error("$addr is not subscribed to $list", \@arg);
				return undef;
			};
			
			unless($glist->file_check($file, FC_FILE, FC_WRITE)) {
				return undef;
			};
			open(LH, ">$file")
				|| $glist->fatal("Couldn't open file $file: $!")
				&& return undef;
			flock(LH, LOCK_EX);
			print LH join("\n", @file_contents);
			flock(LH, LOCK_UN);
			close(LH);

			$glist->log("$addr disabled from $list (sent by $sender)");
			
			my $message = << "			EOF"
From: $request
To: $addr
Subject: [$list] $addr disabled

Sending of list $list to $addr is now disabled.

To reactivate, send this command back:

_________________________________________________

enable $addr $password $list
_________________________________________________

-- 
glist
			EOF
			;

			$self->sendmail($message);

			return 1;
		};
		$self->log("No such list: $list");
	};

	return undef;
};

sub enable {
	my ($self, $addr, $password, $list, $sender) = @_;

	my @arg = \($list, $addr, $sender);

	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $request = $config->{global}{request};

	if(!$password) {
		$self->error("Missing password.", \@arg);
		return undef;
	};

	my $existing_password = $self->get_password($addr);

	unless($password eq $existing_password) {
		$self->error("Password incorrect.", \@arg);
		return undef;
	};

	if($glist->is_list($list)) {
		if($config->{$list}{type} eq 'file') {
			my $file = $config->{$list}{file};

			unless($glist->file_check($file, FC_FILE, FC_READ, [FC_NOZERO])) {
				return undef;
			};
			
			my @file_contents;
			my $found = 0;
			open(LH, $file)
				|| $glist->fatal("Couldn't open file $file: $!")
				&& return undef;
			while(<LH>) {
				chomp;
				if(/^#DISABLED;$addr\s*$/) {
					push(@file_contents, "$addr");
					$found = 1;
				}
				else {
					push(@file_contents, $_);
				};
			};
			close(LH);
			
			unless($found) {
				$self->error("$addr is not subscribed to $list", \@arg);
				return undef;
			};
			
			unless($glist->file_check($file, FC_FILE, FC_WRITE)) {
				return undef;
			};
			open(LH, ">$file")
				|| $glist->fatal("Couldn't open file $file: $!")
				&& return undef;
			flock(LH, LOCK_EX);
			print LH join("\n", @file_contents);
			flock(LH, LOCK_UN);
			close(LH);

			$glist->log("$addr enabled to $list (sent by $sender)");
			
			my $message = << "			EOF"
From: $request
To: $addr
Subject: [$list] $addr enabled

Sending of list $list to $addr is now enabled.

To disable sending to this adress send this command back:

_________________________________________________

disable $addr $password $list
_________________________________________________

-- 
glist
			EOF
			;

			$self->sendmail($message);

			return 1;
		};
		$self->log("No such list: $list");
	};

	return undef;
};

sub unsubscribe {
	my ($self, $addr, $password, $list, $sender) = @_;

	my (@rcpt, $found);

	my @arg = \($list, $addr, $sender);
	
	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $hostname = $config->{global}{hostname};
	my $request = $config->{global}{request};

	unless($config->{$list}{adm_by_mail} eq 'yes') {
		$self->error("Sorry. You cannot unsubscribe from this list by mail.", \@arg);
		return undef;
	};

	if(!$password) {
		$self->error("Missing password.", \@arg);
		return undef;
	};

	my $existing_password = $self->get_password($addr);
	
	unless($password eq $existing_password) {
		$self->error("Password incorrect.", \@arg);
		return undef;
	};

	if($glist->is_list($list)) {
		if($config->{$list}{type} eq 'file') {
			my $file = $config->{$list}{file};

			unless($glist->file_check($file, FC_FILE, FC_READ, [FC_NOZERO])) {
				return undef;
			};

			open(LH, $file)
				|| $glist->fatal("Couldn't open file $file: $!")
				&& return undef;
			while(<LH>) {
				chomp;
				unless ($_ eq $addr) {
					push(@rcpt, $_);
				}
				else { 
					$found=1;
				};
			};
			close(LH);

			unless($found) {
				$self->error("$addr is not subscribed to $list", \@arg);
				return undef;
			};

			unless($glist->file_check($file, FC_FILE, FC_WRITE)) {
				return undef;
			};
			open(LH, ">$file")
				|| $glist->fatal("Couldn't open file $file: $!")
				&& return undef;
			flock(LH, LOCK_EX);
			print LH join("\n", @rcpt);
			flock(LH, LOCK_UN);
			close(LH);

			$glist->log("$addr unsubscribed from $list (sent by $sender)");

			my $message = << "			EOF"
From: $request
To: $addr
Subject: [$list] $addr unsubscribed

$addr was sucessfully unsubscribed from $list.

-- 
please do not reply to this message.
			EOF
			;

			$self->sendmail($message);

			return 1;
		};
	};

	return undef;
};

sub set_password {
	my ($self, $addr, $password) = @_;
	my $arg;

	my $glist = $self->glist();
	my $db = $glist->prefix() . '/var/run/user.db';

	unless($self->get_password($addr)) {
		unless($glist->file_check($db, FC_FILE, FC_WRITE, [FC_MBO])) {
			if(-f $db) {
				unlink $db or return undef;
			};
		};
		$password = $self->encrypt($password);
		open(DB, "+>>$db")
			|| $glist->fatal("Couln't open $db: $!")
			&& return undef;
		flock(DB, LOCK_EX);
		print DB "$addr:$password\n";
		flock(DB, LOCK_UN);
		close(DB);
		chmod(0600, $db);
	}
	else {
		$self->error("User already has a password set", $arg);
	};
	
};

sub set_session_id {
	my ($self, $addr, $list) = @_;

	my $glist = $self->glist();
	my $db = $glist->prefix() . '/var/run/session.db';
	my $id = $self->gen_session_id();

	dbmopen(my %session, $db, 0600)
		|| $glist->fatal("Couldn't open session db $db: $!")
		&& return undef;
	$session{"$addr:$list"} = $id;
	dbmclose(%session);

	return $id;
};

sub get_session_id {
	my ($self, $addr, $list) = @_;
	
	my $glist = $self->glist();
	my $db = $glist->prefix() . '/var/run/session.db';
	my $id;

	dbmopen(my %session, $db, 0600)
		|| $glist->fatal("Couldn't open session db $db: $!")
		&& return undef;
	$id = $session{"$addr:$list"};
	delete $session{$addr};
	dbmclose(%session);

	return $id;
};

sub salt {
	my $self = shift;
	my $glist = $self->glist();
	my $salt_file = $glist->prefix() . '/var/run/.salt';

	my $salt;

	if($glist->file_check($salt_file, FC_FILE, FC_READ, [FC_MBO, FC_NOZERO])) {
		open(SALT, $salt_file)
			|| $glist->fatal("Unable to open salt file $salt: $!")
			&& return undef;
		while(<SALT>) {
			chomp;
			s/^\s*//;
			s/\s*$//;
			$salt = $_;
			last;
		};
		close(SALT);
	};

	return $salt;
};

sub encrypt {
	my ($self, $text) = @_;
	my $des = new Crypt::TripleDES;
	my $ciphertext = $des->encrypt3($text, $self->salt());
	return unpack("H*", $ciphertext);
};

sub decrypt {
	my ($self, $ciphertext) = @_;
	my $des = new Crypt::TripleDES;
	$ciphertext = pack("H*", $ciphertext);
	$ciphertext = $des->decrypt3($ciphertext, $self->salt());
	$ciphertext =~ s/\s*//g;
	return $ciphertext;
};

sub get_password {
	my ($self, $addr) = @_;
	my $glist = $self->glist();

	my $db = $glist->prefix() . '/var/run/user.db';

	if($glist->file_check($db, FC_FILE, FC_READ, [FC_NOZERO])) {
		open(DB, $db)
			|| $glist->fatal("Couldn't open $db: $!")
			&& return undef;
		while(<DB>) {
			chomp;
			my ($username, $password) = split(':', $_);
			if($username eq $addr) {
				$password = $self->decrypt($password);
				return $password;
			};
		};
		close(DB);
	};

	return undef;
};

sub help {
	my ($self, $addr) = @_;

	my $glist = $self->glist();
	my $config = $glist->gconf();
	my $request = $config->{global}{request};
	my $hostname = $config->{global}{hostname};

	my $version = sprintf("%s", $Glist::VERSION);
	
	my $message = <<"	EOF"
From: $request
To: $addr
Subject: glist help

GLIST STATUS
	$hostname is running glist $version

BRIEF COMMAND INDEX

	subscribe   -	subscribe to mailinglist
	unsubscribe -	unsubscribe from mailinglist
	disable     -   disable sending to this adress
	enable      -   re-activate sending after a disable
	remind	    -	send forgotten password
	auth	    -   confirm subscription
	help        -	this message screen

DETAILED COMMAND INDEX

	* subscribe
		SYNOPSIS
			subscribe <recipient> <mailinglist>
		ARGUMENTS
			mailinglist        - the mailinglist to subscribe to
			recipient          - the recipient to receive mail to the list.
		EXAMPLE
			subscribe $addr mailinglist\@$hostname
	* unsubscribe
		SYNOPSIS
			unsubscribe <recipient> <password> <mailinglist>
		ARGUMENTS
			mailinglist       - the mailinglist to subscribe to
			recipient         - the recipient to receive mail to the list.
			password	  - password entered in auth when subscribing
		EXAMPLE
			unsubscribe $addr secretpassword mailinglist\@$hostname
	* disable
		SYNOPSIS
			disable <recipient> <password> <mailinglist>
		ARGUMENTS
			mailinglist       - the mailinglist to subscribe to
			recipient         - the recipient to receive mail to the list.
			password	  - password entered in auth when subscribing
		EXAMPLE
			disable $addr secretpassword mailinglist\@$hostname
	* enable
		SYNOPSIS
			enable <recipient> <password> <mailinglist>
		ARGUMENTS
			mailinglist       - the mailinglist to subscribe to
			recipient         - the recipient to receive mail to the list.
			password	  - password entered in auth when subscribing
		EXAMPLE
			enable $addr secretpassword mailinglist\@$hostname
			
	* remind
		SYNOPSIS
			remind <recipient>	
		ARGUMENTS
			recipient         - the recipient to receive mail to the list.
		EXAMPLE
			remind $addr
	* auth
		SYNOPSIS
			auth <recipient> <session-id> <password> <confirmed-password> <mailinglist>
		ARGUMENTS
			mailinglist       - the mailinglist to subscribe to
			session-id	  - ID received when you sent subscribe
			recipient         - the recipient to receive mail to the list.
			password	  - password entered in auth when subscribing
			confirmed-pass	  - the same password again.
		EXAMPLE
			auth $addr secretpassword secretpassword mailinglist\@$hostname

EOF

-- 
Please do not reply to this message.

	EOF
	;

	$glist->log("Sent help to $addr");

	$self->sendmail($message);

	return 1;
};

sub gen_session_id {
	my $mkpasswd = sub {
		my $pass;   # password
		my $count;  # current iteration

	        # Characters on the left side of the keyboard.
	        my $rl_left = [ qw(
	                    q Q w W e E r R t T
	                    y Y a A s S d D f F
	                    g G z Z x X c C v V
	                    1 2 3 4 5 6)        ];

		# Characters on the right side of the keyboard.
		my $rl_right = [ qw(
			u U i O o O p P h H
			j J k K l L b B n N
			m M 7 8 9 0)        ];

		PASSWORD:
		for($count = 0; $count < 300; $count++) {
			my $seen = { }; # anonymous local hash.
			srand;

			local $^W=0;
			$pass = join '', (0..9, 'A'..'Z', 'a'..'z')[
				rand 64, rand 64, rand 64, rand 64,
				rand 64, rand 64, rand 64, rand 64,
			];

			# must be 8 chars!
			next PASSWORD unless (length $pass == 8);

			my @chars = split('', $pass);
			CHAR: # Checks on each character of the string.
			foreach my $chr (@chars) {

			if  ( join('!', @$rl_left) =~ /!$chr!/ ) {
				$seen->{left}++;
			}
			elsif   (join('!', @$rl_right) =~ /!$chr!/) {
				$seen->{right}++;
			};

			if  ($chr =~ /^[A-Z]$/) {
				$seen->{uppercase}++;
			}
			elsif   ($chr =~ /^[a-z]$/) {
				$seen->{lowercase}++;
			}
			elsif   ($chr =~ /^[0-9]$/) {
				$seen->{digit}++;
			};

			# pick a new password if we've got
			# the same character twice.
			next PASSWORD if $seen->{"$chr"}++;
		};

		# Must have characters from both side of the keyboard.
		# (Yes! We do this below as well, but we need to check
		# if they are true so we don't get an illegal
		# division by zero!)
		next PASSWORD unless defined $seen->{left};
		next PASSWORD unless defined $seen->{right};

		# Must be about the same amount of characters
		# from the left side of the keyboard
		# as the right side of the keyboard
		next PASSWORD if ($seen->{left} / $seen->{right} <= 0.7);
		next PASSWORD if ($seen->{left} / $seen->{right} >= 1.4);

		# Must have at least two uppercase chars.
		next PASSWORD unless $seen->{uppercase} > 2;
		# Must have at least two lowercase chars.
		next PASSWORD unless $seen->{lowercase} > 2;
		# Must have at least one digit
		next PASSWORD unless $seen->{digit};

		# break the loop if all the checks went ok.
		last PASSWORD;
	};
	return $pass;
	};
	my $passwd;
        while(1) { last if $passwd=&$mkpasswd };
        return $passwd;
};

1;
