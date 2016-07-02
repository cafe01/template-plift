use strict;
use Test::More 0.98;
use FindBin;
use Plift;


my $engine = Plift->new(
    path => ["$FindBin::Bin/templates", "$FindBin::Bin/other_templates"],
);


subtest 'find_template_file' => sub {

    is $engine->find_template_file('index'), "$FindBin::Bin/templates/index.html";
    is $engine->find_template_file('other_index'), "$FindBin::Bin/other_templates/other_index.html";
};


subtest 'load_template' => sub {

    is $engine->load_template('index')->find('h1')->size, 1;
    is $engine->load_template('index')->find('p')->size, 1;
};


subtest 'get_handler' => sub {

    my $include_handler = $engine->get_handler('include');
    is $include_handler->{xpath}, './x-include | ./*[@data-plift-include]';
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

    is $engine->get_handler('foo')->{xpath}, './foo | ./*[@data-foo]';
    is $engine->get_handler('foo')->{sub}, $foo_handler;
    is $engine->get_handler('bar')->{xpath}, './x-bar | ./bar | ./*[@data-bar] | ./*[@bar]';
    is $engine->get_handler('bar')->{sub}, $bar_handler;
};


subtest 'process' => sub {

    my $doc = $engine->process('index');

    isa_ok $doc, 'XML::LibXML::jQuery';
    isa_ok $doc->get(0), 'XML::LibXML::Document';
};




done_testing;
