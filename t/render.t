use strict;
use Test::More 0.98;
use FindBin;
use Plift;

my $engine = Plift->new(
    path => ["$FindBin::Bin/templates"],
);

my @tags = (
    { name => 'tag1', url => '/tag/tag1' },
    { name => 'tag2', url => '/tag/tag2' },
    { name => 'tag3', url => '/tag/tag3' }
);

my %data = (
    fullname => 'Carlos Fernando Avila Gratz',
    contact => {
        phone => 123,
        email => 'foo@example'
    },
    posts => [
        {
            title => 'Post 1',
            url => '/post-1',
            content => '<p>Lorem ipsum dolor sit amet, consectetur adipisicing elit.</p>',
            tags => \@tags
        },
        {
            title => 'Post 2',
            url => '/post-2',
            content => '<p>Lorem ipsum dolor sit amet, consectetur adipisicing elit.</p>',
            tags => \@tags
        },
        {
            title => 'Post 3',
            url => '/post-3',
            content => '<p>Lorem ipsum dolor sit amet, consectetur adipisicing elit.</p>',
            tags => \@tags
        }
    ]
);


test_render_directives();
test_render_references();
done_testing;

sub test_render_directives {

    my $tpl = $engine->template('render');

    $tpl->at('#name' => 'fullname')
        ->at('#code' => sub {
            my ($el, $ctx)  = @_;
            $el->new('<div/>')->text($ctx->get('fullname'))
                              ->append_to($el);
        })
        ->at('#contact' => [
            '.phone' => 'contact.phone',
            '.email' => 'contact.email'
        ])
        ->at('#contact2' => {
            'contact' => [
                '.phone' => 'phone',
                '.email' => 'email',
            ]
        })
        ->at('article' => {
            'posts' => [
                '.position' => 'loop.index',
                '.post-title' => 'title',
                '.post-link@href' => 'url',
                '.post-content@HTML' => 'content',
                'li.tag' => {
                    'tags' => [
                        'a' => 'name',
                        'a@href' => 'url',
                    ]
                },
            ]
        });

    my $doc = $tpl->render(\%data);

    # note $doc->as_html;

    # Scalar
    is $doc->find('#name')->text, $data{fullname};

    # CodeRef
    is $doc->find('#code div')->text, $data{fullname};

    # ArrayRef
    is $doc->find('#contact .phone')->text, $data{contact}{phone};
    is $doc->find('#contact .email')->text, $data{contact}{email};

    # HashRef
    is $doc->find('#contact2 .phone')->text, $data{contact}{phone};
    is $doc->find('#contact2 .email')->text, $data{contact}{email};

    # HashRef (loop)
    is $doc->find('article')->size, scalar @{$data{posts}};
    my $article = $doc->find('article')->first;
    is $article->find('.position')->text, 1;
    is $article->find('.post-title')->text, $data{posts}[0]{title};
    is $article->find('.post-link')->attr('href'), $data{posts}[0]{url};
    is $article->find('.post-content p')->text,
       (ref $article)->new($data{posts}[0]{content})->filter('p')->text;

    is $article->find('li.tag')->size, scalar @{$data{posts}[0]{tags}};
    is $article->find('li.tag:first-child a')->text, $data{posts}[0]{tags}[0]{name};
}

sub test_render_references {
    my $tpl = $engine->template('render-tpl-refs');
    my $doc = $tpl->render(\%data);

    note $doc->as_html;

    is $doc->find('#name')->text, $data{fullname};
    is $doc->find('#name')->attr('title'), $data{fullname};
}
