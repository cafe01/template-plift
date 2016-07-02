package Plift;

use 5.008001;
use strict;
use warnings;
use Moo;
use Class::Load ();
use Path::Tiny ();
use XML::LibXML::jQuery ();
use Carp;

our $VERSION = "0.01";

use constant {
    XML_DOCUMENT_NODE => 9,
    XML_DOCUMENT_FRAG_NODE => 11
};

has 'path', is => 'ro', default => sub { [] };
has 'plugins', is => 'ro', default => sub { [] };
has 'encoding', is => 'rw', default => 'UTF-8';
has 'debug', is => 'rw', default => sub { $ENV{PLIFT_DEBUG} };
has 'max_file_size', is => 'rw', default => 1024 * 1024;

# has '_cache', is => 'ro', default => sub { {} };


sub BUILD {
    my $self = shift;

    # init components
    # builtin directives
    my @components;

    # include
    $self->add_handler({
        name      => 'include',
        tag       => 'x-include',
        attribute => 'data-plift-include',
        handler   => \&_process_include
    });

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


sub process {
    my ($self, $template) = @_;

    # process template
    my $element = $self->load_template($template);
    $self->process_element($element);

    # run output filters
    my $document = $element->document;

    # return document
    $document;
}

sub process_element {
    # body...
}


sub parse_html {
    my ($self, $source) = @_;
    XML::LibXML::jQuery->new($source);
}

sub load_template {
    my ($self, $name, $existing_document) = @_;

    # resolve template name to file
    my ($template_file, $try_files) = $self->find_template_file($name);
    die sprintf "Can't find a template file for template '%s'. Tried:\n%s\n", $name, join(",\n", @$try_files)
        unless $template_file;

    # max file size


    # parse source
    my $dom = XML::LibXML::jQuery->new($self->encoding eq 'UTF-8' ? $template_file->slurp_utf8
                                                                  : $template_file->slurp( binmode => ":unix:encoding(".$self->encoding.")"));

    # check for data-plift-template attr, and use that element
    my $body = $dom->xfind('//body[@data-plift-template]');

    if ($body->size) {
        my $selector = $body->attr('data-plift-template');
        $dom = $dom->find($selector);
        confess "Can't find template via selector '$selector' (referenced at <body data-plift-template=\"$selector\">)."
            unless $dom->size;
    }

    # adopt into document
    if ($existing_document) {

        # replace DTD
        if ($dom->size && (my $dtd = $dom->get(0)->ownerDocument->internalSubset)) {
            $existing_document->removeInternalSubset;
            $existing_document->createInternalSubset( $dtd->getName, $dtd->publicId, $dtd->systemId );
        }

        # adopt nodes
        my @nodes = map { $existing_document->adoptNode($_); $_ }
                    grep { node->getOwner->nodeType == XML_DOCUMENT_NODE }
                    @{ $dom->{nodes} };

        # reinstantitate on new document
        $dom = XML::LibXML::jQuery->new(\@nodes);
    }

    $dom;
}

sub find_template_file {
    my ($self, $template_name) = @_;
    my @try_files;

    foreach my $path (@{$self->path}) {

        my $file = "$path/$template_name.html";
        push @try_files, $file;
        return Path::Tiny->new($file) if -e $file;
    }

    wantarray ? (undef, \@try_files) : undef;
}

sub add_handler {
    my ($self, $config) = @_;

    confess "missing handler callback"
        unless $config->{handler};

    confess "missing handler name"
        unless $config->{name};

    my @match;

    push(@match, map { "./$_" } ref $config->{tag} ? @{$config->{tag}} : $config->{tag})
        if exists $config->{tag};

    push(@match, map { "./*[\@$_]" } ref $config->{attribute} ? @{$config->{attribute}} : $config->{attribute})
        if exists $config->{attribute};

    push @match, $config->{xpath}
        if $config->{xpath};

    my $match = join ' | ', @match;

    printf STDERR "[Plift] Adding handler: $match\n"
        if $self->debug;

    # check config has one of tag/attribute/xpath
    confess "Invalid handler. Missing at least one binding criteria (tag, attribute or xpath)."
        unless $match;

    my $handler = {
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


sub _process_include {
    # body...
}



1;
__END__

=encoding utf-8

=head1 NAME

Plift - It's new $module

=head1 SYNOPSIS

    use Plift;

    my $plift = Plift->new(
        path => \@paths, # defaul ['.']
        components => [qw/ Script Blog Gallery GoogleMap Youtube /],
    );

    $plift->set('name', 'Carlos Fernando');
    $plift->set('now', DataTime->now);




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
