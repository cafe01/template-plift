package Plift::Context;

use Moo;
use Carp;
use Scalar::Util qw/ blessed /;
use aliased 'XML::LibXML::jQuery';

has 'template', is => 'ro', required => 1;
has 'encoding', is => 'ro', default => 'UTF-8';
has 'loop_var', is => 'ro', default => 'loop';
has 'handlers', is => 'ro', default => sub { [] };
has '_load_template', is => 'ro', required => 1, init_arg => 'load_template';


has 'document', is => 'rw';
has 'relative_path_prefix', is => 'rw', init_arg => undef;
has 'is_rendering', is => 'rw', init_arg => undef, default => 0;

has '_data_stack',   is => 'ro', default => sub { [] };
has 'directives',   is => 'ro', default => sub { [] };


sub data {
    my $self = shift;
    my $stack = $self->_data_stack;
    push @$stack, +{} if @$stack == 0;
    $stack->[-1];
}


sub _push_stack {
    my ($self, $data_point) = @_;
    my $data = $self->get($data_point) || {};
    push @{$self->_data_stack}, $data;
    $self;
}

sub _pop_stack {
    my ($self) = @_;
    pop @{$self->_data_stack};
    $self;
}


sub at {
    my $self = shift;

    if (my $reftype = ref $_[0]) {

        push @{$self->directives}, @$_[0]
            if $reftype eq 'ARRAY';

        push @{$self->directives}, %$_[0]
            if $reftype eq 'HASH';
    }
    else {
        push @{$self->directives}, @_;
    }

    $self;
}



sub set {
    my $self = shift;

    confess "set() what?"
        unless defined $_[0];

    my $data   = $self->data;

    # set(hashref)
    if (my $reftype = ref $_[0]) {

        confess "Invalid parameter given to set(data): data must be a hashref."
            unless $reftype eq 'HASH';

        # copy data
        $data->{$_} = $_[0]->{$_}
            for keys %{$_[0]};

        return $self;
    }

    # set(key, value)
    $data->{$_[0]} = $_[1];

    $self;
}


sub get {
    my ($self, $reference) = @_;

    my $data = $self->data;
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

        my $next_data;

        # hash key
        if (ref $data eq 'HASH') {

            $next_data = $data->{$key};
        }

        # array: numeric keys only
        elsif (ref $data eq 'ARRAY') {

            confess "get('$reference') error: '$current_path' is an array and '$key' is not a numeric index."
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
    return $data;
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
        $el = jQuery->new($el);
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

    # process tempalte file
    my $element = $self->process_template($self->template);

    # render data
    $self->render_element($element, $self->directives);

    # TODO output filters

    # return the document
    $self->is_rendering(0);
    $element->document
}

sub render_element {
    my ($self, $el, $directives, $data_root) = @_;

    for (my $i = 0; $i < @$directives; $i += 2) {

        my ($selector, $attribute) = split '@', $directives->[$i];
        my $action = $directives->[$i+1];

        # printf STDERR "# directive: $selector\n";
        my $target_element = $el->find($selector);
        next unless $target_element->size > 0;

        # Scalar
        if (!ref $action) {


            my $value = $self->get($action);
            # printf STDERR "#\taction: $action -> $value\n";

            $target_element->remove unless defined $value;

            # attribute or HTML
            if (defined $attribute) {

                if ($attribute eq 'HTML') {
                    $target_element->html($value);
                }
                else {
                    $target_element->attr($attribute, $value);
                }
            }
            # text node
            else {
                # printf STDERR "# is text: $value";
                $target_element->text($value);
            }
        }

        # ArrayRef
        elsif (ref $action eq 'ARRAY') {

            $self->render_element($target_element, $action);
        }

        # HashRef
        elsif (ref $action eq 'HASH') {

            my ($new_data_root, $new_directives) = %$action;

            # $new_data_root = "$data_root.$new_data_root"
            #     if defined $data_root;

            my $new_data = $self->get($new_data_root);

            # loop render
            if (defined $new_data && ref $new_data eq 'ARRAY') {

                my $total = @$new_data;
                for (my $i = 0; $i < @$new_data; $i++) {

                    $self->_push_stack("$new_data_root.$i");
                    $self->data->{$self->loop_var} = {
                        index => $i+1,
                        total => $total
                    };

                    my $tpl = $target_element->clone;
                    $self->render_element($tpl, $new_directives);
                    $tpl->insert_before($target_element);

                    delete $self->data->{$self->loop_var};
                    $self->_pop_stack;
                }

                $target_element->remove;
            }
            else {

                $self->_push_stack($new_data_root);
                $self->render_element($target_element, $new_directives);
                $self->_pop_stack;
            }
        }

        # CodeRef
        elsif (ref $action eq 'CODE') {
            # Template::Pure used this coderef to receive a value.
            # our coderef is used to perform custom element rendering,
            # We support evaluating a value from a coderef when a datapoint is a coderef.
            $action->($target_element, $self);
        }
    }
}






1;


__END__

=head1 METHOD

=head2 reset

Resets the data and schema.

=cut
