package Plift::Context;

use Moo;
use Carp;
use Scalar::Util qw/ blessed /;
use aliased 'XML::LibXML::jQuery';
use Data::Printer;

has 'template', is => 'ro', required => 1;
has 'encoding', is => 'ro', default => 'UTF-8';
has 'loop_var', is => 'ro', default => 'loop';
has 'handlers', is => 'ro', default => sub { [] };
has 'internal_id_attribute', is => 'ro', default => 'data-plift-id';
has '_load_template', is => 'ro', required => 1, init_arg => 'load_template';


has 'document', is => 'rw';
has 'relative_path_prefix', is => 'rw', init_arg => undef;
has 'is_rendering', is => 'rw', init_arg => undef, default => 0;

has '_data_stack',   is => 'ro', default => sub { [] };
has '_directive_stack',   is => 'ro', default => sub { [] };



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

sub directives {
    my $self = shift;
    my $stack = $self->_directive_stack;
    push @$stack, +{
        directives => [],
        selector => '',
    } if @$stack == 0;
    $stack->[-1];
}

sub rewind_directive_stack {
    my ($self, $element) = @_;

    # rewind all
    unless (defined $element) {

        my $directive_stack = $self->_directive_stack;
        pop @$directive_stack while (@$directive_stack > 1);
        return;
    }

    # rewind until parent is found
    # pop stack until we find a parent or reach the root of stack
    my $stack = $self->_directive_stack;
    while (@$stack > 1) {

        my $parent = $element->parent;
        my $parent_selector = $stack->[-1]->{selector};

        while ($parent->get(0)->nodeType != 9) {

            return if $parent->filter($parent_selector)->size == 1;

            $parent = $parent->parent;
        }

        pop @$stack;
    }
}

sub push_at {
    my ($self, $selector, $data_point) = @_;

    my $inner_directives = [];
    $self->at($selector => { $data_point => $inner_directives });
    push @{$self->_directive_stack}, {
        selector   => $selector,
        directives => $inner_directives
    };

    # p $self->_directive_stack;

    $self;
}

sub pop_at {
    my $self = shift;
    pop @{$self->_directive_stack};
    $self;
}



my $internal_id = 1;
sub internal_id {
    my ($self, $node) = @_;

    unless ($node->hasAttribute($self->internal_id_attribute)) {
        $node->setAttribute($self->internal_id_attribute, $internal_id++);
    }

    return $node->getAttribute($self->internal_id_attribute);
}




sub at {
    my $self = shift;
    my $directives = $self->directives->{directives};
    if (my $reftype = ref $_[0]) {

        push @$directives, @$_[0]
            if $reftype eq 'ARRAY';

        push @$directives, %$_[0]
            if $reftype eq 'HASH';
    }
    else {
        push @$directives, @_;
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

    # match elements
    my $callback = sub {
        $self->dispatch_handlers(@_);
    };

    # xpath
    my $find_xpath = join ' | ', map { $_->{xpath} } @{ $self->handlers };
    my $filter_xpath = $find_xpath;
    $filter_xpath =~ s{\.//}{./}g;

    $element->xfilter($filter_xpath)->each($callback);
    $element->xfind($find_xpath)->each($callback);
}

sub dispatch_handlers {
    my ($self, $i, $node) = @_;
    my $tagname = $node->localname;
    my $el = jQuery->new($node);

    # printf STDERR "# el($i): %s\n", $el->as_html;

    foreach my $handler (@{ $self->handlers }) {

        # dispatch by tagname
        my $handler_match = 0;
        if ($handler->{tag} && scalar grep { $_ eq $tagname } @{$handler->{tag}}) {

            $handler_match = 1;
        }

        # dispatch by attribute
        elsif ($handler->{attribute}) {

            foreach my $attr (@{$handler->{attribute}}) {

                if ($node->hasAttribute($attr)) {

                    $handler_match = 1;
                    last;
                }
            }
        }

        # dispatch
        # printf STDERR "# dispatching: <%s /> -> '%s'\n", $tagname, $handler->{name};
        $handler->{sub}->($el, $self)
            if $handler_match;
    }
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

    # rewind directive stack, then render
    $self->rewind_directive_stack;
    $self->render_directives($element, $self->directives->{directives});

    # TODO output filters

    # remove internal id attribute
    $element->xfind(sprintf '//*[@%s]', $self->internal_id_attribute)
            ->remove_attr($self->internal_id_attribute);

    # return the document
    $self->is_rendering(0);
    $element->document;
}

sub render_directives {
    my ($self, $el, $directives) = @_;

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

            !defined $attribute  ? $target_element->text($value) :
            $attribute eq 'HTML' ? $target_element->html($value)
                                 : $target_element->attr($attribute, $value);
        }

        # ArrayRef
        elsif (ref $action eq 'ARRAY') {

            $self->render_directives($target_element, $action);
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
                    $self->render_directives($tpl, $new_directives);
                    $tpl->insert_before($target_element);

                    delete $self->data->{$self->loop_var};
                    $self->_pop_stack;
                }

                $target_element->remove;
            }
            else {

                $self->_push_stack($new_data_root);
                $self->render_directives($target_element, $new_directives);
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
