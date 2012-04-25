#!/usr/bin/perl

if( -e "./mykey0.priv" ){
	system("rm -f ./mykey0.priv");
};

if( -e "./mykey1.priv" ){
	system("rm -f ./mykey1.priv");
};

exit(0);

1;

