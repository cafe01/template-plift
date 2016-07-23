package Plift::Handler::Wrap;

use Moo;
use Carp;


sub register {
    my ($self, $engine) = @_;

    $engine->add_handler({
        name      => 'wrap',
        tag       => 'x-wrap',
        attribute => 'data-plift-wrap',
        handler   => sub {

            $self->wrap(@_);
        }
    })
}


sub wrap {
    my ($self, $element, $ctx) = @_;

    my $is_tag = $element->tagname eq 'x-wrap';
    my $template_name = $is_tag ? $element->attr('template')
                                : $element->attr('data-plift-wrap');

    $template_name ||= 'layout';

    # params
    my %params =  ( at => '#content' );

    foreach (qw/ at if unless replace content /) {

        my $value = $element->attr("data-$_") || $element->attr($_);

        unless ($is_tag) {
            $element->remove_attr("data-$_");
            $element->remove_attr($_);
        }

        $params{$_} = $value if $value;
    }

    # contitional remove
    if (
        (defined $params{if} && !$ctx->get($params{if}))
        || (defined $params{unless} && $ctx->get($params{unless}))
        ) {

        $element->replace_with($element->children) if $is_tag;
        return;
    }

    # load template
    my $dom = $ctx->process_template($template_name);

    # $dom elements comes unbound of document, insert somewhere
    $dom->insert_after($element);

    # find wrapper
    my $wrapper = $dom->find($params{at});
    $wrapper = $dom->filter($params{at}) if $wrapper->size == 0;

    confess "wrap error: can't find wrapper element (with id '".$params{at}."') on:\n".$dom->as_html
        unless $wrapper->size > 0;

    # wrap element
    my $is_xtag = $element->tagname =~ /^x-/;
    if ($params{replace}) {
        $wrapper->replace_with($is_xtag || $params{content} ? $element->contents : $element);
    }
    else {
        $wrapper->append($is_xtag || $params{content} ? $element->contents : $element);
    }

    $element->remove if $is_xtag || $params{content};
}





1;

__END__

=encoding utf-8

=head1 NAME

Plift::Handler::Wrap - Wrap with other template file.

=head1 LICENSE

Copyright (C) Carlos Fernando Avila Gratz.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Carlos Fernando Avila Gratz E<lt>cafe@kreato.com.brE<gt>

=cut
