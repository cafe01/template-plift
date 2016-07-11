use strict;
use Test::More 0.98;
use FindBin;
use Plift;


my $engine = Plift->new(
    path => ["$FindBin::Bin/templates", "$FindBin::Bin/other_templates"],
);


subtest 'wrap' => sub {

    my $ctx = $engine->template('wrap/wrap');
    my $doc = $ctx->render();

    note $doc->as_html;
    is $doc->find('header, footer')->size, 2;
    is $doc->find('#content h1')->size, 1;
};

# subtest 'at' => sub {
#
#     my $ctx = $engine->template('wrap/at');
#     my $doc = $ctx->render();
#
#     note $doc->as_html;
#     is $doc->find('header, footer')->size, 2;
#     is $doc->find('.main-content h1')->size, 1;
# };
#
# subtest 'replace' => sub {
#
#     my $ctx = $engine->template('wrap/replace');
#     my $doc = $ctx->render();
#
#     note $doc->as_html;
#     is $doc->find('header, footer')->size, 2;
#     is $doc->find('div > h1, div > p')->size, 2;
#     is $doc->find('#content')->size, 0;
# };
#
# subtest 'content' => sub {
#
#     my $ctx = $engine->template('wrap/content');
#     my $doc = $ctx->render();
#
#     note $doc->as_html;
#     is $doc->find('header, footer')->size, 2;
#     is $doc->find('#content > h1, #content > p')->size, 2;
# };
#
#
# subtest 'replace + content' => sub {
#
#     my $ctx = $engine->template('wrap/replace-content');
#     my $doc = $ctx->render();
#
#     note $doc->as_html;
#     is $doc->find('header, footer')->size, 2;
#     is $doc->find('body > h1, body > p')->size, 2;
# };




done_testing;
