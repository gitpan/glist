#!/usr/bin/perl 

=comment
/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*	Glist.pm
* PURPOSE
*	Give a set of functions and objects for the glist daemon
*	suite to do it's work in a consistent way.
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

package Glist;

use strict;
use Exporter;
use Socket;
use Fcntl qw(:flock);
use IO::Handle;
use File::Copy;
use Version;
use Carp;
use less qw(memory CPU meat fat);

use vars qw(
	$DEFAULT_ATTACHMENT_SIZE_LIMIT
	$DEFAULT_DELETE_NON_TEXT_ATTACHMENTS
	$DEFAULT_SIZE_LIMIT 
	$SIZE_OF_CHUNK
	$SECONDS_TO_SLEEP
	$VERSION 
	$VERSIONINFO
	&FC_FILE
	&FC_DIR
	&FC_SYM
	&FC_FIFO
	&FC_READ
	&FC_WRITE
	&FC_EXEC
	&FC_MBO
	&FC_NOZERO
	&PRI_PROCESS
	&PRIORITY
	@EXPORT 
	@EXPORT_OK 
	%EXPORT_TAGS 
	@ISA 
);

# ----------- CONFIGURATION -------- #
# ### The user UID we run as.
  my $G_UID = '@@GLIST_UID@@';

# ### The group GID we run as
  my $G_GID = '@@GLIST_GID@@';

# ----------- CONSTANTS ------------ #

$VERSION = "0.9.17";	# Could you possibly guess?

# ### Default message size limit.
$DEFAULT_SIZE_LIMIT = 40960000;

# ### Default attachemnt size limit.
$DEFAULT_ATTACHMENT_SIZE_LIMIT = 2000; # 2mb

# ### Delete non-text attachments as default?
$DEFAULT_DELETE_NON_TEXT_ATTACHMENTS = 0;

# ### How many recipients for each mail sent.
$SIZE_OF_CHUNK = 64;

# ### How many seconds to sleep between each send.
$SECONDS_TO_SLEEP = 7;

# ### FILE TYPE CHECKS FOR file_check
sub FC_FILE 	{1};			# File is a file
sub FC_DIR	{2};			# File is a directory
sub FC_SYM	{3};			# File is a symlink
sub FC_FIFO	{4};			# File is a FIFO

# ### PERMISSION CHECKS FOR file_check()
sub FC_READ	{1};			# File is readable
sub FC_WRITE	{2};			# File is writeable
sub FC_EXEC	{3};			# File is executable

# ### SPECIAL CHECKS FOR file_check()
sub FC_MBO	{1};			# File is owned by EUID
sub FC_NOZERO	{2};			# File is not of zero length

# PRIO_PROCESS (as defined by the system c libraries)
sub PRI_PROCESS	{0};
# Process priority for our daemons.
sub PRIORITY	{5};

@ISA = qw(Exporter);

@EXPORT = qw(
	$VERSION $DEFAULT_SIZE_LIMIT $SIZE_OF_CHUNK $SECONDS_TO_SLEEP
	$DEFAULT_ATTACHMENT_SIZE_LIMIT $DEFAULT_DELETE_NON_TEXT_ATTACHMENTS
	FC_FILE FC_DIR FC_SYM FC_FIFO FC_READ FC_WRITE FC_EXEC FC_MBO FC_NOZERO
	PRI_PROCESS PRIORITY $VERSIONINFO
);

@EXPORT_OK = qw(
	$VERSION $DEFAULT_SIZE_LIMIT $SIZE_OF_CHUNK $SECONDS_TO_SLEEP
	$DEFAULT_ATTACHMENT_SIZE_LIMIT $DEFAULT_DELETE_NON_TEXT_ATTACHMENTS
	FC_FILE FC_DIR FC_SYM FC_FIFO FC_READ FC_WRITE FC_EXEC FC_MBO FC_NOZERO
	PRI_PROCESS PRIORITY $VERSIONINFO
);

%EXPORT_TAGS = ();

# ###############################
# CONSTRUCTOR: Glist new(hash arguments)
#
# DESCRIPTION:
#	Construct a new Glist object.
#
# ARGUMENTS:
#	The Glist object constructor takes an hash as arguments.
#	
#	Required arguments:
#		* prefix	- the prefix path of the program
#		* name		- the name to use in logging
#	
#	Optional arguments:
#		* verbose	- give verbose messages (1/0)
#		* use_sql	- use sql functions (1/0)
#		* no_action	- don't perform any actions (1/0)
#		* daemon	- tell us that we are running in daemon mode,
#				  thus do not print any messages to STDERR
#
sub new {
	my %argv = @_;
	my $obj = { };

	bless $obj, 'Glist';

	# ### Get prefix:
	if($argv{prefix}) {
		$obj->prefix( $argv{prefix} );
	}
	else {
		$obj->error("Missing prefix, please reconfigure script.");
	};

	# ### Give verbose messages?
	if($argv{verbose}) {
		$obj->verbose( $argv{verbose} );
	};

	# ### Don't perform any *possible* destructive actions?
	if($argv{no_action}) {
		$obj->no_action( $argv{no_action} );
	};
	
	# ### Are we running as a daemon?
	if($argv{daemon}) {
		$obj->daemon( $argv{daemon} );
	};

	# ### Our current name (for logging purposes)
	if($argv{name}) {
		$obj->name( $argv{name} );
	};

	# ### Do we have SQL support?
	if($argv{use_sql}) {
		$obj->use_sql($argv{use_sql});
	};

	# Should only get the configuration once!
	$obj->gconf($obj->get_config());

	my $version = Version->new($VERSION);
	$obj->version($version);

	return $obj;
} 

