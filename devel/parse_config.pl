sub get_config {
	my $self = shift;
	my $config = $self->config();

	my(	$type, 		# Current configuration entry type.
		$blockname, 	# Current block name (list blockname {)
		$in_block, 	# True if we're in a block.
		%config		# Final hash with configuration
	);
	open(CONFIG, $CONFIG)
		|| $self->error("Couldn't open config $config: $!")
		&& return undef;
	LINE:
	while(<CONFIG>) {
		# Chomp newline.
		chomp;
	
		# No blank lines
		next LINE if /^\s*$/;
		# No comments
		next LINE if /^\s*#/;

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
			elsif(/^\s*(.+?):\s*(.+?)\s*;\s*$/) {
				# ... parse the entry and store it's value.
				$config{$blockname}->{$1} = $2;
				# .. then go to the next line;
				next LINE;
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
		};
	};
	close(CONFIG) 
		|| $self->error("Couldn't close config $config. $!")
		&& return undef;

	foreach my $list (keys %config) {
		print $list, "\n";
		foreach my $config_key (keys %{$config{$list}}) {
			print "\t$config_key => $config{$list}->{$config_key}\n";
		};
	};

	return \%config;
};

