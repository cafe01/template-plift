package Plift;

use 5.008001;
use strict;
use warnings;
use Moo;
use Class::Load ();
use Path::Tiny ();
use XML::LibXML::jQuery ();
use Carp;
use Plift::Context;

our $VERSION = "0.01";

use constant {
    XML_DOCUMENT_NODE      => 9,
    XML_DOCUMENT_FRAG_NODE => 11,
    XML_DTD_NODE           => 14
};

has 'path', is => 'ro', default => sub { [] };
has 'plugins', is => 'ro', default => sub { [] };
has 'encoding', is => 'rw', default => 'UTF-8';
has 'debug', is => 'rw', default => sub { $ENV{PLIFT_DEBUG} };
has 'max_file_size', is => 'rw', default => 1024 * 1024;
has 'enable_cache', is => 'rw', default => 1;
has 'max_cached_files', is => 'rw', default => 50;

has '_cache', is => 'ro', default => sub { {} };



sub BUILD {
    my $self = shift;

    # init components
    # builtin directives
    my @components = qw/ Handler::Include  Handler::Wrap Handler::Render/;

    # plugins
    push @components, map { $_ =~ /^\+/ ? $_ : 'Plugin::'.$_ }
                      @{ $self->plugins };


    # instantiate and init
    foreach my $name (@components) {

        my $class = $name =~ /^\+/ ? substr($name, 1)
                                   : __PACKAGE__.'::'.$name;

        my $plugin = Class::Load::load_class($class)->new;
        $plugin->register($self);
    }
}


sub template {
    my ($self, $name, $options) = @_;
    $options ||= {};

    # path copy for the load_template closure
    # this way we do not expose the engine nor the path to the context object
    my @path = @{ $options->{path} || $self->path };

    Plift::Context->new(
        template => $name,
        encoding => $options->{encoding} || $self->encoding,
        handlers => [@{ $self->{handlers}}],
        load_template => sub {
            my ($ctx, $name) = @_;
            $self->_load_template($name, \@path, $ctx)
        }
    );
}


sub process {
    my ($self, $template, $data, $schema) = @_;

    my $ctx = $self->template($template);

    $ctx->at($schema)
        if $schema;

    $ctx->render($data);
}


sub _load_template {
    my ($self, $name, $path, $ctx) = @_;

    # resolve template name to file
    my ($template_file, $template_path) = $self->_find_template_file($name, $path, $ctx->relative_path_prefix);
    die sprintf "Can't find a template file for template '%s'. Tried:\n%s\n", $name, join(",\n", @$path)
        unless $template_file;

    # update contex relative path
    # $ctx->push_file($template_file);
    $ctx->relative_path_prefix($template_file->parent->relative($template_path));

    # cached file
    my $stat = $template_file->stat;
    my $mtime = $stat->mtime;
    my $cache = $self->_cache;
    my $dom;

    # get from cache
    if ($self->enable_cache && (my $entry = $cache->{"$template_file"})) {

        if ($entry->{mtime} == $mtime) {
            $dom = $entry->{dom}->clone->contents;
            $dom->append_to($dom->document);
            $entry->{hits} += 1;
            $entry->{last_hit} = time;
            # printf STDERR "# Plift cache hit: '$template_file' => %d hits\n", $entry->{hits};
        }
        else {
            delete $cache->{"$template_file"};
        }
    }

    unless ($dom) {

        # max file size
        die sprintf("Template file '%s' exceeds the max_file_size option! (%d > %d)\n", $template_file, $stat->size, $self->max_file_size)
            if $stat->size > $self->max_file_size;

        # parse source
        $dom = XML::LibXML::jQuery->new($ctx->encoding eq 'UTF-8' ? $template_file->slurp_utf8
                                                                  : $template_file->slurp( binmode => ":unix:encoding(".$self->encoding.")"));

        # cache it
        if ($self->enable_cache) {

            # control cache size
            if (scalar keys(%$cache) == $self->max_cached_files) {

                my @least_used = sort { $cache->{$b}{last_hit} <=> $cache->{$a}{last_hit} }
                                 keys %$cache;

                delete $cache->{$least_used[0]};
            }

            $cache->{"$template_file"} = {
                dom   => $dom->document->clone,
                mtime => $mtime,
                hits => 0,
                last_hit => 0,
            };
        }
    }

    # check for data-plift-template attr, and use that element
    my $body = $dom->xfind('//body[@data-plift-template]');

    if ($body->size) {

        my $selector = $body->attr('data-plift-template');
        $dom = $dom->find($selector);
        confess "Can't find template via selector '$selector' (referenced at <body data-plift-template=\"$selector\">)."
            unless $dom->size;
    }

    # adopt into document
    if (my $existing_document = $ctx->document) {

        $existing_document = $existing_document->get(0);

        # replace DTD
        if ($dom->size && (my $dtd = $dom->get(0)->ownerDocument->internalSubset)) {
            $existing_document->removeInternalSubset;
            $existing_document->createInternalSubset( $dtd->getName, $dtd->publicId, $dtd->systemId );
        }

        # adopt nodes
        my @nodes = map { $existing_document->adoptNode($_); $_ }
                    grep { $_->nodeType != XML_DTD_NODE }
                    grep { $_->getOwner->nodeType == XML_DOCUMENT_NODE }
                    @{ $dom->{nodes} };

        # reinstantitate on new document
        $dom = XML::LibXML::jQuery->new(\@nodes);
    }

    # 1st tempalte loaded, set contex document
    else {
        $ctx->document($dom->document);
    }

    $dom;
}

