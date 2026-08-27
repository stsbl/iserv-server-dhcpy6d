use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Path qw(make_path);
use File::Spec;
use Cwd qw(getcwd);

my $root = getcwd();
my $generator = "$root/iconf/etc/dhcpy6d.conf/30server-dhcpy6d_interfaces.pl";
ok(-f $generator, 'server generator exists');

my $tmp = tempdir(CLEANUP => 1);
my $bin = "$tmp/bin"; make_path($bin, "$tmp/config", "$tmp/state");
open my $netquery, '>', "$bin/netquery6" or die $!;
print {$netquery} <<'SH';
#!/bin/sh
case "$*" in
  *ip*prefix*length*)
    printf 'br1118\t2001:db8:100:2018::1\t2001:db8:100:2018::\t64\n'
    printf 'br1118\tfd00:1::1\tfd00:1::\t64\n' ;;
  *) printf 'br1118\n' ;;
esac
SH
close $netquery;
chmod 0755, "$bin/netquery6";
open my $dhcp, '>', "$tmp/config/ipv6-dhcp-interfaces.list" or die $!;
print {$dhcp} "dsl\n"; close $dhcp;
open my $delegation, '>', "$tmp/config/ipv6-delegation-interfaces.list" or die $!;
print {$delegation} "br1118\n"; close $delegation;
open my $sla, '>', "$tmp/state/dsl.sla-len" or die $!;
print {$sla} "56\n"; close $sla;

open my $in, '<', $generator or die $!;
my $script = do { local $/; <$in> };
$script =~ s/use IServ::Conf;/our \$conf = { DHCP => ['br1118'] };/;
open my $helper, '>', "$bin/iserv-ipv6-prefix" or die $!;
print {$helper} <<'SH';
#!/bin/sh
[ "$1" = --placeholder ] && { case "$2" in fd*) echo "$2";; *::) echo '$prefix$18::';; *) echo '$prefix$18::1';; esac; }
SH
close $helper;
chmod 0755, "$bin/iserv-ipv6-prefix";
my $run = "$tmp/generator.pl";
open my $out, '>', $run or die $!;
$script =~ s!/usr/lib/iserv/iserv-ipv6-prefix!$bin/iserv-ipv6-prefix!g;
print {$out} $script; close $out; chmod 0755, $run;
my $result = `PATH=$bin:$ENV{PATH} ISERV_IPV6_DHCP_CONFIG_DIR=$tmp/config ISERV_IPV6_DHCPCD_STATE_DIR=$tmp/state $run`;
is($? >> 8, 0, 'generator exits successfully');
like($result, qr/pattern = \$prefix\$18::\$eui64\$/, 'delegated global pool uses prefix placeholder');
like($result, qr/ntp_server = \$prefix\$18::1 fd00:1::1/, 'delegated global advertisement uses placeholder while ULA stays literal');
unlike($result, qr/2001:db8:100:2018/, 'materialized delegated global prefix is absent');
done_testing;
