#!/usr/bin/perl -CSDAL

use strict;
use warnings;
use IServ::Conf;

# Keep authentication keys independent of the disposable lease database.
my $enabled = $conf->{DHCPv6Reconfigure} // 1;
my $state = $enabled
    ? '/var/lib/dhcpy6d/reconfigure.sqlite' : '';
print "# Authenticated client renewal; keys persist across restarts.\n";
print "reconfigure_state_file = $state\n\n";

