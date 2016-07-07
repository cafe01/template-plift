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
    my @components = qw/ Handler::Include  Handler::Wrap /;

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
            $self->load_template($name, \@path, $ctx)
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


sub load_template {
    my ($self, $name, $path, $ctx) = @_;

    # resolve template name to file
    my ($template_file, $template_path) = $self->find_template_file($name, $path, $ctx->relative_path_prefix);
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

sub find_template_file {
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

Plift - It's new $module

=head1 SYNOPSIS

    use Plift;

    my $plift = Plift->new(
        path    => \@paths, # defaul ['.']
        plugins => [qw/ Script Blog Gallery GoogleMap Youtube /],
    );

    my $template = $plift->template("index"); # looks for index.html on every path

    $template->set('name', 'Carlos Fernando');
    $template->set('now', DataTime->now);

    my $document = $template->render;




=head1 DESCRIPTION

Plift is a html template engine which enforces strict separation of business logic
from the view. It's designed to be designer friendly, safe, exstensible and fast
enough to be used as a web request renderer. This module tries to follow the
principles described in the paper I<Enforcing Strict Model-View Separation in Template Engines>
by Terence Parr of University of San Francisco. The goal is to provide suficient
power without providing constructs that allow separation violations.

=head1 METHODS

=head2 register_handler

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





=head1 THE PAPER

=head1 LICENSE

Copyright (C) Carlos Fernando Avila Gratz.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Carlos Fernando Avila Gratz E<lt>cafe@kreato.com.brE<gt>

=cut
