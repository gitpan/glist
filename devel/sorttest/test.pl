opendir DIR, ".";
my @files;
for(sort {$a <=> $b} readdir DIR) {
	push @files, $_ if -f $_;
}
print join(" ", @files), "\n";

closedir DIR;

