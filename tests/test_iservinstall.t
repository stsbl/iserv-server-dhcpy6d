use strict;
use warnings;
use Test::More;

my $rules = 'debian/iservinstall';
ok(-f $rules, 'iservinstall exclusions exist') or BAIL_OUT('missing iservinstall exclusions');
open my $fh, '<', $rules or die $!;
my $content = do { local $/; <$fh> };
close $fh;
like($content, qr/^X:tests(?:\/\*)?$/m, 'test resources are excluded from iservinstall');

done_testing;
