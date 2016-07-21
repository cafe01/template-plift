use strict;
use Test::More 0.98;
use FindBin;
use Plift;


my $engine = Plift->new(
    paths => ["$FindBin::Bin/templates", "$FindBin::Bin/other_templates"],
);

subtest 'set()' => sub {

    my $ctx = $engine->template('index');

    $ctx->set('name', 'Carlos Fernando')
        ->set({
            foo => 'foo value',
            bar => 'bar value',
        })
        ->set('items', [
            { name => 'Item 1', description => 'Item 1 description' },
            { name => 'Item 2', description => 'Item 2 description' },
            { name => 'Item 3', description => 'Item 3 description' },
        ]);

    is_deeply $ctx->data, {
        name => 'Carlos Fernando',
        foo => 'foo value',
        bar => 'bar value',
        items => [
            { name => 'Item 1', description => 'Item 1 description' },
            { name => 'Item 2', description => 'Item 2 description' },
            { name => 'Item 3', description => 'Item 3 description' },
        ]
    }, 'data';
};


subtest 'get()' => sub {

    my $ctx = $engine->template('index');
    my $object = Some::Class->new;

    $ctx->set({
        value => 'foo',
        hash => { value => 'foo' },
        deep => { hash => { value => 'foo' } },
        array => [qw/ foo bar baz /],
        complex => {
            array_of_hash => [{ value => 'foo' }],
            hash_of_array => { items => ['foo']},
        },
        object => $object,
        code => sub { 'foo' },
        user => {
            name => sub { "$_[1]->{first_name} $_[1]->{last_name}"},
            alt_name => sub { $_[0]->get('user.first_name') .' '. $_[0]->get('user.last_name') },
            first_name => 'First',
            last_name => 'Last',
        },
        hash_from_code => sub { +{ value => 'foo' } },
        object_from_code => sub { $object }
    });

    is $ctx->get('value'), 'foo', 'value';
    is $ctx->get('hash.value'), 'foo', 'hash.value';
    is $ctx->get('deep.hash.value'), 'foo', 'deep.hash.value';
    is $ctx->get('array.0'), 'foo', 'array.0';
    is $ctx->get('array.1'), 'bar', 'array.1';
    is $ctx->get('complex.array_of_hash.0.value'), 'foo', 'complex.array_of_hash.0.value';
    is $ctx->get('complex.hash_of_array.items.0'), 'foo', 'complex.hash_of_array.items.0.value';
    is $ctx->get('object.foo_method'), $object->foo_method, 'object.method';
    is $ctx->get('code'), 'foo', 'code';
    is $ctx->get('user.name'), 'First Last', 'code with data args';
    is $ctx->get('user.alt_name'), 'First Last', 'code with data args';
    is $ctx->get('hash_from_code.value'), 'foo', 'hash_from_code.value';
    is $ctx->get('object_from_code.foo_method'), $object->foo_method, 'object_from_code.method';
};


subtest 'render' => sub {

    my $c = $engine->template('index');

    my $doc = $c->render;
    isa_ok $doc->get(0), 'XML::LibXML::Document';
    is $doc->find('h1')->size, 1;
};


subtest 'helper' => sub {

    my $engine = Plift->new(
        paths  => ["$FindBin::Bin/templates"],
        helper => Some::Class->new
    );

    $engine->add_handler({
        name => 'test_helper',
        tag => 'section',
        handler => sub {
            my ($el, $ctx) = @_;
            $el->text($ctx->foo_method);
        }
    });

    my $ctx = $engine->template('section');
    my $doc = $ctx->render;
    is $doc->find('section')->text, 'foo', 'context helper';
};

done_testing;


{
    package Some::Class;
    use Moo;

    sub foo_method { 'foo' }
}
