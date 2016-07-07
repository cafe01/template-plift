package Plift::Context;

use Moo;
use Carp;
use Scalar::Util qw/ blessed /;

has 'template', is => 'ro', required => 1;
has 'encoding', is => 'ro', default => 'UTF-8';
has 'handlers', is => 'ro', default => sub { [] };
has '_load_template', is => 'ro', required => 1, init_arg => 'load_template';


has 'document', is => 'rw';
has 'relative_path_prefix', is => 'rw', init_arg => undef;
has 'is_rendering', is => 'rw', init_arg => undef, default => 0;

has 'schema', is => 'ro', default => sub { {} };
has '_data_stack',   is => 'ro', default => sub { [] };
has '_files', is => 'ro', default => sub { [] };


sub push_file {
    push @{ shift->_files }, shift;
}

sub pop_file {
    pop @{ shift->_files };
}

sub data {
    my $self = shift;
    my $stack = $self->_data_stack;
    push @$stack, +{} if @$stack == 0;
    $stack->[-1];
}


sub current_file {
    shift->_files->[-1]
}



sub set {
    my $self = shift;

    confess "set() what?"
        unless defined $_[0];

    my $data   = $self->data;
    my $schema = $self->schema;

    # set(hashref)
    # set(hashref, schema)
    if (my $reftype = ref $_[0]) {

        confess "Invalid parameter given to set(data[, schema]): data must be a hashref."
            unless $reftype eq 'HASH';

        # copy data
        $data->{$_} = $_[0]->{$_}
            for keys %{$_[0]};

        # copy schema
        if (@_ == 2) {

            confess "Invalid parameter given to set(data, schema): schema must be a hashref."
                unless ref $_[1] eq 'HASH';

            $schema->{$_} = $_[1]->{$_}
                for keys %{$_[1]};
        }

        return $self;
    }

    # set(key, value, schema)
    $data->{$_[0]} = $_[1];

    $schema->{$_[0]} = $_[2]
        if defined $_[2];

    $self;
}


sub get {
    my ($self, $reference) = @_;

    my $data = $self->data;
    my $schema = $self->schema;
    my @keys = split /\./, $reference;

    # empty key
    die "invalid reference '$reference'"
        if grep { !defined } @keys;

    # traverse data, valid reference formats:
    # - foo
    # - foo.bar
    # - foo.0
    # - foo.0.bar

    my $current_path = '';
    while (defined (my $key = shift @keys)) {

        # undefined data
        confess "get('$reference') error: '$current_path' is undefined."
            unless defined $data;

        # cant traverse non-ref data
        die "get('$reference') error: can't traverse key '$key': '$current_path' is a non-ref value."
            unless ref $data;

        # append path
        $current_path .= length $current_path ? ".$key" : $key;

        # traverse schema
        $schema = defined $schema && ref $schema eq 'HASH' ? $schema->{$key} : undef;

        my $next_data;

        # hash key
        if (ref $data eq 'HASH') {

            $next_data = $data->{$key};
        }

        # array: numeric keys only
        elsif (ref $data eq 'ARRAY') {

            die "get('$reference') error: '$current_path' is an array and '$key' is not a numeric index."
                unless $key =~ /^\-?\d+$/;

            $next_data = $data->[$key];
        }

        elsif (blessed $data) {

            die sprintf("get('%s') error: '%s' is an '%s' instance and '%s' is not a existing method.",
                $reference, $current_path, ref $data, $key) unless $data->can($key);

            $next_data = $data->$key;
        }

        elsif (ref $data) {

            die sprintf "get('%s') error: can't traverse key '%s': '%s' is a unsupported ref value (%s).",
                $reference, $key, $current_path, ref $data;
        }

        # next data is code, replace by its rv
        $next_data = $next_data->($self, $data)
            if ref $next_data eq 'CODE';

        $data = $next_data;
    }

    $data = '' unless defined $data;
    return wantarray ? ($data, $schema) : $data;
}


sub process_template {
    my ($self, $template_name) = @_;

    my $element = $self->load_template($template_name);
    $self->process_element($element);

    $element;
}


# load a template from the paths contained in the _load_template closure
sub load_template {
    my ($self, $name) = @_;
    $self->_load_template->($self, $name);
}

sub process_element {
    my ($self, $element) = @_;
    my $handlers = $self->handlers;

    # match elements
    my $callback = sub {

        my ($i, $el) = @_;
        my $tagname = $el->tagname;

        # printf STDERR "# el($i): %s\n", $el->as_html;

        foreach my $handler (@$handlers) {

            # dispatch by tagname
            if ($handler->{tag} && scalar grep { $_ eq $tagname } @{$handler->{tag}}) {

                # printf STDERR "# dispatching: <%s /> -> '%s'\n", $tagname, $handler->{name};
                $handler->{sub}->($el, $self);

            }

            # dispatch by attribute
            elsif ($handler->{attribute}) {

                foreach my $attr (@{$handler->{attribute}}) {

                    if ($el->get(0)->hasAttribute($attr)) {

                        # printf STDERR '# dispatching: <%s %s="%s" /> -> "%s"'."\n",
                            # $tagname, $attr, $el->attr($attr), $handler->{name};

                        $handler->{sub}->($el, $self);
                    }

                }
            }
        }

    };

    # xpath
    my $find_xpath = join ' | ', map { $_->{xpath} } @$handlers;
    my $filter_xpath = $find_xpath;
    $filter_xpath =~ s{\.//}{./}g;
    # printf STDERR "# process_element(%s): \n%s\n", $find_xpath, $element->as_html;
    # printf STDERR "# process_element(%s): %s\n", $find_xpath, $filter_xpath;
    $element->xfilter($filter_xpath)->each($callback);
    $element->xfind($find_xpath)->each($callback);

}

sub render  {
    my ($self, $data) = @_;

    $self->set($data)
        if defined $data;

    # already rendering
    die "Can't call render() now. We are already rendering."
        if $self->is_rendering;

    $self->is_rendering(1);

    # load tempalte file
    my $element = $self->load_template($self->template);

    # process element
    $self->process_element($element);

    # TODO output filters

    # return the document
    $element->document
}







1;


__END__

=head1 METHOD

=head2 reset

Resets the data and schema.

=cut
