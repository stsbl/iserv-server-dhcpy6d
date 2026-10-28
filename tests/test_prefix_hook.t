use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
my $base = 'iconf/usr/lib/dhcpcd/dhcpcd-hooks/70-dhcpy6d';
ok(-d $base, 'managed delegated-prefix notification hook exists') or BAIL_OUT('missing hook');
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/bin");
sub write_file { my ($name,$text)=@_; open my $fh,'>',$name or die $!; print $fh $text; close $fh; }
open my $fh,'<',"$base/20server-dhcpy6d_orig" or die $!;
my $source=do { local $/; <$fh> };
open my $header_fh,'<',"$base/00server-dhcpy6d_head.templ" or die $!;
$source=do {local $/; <$header_fh>} . $source;

$source =~ s{/var/lib/dhcpy6d/environment-prefix}{$dir/environment-prefix}g;
$source =~ s{/etc/default/dhcpy6d}{$dir/defaults}g;
write_file("$dir/defaults", "ENABLE_DYNAMIC_PREFIX_FROM_DHCPCD=yes\n");
write_file("$dir/hook.orig",$source);
is(system('patch','--quiet','-o',"$dir/hook", "$dir/hook.orig", "$base/40server-dhcpy6d_notify.patch"),0,'notification patch applies to packaged source');
open my $managed_fh,'<',"$dir/hook" or die $!;
my $managed=do {local $/; <$managed_fh>};
$managed =~ s{/etc/dhcpcd.conf}{$dir/dhcpcd.conf}g;
write_file("$dir/hook",$managed);
write_file("$dir/dhcpcd.conf", "interface wan0\n  ia_pd 1 lan0/0/64\ninterface lan0\n");

write_file("$dir/bin/ipv6chdetectd", "#!/bin/sh\necho notify >> '$dir/log'\n");
write_file("$dir/bin/systemctl", "#!/bin/sh\necho blocking-service-call >> '$dir/log'\nexit 1\n");
write_file("$dir/bin/install", "#!/bin/sh\nwhile [ \$# -gt 2 ]; do shift; done\ncp \"\$1\" \"\$2\"\n");
chmod 0755,glob "$dir/bin/*";
local $ENV{PATH}="$dir/bin:$ENV{PATH}";
local $ENV{reason}='BOUND6';
local $ENV{interface}='wan0';
local $ENV{new_dhcp6_ia_pd1_prefix1}='2001:db8:1234:5600::';
local $ENV{new_dhcp6_ia_pd1_prefix1_length}=56;
is(system('/bin/sh',"$dir/hook"),0,'prefix change returns successfully');
open my $log,'<',"$dir/log" or die $!;
is(do {local $/; <$log>},"notify\n",'prefix change queues exactly one notification and no synchronous restart');
open my $prefix,'<',"$dir/environment-prefix" or die $!;
like(do {local $/; <$prefix>}, qr/PREFIX_VAL=2001:0db8:1234:56/, 'delegated prefix environment is still updated');
{
  local $ENV{interface}='lan0';
  local $ENV{reason}='NOCARRIER';
  is(system('/bin/sh',"$dir/hook"),0,'downstream carrier loss returns successfully');
  open my $retained,'<',"$dir/environment-prefix" or die $!;
  like(do {local $/; <$retained>}, qr/PREFIX_VAL=2001:0db8:1234:56/, 'downstream carrier loss preserves the upstream prefix');
}
{
  local $ENV{interface}='lan0';
  local $ENV{reason}='BOUND6';
  local $ENV{new_dhcp6_ia_pd1_prefix1}='';
  local $ENV{new_dhcp6_ia_pd1_prefix1_length}='';
  is(system('/bin/sh',"$dir/hook"),0,'downstream lease without a delegation returns successfully');
  open my $retained,'<',"$dir/environment-prefix" or die $!;
  like(do {local $/; <$retained>}, qr/PREFIX_VAL=2001:0db8:1234:56/, 'unrelated lease does not clear the upstream prefix');
}
local $ENV{reason}='EXPIRE6';
is(system('/bin/sh',"$dir/hook"),0,'prefix expiration returns successfully');
open my $expired,'<',"$dir/environment-prefix" or die $!;
is(do {local $/; <$expired>}, "PREFIX_OPT=\nPREFIX_VAL=\n", 'expired delegated prefix is cleared');
write_file("$dir/environment-prefix", "PREFIX_OPT=--prefix\nPREFIX_VAL=2001:0db8:1234:56\n");
{
  local $ENV{interface}='lan0';
  local $ENV{reason}='NOCARRIER';
  is(system('/bin/sh',"$dir/hook"),0,'legacy prefix survives downstream event before renewal');
  open my $legacy,'<',"$dir/environment-prefix" or die $!;
  like(do {local $/; <$legacy>}, qr/PREFIX_VAL=2001:0db8:1234:56/, 'legacy owner fallback does not confuse downstream and upstream');
}
is(system('/bin/sh',"$dir/hook"),0,'legacy upstream expiration works without an intervening renewal');
open my $legacy_expired,'<',"$dir/environment-prefix" or die $!;
is(do {local $/; <$legacy_expired>}, "PREFIX_OPT=\nPREFIX_VAL=\n", 'legacy delegated prefix is cleared on its first upstream loss');
done_testing;
