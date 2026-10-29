use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

sub read_file { open my $fh, '<', $_[0] or die $!; return do { local $/; <$fh> }; }
sub write_file { my ($file, $text) = @_; open my $fh, '>', $file or die $!; print {$fh} $text; close $fh; }
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/bin", "$dir/mod/IServ");
write_file("$dir/bin/netquery6", <<'SH');
#!/bin/sh
case "$*" in
  *-gulq*) [ "${HAS_IPV6:-1}" = 1 ] ;;
  *ip*prefix*length*) printf 'br1118\t2001:db8:1::1\t2001:db8:1::\t64\nbr2222\t2001:db8:2::1\t2001:db8:2::\t64\n' ;;
  *) printf 'br1118\nbr2222\n' ;;
esac
SH
write_file("$dir/bin/iserv-ipv6-prefix", "#!/bin/sh\nprintf '%s\\n' \"\$2\"\n");
chmod 0755, "$dir/bin/netquery6", "$dir/bin/iserv-ipv6-prefix";
my $interfaces = read_file('iconf/etc/dhcpy6d.conf/30server-dhcpy6d_interfaces.pl');
$interfaces =~ s!\Q/usr/lib/iserv/iserv-ipv6-prefix\E!$dir/bin/iserv-ipv6-prefix!g;
write_file("$dir/interfaces.pl", $interfaces);
my $general = read_file('iconf/etc/dhcpy6d.conf/20server-dhcpy6d_general.templ');
write_file("$dir/general.sh", ". '$dir/cfg'\ncat <<'HEADER'\nHEADER\ncat <<END_CONFIG\n$general\nEND_CONFIG\n");
my $check = read_file('iservchk/40dhcpy6d/20server-dhcpy6d.sh');
$check =~ s!\Q/usr/lib/iserv/cfg\E!$dir/cfg!g;
write_file("$dir/check.sh", $check);
local $ENV{PATH} = "$dir/bin:$ENV{PATH}";
local $ENV{PERL5LIB} = "$dir/mod";
for my $case (
    ['specific', ['ipv4only'], ['br1118'], ['br1118']],
    ['IPv4 disabled', [], ['*'], ['br1118', 'br2222']],
    ['IPv6 disabled', ['*'], [], []],
    ['other interface', ['br1118'], ['br2222'], ['br2222']],
) {
    my ($label, $v4, $v6, $expected) = @$case;
    my $v4_value = join ' ', map { "'$_'" } @$v4;
    my $v6_value = join ' ', map { "'$_'" } @$v6;
    write_file("$dir/cfg", "DHCP=($v4_value)\nDHCPv6=($v6_value)\nDomain=example.test\n");
    write_file("$dir/mod/IServ/Conf.pm", "package IServ::Conf; use Exporter 'import'; our \@EXPORT = qw(\$conf); our \$conf = { DHCP => [" . join(',', map { "'$_'" } @$v4) . "], DHCPv6 => [" . join(',', map { "'$_'" } @$v6) . "] }; 1;\n");
    my $config = `bash '$dir/general.sh'`;
    is($? >> 8, 0, "$label: general template renders");
    my ($line) = $config =~ /^interface = (.*)$/m;
    my @selected = split /\s+/, $line;
    is_deeply(\@selected, $expected, "$label: listener interfaces follow DHCPv6 only");
    my $classes = `$^X -CSDAL '$dir/interfaces.pl'`;
    is($? >> 8, 0, "$label: address classes render");
    my @classes = $classes =~ /^\[class_default_([^]]+)\]$/mg;
    is_deeply(\@classes, $expected, "$label: address classes follow DHCPv6 only");
    for my $has_ipv6 (0, 1) {
        local $ENV{HAS_IPV6} = $has_ipv6;
        my $enabled = @$v6 && $has_ipv6;
        my $commands = `bash '$dir/check.sh'`;
        is($? >> 8, 0, "$label: iservchk generator succeeds (IPv6=$has_ipv6)");
        like($commands, $enabled ? qr/^Start dhcpy6d dhcpy6d$/m : qr/^Stop dhcpy6d dhcpy6d$/m,
            "$label: iservchk respects DHCPv6 and IPv6 availability");

    }
}
done_testing;
