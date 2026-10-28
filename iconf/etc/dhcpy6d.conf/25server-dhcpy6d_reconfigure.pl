#!/usr/bin/perl -CSDAL

use strict;
use warnings;
use IServ::Conf;

# Keep authentication keys independent of the disposable lease database.
my $state = $conf->{DHCPv6Reconfigure}
    ? '/var/lib/dhcpy6d/reconfigure.sqlite' : '';
print "# Authenticated client renewal; keys persist across restarts.\n";
print "reconfigure_state_file = $state\n\n";