# ###############################
# ACCESSOR: hashref gconf(hashref gconf)
#
# DESCRIPTION
#	The configuration hash
#
sub gconf {
	my ($self, $gconf) = @_;
	if($gconf) {
		unless(ref $gconf) {
			$self->error("Internal error. \$gconf is not a reference!");
		}
		else {
			$self->{GCONF} = $gconf;
		};
	};
	return $self->{GCONF};
}

# ###############################
# ACCESSOR: string name(string name)
#
# DESCRIPTION:
#	The name to use in logging. (see Glist::Log)
#
sub name {
	my ($self, $name) = @_;
	$self->{NAME} = $name if $name;
	return $self->{NAME};
}

# ###############################
# ACCESSOR: Version version(Version version)
#
# DESCRIPTION:
#	Our version object
#
sub version{
	my ($self, $version) = @_;
	$self->{VERSION} = $version if $version;
	return $self->{VERSION};
}

############################################
# METHOD: string error(string errormsg)
#
# DESCRIPTION:
#       Set or get current error message.
#	Log errors to stderr or the logdaemon.
#
sub error {
	my($self, $error) = @_;
        if($error) {
                $self->{ERROR} = $error;

                # Log the error...
                $self->log($error);

                # ...and we should print our errors to stderr,
                # but not if we're in daemon mode.
                unless($self->daemon()) {
                        print STDERR $error, "\n";
                };
        };
        return $self->{ERROR};
}

sub warning {
	my($self, $warn) = @_;
	if($warn) {
		$self->{WARN} = $warn;
		$self->log($warn);
		unless($self->daemon()) {
			print STDERR $warn, "\n";
		}
	}
	return $self->{WARN};
}

############################################
# METHOD: bool fatal(string msg);
#
# DESCRIPTION:
#	Throw a fatal exception.
#	If a handler for this exception is defined,
#	execeute it with exec_handler.
#
sub fatal {
	my ($self, $fatal) = @_;
	my $config = $self->gconf();
	if($fatal) {
		$self->error($fatal);
		if(defined $config->{global}{fatal_handler}) {
			$self->exec_handler($config->{global}{fatal_handler}, $fatal);
		};
	};
	return 1;
}

############################################
# ACCESSOR: int daemon(bool daemon)
#
# DESCRIPTION:
#       Are we in daemon mode? (1/0)
#
sub daemon {
	my ($self, $daemon) = @_;
        if($daemon) {
                $self->{DAEMON} = 1;
        };
        return $self->{DAEMON};
}

############################################
# ACCESSOR: string prefix(string path)
#
# DESCRIPTION:
#       Set or get prefix path
#
sub prefix {
	my ($self, $prefix) = @_;
        if($prefix) {
                unless(-d $prefix) {
                        $self->error("Prefix $prefix is not a directory");
                        return undef;
                };
                $self->{PREFIX} = $prefix;
        };
        return $self->{PREFIX};
}

############################################
# METHOD: string spool(void)
#
# DESCRIPTION:
#       Get our mailspool directory
#
sub spool {
        my $self = shift;

        # $PREFIX/spool
        my $spool = $self->prefix() . '/' . 'spool';

        # Must be directory
        unless (-d $spool) {
                $self->fatal("(Glist::spool) No such directory: $spool");
                return undef;
        };

        $self->{SPOOL} = $spool;

        return $self->{SPOOL};
}

############################################
# METHOD: string outgoing(void)
#
# DESCRIPTION:
#       Get the outgoing spool dir.
#
sub outgoing {
        my $self = shift;
        my $outgoing = $self->spool() . '/' . 'outgoing';
	unless(-d $outgoing) {
		$self->fatal("(Glist::outgoing) Warning: No such directory: $outgoing");
	};
        return $outgoing;
}

############################################
# METHOD: string incoming(void)
#
# DESCRIPTION:
#	Get the incoming spool dir.
#
sub incoming {
	my $self = shift;
	my $incoming = $self->spool() . '/' . 'incoming';
	unless(-d $incoming) {
		$self->fatal("(Glist::incoming) Warning: No such directory: $incoming");
	};
	return $incoming;
}

############################################
# METHOD: string hold(void)
#
# DESCRIPTION:
#	Get the hold spool dir.
#
sub hold {
	my $self = shift;
	my $hold = $self->spool() . '/' . 'hold';
	unless(-d $hold) {
		$self->fatal("(Glist::hold) Warning: No such directory: $hold");
	};
	return $hold;
}

############################################
# METHOD: string deferred(void)
#
# DESCRIPTION:
#       Get the defferred dir.
#
sub deferred {
        my $self = shift;
        my $deferred = $self->spool() . '/' . 'deferred';
	unless(-d $deferred) {
		$self->fatal("(Glist::deferred) Warning: No such directory: $deferred");
	};
        return $deferred;
}

############################################
# METHOD: string send_spool(void)
#
# DESCRIPTION:
#       Get the send spool
sub send_spool {
        my $self = shift;
        my $send = $self->spool() . '/' . 'send';
	unless(-d $send) {
		$self->fatal("(Glist::send_spool) Warning: No such directory: $send");
	};
        return $send;
}

