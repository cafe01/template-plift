package Plift::Handler::Render;

use Moo;
use Carp;


sub register {
    my ($self, $engine) = @_;

    $engine->add_handler({
        name      => 'render',
        tag       => 'x-render',
        attribute => ['data-render'],
        handler   => \&create_directives
    });
}


sub create_directives {
    my ($element, $ctx) = @_;
    my $node = $element->get(0);

    # walk directive stack, get node id
    $ctx->rewind_directive_stack($element);

    # parse directive
    my $is_tag = $node->localname eq 'x-render';
    my $render_instruction = $node->getAttribute($is_tag ? 'data' : 'data-render');
    $node->removeAttribute('data-render') unless $is_tag;

    # prepare selector
    my $internal_id = $ctx->internal_id($element->get(0));
    my $selector = sprintf '*[%s="%s"]', $ctx->internal_id_attribute, $internal_id;

    # data-render="[datapoint]" (step into directive)
    if ($render_instruction =~ /^\s*\[\s*([\w._-]+)\s*\]\s*$/) {

        # push directive stack
        $ctx->push_at($selector, $1);
    }

    # data-render="datapoint"
    else {

        my @data_points = map { [split '@', $_] }
                          split /\s+/, $render_instruction;

        foreach my $item (@data_points) {

            my ($data_point, $attribute) = @$item;
            $ctx->at(defined $attribute ? "$selector\@$attribute" : $selector, $data_point);
       }
    }
}








1;

__END__

=encoding utf-8

=head1 NAME

Plift::Handler::Render - Render data referenced in templates.

=head1 LICENSE

Copyright (C) Carlos Fernando Avila Gratz.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Carlos Fernando Avila Gratz E<lt>cafe@kreato.com.brE<gt>

=cut
