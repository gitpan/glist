#!/usr/bin/perl 
#:%!expand -t 4
###
 # Copyright (C) Ask Solem Hoel <ask@unixmonks.net>
 #
 #     This program is free software; you can redistribute it and/or modify
 #     it under the terms of the GNU General Public License as published by
 #     the Free Software Foundation; either version 2 of the License, or
 #     (at your option) any later version.
 #
 #     This program is distributed in the hope that it will be useful,
 #     but WITHOUT ANY WARRANTY; without even the implied warranty of
 #     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 #     GNU General Public License for more details.
 #
 #     You should have received a copy of the GNU General Public License
 #     along with this program; if not, write to the Free Software
 #     Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111, USA.
 ###

# ####################################
# Script: genbangpath.pl
#
# Author: Ask Solem Hoel <ask@unixmonks.net>
#
# Purpose: Generate #! line in top of file with given program.
#
use strict;

die("Usage: $0 /path/to/perl FILE1 FILE2 ... FILEn\n")
        unless @ARGV;
my $perl = shift @ARGV;
my $perlinterp = $perl;
$perlinterp =~ s/^\s*//;
$perlinterp =~ s/\s*$//;

if($perlinterp =~ /[\`\;\|\'\"]/) {
	die("Bad characters in perl interpreter.\n");
};

$perlinterp =~ s/\s+.+$//;
-x $perlinterp || die("Error: No perl interpreter at '$perl'!\n");

foreach my $file (@ARGV) {
	if($file =~ /[\`\;\|\'\"]/) {
		print STDERR("Bad chars in filename: $file\n");
		next;
	};
        if (-f $file) {
                print("Setting sheebang for file: $file\n");
                my @file_content;
                open(FH, $file) || die("Error with $file: $!\n");
                while(<FH>) {
                        chomp $_;
                        push(@file_content, $_);
                };
                close(FH) || die("Couldn't close $file: $!\n");
                if (($file_content[0] =~ /^\\\!/) || ($file_content[0] =~ /^\#\s*\!/)) {
                        $file_content[0] = "#!$perl";
                        my $bangpath = shift(@file_content);
                        open( FH, ">$file" ) || die("Couldn't open $file for writing!");
                                print FH "$bangpath\n";
                                print FH join("\n", @file_content), "\n";
                        close(FH) || die("Couldn't save $file: $!\n");
                }
        }
        else {
                warn("Warning: No such file '$file', not processed!\n");
        }
};

