#!/usr/bin/perl
use strict;

require "../lib/timed_run.pl";

open( INPUT, "< ../input/2b_tested.lst" ) or die $!;

my $distro = "";
my $arch = "64";

my $line;

while( $line = <INPUT> ){
	chomp($line);
	if( $line =~ /^([\d\.]+)\s+(.+)\s+(.+)\s+(\d+)\s+(.+)\s+\[([\w\s\d]+)\]/ ){
		$distro = $2;
		$arch = $4;
	};
};

close(INPUT);

my $output = "";
my $err_str = "";

my $last_m = "";

if( $distro eq "DEBIAN" || $distro eq "FEDORA" ){
	print "Distro $distro\n";
	print "Running ebstest_virtio.sh\n";

	my $toed;
	$toed = timed_run("./ebstest_virtio.sh", 900);		# 15 min deadline 

	$output = get_recent_outstr();
	$err_str = get_recent_errstr();

	print "\n################# STDOUT ##################\n";
        print $output . "\n";
        print "\n\n################# STDERR ##################\n";
        print $err_str . "\n";

	if( $toed ){
		print "ebstest_virtio.sh TIME-OUT !!\n";
		exit(1);
	};

	my @temp_arr = split( /\n/, $output );
	
	$last_m = @temp_arr[@temp_arr-1];
}else{
	print "Distro $distro\n";
        print "Running ebstest.sh \n";

	my $toed;
	$toed = timed_run("./ebstest.sh", 900);                # 15 min deadline

        $output = get_recent_outstr();
        $err_str = get_recent_errstr();

        print "\n################# STDOUT ##################\n";
        print $output . "\n";
        print "\n\n################# STDERR ##################\n";
        print $err_str . "\n";

        if( $toed ){
                print "ebstest.sh TIME-OUT !!\n";
                exit(1);
        };

        my @temp_arr = split( /\n/, $output );

        $last_m = @temp_arr[@temp_arr-1];	
};

if( $last_m =~ /Done/ ){
	print "Last Message : $last_m\n";
	print "EBS TEST has completed\n";
	exit(0);
}else{
	print "EBS TEST has FAILED !!\n";
	exit(1);
};

exit(1);

1;


