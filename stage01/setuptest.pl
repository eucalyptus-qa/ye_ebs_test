#!/usr/bin/perl

open (STDERR, ">&STDOUT");

$ec2timeout = 20;
$mode = shift @ARGV;

if( $mode eq "" ){
        my $this_mode = `cat ../input/2b_tested.lst | grep NETWORK`;
        chomp($this_mode);
        if( $this_mode =~ /^NETWORK\s+(\S+)/ ){
                $mode = lc($1);
        };
};

print "Mode:\t$mode \n\n";

if ($mode eq "system" || $mode eq "static") {
    $managed = 0;
} else {
    $managed = 1;
}
#set up some keys
$numkeys = int(rand(2)+1);
print "adding '$numkeys' keys\n";
for ($i=0; $i<$numkeys; $i++) {
    print "\tadding key $mykey$i...\n";
    system("date");
$cmd = "runat $ec2timeout ec2-add-keypair mykey$i | grep -v KEYPAIR > mykey$i.priv";
    $rc = system($cmd);
    if ($rc) {
	print "ERROR: failed to add keypair - '$cmd'\n";
	exit(1);
    }
    system("chmod 0600 mykey$i.priv");
}
print "added '$numkeys' keys\n";


if ($managed) {
#set up some addrs
    $numips = 1;
    print "adding '$numips' addrs\n";
    for ($i=0; $i<$numips; $i++) {
	print "\tallocating ip...\n";
	$cmd = "ec2-allocate-address";
	$rc = system($cmd);
	if ($rc) {
	    print "ERROR: failed to allocate address - '$cmd'\n";
	    exit(1);
	}
    }
    print "allocated '$numips' addrs\n";
}
#set up some groups
$numgroups = int(rand(2)+1);
print "adding '$numgroups' groups\n";
for ($i=0; $i<$numgroups; $i++) {
    print "\tadding group...\n";
    system("date");
$cmd = "runat $ec2timeout ec2-add-group -d \"group$i\" group$i";
    $rc = system($cmd);
    if ($rc) {
	print "ERROR: failed to add group - '$cmd'\n";
	exit(1);
    }
}
print "added '$numgroups' groups\n";

#set up ingress rules
print "authorizing '$numgroups' groups\n";
for ($i=0; $i<$numgroups; $i++) {
    print "\tallowing ICMP and SSH\n";
    system("date");
$cmd = "runat $ec2timeout ec2-authorize group$i -P icmp -s 0.0.0.0/0 -t -1:-1";
    $rc = system($cmd);
    if ($rc) {
	print "ERROR: failed to authorize '$cmd'\n";
	exit(1);
    }
    system("date");
$cmd = "runat $ec2timeout ec2-authorize group$i -P tcp -p 22 -s 0.0.0.0/0";
    $rc = system($cmd);
    if ($rc) {
	print "ERROR: failed to authorize '$cmd'\n";
	exit(1);
    }
}
print "authorized '$numgroups' groups\n";
exit(0);