############################################
# METHOD: string rewrite_spool(void)
#
# DESCRIPTION:
#	Get the rewrite spool
#
sub rewrite_spool {
	my $self = shift;
	my $rewrite = $self->spool() . '/' . 'rewrite';
	unless(-d $rewrite) {
		$self->fatal("(Glist::rewrite_spool) Warning: No such directory: $rewrite");
	};
	return $rewrite;
}

############################################
# METHOD : string approveq(void)
#
# DESCRIPTION:
#	Get the approveq queue
#	XXX: Not yet implemented.
sub approveq {
	my $self = shift;
	my $approveq = $self->spool() . '/' . 'approveq';
	unless(-d $approveq) {
		$self->fatal("(Glist::approveq) Warninig: No such directory: $approveq");
	};
	return $approveq;
}
	
############################################
# METHOD: string logfile(void)
#
# DESCRIPTION:
#       Set or get logfile (really a directory)
#
sub logfile {
        my $self = shift;
        # $PREFIX/var/log/sendd
        my $logfile = $self->prefix() . '/' . 'var' . '/' . 'log' . '/' . 'glist';
        $self->{LOGFILE} = $logfile if $logfile;
        return $self->{LOGFILE};
}

############################################
# METHOD: string gl_socket(void)
#
# DESCRIPTION:
#	Get our logd socket file.
#
sub gl_socket {
	my $self = shift;
	my $socket = $self->prefix() . '/' . 'var' . '/' . 'run' . '/' . 'logd.sock';
	return $socket;
}

############################################
# METHOD: string gc_socket(void)
#
# DESCRIPTION:
#	Get our gconfd socket file.
#	XXX: Not yet implemented.
#
sub gc_socket {
	my $self = shift;
	my $socket = $self->prefix() . '/' . 'var' . '/' . 'run' . '/' . 'gconfd.sock';
	return $socket;
}

############################################
# ACCESSOR: int use_sql(bool use_sql)
#
# DESCRIPTION:
#	Sets wether we should include SQL support or not.
#
sub use_sql {
	my ($self, $use_sql) = @_;
	$self->{USE_SQL} = $use_sql if $use_sql;
	return $self->{USE_SQL};
}

############################################
# ACCESSOR: int verbose(bool verbose)
#
# DESCRIPTION:
#       Set or get verbose switch
#
sub verbose {
	my ($self, $verbose) = @_;
        if($verbose) {
                $self->{VERBOSE} = $verbose;
        };
        return $self->{VERBOSE};
}

############################################
# ACCESSOR: int no_action(bool no_action)
# 
# DESCRIPTION:
#       Set or get no_action switch
#
sub no_action {
	my ($self, $no_action) = @_;
        if($no_action) {
                $self->{NO_ACTION} = $no_action;
                $self->log("(Glist::no_action) Notice: Running in no action mode.");
        };
        return $self->{NO_ACTION};
}

############################################
# METHOD: string etc(void)
#
# DESCRIPTION:
#       Get configuration directory
#
sub etc {
        my $self = shift;
        my $etc = $self->prefix() . '/' . 'etc';

        # Must be directory
        unless(-d $etc) {
                $self->error("(Glist::etc) No such directory: $etc");
                return undef;
        };
        $self->{ETC} = $etc;

        return $self->{ETC};
}

############################################
# ACCESSOR: string tmp(void)
#
# DESCRIPTION:
#       Get the directory to store temporary files in.
#
sub tmp {
        my $self = shift;
        my $tmp = $self->prefix() . '/' . 'var' . '/' . 'run';

        # Must be directory
        unless(-d $tmp) {
                $self->fatal("(Glist::tmp) No such directory: $tmp");
                return undef;
        };
        # Must be writable
        unless(-w $tmp) {
                $self->fatal(sprintf("(Glist::tmp) %s is not writable by user %s",
                        $tmp,
                        getpwuid $> # $EUID
                ));
                return undef;
        };
        $self->{TMP} = $tmp;

        return $self->{TMP};
}

############################################
# METHOD: int log(string message)
#
# DESCRIPTION:
#       Log message to logfile
#
sub log {
	my ($self, $msg) = @_;

        $msg ||= 'Unexpected event';

	unless(-S $self->gl_socket()) {
		print STDOUT $msg, "\n";
		die("Log daemon not running? Exiting.\n");
	};
	socket(CLIENT, PF_UNIX, SOCK_DGRAM , 0);
	connect(CLIENT, sockaddr_un($self->gl_socket()))
		|| die("Couldn't connect to log daemon: $!\n");
	CLIENT->autoflush(1);
	$|++;

	printf CLIENT ("name=%s pid=%d message=%s\n",
		$self->name(),
		$$,
		$msg,
	);

        return 1;
}

############################################
# METHOD: int dead_logdaemon(void)
#
# DESCRIPTION
#	Check wether logdaemon is alive or not.
#
sub dead_logdaemon {
	my $self = shift;

	unless(-S $self->gl_socket()) {
		return "Unable to continue: Log daemon not running?";
	};
	socket(CLIENT, PF_UNIX, SOCK_DGRAM, 0);
	connect(CLIENT, sockaddr_un($self->gl_socket()))
		|| return "Unable to continue: Couldn't connect to log daemon: $!";

	return undef;
}

