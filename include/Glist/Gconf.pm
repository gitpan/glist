#!/usr/bin/perl 

package Glist::Gconf;
use Glist;
use Carp;
use Socket;
use strict;

sub TIEHASH {
	my $self = shift;
	my $glist = shift;
	my $node = {};
	bless $node, $self;
	$node->glist($glist);
}

sub glist {
	my($self, $glist) = @_;
	$self->{GLIST} = $glist if $glist;
	return $self->{GLIST};
}
	

sub FETCH {
	my($self, $var) = @_;
	my $glist = $self->glist();
        unless(-S $glist->gc_socket()) {
                die("Config daemon not running? Exiting.\n");
        };
        socket(CLIENT, PF_UNIX, SOCK_DGRAM , 0);
        connect(CLIENT, sockaddr_un($glist->gc_socket()))
                || die("Couldn't connect to config daemon: $!\n");
        CLIENT->autoflush(1);
        $|++;

        printf STDERR ("name=gconf block=global key=%s\n",
                $var,
        );
	while(my $answer = <CLIENT>) {
		print "$answer\n";
	};

        return 1;

}


sub UNTIE {
	my $self = shift;
	return undef;
}


1;