sub _find_template_file {
    my ($self, $template_name, $path, $relative_prefix) = @_;
    $relative_prefix ||= '';

    # append prefix to relative paths (Only './foo' and '../foo' are considered relative, not plain 'foo')
    $template_name = "$relative_prefix/$template_name"
        if $template_name =~ /^\.\.?\//
           && defined $relative_prefix
           && length $relative_prefix;

    # clean \x00 char that can be used to truncate our string
    $template_name =~ tr/\x00//d;

    foreach my $path (@$path) {

        if (-e (my $file = "$path/$template_name.html")) {

            # check file is really child of path
            $file = Path::Tiny->new($file)->realpath;
            $path = Path::Tiny->new($path)->realpath;

            unless ($path->subsumes($file)) {
                warn "[Plift] attempt to traverse out of path via '$template_name'";
                return;
            }

            return wantarray ? ($file, $path) : $file;
        }
    }

    return;
}

sub add_handler {
    my ($self, $config) = @_;

    confess "missing handler callback"
        unless $config->{handler};

    confess "missing handler name"
        unless $config->{name};

    my @match;

    for my $key (qw/ tag attribute /) {
        $config->{$key} = [$config->{$key}]
            if defined $config->{$key} && !ref $config->{$key};
    }

    push(@match, map { ".//$_" } @{$config->{tag}})
        if $config->{tag};

    push(@match, map { ".//*[\@$_]" } @{$config->{attribute}})
        if $config->{attribute};

    push @match, $config->{xpath}
        if $config->{xpath};

    my $match = join ' | ', @match;

    printf STDERR "[Plift] Adding handler: $match\n"
        if $self->debug;

    # check config has one of tag/attribute/xpath
    confess "Invalid handler. Missing at least one binding criteria (tag, attribute or xpath)."
        unless $match;

    my $handler = {
        tag => $config->{tag},
        attribute => $config->{attribute},
        name => $config->{name},
        xpath => $match,
        sub => $config->{handler}
    };

    push @{$self->{handlers}}, $handler;
    $self->{handlers_by_name}->{$handler->{name}} = $handler;

    $self;
}

sub get_handler {
    my ($self, $name) = @_;
    $self->{handlers_by_name}->{$name};
}




1;
__END__

=encoding utf-8

=head1 NAME

Plift - Designer friendly, safe, extensible HTML template engine.

=head1 SYNOPSIS

    use Plift;

    my $plift = Plift->new(
        path    => \@paths,                               # default ['.']
        plugins => [qw/ Script Blog Gallery GoogleMap /], # plugins not included
    );

    my $tpl = $plift->template("index");

    # set render directives
    $tpl->at({
        '#name' => 'fullname',
        '#contact' => [
            '.phone' => 'contact.phone',
            '.email' => 'contact.email'
        ]
    });

    # render render with data
    my $document = $tpl->render({

        fullname => 'Carlos Fernando Avila Gratz',
        contact => {
            phone => '+55 27 1234-5678',
            email => 'cafe@example.com'
        }
    });

    # print
    print $document->as_html;