############################################
# METHOD: int dead_confdaemon(void)
#
# DESCRIPTION
#	Check wether gconfdaemon is alive or not.
#	XXX: Not yet implemented.
#
sub dead_confdaemon {
	my $self = shift;
	unless(-S $self->gc_socket()) {
		return "Unable to continue: Config daemon not running?";
	};
	socket(CLIENT, PF_UNIX, SOCK_DGRAM, 0);
	connect(CLIENT, sockaddr_un($self->gc_socket()))
		|| return "Unable to continue: Couldn't connect to config daemon: $!";

	return undef;
}

############################################
# METHOD: string passwd(void)
#
# DESCRIPTION:
#       Get the password file from the configuration directory.
#
sub passwd {
        my $self = shift;
        my $PASSWD = $self->etc() . "/" . "glist.passwd";

        # Sanity checks.
        unless(-f $PASSWD) {
                $self->fatal("Can't get password file: $PASSWD");
                return undef;
        };

        # Check for weak permissions.
        my ($dev, $ino, $mode) = stat $PASSWD;
        my $octal_mode = sprintf("%.4o", $mode);
        unless($octal_mode == 100600 || $octal_mode == 100400) {
                $self->fatal(sprintf("Error: %s is accessable by other than user %s.",
                        $PASSWD,
                        getpwuid $> # $EUID
                ));
                return undef;
        };

        $self->{PASSWD} = $PASSWD;
        return $self->{PASSWD};
}

############################################
# METHOD: string config(void)
#
# DESCRIPTION:
#	Get the glist configuration file.
#
sub config {
	my $self = shift;
	my $config = $self->etc() . "/" . "glist.config";

	unless(-f $config) {
		$self->error("Can't get configuration file: $config");
		return undef;
	};

	$self->{CONFIG} = $config;
	return $self->{CONFIG};
}

############################################
# METHOD: arrayref get_pw_ent(string server, string database)
#
# SYNOPSIS:
#       my (    $db_server,
#               $database,
#               $user,
#               $password,
#		$dbtype
#       ) = $self->get_pw_ent($server, $db) || return;
#
# DESCRIPTION:
#       Get the password file entry for a given server name and
#       database name.
#
sub get_pw_ent($$$) {
	my ($self, $server, $database) = @_;

	my $adm = $self->Glist::Admin::new();

	unless($self->file_check($self->passwd(), FC_FILE, FC_READ, [FC_MBO, FC_NOZERO])) {
		return undef;
	};

        open(PASSWD, $self->passwd())
                || $self->fatal(sprintf("Couldn't open passwd %s: %s", $self->passwd(), $!))
                && return undef;
	flock(PASSWD, LOCK_SH);
        while(<PASSWD>) {
                chomp;
                # ignore comments
                next if /^\s*#/;
		next if /^\s*\/\//;

                # fields are split by :
                my @fields = split(':', $_);
                if(($fields[0] eq $server) && ($fields[1] eq $database)) {
                        return \@fields;
                };
        };
	flock(PASSWD, LOCK_UN);
        close(PASSWD);

        $self->fatal("Couldn't get password entry for server: $server and db: $database");
        return undef;
}

############################################
# METHOD: arrayref get_spool_files(string spool_dir)
#
# DESCRIPTION:
#       Returns list of files in the mail spool.
#
sub get_spool_files {
	my($self, $spool) = @_;
        my $files = ( ); # anonymous array

	unless($self->file_check($spool, FC_DIR, FC_WRITE, [FC_MBO])) {
		return undef;
	};

        opendir SPOOL, $spool
                || $self->fatal(sprintf("Couldn't open spool %s: %s!", $spool, $!))
                && return undef;
	for(sort {$a <=> $b} readdir SPOOL) {
		my $cf = sprintf "%s/%s", $spool, $_;
		push @$files, $cf if -f $cf;
	}
	closedir SPOOL;
        return $files;
}

############################################
# METHOD: string move_to_newspool(string file, string spool)
#
# DESCRIPTION:
#	Move a file to a new spool.
#	Returns the new filename.
#
sub move_to_newspool {
	my ($self, $file, $spool) = @_;
	unless(-d $spool) {
		$self->fatal("No such spool: $spool !");
		return undef;
	}
	my $new_file = $file;
	$new_file =~ s%.*/%%;
	$new_file = $spool . '/' . $new_file;
	$new_file = $self->rename_if_file_exists($new_file);
	move($file, $new_file)
		|| $self->fatal("Couldn't move file $file: $!")
		&& return undef;
	$self->log("(Glist::move_to_newspool) Moved to $spool: $file => $new_file") if $self->verbose();
	return $new_file;
};

############################################
# METHOD: int remove_from_spool(string file)
#
# DESCRIPTION:
#       Remove a given filename from the mail spool
#
sub remove_from_spool {
	my($self, $file) = @_;
        unlink $file || $self->log("Couldn't unlink file: $file: $!");
        $self->log("(Glist::remove_from_spool) Removed: $file") if $self->verbose();
        return 1;
};

