package Fatal::Sendmail;
# ### Fatal handler example.

use strict;

my $SENDMAIL = "/usr/sbin/sendmail";
my $RCPT = 'ask@unixmonks.net';

sub new { return bless { }, shift }

sub handler {
	my($self, $g) = @_;
	my $error = $g->error();
	open( SM, "|$SENDMAIL -t") or die("Couldn't open sendmail: $!\n");
	print SM "From: <error\@foo.bar>\n";
	print SM "To: <$RCPT>\n";
	print SM "Subject: Glist error!\n";
	print SM "\n";
	print SM "Error: $error\n";
	close SM or die("Couldn't close sendmail: $!");
	return 1;
};

1;