=head1 DESCRIPTION

Plift is a HTML template engine which enforces strict separation of business logic
from the view. It's designed to be designer friendly, safe, extensible and fast
enough to be used as a web request renderer. This module tries to follow the
principles described in the paper I<Enforcing Strict Model-View Separation in Template Engines>
by Terence Parr of University of San Francisco. The goal is to provide suficient
power without providing constructs that allow separation violations.

=head1 INSPIRATION

The first version of Plift was inspired by the template system provided by
L<Lift|http://liftweb.net/> (hence the name), a web framework for the Scala
programming language. They apply a concept called "View-First", which differs
from the traditional "Controller-First" concept popularized by the MVC frameworks.

On the "Controller-First" approach, the Controller is executed first, and is
responsible for pulling data from the "Model", then making this data available
to the "View". This creates a tight coupling between the controller and the
final rendered webpage, since it needs to know and gather all data possibly
need by the webpage templates. Thats perfect for well defined webapp actions,
but not so perfect for creating reusable website components.

On the other hand, a "View-First" framework starts by parsing the view, then
executing small, well-defined pieces of code triggered by special html attributes
found in the template itself. These code snippets are responsible for rendering
dynamic data using the html element (that triggered it) as the data template.
That reflects the reality that a webpage is composed by independent,
well-defined blocks of dynamic html (surrounded by static html, of course), like
a menu, gallery, a list of blog posts or any other content.

Using that approach, a CMS application can provide all sorts of special html
elements for template designers to use, like:

    <google-map address="..." />

    <youtube-video id="..." />

    <!-- a form that renders itself -->
    <x-form name="contact" />

    <blog-list limit="3">
        <!-- html template for list posts here -->
    </blog-list>

    <gallery limit="3">
        <!-- html template for list posts here -->
    </gallery>

    <youtube-playlist id="...">
     <!-- html template for list items here -->
    </youtube-playlist>

A kind of server-side L<"Custom Elements"|https://developer.mozilla.org/en-US/docs/Web/Web_Components/Custom_Elements>).

My frist version of Plift (back in 2013, DarkPAN) implemented only the
minimum to execute the "View-First" approach: it could 'include', 'wrap' and
call code snippets triggered from html elements. It couldn't even interpolate
data by itself. And that proved to be enough to create dozens of corporate
websites and (albeit simple) webapps (including our own website
http://kreato.com.br, of course). With small annoyances here and there, but
haven't been using L<Template>::Toolkit type of engine (for website templating)
since then.

That being said, this version of plift

=head1 METHODS

=head2 add_handler

=over

=item Arguments: \%parameters

=back

Binds a handler to one or more html tags, attributes, or xpath expression.
Valid parameters are:

=over

=item tag

Scalar or arrayref of HTML tags bound to this handler.

=item attribute

Scalar or arrayref of HTML attributes bound to this handler.

=item xpath

XPath expression matching the nodes bound this handler.

=back

=head2 template

=over

=item Arguments: $template_name

=back

Creates a new L<Plift::Context> instance, which will load, process and render
template C<$template_name>. See L<Plift::Context/at>, L<Plift::Context/set> and
L<Plift::Context/render>.

=head2 process

=over

=item Arguments: $template_name, $data, $directives

=item Return Value: L<$document|XML::LibXML::jQuery>

=back

A shortcut method.
A new context is created via  L</template>, rendering directives are set via
L<Plift::Context/at> and finally the template is rendered via L<Plift::Context/render>.


    my $data = {
        fullname => 'John Doe',
        contact => {
            phone => 123,
            email => 'foo@example'
        }
    };

    my $directives = [
        '#name' => 'fullname',
        '#name@title' => 'fullname',
        '#contact' => {
            'contact' => [
                '.phone' => 'phone',
                '.email' => 'email',
            ]
    ]

    my $document = $plift->process('index', $data, $directives);


=head1 THE PAPER

=head1 LICENSE

Copyright (C) Carlos Fernando Avila Gratz.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Carlos Fernando Avila Gratz E<lt>cafe@kreato.com.brE<gt>

=cut
