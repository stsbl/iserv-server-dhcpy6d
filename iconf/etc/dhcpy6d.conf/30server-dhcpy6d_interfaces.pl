#!/usr/bin/perl -CSDAL

use warnings;
use strict;
use IServ::Conf;
use List::MoreUtils qw(uniq);
use Socket qw(AF_INET6 inet_pton);

my %activate_dhcp = ("*", 1);

if (exists $conf->{DHCP})
{
  %activate_dhcp = map { $_ => 1 } @{ $conf->{DHCP} };
}

my $config_dir = $ENV{ISERV_IPV6_DHCP_CONFIG_DIR} // '/var/lib/iserv/config';
my $state_dir = $ENV{ISERV_IPV6_DHCPCD_STATE_DIR} // '/var/lib/iserv/config-ipv6/dhcpcd';
my %delegation = map { chomp; $_ => 1 } grep { /\S/ } do {
  my $file = "$config_dir/ipv6-delegation-interfaces.list";
  -f $file ? do { open my $fh, '<', $file or die "$file: $!"; <$fh> } : ();
};
my ($upstream) = do {
  my $file = "$config_dir/ipv6-dhcp-interfaces.list";
  -f $file ? do { open my $fh, '<', $file or die "$file: $!"; grep { /\S/ } <$fh> } : ();
};
chomp $upstream if defined $upstream;
my $sla_len = 62;
if (defined $upstream && -f "$state_dir/$upstream.sla-len") {
  open my $fh, '<', "$state_dir/$upstream.sla-len" or die "$state_dir/$upstream.sla-len: $!";
  $sla_len = <$fh>; chomp $sla_len;
}

sub prefix_placeholder {
  my ($address) = @_;
  return $address unless defined $upstream && $sla_len =~ /^\d+$/ && $sla_len % 4 == 0;
  return $address if $address =~ /^f[cd]/i; # ULA stays stable.
  my $packed = inet_pton(AF_INET6, $address) or return $address;
  my $hex = unpack('H*', $packed);
  my $offset = $sla_len / 4;
  my $tail = substr($hex, $offset);
  my $first_length = 4 - ($offset % 4);
  my $suffix = substr($tail, 0, $first_length);
  my @groups = (substr($tail, $first_length) =~ /(.{4})/g);
  $suffix .= ':' . join(':', @groups) if @groups;
  $suffix =~ s/(?:^|:)0000(?::0000)*(?=:|$)/::/;
  $suffix =~ s/(^|:)0+([0-9a-f])/$1$2/g;
  $suffix =~ s/:::+/::/g;
  return '$prefix$' . $suffix;
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
    push @ips, $delegation{$nic} ? prefix_placeholder($net[0]) : $net[0];
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
    my $pattern = $delegation{$nic} ? prefix_placeholder($prefix) : $prefix;
    $addresses .= "pattern = $pattern\$eui64\$\n";
    $addresses .= "ia_type = na\n";
    $addresses .= "\n";
    push @address_pools, $address_key;

    my $temp_address_key = "temp_${nic}_$i";
    $addresses .= "[address_$temp_address_key]\n";
    $addresses .= "# Choosing random addresses.\n";
    $addresses .= "category = random\n";
    $addresses .= "pattern = $pattern\$random64\$\n";
    $addresses .= "ia_type = ta\n";
    $addresses .= "\n";
    push @address_pools, $temp_address_key;

    $i++;
  }

  print "[class_default_$nic]\n";
  print "addresses = " . join(" ", sort @address_pools) . "\n";
  print "ntp_server = $ips\n";
  print "interface = $nic\n";
  print "filter_mac = .*\n";
  print "\n";
  print "[class_fixed_$nic]\n";
  print "addresses = fixed fixed_ta\n";
  print "interface = $nic\n";
  print "ntp_server = $ips\n";
  print "advertise = addresses prefixes\n";
  print 'call_up = sudo /usr/sbin/dhcpy6d-add-route $prefix$/$length$ $router$ ' . "$nic\n";
  print 'call_down = sudo /usr/sbin/dhcpy6d-del-route $prefix$/$length$ $router$ ' . "$nic\n";
  print "filter_mac = .*\n";
  print "\n";
  print $addresses;
}

