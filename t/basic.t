use strict;
use Test::More 0.98;
use FindBin;
use Plift;


my $engine = Plift->new(
    path => ["$FindBin::Bin/templates", "$FindBin::Bin/other_templates"],
);


isa_ok $engine->template('index'), "Plift::Context", 'template()';
isa_ok $engine->process('index'), 'XML::LibXML::jQuery', 'process()';
like $engine->render('index'), qr/Hello Plift/, 'render()';


subtest '_find_template_file' => sub {

    is $engine->_find_template_file('index', $engine->path), "$FindBin::Bin/templates/index.html";
    is $engine->_find_template_file('other_index', $engine->path), "$FindBin::Bin/other_templates/other_index.html";

    is_deeply [$engine->_find_template_file('index', $engine->path)],
              ["$FindBin::Bin/templates/index.html", "$FindBin::Bin/templates"];

    is $engine->_find_template_file('layout/footer', $engine->path), "$FindBin::Bin/templates/layout/footer.html";
    is $engine->_find_template_file('./header', $engine->path, 'layout/'), "$FindBin::Bin/templates/layout/header.html";
    is $engine->_find_template_file('../index', $engine->path, 'layout/'), "$FindBin::Bin/templates/index.html";

    is_deeply [$engine->_find_template_file('layout/footer', $engine->path)],
              ["$FindBin::Bin/templates/layout/footer.html", "$FindBin::Bin/templates"];

    # traverse out
    is $engine->_find_template_file('../../../../../../../../../../etc/passwd', $engine->path), undef;

    # null char attack
    is $engine->_find_template_file('index.secret'."\x00", $engine->path), undef;

};


subtest '_load_template' => sub {

    my $c = $engine->template('index');

    is $engine->_load_template('index', $engine->path, $c)->find('h1')->text, 'Hello Plift';
    is $c->relative_path_prefix, '.';

    my $document = $c->document->get(0);
    isa_ok $document, 'XML::LibXML::Document', 'ctx->document';

    is $engine->_load_template('layout/footer', $engine->path, $c)->filter('footer')->size, 1;
    is $c->relative_path_prefix, 'layout';

    is $engine->_load_template('./header', $engine->path, $c)->filter('header')->size, 1;
    is $c->relative_path_prefix, 'layout';

    is $engine->_load_template('./footer/widget', $engine->path, $c)->filter('div')->size, 1;
    is $c->relative_path_prefix, 'layout/footer';

    note $engine->_load_template('layout', $engine->path, $c)->as_html;
    is $engine->_load_template('layout', $engine->path, $c)->find('div')->size, 2;
    is $c->relative_path_prefix, '.';

    ok $engine->_load_template('layout', $engine->path, $c)->document->get(0)
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
