package Plift::Directive::Include;

use strict;
use warnings;


sub register {
    my ($self, $engine) = @_;

    $engine->add_handler({
        name => 'include',
        tag => 'x-include',
        attribute => 'data-plift-include',
        handler => sub {
            $self->include(@_);
        }
    })
}


sub include {
    my ($self, $engine, $element) = @_;

    my $is_tag = $element->tagname eq 'x-include';
    my $template_name = $is_tag ? $element->attr('template')
                                : $element->attr('data-plift-include');

    my $dom = $engine->load_template( $template_name, $element ? $element->get(0)->ownerDocument : () );

    # initial process()
    # return $dom unless defined $element;

    # replace / append
    if ($is_tag) {
        $element->replace_with($dom);
    }
    else {
        $element->append($dom);
        $element->remove_attribute('data-plift-include');
    }

    $engine->process_element($dom);
}





1;

=encoding utf-8

=head1 NAME

Plift::Directive::Include - Include template files.

=cut
