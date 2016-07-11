package Plift::Handler::Include;

use Moo;


sub register {
    my ($self, $engine) = @_;

    $engine->add_handler({
        name      => 'include',
        tag       => 'x-include',
        attribute => 'data-plift-include',
        handler   => sub {

            $self->include(@_);
        }
    })
}


sub include {
    my ($self, $element, $ctx) = @_;

    my $is_tag = $element->tagname eq 'x-include';
    my $template_name = $is_tag ? $element->attr('template')
                                : $element->attr('data-plift-include');

    my $if = $element->attr('if') || $element->attr('data-if');
    my $unless = $element->attr('unless') || $element->attr('data-unless');

    # no template name
    unless ($template_name) {

        my $error = "include error: missing template name\nsyntax:\n";
        $error .= $is_tag ? '<x-include template="<template_name>"'
                          : sprintf('<%s data-plift-include="<template_name>">', $element->tagname);

        $element->html($element->new('<pre/>')->text($error));
        return;
    }

    # contitional remove
    if (
        (defined $if && !$ctx->get($if))
        || (defined $unless && $ctx->get($unless))
        ) {

        $element->remove if $is_tag;
        return;
    }

    # remove our attributes
    unless ($is_tag) {
        $element->remove_attr($_) for
            qw/ data-plift-include data-if data-unless if unless/;
    }

    my $dom = $ctx->process_template( $template_name );

    # replace or append
    if ($is_tag) {
        $element->replace_with($dom);
    }
    else {
        $element->append($dom);
    }

}





1;

=encoding utf-8

=head1 NAME

Plift::Handler::Include - Include other template files.

=cut
