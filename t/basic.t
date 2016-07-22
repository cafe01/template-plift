use strict;
use Test::More 0.98;
use FindBin;
use Plift;


my $engine = Plift->new(
    paths => ["$FindBin::Bin/templates", "$FindBin::Bin/other_templates"],
);


isa_ok $engine->template('index'), "Plift::Context", 'template()';
isa_ok $engine->process('index'), 'XML::LibXML::jQuery', 'process()';
like $engine->render('index'), qr/Hello Plift/, 'render()';


subtest '_find_template_file' => sub {

    is $engine->_find_template_file('index', $engine->paths), "$FindBin::Bin/templates/index.html";
    is $engine->_find_template_file('other_index', $engine->paths), "$FindBin::Bin/other_templates/other_index.html";

    is_deeply [$engine->_find_template_file('index', $engine->paths)],
              ["$FindBin::Bin/templates/index.html", "$FindBin::Bin/templates"];

    is $engine->_find_template_file('layout/footer', $engine->paths), "$FindBin::Bin/templates/layout/footer.html";
    is $engine->_find_template_file('./header', $engine->paths, 'layout/'), "$FindBin::Bin/templates/layout/header.html";
    is $engine->_find_template_file('../index', $engine->paths, 'layout/'), "$FindBin::Bin/templates/index.html";

    is_deeply [$engine->_find_template_file('layout/footer', $engine->paths)],
              ["$FindBin::Bin/templates/layout/footer.html", "$FindBin::Bin/templates"];

    # traverse out
    is $engine->_find_template_file('../../../../../../../../../../etc/passwd', $engine->paths), undef;

    # null char attack
    is $engine->_find_template_file('index.secret'."\x00", $engine->paths), undef;

};


subtest '_load_template' => sub {

    my $c = $engine->template('index');

    is $engine->_load_template('index', $engine->paths, $c)->find('h1')->text, 'Hello Plift';
    is $c->relative_path_prefix, '.';

    my $document = $c->document->get(0);
    isa_ok $document, 'XML::LibXML::Document', 'ctx->document';

    is $engine->_load_template('layout/footer', $engine->paths, $c)->filter('footer')->size, 1;
    is $c->relative_path_prefix, 'layout';

    is $engine->_load_template('./header', $engine->paths, $c)->filter('header')->size, 1;
    is $c->relative_path_prefix, 'layout';

    is $engine->_load_template('./footer/widget', $engine->paths, $c)->filter('div')->size, 1;
    is $c->relative_path_prefix, 'layout/footer';

    note $engine->_load_template('layout', $engine->paths, $c)->as_html;
    is $engine->_load_template('layout', $engine->paths, $c)->find('div')->size, 2;
    is $c->relative_path_prefix, '.';

    ok $engine->_load_template('layout', $engine->paths, $c)->document->get(0)
                                                            ->isSameNode($document);

    # inline
    is $engine->_load_template(\'<div/>', $engine->paths, $c)->filter('div')->size, 1;
    ok $engine->_load_template(\'<div/>', $engine->paths, $c)
              ->document->get(0)
              ->isSameNode($document);
};


subtest 'get_handler' => sub {

    my $include_handler = $engine->get_handler('include');
    is $include_handler->{xpath}, './/x-include | .//*[@data-plift-include]';
};


subtest 'add_handler' => sub {

    my $foo_handler = sub {};
    my $bar_handler = sub {};

    $engine->add_handler({
        name => 'foo',
        tag => 'foo',
        attribute => 'data-foo',
        handler => $foo_handler

    })->add_handler({
        name => 'bar',
        tag => ['x-bar', 'bar'],
        attribute => [qw/ data-bar bar /],
        handler => $bar_handler
    });

    is $engine->get_handler('foo')->{xpath}, './/foo | .//*[@data-foo]';
    is $engine->get_handler('foo')->{sub}, $foo_handler;
    is $engine->get_handler('bar')->{xpath}, './/x-bar | .//bar | .//*[@data-bar] | .//*[@bar]';
    is $engine->get_handler('bar')->{sub}, $bar_handler;
};





done_testing;