############################################
# METHOD: hashref get_config(string config);
#
# DESCRIPTION:
#	Parse and read configuration from the 
#	configuration file(s) and return reference
#	to hash with configuration.
#
sub get_config {
	my ($self, $config) = @_;

	$config ||= $self->config();

	my(	$type, 		# Current configuration entry type.
		$blockname, 	# Current block name (list blockname {)
		$in_block, 	# True if we're in a block.
		%config,	# Final hash with configuration
		%alias		# Aliases to existing lists
	);
	unless($self->file_check($config, FC_FILE, FC_READ, [FC_MBO, FC_NOZERO])) {
		return undef;
	};

	open(CONFIG, $config)
		|| $self->error("Couldn't open config $config: $!")
		&& return undef;
	flock(CONFIG, LOCK_SH);
	LINE:
	while(<CONFIG>) {
		# Chomp newline.
		chomp;
	
		# No blank lines
		next LINE if /^\s*$/;
		# No comments
		next LINE if /^\s*#/;
		next LINE if /^\s*\/\//;

		# Optimize
		study;

		# If we're in a block ({ .. })....
		if($in_block) {
			# ... and if we're ending it;
			if(/^\s*};?\s*$/) {
				# end the block...
				$in_block = undef;
				$blockname = undef;
				# ... and go to the next line
				next LINE;
			} # But if we got a configuration entry
			elsif(/^\s*(.+?)\s+(.+?)\s*$/) {
				my $key = $1;
				my $value = $2;
				next LINE if(length $key > 63);
				next LINE if(length $value > 254);
				next LINE unless($key =~ /^[\w\d\_\-]+$/);
				next LINE if($value =~ /[\|\(\)\$\;\`\'\"]/);
				if($key eq 'include' || $key eq 'require') {
					if(-f $value) {
						open(INCLUDE, $value) || next LINE;
						INC:
						while(<INCLUDE>) {
							chomp;
							next LINE if /^\s*#/;
							next LINE if /^\s*\/\//;
							next LINE if /^\s*$/;
							if(/^\s*(.+?)\s+(.+?)\s*$/) {
								my $inc_key = $1;
								my $inc_value = $2;
								next LINE if(length $inc_key > 63);
								next LINE if(length $inc_value > 254);
								next LINE unless($inc_key =~ /^[\w\d\_\-]+$/);
								next LINE if($inc_value =~ /[\|\(\)\$\;\`\'\"]/);
								$config{$blockname}->{$inc_key} = $inc_value;
								next INC;
							};
						};
						close(INCLUDE);
					};
				}
				else {
					# ... parse the entry and store it's value.
					$config{$blockname}->{$key} = $value;
					# .. then go to the next line;
					next LINE;
				};
			};
		}
		# Wait until we get a configuration block...
		elsif(/^\s*list\s+(.+?)\s+{\s*$/) {
			# Then defined the block and start parsing it's value;
			$type = 'list';
			$blockname = $1;
			# Don't want duplicate configuration keys.
			next if ($config{$blockname});
			$in_block = 1;
			next LINE;
		}
		elsif(/^\s*alias\s+(.+?)\s+(.+?)\s*$/) {
			$alias{$1} = $2;
		};
	};
	flock(CONFIG, LOCK_UN);
	close(CONFIG) 
		|| $self->error("Couldn't close config $config. $!")
		&& return undef;

	# Should be able to lookup by sender as well.
	LISTALIAS:
	foreach my $list (keys %config) {
		next LISTALIAS unless $list;
		next LISTALIAS unless $config{$list};
		next LISTALIAS unless $config{$list}{sender};
		$config{$config{$list}{sender}} = $config{$list};
	};

	# Create aliases
	foreach my $alias_name (keys %alias) {
		foreach my $configkey (keys %{$config{$alias{$alias_name}}}) {
			$config{$alias_name}{$configkey} = $config{$alias{$alias_name}}{$configkey};
		};
	};

	return \%config;
}

sub rewrite_with_error {
	my $self = shift;
	my $file = shift;
	my $error = shift;
	my $mailinglist = shift;
	my $sender = shift;

	my $in_header = 1;
	my @header;
	my @body;

	unless($self->file_check($file, FC_FILE, FC_WRITE)) {
		return undef;
	};

	open(FILE, $file)
		|| $self->fatal("Couldn't open $file: $!")
		&& return undef;
	flock(FILE, LOCK_EX);
	while(<FILE>) {
		if($in_header) {
			if(/^$/) {
				$in_header = 0;
			}
			else {
				push(@header, $_);
			};
		}
		else {
			push(@body, $_);
		};
	};
	flock(FILE, LOCK_UN);
	close(FILE);
	
	push(@header, "X-GL-Error: $error\n");
	push(@header, "X-Mailinglist: $mailinglist\n");
	push(@header, "X-Original-Sender: $sender\n");

	my $message = sprintf("%s\n%s",
		join('', @header),
		join('', @body)
	);

	open(FILE, ">$file")
		|| $self->fatal("Couldn't open $file for writing: $!")
		&& return undef;
	flock(FILE, LOCK_EX);
	print FILE $message;
	flock(FILE, LOCK_UN);
	close(FILE)
		|| $self->fatal("Couldn't close $file: $!")
		&& return undef;

	return 1;
};

sub is_list {
	my $self = shift;
	my $list = shift;

	my $config = $self->gconf();

	if(ref($config->{$list})) {
		return 1;
	}
	else {
		return undef;
	};
};

sub size_ok {
	my $self = shift;
	my $file = shift;
	my $list = shift;
	my $message_size = 0;
	my $size_limit = $DEFAULT_SIZE_LIMIT;
	
	my $config = $self->gconf();

	if(defined($config->{$list}{size_limit})) {
		$size_limit = $config->{$list}{size_limit};
	};

	
	my $in_body = 0;
	unless($self->file_check($file, FC_FILE, FC_READ)) {
		return undef;
	};

	open(FILE, $file)
		|| $self->fatal("Couldn't open $file: $!")
		&& return undef;
	while(<FILE>) {
		chomp;
		if($in_body) {
			$message_size += length($_);
		}
		else {
			$in_body = 1 if /^$/;
		};
	};
	close(FILE);

	($message_size > $size_limit) ? (return undef) : (return 1);
};

sub rename_if_file_exists {
	my $self = shift;
	my $file = shift;

	while(-f $file) {
		$self->log("Filename $file already exists, renaming...");
		$file = $file.$$++;
	};

	return $file;
};

sub subscribe_allowed {
	my $self = shift;
	my $address = shift;
	my $list = shift;

	my $config = $self->gconf();

	if(defined($config->{$list}{allow_subscribe})) {
		ADDRESS:
		foreach my $sub_addr (split(/\s*,\s*/, $config->{$list}{allow_subscribe})) {
			$sub_addr = quotemeta $sub_addr;
			if($sub_addr =~ /^file::(.+?)$/) {
				my $sub_file = $1;

				if($self->file_check($sub_file, FC_FILE, FC_READ, [FC_NOZERO])) {
					open(BL, $sub_file) 
					  or $self->error("Warning: Couldn't open allow_subscribe file $sub_file for $list: $!")
					  and next ADDRESS;
					while(<BL>) {
						chomp;
						next if /^\s*#/;
						next if /^\s*\/\//;
						next if /^\s*$/;
						$_ = quotemeta $_;
						$_ = lc $_; # not case-sensitive
						return 1 if $address =~ /$_/;
					};
					close(BL);
				}
				else {
					$self->error("Warning: No such allow_subscribe file for list $list: $sub_file");
				};
			}
			else {
				return 1 if ($address =~ /$sub_addr/i);
			};
		};
		return undef;
	};
	# ### 
	# return true anyway if allow_subscribe
	# was not configured for this list.
	return 1;
};

sub in_blacklist {
	my $self = shift;
	my $address = shift;
	my $list = shift;

	my $config = $self->gconf();
	
	if(defined($config->{$list}{blacklist})) {
		ADDRESS:
		foreach my $bl_addr (split(/\s*,\s*/, $config->{$list}{blacklist})) {
			$bl_addr = quotemeta($bl_addr);
			if($bl_addr =~ /^file::(.+?)$/) {
				my $bl_file = $1;
				if($self->file_check($bl_file, FC_FILE, FC_READ, [FC_NOZERO])) {
					open(BL, $bl_file)
						|| $self->error("Warning: Couldn't open blacklist $bl_file for $list: $!")
						&& next ADDRESS;
					while(<BL>) {
						chomp;
						next if /^\s*#/;
						next if /^\s*\/\//;
						next if /^\s*$/;
						$_ = quotemeta($_);
						$_ = lc $_; # not case-sensitive.
						return 1 if ($address =~ /$_/);
					};
					close(BL);
				}
				else {
					$self->error("Warning: No such blacklist file for list $list: $bl_file");
				};
			}
			else {
				return 1 if ($address =~ /$bl_addr/i);
			};
		};
	};
		
	return undef;
};

sub get_header {
	my $self = shift;
	my $list = shift;
	my $header;

	my $config = $self->gconf();

	if(defined($config->{$list}{header})) {
		if($self->file_check($config->{$list}{header}, FC_FILE, FC_READ)) {
			open(HEADER, $config->{$list}{header})
				|| $self->error("Couldn't open header file for list $list: $header")
				&& return undef;
			while(<HEADER>) {
				$header .= $_;
			};
			close(HEADER);
			return $header;
		}
		else {
			$self->error("Warning: No such header file for list $list: $header");
		};
	};

	return undef;
};

sub get_footer {
	my $self = shift;
	my $list = shift;
	my $footer ;

	my $config = $self->gconf();

	if(defined($config->{$list}{footer})) {
		if($self->file_check($config->{$list}{footer}, FC_FILE, FC_READ)) {
			open(FOOTER, $config->{$list}{footer})
				|| $self->error("Couldn't open footer file for list $list: $footer")
				&& return undef;
			while(<FOOTER>) {
				$footer .= $_;
			};
			close(FOOTER);
			return $footer;
		}
		else {
			$self->error("Warning: No such footer file for list $list: $footer");
		};
	};

	return undef;
};

sub file_check {
	my $self = shift;
	my $file = shift;
	my $type = shift;
	my $perm = shift;
	my $special = shift;

	my $username = [getpwuid($>)]->[0];

	$type ||= FC_FILE;
	$perm ||= FC_READ;

	if(ref($special)) {
		foreach my $flag (@$special) {
			if($flag == FC_MBO) {
				#unless(-o $file) {
				#	$self->error("file_check error: $file is not owned by $username");
				#	return undef;
				#};
			}
			elsif($flag == FC_NOZERO) {
				if(-z $file) {
					$self->error("file_check warning: $file has zero size");
					return undef;
				};
			};
		};
	};

	unless(-r $file) {
		$self->error("file_check error: $file is not readable by $username");
		return undef;
	};

	if($perm == FC_WRITE) {
		unless(-w $file) {
			$self->error("file_check error: $file is not writable by $username");
			return undef;
		};
	};
	
	if($perm == FC_EXEC) {
		unless(-x $file) {
			$self->error("file_check error: $file is not executable by $username");
			return undef;
		};
	};

	if(-d $file) {
		unless($type == FC_DIR) {
			$self->error("file_check error: $file is a directory");
			return undef;
		};
	}
	elsif(-l $file) {
		unless($type == FC_SYM) {
			$self->error("file_check error: $file is a symbolic link");
			return undef;
		};
	}
	elsif(-p $file) {
		unless($type == FC_FIFO) {
			$self->error("file_check error: $file is a named pipe");
			return undef;
		};
	}
	elsif(-S $file) {
		unless($type == FC_FIFO) {
			$self->error("file_check error: $file is a socket");
			return undef;
		};
	}
	elsif(-b $file || -c $file || -t $file || -k $file) {	
		$self->error("file_check error: $file is a special file");
	};

	return 1;
};	
	
sub check_attachments {
	my $self = shift;		# glist object
	my $file = shift;		# message file
	my $list = shift;		# message destination (mailinglist)

	my $config = $self->gconf();	# glist configuration

	my $in_header = 1;		# are we in the header of the message?
	my $boundary = undef;		# name of the message boundary
	my $attachment_count = 0;	# number of attachments in message
	my %non_text_att;		# hash with attachments not of type text
	my $in_content_type = 0;	# are we in a content-type header?
	my $in_att_header = 0;		# are we in an attachments header?
	my $in_att_body = 0;		# are we in an attachments body?`
	my $curr_not_valid = 0;		# is the current attachment not a valid one?
	my @header;			# array with headers
	my %attachments;		# hash with attachments
	my $message;			# whole message
	my $no_attachments = 0;		# the message has no attachments?

	my $max_size = $DEFAULT_ATTACHMENT_SIZE_LIMIT;
	my $delete_non_text = $DEFAULT_DELETE_NON_TEXT_ATTACHMENTS;

	if(defined($config->{$list}{attachment_size_limit})) {
		$max_size = $config->{$list}{attachment_size_limit};
	};

	if(defined($config->{$list}{allow_attachments})) {
		if($config->{$list}{allow_attachments} eq 'yes') {
			$delete_non_text = 0;
		}
		elsif($config->{$list}{allow_attachments} eq 'no') {
			$delete_non_text = 1;
		};
	};

	open(MSG, $file)
		|| $self->fatal("Couldn't open message $file: $!")
		&& return undef;
	flock(MSG, LOCK_EX);
	while(<MSG>) {
		chomp;
		if($in_header) {
			push(@header, $_);
			if(/^$/) {
				$in_header = 0;
			}
			elsif(/^Content-Type:\s*/i) {
				$in_content_type = 1;
				if(/^Content-Type:.*?boundary="(.+?)".*?$/i) {
					$boundary = $1;
					$self->log("Message has boundary: $boundary");
					$in_content_type = 0;
				}
			}
			elsif($in_content_type) {
				$self->log("$_");
				if(/^\s+/) {
					if(/^\s+.*?boundary="(.+?)".*?$/) {
						$boundary = $1;
						$self->log("Message has boundary: $boundary");
					}
					else {
						$no_attachments = 1;
					}		
				}
				else {
					$no_attachments = 1;
				}
				$in_content_type = 0;
			}
		}
		else {
			last unless $boundary;
			last if ($_ eq "--$boundary--");
			if($_ eq "--$boundary") {
				$attachment_count++;
				push(@{$attachments{$attachment_count}}, "\n");
				$in_att_body = 0;
				$in_att_header = 1;
				$curr_not_valid = 0;
			}
			elsif($in_att_header == 1) {
				if(/^$/) {
					$in_att_header = 0;
					$in_att_body = 1;
				}
				else {
					if(/Content-type:\s+/i) {
						/^Content-type:\s+(.+?)(;|\s+|$)/i;
						my $c_con_type = $1;
						$self->log("Attachment #$attachment_count: Content-type: $c_con_type");
						unless($self->check_content_type($c_con_type, $list)) {
							$curr_not_valid = 1;
						};
						if($self->check_content_deny($c_con_type, $list)) {
							$curr_not_valid = 1;
						};
					};
				};
			}
			elsif($in_att_body == 1) {
				if($curr_not_valid) {
					$non_text_att{$attachment_count} += length;
				};
			};	
			push(@{$attachments{$attachment_count}}, $_);
		};
	};
	flock(MSG, LOCK_UN);
	close(MSG);

	$no_attachments = 1 unless $boundary;
	return 1 if $no_attachments;

	foreach my $att_no (keys %non_text_att) {
		$non_text_att{$att_no} = sprintf("%.4f", $non_text_att{$att_no} / 1024);
		if($non_text_att{$att_no} > $max_size) {
			$self->error("Attachment #$att_no in file $file exceeds maximum size. Deleted");
			#delete $attachments{$att_no};
			$attachments{$att_no} = [
				"",
				"--$boundary",
				"Content-Type: text/plain",
				"",
				"[Attachment deleted because it exceeds maximum size limit.]",
				"",
			];
		}
		elsif($delete_non_text == 1) {
			$self->error("Attachment #$att_no in file $file is deleted.");
			$attachments{$att_no} = [
				"",
				"--$boundary",
				"Content-Type: text/plain",
				"",
				"[Deleted attachment because of illegal content-type.]",
				"",
			];
		};
	};

	$message = join("\n", @header);
	$message .= "\n";
	foreach my $att_no (sort { $a <=> $b } keys %attachments) {
		next unless $att_no;
		$message .= join("\n", @{$attachments{$att_no}});
	};
	$message .= "\n--$boundary--\n\n";

	open(MSG, ">$file")
		|| $self->fatal("Couldn't open message $file for writing: $!")
		&& return undef;
	flock(MSG, LOCK_EX);
	print MSG $message;
	flock(MSG, LOCK_UN);
	close(MSG);

	return 1;
};

sub need_approve_sub {
	my($self, $list, $need_approve_sub) = @_;

	if($need_approve_sub && $list) {
		$self->{NEED_APPROVE_SUB}{$list} = 1;
	}
	else {
		return undef unless $list;
		return $self->{NEED_APPROVE_SUB}{$list};
	};
};
	
sub need_approve_posts {
	my($self, $list, $need_approve_posts) = @_;

	if($need_approve_posts && $list) {
		$self->{NEED_APPROVE_POSTS}{$list} = 1;
	}
	else {
		return undef unless $list;
		return $self->{NEED_APPROVE_POSTS}{$list};
	};
};

sub check_content_deny {
	my($self, $type, $list) = @_;
	my $config = $self->gconf();
	my $not_valid = 0;

	$type = lc $type;

	if(defined $config->{$list}{content_deny}) {
		foreach my $check (split(/\s*,\s*/, $config->{$list}{content_deny})) {
			$check = lc $check;
			$check = quotemeta $check;
			if($type =~ /$check/) {
				$not_valid = 1;
				last;
			};
		};
		if($not_valid) {
			return 1;
		}
		else {
			return undef;
		};
	};
};

sub check_content_type {
	my($self, $type, $list) = @_;
	my $config = $self->gconf();
	my $valid = 0;

	$type = lc $type;

	if(defined $config->{$list}{content_checks}) {
		foreach my $check (split(/\s*,\s*/, $config->{$list}{content_checks})) {
			$check = lc($check);
			$check = quotemeta $check;
			if($type =~ /$check/) {
				$valid = 1;
				last;
			};
		};
		if($valid) {
			return 1;
		}
		else {
			return undef;
		};
	}
	else {
		unless($self->ok_content_type($type)) {
			return undef;
		};
		return 1;
	};
};

sub ok_content_type {
	my($self, $content_type) = @_;

	my %valid_types = (
		'text/plain'			=> 1,
		'message/rfc822' 		=> 1,
		'message/rfc822-headers' 	=> 1,
		'multipart/mixed'		=> 1,
		'multipart/alternative'		=> 1,
	);

	return 1
	  if $valid_types{$content_type};
};

sub exec_handler {
	my($self, $module, @args) = @_;

	eval ("
		use $module;
		my \$obj = $module->new();
		\$obj->handler(\$self, \@args);
	");
	if($@) {
		$self->error("Error in handler $module: $@");
		return undef;
	}
	return 1;
};

sub parsemail {
	# ### Take file as argument.
	my($self, $file) = @_;
	my(	@header, 	# array with headers.
		@body, 		# array with body lines
		$in_body, 	# we're finished with header section and
				# in the body.
		$locked_to,	# $locked_to_recipient.
		$ch,		# $current header data.
		$ic,		# in a header comment (1++/0)
		%h,		# final header hash.
		$t,		# to set $w to an undefined variable.
	);

	# ### This is a list of headers used when processing a message.
	# The key is the name of the header in all lowercase, and the value is the name
        # with the correct case that we should use for processing later.
        # All header names in this list will be translated to the value with
        # the correct case.

        my %headers_used = (
                to              => 'To',
                cc              => 'Cc',
                from            => 'From',
                subject         => 'Subject',
                precedence      => 'Precedence',
                "x-loop"        => 'X-Loop',
                "x-list"        => 'X-List',
                "content-type"  => 'Content-Type',
                "reply-to"      => 'Reply-To',
        );

	open(MAIL, $file) || return -1;
	LINE:
	for(my $linecount = 0; <MAIL>; $linecount++) {
		chomp;
                # ### Check if we got a locked recipient from gfetch.
                # A line starting with --:# at the first line in the file
                # shows this.
                if($linecount == 0) {
                        if(/--:#(.+?)\s*$/) {
                                $locked_to = $1;
				next LINE;
                        };
                }
		# ### header section is over. mmm, body,
		elsif($in_body) {
			push @body, $_; next LINE;
		}
		else {
			# ### header section is over if hit an empty line.
			($in_body = 1, next LINE) unless length;
			my $ch; # current header

			# ### 
			# get rid of the header comments,
			# the Subject header can have "(" + ")", though.
			if(lc $_ !~ /^subject:/) {
				foreach(split//) {
					$ic++ if $_ eq '(';
					$ch .= $_ unless $ic;
					$ic-- if $_ eq ')';
				};
			}
			else {
				$ch = $_;
			};
			
			# ###
			# if this is a wrapped line (starts with whitespace)
			# concatenate it to the last element in the list.
			my $prev_line = scalar(@header) - 1;
			if($ch =~ /^\s+/ && $linecount != 0 && defined $header[$prev_line]) {
				$ch =~ s/^\s+//;
				$header[$prev_line] .= $ch;
				next LINE;
			};
			push(@header, $ch);
		};
	};
	close(MAIL);

	# ###
	# assemble the header. split them all by : into a fresh hash.
	foreach(@header) {
		next unless /^[a-zA-Z0-9_-]+:/;
		my($key, $value) = split(/:\s*/, $_, 2);
		if(defined $headers_used{ lc $key }) {
	                $key = $headers_used{ lc $key };
		};
		$h{$key} = $value;
	};

	# ###
	# we return a reference to a list with references to
	# header hash and body array.
	return [ \%h, \@body, \$locked_to ];
};

1;
