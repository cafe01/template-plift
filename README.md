[![Build Status](https://travis-ci.org/cafe01/template-plift.svg?branch=master)](https://travis-ci.org/cafe01/template-plift)
# NAME

Plift - Designer friendly, safe, extensible HTML template engine.

# SYNOPSIS

    use Plift;

    my $plift = Plift->new(
        path    => \@paths,                               # default ['.']
        plugins => [qw/ Script Blog Gallery GoogleMap /], # plugins not included
    );

    my $tpl = $plift->template("index");

    # set render directives
    $tpl->at({
        '#name' => 'fullname',
        '#contact' => [
            '.phone' => 'contact.phone',
            '.email' => 'contact.email'
        ]
    });

    # render render with data
    my $document = $tpl->render({

        fullname => 'Carlos Fernando Avila Gratz',
        contact => {
            phone => '+55 27 1234-5678',
            email => 'cafe@example.com'
        }
    });

    # print
    print $document->as_html;

# DESCRIPTION

Plift is a HTML template engine which enforces strict separation of business logic
from the view. It's designed to be designer friendly, safe, extensible and fast
enough to be used as a web request renderer. This module tries to follow the
principles described in the paper _Enforcing Strict Model-View Separation in Template Engines_
by Terence Parr of University of San Francisco. The goal is to provide suficient
power without providing constructs that allow separation violations.

# INSPIRATION

The first version of Plift was inspired by the template system provided by
[Lift](http://liftweb.net/) (hence the name), a web framework for the Scala
programming language. They apply a concept called "View-First", which differs
from the traditional "Controller-First" concept popularized by the MVC frameworks.

On the "Controller-First" approach, the Controller is executed first, and is
responsible for pulling data from the "Model", then making this data available
to the "View". This creates a tight coupling between the controller and the
final rendered webpage, since it needs to know and gather all data possibly
need by the webpage templates. Thats perfect for well defined webapp actions,
but not so perfect for creating reusable website components.

On the other hand, a "View-First" framework starts by parsing the view, then
executing small, well-defined pieces of code triggered by special html attributes
found in the template itself. These code snippets are responsible for rendering
dynamic data using the html element (that triggered it) as the data template.
That reflects the reality that a webpage is composed by independent,
well-defined blocks of dynamic html (surrounded by static html, of course), like
a menu, gallery, a list of blog posts or any other content.

Using that approach, a CMS application can provide all sorts of special html
elements for template designers to use, like:

    <google-map address="..." />

    <youtube-video id="..." />

    <!-- a form that renders itself -->
    <x-form name="contact" />

    <blog-list limit="3">
        <!-- html template for list posts here -->
    </blog-list>

    <gallery limit="3">
        <!-- html template for list posts here -->
    </gallery>

    <youtube-playlist id="...">
     <!-- html template for list items here -->
    </youtube-playlist>

A kind of server-side ["Custom Elements"](https://developer.mozilla.org/en-US/docs/Web/Web_Components/Custom_Elements)).

My frist version of Plift (back in 2013, DarkPAN) implemented only the
minimum to execute the "View-First" approach: it could 'include', 'wrap' and
call code snippets triggered from html elements. It couldn't even interpolate
data by itself. And that proved to be enough to create dozens of corporate
websites and (albeit simple) webapps (including our own website
http://kreato.com.br, of course). With small annoyances here and there, but
haven't been using [Template](https://metacpan.org/pod/Template)::Toolkit type of engine (for website templating)
since then.

That being said, this version of plift

# METHODS

## add\_handler

- Arguments: \\%parameters

Binds a handler to one or more html tags, attributes, or xpath expression.
Valid parameters are:

- tag

    Scalar or arrayref of HTML tags bound to this handler.

- attribute

    Scalar or arrayref of HTML attributes bound to this handler.

- xpath

    XPath expression matching the nodes bound this handler.

## template

- Arguments: $template\_name

Creates a new [Plift::Context](https://metacpan.org/pod/Plift::Context) instance, which will load, process and render
template `$template_name`. See ["at" in Plift::Context](https://metacpan.org/pod/Plift::Context#at), ["set" in Plift::Context](https://metacpan.org/pod/Plift::Context#set) and
["render" in Plift::Context](https://metacpan.org/pod/Plift::Context#render).

## process

- Arguments: $template\_name, $data, $directives
- Return Value: [$document](https://metacpan.org/pod/XML::LibXML::jQuery)

A shortcut method.
A new context is created via  ["template"](#template), rendering directives are set via
["at" in Plift::Context](https://metacpan.org/pod/Plift::Context#at) and finally the template is rendered via ["render" in Plift::Context](https://metacpan.org/pod/Plift::Context#render).

    my $data = {
        fullname => 'John Doe',
        contact => {
            phone => 123,
            email => 'foo@example'
        }
    };

    my $directives = [
        '#name' => 'fullname',
        '#name@title' => 'fullname',
        '#contact' => {
            'contact' => [
                '.phone' => 'phone',
                '.email' => 'email',
            ]
    ]

    my $document = $plift->process('index', $data, $directives);

# SIMILAR PROJECTS

This is a list of modules (that I know of) that pursue similar goals:

- [HTML::Template](https://metacpan.org/pod/HTML::Template)

    Probably one of the first to use (almost) valid html files as templates, and
    encourage less business logic to be embedded in the templates.

- [Template::Pure](https://metacpan.org/pod/Template::Pure)

    Perl reimplementation of Pure.js. This module inspired Plift's render directives.

- [Template::Semantic](https://metacpan.org/pod/Template::Semantic)

    Similar to Template::Pure, but mixes data with render directives.

# LICENSE

Copyright (C) Carlos Fernando Avila Gratz.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Carlos Fernando Avila Gratz &lt;cafe@kreato.com.br>
