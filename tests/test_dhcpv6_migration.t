use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

sub read_file { open my $fh, '<', $_[0] or die $!; return do { local $/; <$fh> }; }
sub write_file { my ($file, $text) = @_; open my $fh, '>', $file or die $!; print {$fh} $text; close $fh; }
my $fragment = read_file('iservchk/80legacy/40server-dhcpy6d_dhcpv6');
my ($check, $repair) = $fragment =~ /^Test [^\n]+\n(.*?)\n  ---\n(.*)$/s;
ok(defined $check && defined $repair, 'migration has check and repair blocks') or BAIL_OUT('invalid legacy fragment');
my $postinst = read_file('debian/postinst');

sub fixture {
    my ($config) = @_;
    my $dir = tempdir(CLEANUP => 1);
    make_path("$dir/bin", "$dir/state");
    write_file("$dir/config", $config);
    write_file("$dir/update.log", '');
    write_file("$dir/cfg", ". '$dir/config'\n" . <<'SH');
kill() {
    grep -qx 40server-dhcpy6d_dhcpv6 "$TEST_DIR/update.log" || return 1
    printf '%s\n' "$*" >> "$TEST_DIR/rerun.log"
}
SH
    write_file("$dir/bin/newconf", <<'SH');
#!/bin/sh
printf 'newconf\n' >> "$TEST_DIR/actions.log"
[ "${NEWCONF_FAIL:-0}" = 0 ]
SH
    write_file("$dir/bin/store_cfg", <<'SH');
#!/bin/bash
set -e
[ "$1" = -a ] && [ "$3" = DHCPv6 ]
printf 'store\n' >> "$TEST_DIR/actions.log"
[ "${STORE_FAIL:-0}" = 0 ]
file=$2
shift 3
printf 'DHCPv6=(' >> "$file"
for item; do printf ' %q' "$item" >> "$file"; done
printf ' )\n' >> "$file"
SH
    chmod 0755, "$dir/bin/newconf", "$dir/bin/store_cfg";
    for my $entry (['check', $check], ['repair', $repair], ['postinst', $postinst]) {
        my ($name, $script) = @$entry;
        $script =~ s!\Q/var/lib/iserv/server-dhcpy6d\E!$dir/state!g;
        $script =~ s!\Q/var/lib/iserv/config/update.log\E!$dir/update.log!g;
        $script =~ s!\Q/etc/iserv/config\E!$dir/config!g;
        $script =~ s!\Q/usr/lib/iserv/cfg\E!$dir/cfg!g;
        $script =~ s!\Q/usr/lib/iserv/newconf\E!$dir/bin/newconf!g;
        write_file("$dir/$name", $script);
    }
    return $dir;
}
sub run_script {
    my ($dir, $name, @args) = @_;
    local $ENV{TEST_DIR} = $dir;
    local $ENV{PATH} = "$dir/bin:$ENV{PATH}";
    local $ENV{ISERVCHK_TOP_PID} = 12345;
    return system('bash', "$dir/$name", @args) >> 8;
}
sub read_setting {
    my ($dir) = @_;
    my $result = `bash -c '. "\$1"; printf "%s\\n" "\${#DHCPv6[\@]}"; for item in "\${DHCPv6[\@]}"; do printf "%s\\n" "\$item"; done' _ '$dir/config'`;
    is($? >> 8, 0, 'stored configuration remains valid Bash');
    return $result;
}

{
    my $dir = fixture("DHCP=('ipv4-only')\n");
    is(run_script($dir, 'postinst', 'configure', ''), 0, 'fresh installation succeeds');
    ok(!-e "$dir/state/package_upgrade.flag", 'fresh installation has no upgrade marker');
    is(run_script($dir, 'check'), 0, 'fresh installation marks migration complete without repair');
    is(read_file("$dir/config"), "DHCP=('ipv4-only')\n", 'fresh installation does not inherit DHCP');
    is(read_file("$dir/update.log"), "40server-dhcpy6d_dhcpv6\n", 'fresh installation records success');
    is(run_script($dir, 'postinst', 'configure', '1.0'), 0, 'later upgrade sets marker');
    is(run_script($dir, 'check'), 0, 'later upgrade does not migrate a previously fresh installation');
    is(read_file("$dir/update.log"), "40server-dhcpy6d_dhcpv6\n", 'success marker is not duplicated');
}
for my $case (
    ["DHCP=('*')\n", "1\n*\n", 'wildcard'],
    ["DHCP=('lan0' 'lan1')\n", "2\nlan0\nlan1\n", 'interface list'],
    ["DHCP=()\n", "0\n", 'disabled DHCP'],
    ['', "1\n*\n", 'legacy default when DHCP is absent'],
) {
    my ($config, $expected, $label) = @$case;
    my $dir = fixture($config);
    is(run_script($dir, 'postinst', 'configure', '1.0'), 0, "$label: upgrade postinst succeeds");
    ok(-f "$dir/state/package_upgrade.flag", "$label: upgrade marker exists");
    is(run_script($dir, 'check'), 1, "$label: pending upgrade requires migration");
    is(run_script($dir, 'repair'), 0, "$label: migration succeeds");
    is(read_setting($dir), $expected, "$label: DHCPv6 preserves the old selection");
    is(read_file("$dir/actions.log"), "store\nnewconf\n", "$label: write then regenerate config");
    is(read_file("$dir/rerun.log"), "-USR1 12345\n", "$label: request full iservchk rerun after recording success");
    is(run_script($dir, 'check'), 0, "$label: migration is idempotent");
}
{
    my $dir = fixture("DHCP=('lan0')\nDHCPv6=('lan1')\n");
    is(run_script($dir, 'postinst', 'configure', '1.0'), 0, 'explicit destination: upgrade');
    is(run_script($dir, 'repair'), 0, 'explicit destination: repair succeeds');
    is(read_setting($dir), "1\nlan1\n", 'explicit DHCPv6 is not overwritten');
    is(read_file("$dir/actions.log"), "newconf\n", 'explicit destination only regenerates config');
}
for my $failure ('STORE_FAIL', 'NEWCONF_FAIL') {
    my $dir = fixture("DHCP=('lan0' 'lan1')\n");
    run_script($dir, 'postinst', 'configure', '1.0');
    { local $ENV{$failure} = 1; isnt(run_script($dir, 'repair'), 0, "$failure propagates failure"); }
    is(read_file("$dir/update.log"), '', "$failure does not mark migration successful");
    is(run_script($dir, 'check'), 1, "$failure remains pending");
    is(run_script($dir, 'repair'), 0, "$failure can be retried");
    is(read_setting($dir), "2\nlan0\nlan1\n", "$failure retry preserves selection");
    is(run_script($dir, 'check'), 0, "$failure retry records success");
}
{
    my $dir = fixture('');
    is(run_script($dir, 'postinst', 'abort-upgrade', '1.0'), 0, 'abort-upgrade succeeds');
    ok(!-f "$dir/state/package_upgrade.flag", 'abort-upgrade does not mark a configured upgrade');
}

done_testing;
