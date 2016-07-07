#!/usr/bin/env perl
use strict;
use 5.010;
use Benchmark ':all';
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use Plift;
use Template::Pure;
use Path::Tiny;
use Template;


my $plift = Plift->new( path => ["$FindBin::Bin/plift"] );
my $tt = Template->new( INCLUDE_PATH => ["$FindBin::Bin/tt"] );


# print "Plift:\n".plift().plift(); exit;
# print "Pure:\n".pure();
# print "TT:\n".tt(); exit;

cmpthese(shift || 5000, {
    Plift => \&plift,
    'Template::Pure'  => \&pure,
    # 'Template::Toolkit'  => \&tt,
    # load_files => sub {
    #
    #     my $file = path("$FindBin::Bin/pure/footer.html")->slurp_utf8;
    #     $file = path("$FindBin::Bin/pure/header.html")->slurp_utf8;
    #     $file = path("$FindBin::Bin/pure/layout.html")->slurp_utf8;
    #     $file = path("$FindBin::Bin/pure/index.html")->slurp_utf8;
    #
    # }
});



sub plift {
    my $output = $plift->process("index")->as_html;
}

sub pure {

    my $footer = Template::Pure->new(
        template => path("$FindBin::Bin/pure/footer.html")->slurp_utf8,
        directives => []);

    my $header = Template::Pure->new(
        template => path("$FindBin::Bin/pure/header.html")->slurp_utf8,
        directives => []);

    my $layout = Template::Pure->new(
        template   => path("$FindBin::Bin/pure/layout.html")->slurp_utf8,
        directives => [ '#content+' => 'content' ]
    );

    my $index = Template::Pure->new(
        template => path("$FindBin::Bin/pure/index.html")->slurp_utf8,
        directives => []);

    my $output = $index->render({
        layout => $layout,
        header => $header,
        footer => $footer,
    });
}


sub tt {

    my $output = '';

    $tt->process('index.html', {}, \$output)
        || die $tt->error();

    $output;
}
