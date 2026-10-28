use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/IServ");
open my $stub, '>', "$tmp/IServ/Conf.pm" or die $!;
print {$stub} <<'PERL';
package IServ::Conf;
use Exporter 'import';
our @EXPORT = qw($conf);
our $conf = {};
$conf->{DHCPv6Reconfigure} = $ENV{TEST_RECONFIGURE} if exists $ENV{TEST_RECONFIGURE};
1;
PERL
close $stub;
my $generator = 'iconf/etc/dhcpy6d.conf/25server-dhcpy6d_reconfigure.pl';
for my $setting (undef, 0, 1) {
    local $ENV{TEST_RECONFIGURE};
    if (defined $setting) { $ENV{TEST_RECONFIGURE} = $setting; }
    else { delete $ENV{TEST_RECONFIGURE}; }
    my $output = `$^X -CSDAL -I$tmp $generator`;
    is($? >> 8, 0, 'configuration generation succeeds');
    my $expected = (!defined($setting) || $setting) ? '/var/lib/dhcpy6d/reconfigure.sqlite' : '';
    like($output, qr/^reconfigure_state_file = \Q$expected\E$/m,
        defined($setting) ? "explicit setting $setting" : 'missing setting enables Reconfigure by default');
    unlike($output, qr/noauthrequired/, 'authentication is never bypassed');
    like($output, qr/\n\n\z/, 'fragment ends with a blank line');
}
open my $control, '<', 'debian/control' or die $!;
like(do { local $/; <$control> }, qr/dhcpy6d \(>= 1\.7\.0-1\+stsblnmu5\)/,
    'package requires persistent authenticated Reconfigure support');
open my $config, '<', 'config/80server-dhcpy6d' or die $!;
like(do { local $/; <$config> }, qr/^default\s+true$/m,
    'IServ configuration metadata enables Reconfigure by default');
done_testing;
