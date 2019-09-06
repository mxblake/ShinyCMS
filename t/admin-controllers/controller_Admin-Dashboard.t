use strict;
use warnings;

use Test::More;

use lib 't/support';
require 'login_helpers.pl';  ## no critic

create_test_admin();

my $t = login_test_admin() or die 'Failed to log in as admin';

$t->get_ok(
    '/admin/dashboard',
    'Fetch admin dashboard'
);
$t->title_like(
	qr{Site Stats for week of \d\d \w\w\w \d\d\d\d - ShinyCMS},
	'Reached admin dashboard'
);

remove_test_admin();

done_testing();