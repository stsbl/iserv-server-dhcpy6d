#!/usr/bin/perl -CSDAL

use warnings;
use strict;
use IServ::Conf;
use List::MoreUtils qw(uniq);

my %activate_dhcp = ("*", 1);

if (exists $conf->{DHCP})
{
  %activate_dhcp = map { $_ => 1 } @{ $conf->{DHCP} };
}

my %ips;

for my $row (split /\n/, qx(netquery6 -gul "nic\tip\tprefix\tlength"))
{
  my ($nic, $ip, $prefix, $length) = split /\t/, $row;
  next if $length ne 64;
  push @{ $ips{$nic} }, [$ip, $prefix];
}

for my $nic (uniq sort split /\n/, qx(netquery6 -gul "nic"))
{
  next if not exists $activate_dhcp{$nic} and
      not grep { /^\*$/ } keys %activate_dhcp;
  next unless exists $ips{$nic};
  my @ips;
  my %prefixes;

  for (@{ $ips{$nic} })
  {
    my @net = @{ $_ };
    push @ips, $net[0];
    $prefixes{ $net[1] } = 1;
  }

  @ips = sort @ips;
  my $ips = join " ", @ips;

  my @address_pools;
  my $addresses = "";
  my $i = 0;
  
  for my $prefix (sort keys %prefixes)
  {
    my $address_key = "${nic}_$i";
    $addresses .= "[address_$address_key]\n";
    $addresses .= "# Choosing EUI-64-based addresses.\n";
    $addresses .= "category = eui64\n";
    $addresses .= "pattern = $prefix\$eui64\$\n";
    $addresses .= "ia_type = na\n";
    $addresses .= "\n";
    push @address_pools, $address_key;

    my $temp_address_key = "temp_${nic}_$i";
    $addresses .= "[address_$temp_address_key]\n";
    $addresses .= "# Choosing random addresses.\n";
    $addresses .= "category = random\n";
    $addresses .= "pattern = $prefix\$random64\$\n";
    $addresses .= "ia_type = ta\n";
    $addresses .= "\n";
    push @address_pools, $temp_address_key;

    $i++;
  }

  print "[class_default_$nic]\n";
  print "addresses = " . join(" ", sort @address_pools) . "\n";
  print "ntp_server = $ips\n";
  print "\n";
  print "[class_fixed_$nic]\n";
  print "addresses = fixed fixed_ta\n";
  print "interface = $nic\n";
  print "ntp_server = $ips\n";
  print "advertise = addresses prefixes\n";
  print 'call_up = sudo /usr/sbin/dhcpy6d-add-route $prefix$/$length$ $router$ mgmt' . "\n";
  print 'call_down = sudo /usr/sbin/dhcpy6d-del-route $prefix$/$length$ $router$ mgmt' . "\n";
  print "filter_mac = .*\n";
  print "\n";
  print $addresses;
}

