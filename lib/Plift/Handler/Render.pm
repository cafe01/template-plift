package Plift::Handler::Render;

use Moo;
use Carp;


sub register {
    my ($self, $engine) = @_;

    $engine->add_handler({
        name      => 'render_data',
        # tag       => 'x-render',
        attribute => 'data-render',
        handler   => sub {

            $self->process(@_);
        }
    })
}


sub process {
    my ($self, $element, $ctx) = @_;

    my @datapoints = map { [split '@', $_] }
                     split /\s+/, $element->attr('data-render');

    $element->remove_attr('data-render');

    foreach my $item (@datapoints) {

        my ($data_point, $attribute) = @$item;
        my $data = $ctx->get($data_point);

        next unless defined $data;

        # Scalar
        unless (ref $data) {

            # printf STDERR "# render: %s -> %s\n", $data_point, $data;
            !defined $attribute  ? $element->text($data) :
            $attribute eq 'HTML' ? $element->html($data)
                                 : $element->attr($attribute, $data);
        }
        else {

            if (ref $data eq 'ARRAY') {

            }
            else {


            }
        }
    }




}





1;

=encoding utf-8

=head1 NAME

Plift::Handler::Wrap - Wrap with other template file.

=cut
